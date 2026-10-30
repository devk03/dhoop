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
    @Published private(set) var checkResult: String?
    private var worker: Task<Void, Never>?
    private var generation = 0
    private var runAgain = false
    private var forceAgain = false
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
    var hasProteinCredentials: Bool { (try? credentials().hasProteinBearer) == true }
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
        next.enabled = false; next.proteinEnabled = false; next.caloriesEnabled = false; next.failures = 0; next.nextAttempt = nil; next.message = "Connection saved · automatic delivery is off"
        // Persist the disabled destination BEFORE changing its credentials; a crash cannot accidentally
        // send an old pending event with credentials meant for a different endpoint.
        try commit(next)
        try SleepWebhookKeychain.save(JSONEncoder().encode(value), account: "credentials")
        UserDefaults.standard.set(false, forKey: NutritionGoalClient.enabledKey)
        NutritionGoalClient.shared.connectionDidChange()
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { _ = try credentials() }
        var next = checkpoint; next.enabled = enabled; next.nextAttempt = nil
        next.message = enabled ? "Verified sleep sends after processing" : "Sleep delivery is off"
        try commit(next); checkResult = nil; generation += 1; worker?.cancel()
        SleepWebhookScheduler.update(enabled: checkpoint.anyEnabled)
    }
    func setProteinEnabled(_ enabled: Bool) throws {
        if enabled { guard try credentials().hasProteinBearer else { throw SleepWebhookFailure.credentials } }
        var next = checkpoint; next.version = 2; next.proteinEnabled = enabled; next.proteinNextAttempt = nil
        next.proteinMessage = enabled ? "Protein sends after the day ends" : "Protein delivery is off"
        try commit(next); checkResult = nil; generation += 1; worker?.cancel()
        SleepWebhookScheduler.update(enabled: checkpoint.anyEnabled)
    }
    func setCaloriesEnabled(_ enabled: Bool) throws {
        if enabled { guard try credentials().hasProteinBearer else { throw SleepWebhookFailure.credentials } }
        var next = checkpoint; next.caloriesEnabled = enabled
        try commit(next); generation += 1; worker?.cancel()
    }
    func enqueue(model: AppModel, force: Bool = false) {
        guard checkpoint.anyEnabled else { return }
        if worker != nil { runAgain = true; forceAgain = forceAgain || force; return }
        worker = Task(priority: .utility) { [weak self, weak model] in
            guard let self, let model else { return }
            _ = await self.deliver(model: model, force: force)
            self.worker = nil
            if self.runAgain {
                let forceNext = self.forceAgain
                self.runAgain = false; self.forceAgain = false
                self.enqueue(model: model, force: forceNext)
            }
        }
    }
    struct ActionFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    /// A manual check awaits one bounded pass. Queueing work is not delivery completion.
    func sendAvailableSummaries(model: AppModel) async throws {
        guard !isSending, worker == nil else { throw ActionFailure(message: "A summary check is already in progress. Wait for it to finish.") }
        guard !storageUnavailable, checkpoint.anyEnabled else {
            throw ActionFailure(message: "Summary delivery is unavailable or off. Saved events remain on this phone.")
        }
        checkResult = nil
        let previousSleep = checkpoint.delivery.lastAcceptedEvent?.eventId
        let previousProtein = checkpoint.delivery.lastAcceptedProtein?.eventId
        let completed = await deliver(model: model, force: true)
        try Task.checkCancellation()
        guard completed else {
            checkResult = "Some summaries could not be sent. Review their status and retry."
            throw ActionFailure(message: "The summary check encountered an interruption. Check the Sleep and Protein delivery statuses. Received summaries stay acknowledged; pending events are retained.")
        }
        if previousSleep != checkpoint.delivery.lastAcceptedEvent?.eventId || previousProtein != checkpoint.delivery.lastAcceptedProtein?.eventId {
            checkResult = "Life confirmed receipt. Any manual values it kept are shown below."
        } else if checkpoint.sleepBacklog == true {
            checkResult = "Checked. More summaries may be waiting; check again later."
        } else { checkResult = "Checked. No new summaries are ready to send." }
    }
    func deliver(model: AppModel, force: Bool = false) async -> Bool {
        guard !isSending, !storageUnavailable, checkpoint.anyEnabled else { return true }
        isSending = true
        let ticket = generation
        defer { isSending = false; SleepWebhookScheduler.update(enabled: checkpoint.anyEnabled) }
        var success = true
        // Newest first, then oldest outstanding: four bounded requests at most. The second slot
        // prevents old corrections starving when one new completed day arrives every day.
        for (protein, oldestFirst) in [(false, false), (true, false), (false, true), (true, true)] {
            let enabled = protein ? checkpoint.proteinEnabled == true : checkpoint.enabled
            let deadline = protein ? checkpoint.proteinNextAttempt : checkpoint.nextAttempt
            guard enabled, force || SleepWebhookPolicy.canSend(enabled: enabled, timeZone: .current, nextAttempt: deadline, now: Date()) else { continue }
            do {
                try Task.checkCancellation()
                guard ticket == generation else { return false }
                let secret = try credentials()
                if protein, !secret.hasProteinBearer { throw SleepWebhookFailure.credentials }
                var next = checkpoint
                let selectionTime = Date()
                let completed = SleepWebhookPolicy.completedDays(now: selectionTime)
                let sleepDays = SleepWebhookPolicy.sleepWakeDays(now: selectionTime)
                if protein {
                    if next.caloriesEnabled != true, next.delivery.proteinPending?.event.calorieSummary != nil {
                        next.proteinMessage = "A prepared calorie summary is paused while calorie export is off."
                        try commit(next); continue
                    }
                    if next.delivery.proteinPending == nil {
                        let includeCalories = next.caloriesEnabled == true
                        let all = try ProteinWebhookProjection.savedEntries(includeCalories: includeCalories)
                        let summaries = try ProteinWebhookProjection.summaries(entries: all,
                            acknowledged: next.delivery.proteinAcknowledged ?? [:], from: completed.from, to: completed.through, includeCalories: includeCalories)
                        let differences = summaries.filter { $0.day <= completed.through && next.delivery.proteinAcknowledged?[$0.day] != $0 }
                        next.proteinBacklog = differences.count > 1
                        guard let candidate = oldestFirst ? differences.last : differences.first else {
                            next.proteinFailures = 0; next.proteinNextAttempt = nil
                            if next.delivery.lastAcceptedProtein == nil {
                                next.proteinMessage = "No protein logged for a completed day. Manual entry on Life is available."
                            } else { next.proteinMessage = "No new protein summaries ready" }
                            try commit(next); continue
                        }
                        next.version = 2; _ = try next.delivery.prepareProtein(candidate)
                        next.proteinMessage = "Sending completed-day protein"
                        try commit(next)
                    }
                    guard let pending = checkpoint.delivery.proteinPending, pending.event.day <= completed.through else { continue }
                    let response = try await SleepWebhookTransport().send(pending.bytes, credentials: secret, protein: true)
                    try Task.checkCancellation(); guard ticket == generation else { return false }
                    next = checkpoint; try next.delivery.acceptProtein(response)
                    next.proteinFailures = 0; next.proteinNextAttempt = nil
                    next.proteinMessage = next.delivery.proteinOutcome == "manual_preserved"
                        ? "Received by Life · manual protein preserved" : "Protein received by Life"
                } else {
                    if next.delivery.pending == nil {
                        let before = SleepExportReadiness(computing: model.intelligence.computing,
                            rescoreOwed: RescoreBackgroundScheduler.isRescoreOwed, generation: RescoreBackgroundScheduler.currentOwedToken,
                            completedPass: RescoreBackgroundScheduler.isOwedAfterCompletedPass)
                        guard let healthStore = await model.repo.storeHandle() else { throw SleepWebhookFailure.storage }
                        let ids = await model.repo.sleepComparisonSourceIds().filter { !$0.hasSuffix("-noop") }
                        let rows = try await healthStore.verifiedWhoopSleepTotals(rawSourceIds: ids, from: sleepDays.from, to: sleepDays.through)
                        try Task.checkCancellation()
                        guard ticket == generation, checkpoint.enabled else { return false }
                        next = checkpoint
                        let after = SleepExportReadiness(computing: model.intelligence.computing,
                            rescoreOwed: RescoreBackgroundScheduler.isRescoreOwed, generation: RescoreBackgroundScheduler.currentOwedToken,
                            completedPass: RescoreBackgroundScheduler.isOwedAfterCompletedPass)
                        let waiting = rows.contains { $0.estimated && !before.allows(estimated: true, after: after) }
                        let candidates = rows.reversed().filter { before.allows(estimated: $0.estimated, after: after) }.map { SleepWebhookSummary(wakeDate: $0.day, sleepMinutes: $0.minutes,
                            method: $0.estimated ? "dhoop_estimate" : "whoop_import", timeZone: "America/Los_Angeles") }
                        let differences = candidates.filter { next.delivery.acknowledged[$0.wakeDate] != $0 }
                        next.sleepBacklog = differences.count > 1 || waiting
                        guard let candidate = oldestFirst ? differences.last : differences.first else {
                            next.failures = 0; next.nextAttempt = nil
                            if waiting { next.message = "Waiting for sleep processing" }
                            else { next.message = "No new sleep summaries ready" }
                            try commit(next); continue
                        }
                        _ = try next.delivery.prepare(candidate); next.message = "Sending verified sleep summary"
                        try commit(next)
                    }
                    guard let pending = checkpoint.delivery.pending, pending.event.wakeDate <= sleepDays.through else { continue }
                    let response = try await SleepWebhookTransport().send(pending.bytes, credentials: secret)
                    try Task.checkCancellation(); guard ticket == generation else { return false }
                    next = checkpoint; try next.delivery.accept(response)
                    next.failures = 0; next.nextAttempt = nil
                    next.message = next.delivery.lastOutcome == "manual_preserved"
                        ? "Received by Life · manual sleep preserved" : "Sleep received by Life"
                }
                try commit(next)
            } catch is CancellationError { return false }
            catch {
                success = false
                guard ticket == generation else { return false }
                var next = checkpoint
                if protein {
                    next.proteinFailures = min((next.proteinFailures ?? 0) + 1, 100)
                    next.proteinNextAttempt = Date().addingTimeInterval(SleepWebhookPolicy.retryDelay(failures: next.proteinFailures!))
                    next.proteinMessage = Self.safeMessage(error)
                } else {
                    next.failures = min(next.failures + 1, 100)
                    next.nextAttempt = Date().addingTimeInterval(SleepWebhookPolicy.retryDelay(failures: next.failures))
                    next.message = Self.safeMessage(error)
                }
                do { try commit(next) }
                catch { checkpoint.message = "Delivery state could not be saved. Export is paused."; storageUnavailable = true; return false }
            }
        }
        return success
    }
    private func setMessage(_ message: String) {
        guard checkpoint.message != message else { return }
        var next = checkpoint; next.message = message
        do { try commit(next) }
        catch { storageUnavailable = true; checkpoint.message = "Delivery state could not be saved. Export is paused." }
    }
    static func safeMessage(_ error: Error) -> String {
        guard let failure = error as? SleepWebhookFailure else { return "Connection interrupted. Your pending summary is saved for retry." }
        switch failure {
        case .http(let code): return [401, 403].contains(code) ? "Life access was denied. Review the connection settings; your pending summary is saved." : "Life returned HTTP \(code). Your pending summary is saved; retry when connected."
        case .receiver(_, let code): return code.guidance
        case .invalidSummary: return "A local record is invalid. Check the logged values; nothing was acknowledged."
        case .credentials: return "Credentials unavailable. Unlock the phone or update the connection."
        case .invalidAcknowledgement, .responseTooLarge: return "Life's receipt could not be verified. Your pending summary is saved for retry."
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
            if args.contains("--enable-protein-webhook") { try setProteinEnabled(true); enqueue(model: model, force: true) }
            if args.contains("--send-sleep-webhook") { enqueue(model: model, force: true) }
            if args.contains("--sleep-webhook-status") { writeStatus() }
        } catch { setMessage(Self.safeMessage(error)) }
        #endif
    }
    private func writeStatus() {
        #if DEBUG
        struct Status: Encodable {
            let enabled: Bool; let message: String; let installationId: String
            let proteinEnabled: Bool; let proteinMessage: String?; let proteinPending: Bool
            let proteinEventId: String?; let proteinDay: String?; let proteinRevision: Int?; let proteinOutcome: String?
            let revision: Int; let pending: Bool; let lastAcceptedAt: Date?
            let eventId: String?; let wakeDate: String?; let acceptedRevision: Int?; let outcome: String?
        }
        let d = checkpoint.delivery
        let safe = Status(enabled: checkpoint.enabled, message: checkpoint.message, installationId: d.installationId,
            proteinEnabled: checkpoint.proteinEnabled == true, proteinMessage: checkpoint.proteinMessage, proteinPending: d.proteinPending != nil,
            proteinEventId: d.lastAcceptedProtein?.eventId, proteinDay: d.lastAcceptedProtein?.day,
            proteinRevision: d.lastAcceptedProtein?.revision, proteinOutcome: d.proteinOutcome,
            revision: d.revision, pending: d.pending != nil, lastAcceptedAt: d.lastAcceptedAt,
            eventId: d.lastAcceptedEvent?.eventId, wakeDate: d.lastAcceptedEvent?.wakeDate,
            acceptedRevision: d.lastAcceptedEvent?.revision, outcome: d.lastOutcome)
        try? JSONEncoder().encode(safe).write(to: documents.appendingPathComponent("dhoop-webhook-status.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #endif
    }
}
#endif
