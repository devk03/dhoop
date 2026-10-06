#if os(iOS)
import Foundation
import Combine
import CryptoKit

@MainActor
final class SleepWebhookClient: ObservableObject {
    static let shared = SleepWebhookClient()
    @Published private(set) var checkpoint = SleepWebhookCheckpoint()
    @Published private(set) var isSending = false
    @Published private(set) var storageUnavailable = false
    private var worker: Task<Void, Never>?
    private var generation = 0
    private let store: SleepWebhookFileStore
    private let documents: URL

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SleepWebhookFileStore(url: root.appendingPathComponent("SleepWebhook/state.json"))
        documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do { checkpoint = try store.load() }
        catch { storageUnavailable = true; checkpoint.message = "Delivery state could not be read. Export is paused." }
        try? retireConsumedSetup()
    }
    var hasCredentials: Bool { (try? credentials()) != nil }
    private func credentials() throws -> SleepWebhookCredentials {
        guard let bytes = try SleepWebhookKeychain.read("credentials") else { throw SleepWebhookFailure.credentials }
        let value = try JSONDecoder().decode(SleepWebhookCredentials.self, from: bytes)
        guard value.isValid, value.endpoint == checkpoint.delivery.endpoint else { throw SleepWebhookFailure.credentials }
        return value
    }
    private func commit(_ next: SleepWebhookCheckpoint) throws {
        guard !storageUnavailable else { throw SleepWebhookFailure.storage }
        try store.save(next)
        checkpoint = next
        writeStatus()
    }
    func configure(_ value: SleepWebhookCredentials) throws {
        guard value.isValid, !isSending else { throw SleepWebhookFailure.invalidConfiguration }
        var next = checkpoint
        try next.delivery.configure(endpoint: value.endpoint)
        next.enabled = false; next.failures = 0; next.nextAttempt = nil; next.message = "Connection saved · automatic delivery is off"
        // Persist the disabled destination BEFORE changing its credentials; a crash cannot accidentally
        // send an old pending event with credentials meant for a different endpoint.
        try commit(next)
        try SleepWebhookKeychain.save(JSONEncoder().encode(value), account: "credentials")
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { _ = try credentials() }
        var next = checkpoint
        next.enabled = enabled; next.nextAttempt = nil
        next.message = enabled ? "Ready to send verified WHOOP sleep" : "Automatic delivery is off"
        try commit(next)
        generation += 1; worker?.cancel()
        SleepWebhookScheduler.update(enabled: enabled)
    }
    func enqueue(model: AppModel, force: Bool = false) {
        guard checkpoint.enabled, worker == nil else { return }
        worker = Task(priority: .utility) { [weak self, weak model] in
            guard let self, let model else { return }
            _ = await self.deliver(model: model, force: force)
            self.worker = nil
        }
    }
    func deliver(model: AppModel, force: Bool = false) async -> Bool {
        guard !isSending, !storageUnavailable, checkpoint.enabled else { return true }
        guard TimeZone.current.identifier == "America/Los_Angeles" else {
            setMessage("Paused outside America/Los_Angeles. No dates are converted.")
            return false
        }
        guard force || SleepWebhookPolicy.canSend(enabled: checkpoint.enabled, timeZone: .current,
                                                  nextAttempt: checkpoint.nextAttempt, now: Date()) else { return true }
        // A partial/failed rescore must settle before exporting its mutable results.
        guard checkpoint.delivery.pending != nil || (!model.intelligence.computing && !RescoreBackgroundScheduler.isRescoreOwed) else {
            setMessage("Waiting for sleep processing to finish")
            SleepWebhookScheduler.update(enabled: true)
            return false
        }
        isSending = true
        let ticket = generation
        defer { isSending = false; SleepWebhookScheduler.update(enabled: checkpoint.enabled) }
        do {
            let secret = try credentials()
            var candidates: [SleepWebhookSummary] = []
            if checkpoint.delivery.pending == nil {
                guard let healthStore = await model.repo.storeHandle() else { throw SleepWebhookFailure.storage }
                var selection = MetricRangeSelection(); selection.preset = .week
                let window = selection.window(now: Date())
                let ids = await model.repo.sleepComparisonSourceIds().filter { !$0.hasSuffix("-noop") }
                let rows = try await healthStore.verifiedWhoopSleepTotals(rawSourceIds: ids, from: window.fromDay, to: window.toDay)
                candidates = rows.reversed().map { row in
                    SleepWebhookSummary(wakeDate: row.day, sleepMinutes: row.minutes,
                        method: row.estimated ? "dhoop_estimate" : "whoop_import", timeZone: "America/Los_Angeles")
                }
            }
            // At most two small requests per invocation. Further history catches up on later triggers.
            for _ in 0..<2 {
                try Task.checkCancellation()
                guard ticket == generation, checkpoint.enabled else { return false }
                guard TimeZone.current.identifier == "America/Los_Angeles" else { throw SleepWebhookFailure.travelPause }
                var next = checkpoint
                if next.delivery.pending == nil {
                    guard let summary = candidates.first(where: { next.delivery.acknowledged[$0.wakeDate] != $0 }) else {
                        if next.delivery.lastAcceptedAt == nil { setMessage("No verified WHOOP sleep available in the last 7 days") }
                        return true
                    }
                    _ = try next.delivery.prepare(summary)
                    next.message = "Sending verified sleep"
                    try commit(next) // immutable bytes and revision durable before the network starts
                }
                guard let pending = checkpoint.delivery.pending else { throw SleepWebhookFailure.invalidState }
                let response = try await SleepWebhookTransport().send(pending.bytes, credentials: secret)
                try Task.checkCancellation()
                guard ticket == generation, checkpoint.enabled else { return false }
                next = checkpoint
                try next.delivery.accept(response)
                next.failures = 0; next.nextAttempt = nil
                next.message = next.delivery.lastOutcome == "manual_preserved"
                    ? "Received by website · your manual entry was preserved"
                    : "Received by website"
                try commit(next) // a failed checkpoint retains the immutable pending event for retry
            }
            return true
        } catch is CancellationError { return false }
        catch {
            if ticket == generation {
                var next = checkpoint
                next.failures = min(next.failures + 1, 100)
                next.nextAttempt = Date().addingTimeInterval(SleepWebhookPolicy.retryDelay(failures: next.failures))
                next.message = Self.safeMessage(error)
                do { try commit(next) }
                catch { checkpoint.message = "Delivery state could not be saved. Export is paused."; storageUnavailable = true }
            }
            return false
        }
    }
    private func setMessage(_ message: String) {
        guard checkpoint.message != message else { return }
        var next = checkpoint; next.message = message
        do { try commit(next) }
        catch { storageUnavailable = true; checkpoint.message = "Delivery state could not be saved. Export is paused." }
    }
    static func safeMessage(_ error: Error) -> String {
        guard let failure = error as? SleepWebhookFailure else { return "Connection interrupted. Pending sleep is saved for retry." }
        switch failure {
        case .http(let code): return "Website returned HTTP \(code). Pending sleep is saved."
        case .credentials: return "Credentials unavailable. Unlock the phone or update the connection."
        case .travelPause: return "Paused outside America/Los_Angeles. No dates are converted."
        case .invalidAcknowledgement, .responseTooLarge: return "Website acknowledgement was invalid. Pending sleep is saved."
        case .storage, .invalidState: return "Delivery state could not be read or saved. Export is paused."
        case .expiredSetup: return "Setup expired or does not match this phone. Prepare a new setup."
        default: return "Check the connection settings. Nothing was acknowledged."
        }
    }

    // Explicit local setup only. Neither raw credentials nor receiver response bodies are written here.
    private struct SetupKey: Codable { let invitation: SleepWebhookSecureSetup.Invitation; let privateKey: Data; var consumed: Bool }
    func prepareSecureSetup() throws {
        guard !storageUnavailable, !isSending else { throw SleepWebhookFailure.storage }
        try commit(checkpoint)
        let key = P256.KeyAgreement.PrivateKey()
        let invite = SleepWebhookSecureSetup.Invitation(version: 1, setupId: UUID().uuidString.lowercased(),
            installationId: checkpoint.delivery.installationId, publicKey: key.publicKey.x963Representation,
            expiresAt: Date().addingTimeInterval(30 * 60))
        try SleepWebhookKeychain.save(JSONEncoder().encode(SetupKey(invitation: invite, privateKey: key.rawRepresentation, consumed: false)), account: "setup")
        try JSONEncoder().encode(invite).write(to: documents.appendingPathComponent("dhoop-webhook-setup-public.json"), options: .atomic)
        setMessage("Secure setup prepared · expires in 30 minutes")
    }
    func importSecureSetup() throws {
        guard let keyBytes = try SleepWebhookKeychain.read("setup") else { throw SleepWebhookFailure.expiredSetup }
        var setup = try JSONDecoder().decode(SetupKey.self, from: keyBytes)
        guard !setup.consumed, setup.invitation.installationId == checkpoint.delivery.installationId else { throw SleepWebhookFailure.expiredSetup }
        let url = documents.appendingPathComponent("dhoop-webhook-setup-sealed.json")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.intValue <= 16_384 else { throw SleepWebhookFailure.invalidConfiguration }
        let envelope = try JSONDecoder().decode(SleepWebhookSecureSetup.Envelope.self, from: Data(contentsOf: url))
        let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: setup.privateKey)
        let value = try SleepWebhookSecureSetup.open(envelope, invitation: setup.invitation, privateKey: key)
        // Consume and discard the decryption key BEFORE saving credentials. A failed configuration
        // requires a fresh invitation; the same envelope can never be replayed to roll credentials back.
        setup = SetupKey(invitation: setup.invitation, privateKey: Data(), consumed: true)
        try SleepWebhookKeychain.save(JSONEncoder().encode(setup), account: "setup")
        try configure(value)
        try? retireConsumedSetup()
        setMessage("Credentials stored in Keychain · delivery is off")
    }
    private func retireConsumedSetup() throws {
        guard let data = try SleepWebhookKeychain.read("setup") else { return }
        let setup = try JSONDecoder().decode(SetupKey.self, from: data)
        guard setup.consumed else { return }
        if !setup.privateKey.isEmpty {
            let retired = SetupKey(invitation: setup.invitation, privateKey: Data(), consumed: true)
            try SleepWebhookKeychain.save(JSONEncoder().encode(retired), account: "setup")
        }
        let source = documents.appendingPathComponent("dhoop-webhook-setup-sealed.json")
        if FileManager.default.fileExists(atPath: source.path) {
            let destination = store.url.deletingLastPathComponent().appendingPathComponent("consumed-" + setup.invitation.setupId + ".sealed")
            // Non-destructive quarantine under the backup-excluded outbox directory. The key is gone.
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }
    func handleDebugSetup(model: AppModel) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        do {
            if args.contains("--prepare-sleep-webhook") { try prepareSecureSetup() }
            if args.contains("--import-sleep-webhook") { try importSecureSetup() }
            if args.contains("--enable-sleep-webhook") { try setEnabled(true); enqueue(model: model, force: true) }
            if args.contains("--send-sleep-webhook") { enqueue(model: model, force: true) }
            if args.contains("--sleep-webhook-status") { writeStatus() }
        } catch { setMessage(Self.safeMessage(error)) }
        #endif
    }
    private func writeStatus() {
        #if DEBUG
        struct Status: Encodable {
            let enabled: Bool; let message: String; let installationId: String
            let revision: Int; let pending: Bool; let lastAcceptedAt: Date?
            let eventId: String?; let wakeDate: String?; let acceptedRevision: Int?; let outcome: String?
        }
        let d = checkpoint.delivery
        let safe = Status(enabled: checkpoint.enabled, message: checkpoint.message, installationId: d.installationId,
            revision: d.revision, pending: d.pending != nil, lastAcceptedAt: d.lastAcceptedAt,
            eventId: d.lastAcceptedEvent?.eventId, wakeDate: d.lastAcceptedEvent?.wakeDate,
            acceptedRevision: d.lastAcceptedEvent?.revision, outcome: d.lastOutcome)
        try? JSONEncoder().encode(safe).write(to: documents.appendingPathComponent("dhoop-webhook-status.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #endif
    }
}
#endif
