#if os(iOS)
import Foundation
import UIKit
import Combine

/// Opt-in Life receiver with bounded foreground and actual Bluetooth-wake inbox recovery.
@MainActor
final class RemoteBuzzClient: ObservableObject {
    static let shared = RemoteBuzzClient()
    @Published private(set) var status = "Remote alerts are off" {
        didSet { writeDebugSnapshotIfRequested() }
    }
    @Published private(set) var invitationJSON: String?
    @Published private(set) var state = RemoteBuzzState()
    @Published private(set) var paired = false
    @Published private(set) var registrationStatus = "Not registered with Life" {
        didSet { writeDebugSnapshotIfRequested() }
    }
    @Published private(set) var inboxStatus = "Missed requests checked when Dhoop has execution time" {
        didSet { writeDebugSnapshotIfRequested() }
    }
    private var inboxChecks = 0
    private var lastInboxCheckedAt: Int?
    private var lastInboxTrigger: String?
    private weak var model: AppModel?
    private var enrollment: RemoteBuzzEnrollment?
    private var loaded = false
    private var subscription: AnyCancellable?
    private var wakeSubscriptions = Set<AnyCancellable>()
    private var inboxPolicy = RemoteBuzzInboxPolicy()
    private var inboxTask: Task<Void, Never>?
    private var foregroundTask: Task<Void, Never>?
    private var foregroundToken: UUID?
    private var foreground = false
    private var retryTask: Task<Void, Never>?
    private var flushing = false
    private let transport = RemoteBuzzTransport()
    private let stateFile = RemoteBuzzStateFile(file: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("Dhoop/RemoteBuzz/state-v2.json"))
    private let credentialsAccount = "remote-buzz-enrollment-v2"
    private let pairingAccount = "remote-buzz-pairing-v2"
    private let updateAccount = "remote-buzz-update-v2"
    private let tokenAccount = "remote-buzz-token-v2"

    private struct PendingUpdate: Codable {
        let bytes: Data
        let revision: Int
        let op: String
        let createdAt: Int
        var attempts = 0
        var lastAttemptAt: Int?
        func mayAttempt(now: Int) -> Bool {
            attempts < 10 && now >= createdAt && now - createdAt < 3600
                && (lastAttemptAt.map { now >= $0 + 30 } ?? true)
        }
    }

    func attach(model: AppModel) {
        self.model = model
        do {
            state = try stateFile.load()
            if let bytes = try SleepWebhookKeychain.read(credentialsAccount), !bytes.isEmpty {
                enrollment = try JSONDecoder().decode(RemoteBuzzEnrollment.self, from: bytes)
            }
            if enrollment == nil {
                var next = state; next.enabled = false
                try persist(next)
            }
            paired = enrollment != nil
            loaded = true
            status = state.revoked ? "Connection revoked on this phone" : state.enabled ? "Phone permits remote alerts" : "Remote alerts are off"
            subscription = model.ble.buzzDelivery.$cues.sink { [weak self] cues in
                Task { @MainActor in self?.collectDeliveryEvidence(cues) }
            }
            wakeSubscriptions.removeAll()
            model.live.$connectSettled.dropFirst().sink { [weak self] _ in
                self?.requestInboxFetch(.reconnect)
            }.store(in: &wakeSubscriptions)
            model.live.$lastFrameType.dropFirst().sink { [weak self] value in
                if value != nil { self?.requestInboxFetch(.bluetooth) }
            }.store(in: &wakeSubscriptions)
            if paired { UIApplication.shared.registerForRemoteNotifications() }
            scheduleFlush()
            setForeground(UIApplication.shared.applicationState == .active)
            #if DEBUG
            // Explicit developer action only. This creates a public invitation, never a grant.
            if CommandLine.arguments.contains("--life-buzz-prepare") { preparePairing() }
            writeDebugSnapshotIfRequested()
            #endif
        } catch {
            loaded = false; status = "Stored alert state could not be read. Alerts are blocked."
        }
    }

    // Read the signed provisioning profile's entitlement; installation checks additionally inspect
    // effective codesign entitlements. No token-shape guess or default Sandbox environment.
    private func signedEnvironment() throws -> String {
        guard Bundle.main.bundleIdentifier == RemoteBuzzV2.topic,
              let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        else { throw RemoteBuzzEnrollmentError.invalid }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 1_048_576,
              let start = bytes.range(of: Data("<?xml".utf8)),
              let end = bytes.range(of: Data("</plist>".utf8), in: start.lowerBound..<bytes.endIndex),
              let profile = try PropertyListSerialization.propertyList(from: bytes[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any],
              entitlements["application-identifier"] as? String == "8MSX699Z2T." + RemoteBuzzV2.topic,
              let environment = entitlements["aps-environment"] as? String,
              ["development", "production"].contains(environment)
        else { throw RemoteBuzzEnrollmentError.invalid }
        return environment == "development" ? "sandbox" : "production"
    }

    func preparePairing() {
        do {
            guard loaded, enrollment == nil else { throw RemoteBuzzEnrollmentError.invalid }
            let identityAccount = "remote-buzz-installation-v2"
            let installationId: String
            if let bytes = try SleepWebhookKeychain.read(identityAccount),
               let existing = String(data: bytes, encoding: .utf8), RemoteBuzzV2.uuid(existing) {
                installationId = existing
            } else {
                installationId = UUID().uuidString.lowercased()
                try SleepWebhookKeychain.save(Data(installationId.utf8), account: identityAccount)
            }
            let pairing = try RemoteBuzzPairing.create(installationId: installationId,
                environment: signedEnvironment(), now: Date())
            try SleepWebhookKeychain.save(JSONEncoder().encode(pairing), account: pairingAccount)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            invitationJSON = String(data: try encoder.encode(pairing.invitation), encoding: .utf8)
            status = "Public pairing invitation ready for Life. Expires in ten minutes."
        } catch { status = "Could not prepare pairing. Check signing and existing connection." }
    }

    func importEnvelope(_ bytes: Data) {
        do {
            guard loaded, enrollment == nil, bytes.count <= 8192,
                  let pairingBytes = try SleepWebhookKeychain.read(pairingAccount), !pairingBytes.isEmpty
            else { throw RemoteBuzzEnrollmentError.invalid }
            let pairing = try JSONDecoder().decode(RemoteBuzzPairing.self, from: pairingBytes)
            let box = try JSONDecoder().decode(RemoteBuzzEnvelope.self, from: bytes)
            let value = try box.open(pairing: pairing, now: Date())
            guard value.environment == (try signedEnvironment()) else { throw RemoteBuzzEnrollmentError.invalid }
            // Preserve installation-wide receipt sequence/revisions and prior evidence across re-pairing.
            var next = state; next.enabled = false; next.revoked = false
            try persist(next)
            try SleepWebhookKeychain.save(JSONEncoder().encode(value), account: credentialsAccount)
            enrollment = value; paired = true; invitationJSON = nil
            try SleepWebhookKeychain.save(Data(), account: pairingAccount)
            status = "Paired with Life. Remote alerts remain off until you enable them."
            UIApplication.shared.registerForRemoteNotifications()
        } catch { status = "Pairing failed. Keep the envelope and create a fresh invitation if expired." }
    }

    func pairingURL() -> URL? {
        do {
            guard let invitationJSON else { throw RemoteBuzzEnrollmentError.invalid }
            let invitation = try JSONDecoder().decode(RemoteBuzzInvitation.self, from: Data(invitationJSON.utf8))
            return try RemoteBuzzPairingLinks.invitationURL(invitation, now: Date())
        } catch { status = "Create a fresh pairing invitation before opening Life."; return nil }
    }
    func importPairingURL(_ url: URL) {
        do {
            importEnvelope(try RemoteBuzzPairingLinks.envelope(from: url))
            NotificationCenter.default.post(name: RemoteBuzzPairingLinks.importedNotification, object: nil)
        } catch { status = "Pairing link rejected. Use the encrypted response file instead." }
    }

    func registered(_ token: Data) {
        do {
            try SleepWebhookKeychain.save(token, account: tokenAccount)
            guard loaded, let enrollment, !state.revoked,
                  enrollment.environment == (try signedEnvironment()) else { return }
            try queueUpdate(op: "register")
            scheduleFlush()
        } catch { registrationStatus = "Could not save push registration. Retry in Settings." }
    }
    func registrationFailed() { registrationStatus = "Apple push registration failed" }

    func setEnabled(_ enabled: Bool) {
        do {
            guard loaded, enrollment != nil, !state.revoked else { throw RemoteBuzzEnrollmentError.invalid }
            var next = state; next.enabled = enabled
            try persist(next)
            if !enabled {
                model?.ble.buzzDelivery.cancel(owner: "remote-life")
                inboxTask?.cancel(); stopForegroundChecks()
            }
            status = enabled ? "Phone permits remote alerts. Life must also allow sends." : "Remote alerts disabled on this phone"
            try queueUpdate(op: enabled ? "register" : "disable")
            scheduleFlush()
            if enabled { startForegroundChecks() }
        } catch {
            if enabled {
                var next = state; next.enabled = false
                try? persist(next)
            }
            status = "Could not update Life permission. Phone alerts are blocked until setup succeeds."
        }
    }
    func revoke() {
        // Stop local effects before any network work; retain credential solely to retry revocation.
        do {
            guard loaded, enrollment != nil else { throw RemoteBuzzEnrollmentError.invalid }
            var next = state; next.enabled = false; next.revoked = true
            try persist(next)
            model?.ble.buzzDelivery.cancel(owner: "remote-life")
            inboxTask?.cancel(); stopForegroundChecks()
            status = "Revoked on phone; updating Life"
            try queueUpdate(op: "revoke")
            scheduleFlush()
        } catch { status = "Revocation could not be saved. Disable in Life Settings as well." }
    }

    private func persist(_ next: RemoteBuzzState) throws {
        try stateFile.save(next)
        state = next
        writeDebugSnapshotIfRequested()
    }

    /// One-shot developer diagnostics expose only public setup and delivery state.
    private func writeDebugSnapshotIfRequested() {
        #if DEBUG
        guard loaded, CommandLine.arguments.contains("--life-buzz-diagnostics")
            || CommandLine.arguments.contains("--life-buzz-prepare") else { return }
        struct Snapshot: Encodable {
            let version: Int
            let capturedAt: Int
            let paired: Bool
            let enabled: Bool
            let revoked: Bool
            let enrollmentId: String?
            let installationId: String?
            let status: String
            let registrationStatus: String
            let inboxStatus: String
            let inboxChecks: Int
            let lastInboxCheckedAt: Int?
            let lastInboxTrigger: String?
            let deviceRevision: Int
            let eventCount: Int
            let receiptCount: Int
            let invitation: RemoteBuzzInvitation?
        }
        do {
            let invitation = invitationJSON.flatMap { try? JSONDecoder().decode(RemoteBuzzInvitation.self, from: Data($0.utf8)) }
            let snapshot = Snapshot(version: 1, capturedAt: Int(Date().timeIntervalSince1970), paired: paired,
                enabled: state.enabled, revoked: state.revoked, enrollmentId: enrollment?.enrollmentId,
                installationId: enrollment?.installationId ?? invitation?.installationId,
                status: status, registrationStatus: registrationStatus,
                inboxStatus: inboxStatus, inboxChecks: inboxChecks, lastInboxCheckedAt: lastInboxCheckedAt,
                lastInboxTrigger: lastInboxTrigger, deviceRevision: state.deviceRevision,
                eventCount: state.events.count, receiptCount: state.receipts.count, invitation: invitation)
            var file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dhoop-life-buzz-diagnostics.json")
            try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try file.setResourceValues(resources)
        } catch {
            // Diagnostics never block pairing/delivery or alter the user-facing registration result.
        }
        #endif
    }
    private func queueUpdate(op: String) throws {
        guard let enrollment else { throw RemoteBuzzEnrollmentError.invalid }
        var next = state
        let revision = try next.nextRevision()
        var body: [String: Any] = ["version": 2, "op": op, "enrollmentId": enrollment.enrollmentId,
            "generation": enrollment.generation, "installationId": enrollment.installationId, "deviceRevision": revision]
        if op == "register" {
            guard let token = try SleepWebhookKeychain.read(tokenAccount), !token.isEmpty else {
                UIApplication.shared.registerForRemoteNotifications()
                registrationStatus = "Waiting for Apple push token"
                return
            }
            body["token"] = token.map { String(format: "%02x", $0) }.joined()
            body["topic"] = enrollment.topic; body["environment"] = enrollment.environment; body["enabled"] = next.enabled
        }
        try persist(next)
        let pending = PendingUpdate(bytes: try JSONSerialization.data(withJSONObject: body), revision: revision,
            op: op, createdAt: Int(Date().timeIntervalSince1970))
        try SleepWebhookKeychain.save(JSONEncoder().encode(pending), account: updateAccount)
        registrationStatus = "Life update pending"
    }

    func receive(_ body: [String: Any], transport source: String = "apns") -> UIBackgroundFetchResult {
        do {
            guard loaded, let model, let enrollment,
                  JSONSerialization.isValidJSONObject(body) else { return .noData }
            let bytes = try JSONSerialization.data(withJSONObject: body)
            guard bytes.count <= 2048 else { return .noData }
            let command = try JSONDecoder().decode(RemoteBuzzCommandV2.self, from: bytes)
            let now = Int(Date().timeIntervalSince1970)
            let appState: String
            switch UIApplication.shared.applicationState {
            case .active: appState = "foreground"
            case .background: appState = "background"
            default: appState = "inactive"
            }
            var next = state
            let dispatch = try next.consume(command, enrollment: enrollment, now: now,
                connected: model.ble.buzzDelivery.link().ready,
                exerciseOwnsBuzz: model.ble.buzzDelivery.exclusiveOwner != nil, transport: source, appState: appState)
            try persist(next)
            // A fresh authenticated push is evidence connectivity recovered; no extra fetch is needed.
            if source == "apns", command.fresh(now: Date()) { inboxPolicy.finish(success: true, commandCount: 1) }
            if dispatch {
                model.requestBuzz(owner: "remote-life", id: "life|" + command.eventId, loops: UInt8(command.loops),
                    due: Date(), grace: min(2, Double(command.expiresAt - now)))
            }
            scheduleFlush()
            return dispatch ? .newData : .noData
        } catch { status = "Incoming alert rejected or could not be saved"; return .failed }
    }

    private func collectDeliveryEvidence(_ cues: [BuzzDeliveryCoordinator.Cue]) {
        guard loaded, let enrollment else { return }
        var next = state
        do {
            for cue in cues where cue.owner == "remote-life" && cue.id.hasPrefix("life|") {
                let eventId = String(cue.id.dropFirst(5))
                guard next.events.contains(where: { $0.id == eventId && $0.enrollmentId == enrollment.enrollmentId }) else { continue }
                let evidence: (String, String)?
                switch cue.status {
                case .requested: evidence = cue.sequence != nil && cue.opcode != nil ? ("strap_requested", "requested") : nil
                case .responseReceived: evidence = ("strap_response", "response_received")
                case .acknowledged: evidence = ("strap_response", "acknowledged")
                case .rejected: evidence = ("strap_response", "rejected")
                case .unavailable: evidence = ("strap_requested", "unavailable")
                case .confirmed: evidence = ("wearer_confirmed", "felt")
                case .notFelt: evidence = ("wearer_confirmed", "not_felt")
                default: evidence = nil
                }
                if let evidence {
                    try next.appendReceipt(eventId: eventId, enrollment: enrollment,
                        stage: evidence.0, outcome: evidence.1, now: Int(Date().timeIntervalSince1970))
                }
            }
            guard next != state else { return }
            try persist(next)
            scheduleFlush()
        } catch { status = "Delivery evidence could not be saved" }
    }
    func confirm(eventId: String, felt: Bool) {
        do {
            guard loaded, let enrollment,
                  state.receipts.contains(where: { $0.receipt.eventId == eventId && $0.receipt.stage == "strap_requested" && $0.receipt.outcome == "requested" })
            else { throw RemoteBuzzEnrollmentError.invalid }
            var next = state
            try next.appendReceipt(eventId: eventId, enrollment: enrollment, stage: "wearer_confirmed",
                outcome: felt ? "felt" : "not_felt", now: Int(Date().timeIntervalSince1970))
            try persist(next)
            model?.ble.buzzDelivery.recordWearerConfirmation(id: "life|" + eventId, felt: felt)
            scheduleFlush()
        } catch { status = "Could not save your vibration confirmation" }
    }

    func retryPending() { scheduleFlush() }
    func checkInbox() { requestInboxFetch(.manual) }
    func setForeground(_ value: Bool) {
        foreground = value
        if value { startForegroundChecks() } else { stopForegroundChecks() }
    }
    private func stopForegroundChecks() {
        foregroundTask?.cancel(); foregroundTask = nil; foregroundToken = nil
    }
    private func startForegroundChecks() {
        guard foreground, loaded, state.enabled, !state.revoked, foregroundTask == nil else { return }
        let token = UUID(); foregroundToken = token
        requestInboxFetch(.foreground)
        foregroundTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(600)
            defer { if self.foregroundToken == token { self.foregroundTask = nil; self.foregroundToken = nil } }
            // Ten minutes maximum per foreground window, cancelled on leaving the foreground.
            for _ in 0..<40 {
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                guard !Task.isCancelled, self.foreground, Date() < deadline else { return }
                self.requestInboxFetch(.foregroundTimer)
            }
        }
    }
    private func requestInboxFetch(_ trigger: RemoteBuzzInboxPolicy.Trigger) {
        guard loaded, state.enabled, !state.revoked, let enrollment, let model, inboxTask == nil,
              model.ble.buzzDelivery.link().ready, model.ble.buzzDelivery.exclusiveOwner == nil,
              inboxPolicy.begin(trigger, now: Date()) else { return }
        inboxTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inboxTask = nil }
            do {
                let now = Int(Date().timeIntervalSince1970)
                let seen = Array(self.state.events.filter { $0.enrollmentId == enrollment.enrollmentId && $0.expiresAt > now }
                    .suffix(128).map(\.id))
                let body: [String: Any] = ["version": 2, "op": "inbox", "enrollmentId": enrollment.enrollmentId,
                    "generation": enrollment.generation, "installationId": enrollment.installationId, "seenEventIds": seen]
                let reply = try await self.transport.send(JSONSerialization.data(withJSONObject: body), enrollment: enrollment,
                    timeout: UIApplication.shared.applicationState == .active ? 15 : 7)
                try Task.checkCancellation()
                let batch = try JSONDecoder().decode(RemoteBuzzInboxResponse.self,
                    from: JSONSerialization.data(withJSONObject: reply))
                guard self.state.enabled, !self.state.revoked, self.enrollment?.enrollmentId == enrollment.enrollmentId,
                      batch.valid(for: enrollment)
                else { throw RemoteBuzzEnrollmentError.invalid }
                var received = 0
                for command in batch.commands {
                    try Task.checkCancellation()
                    // The identical signed-command funnel persists dedup before any BLE dispatch.
                    guard let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any]
                    else { throw RemoteBuzzEnrollmentError.invalid }
                    if self.receive(body, transport: "inbox") == .newData { received += 1 }
                }
                self.inboxPolicy.finish(success: true, commandCount: batch.commands.count)
                self.inboxChecks += 1; self.lastInboxCheckedAt = Int(Date().timeIntervalSince1970)
                self.lastInboxTrigger = trigger.rawValue
                self.inboxStatus = "Inbox checked \(Date().formatted(date: .omitted, time: .standard)) · \(received) new requests accepted locally"
            } catch is CancellationError {
                self.inboxStatus = "Inbox check cancelled"
            } catch {
                self.inboxPolicy.finish(success: false, commandCount: 0)
                self.inboxStatus = "Inbox check unavailable; adaptive retry at the next execution opportunity"
            }
        }
    }
    private func scheduleFlush() {
        guard loaded, enrollment != nil, retryTask == nil else { return }
        // One bounded outbox pass, triggered by an actual event. No background keepalive or monitor.
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.retryTask = nil }
            for _ in 0..<10 {
                guard !Task.isCancelled else { return }
                await self.flushOnce()
                let now = Int(Date().timeIntervalSince1970)
                let pending = (try? SleepWebhookKeychain.read(self.updateAccount)).flatMap { try? JSONDecoder().decode(PendingUpdate.self, from: $0) }
                let hasWork = (pending.map { $0.attempts < 10 && now - $0.createdAt < 3600 } ?? false)
                    || self.state.receipts.contains { !$0.acknowledged && $0.attempts < 10 && now - $0.receipt.observedAt < 3600 }
                guard hasWork else { return }
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            }
        }
    }
    private func flushOnce() async {
        guard !flushing, let enrollment else { return }
        flushing = true
        defer { flushing = false }
        let now = Int(Date().timeIntervalSince1970)
        do {
            if let bytes = try SleepWebhookKeychain.read(updateAccount), !bytes.isEmpty {
                var pending = try JSONDecoder().decode(PendingUpdate.self, from: bytes)
                if pending.mayAttempt(now: now) {
                    pending.attempts += 1; pending.lastAttemptAt = now
                    try SleepWebhookKeychain.save(JSONEncoder().encode(pending), account: updateAccount)
                    let ack = try await transport.send(pending.bytes, enrollment: enrollment)
                    guard ack["version"] as? Int == 2, ack["enrollmentId"] as? String == enrollment.enrollmentId,
                          ack["deviceRevision"] as? Int == pending.revision, ack["status"] as? String == "accepted",
                          let outcome = ack["outcome"] as? String, ["updated", "duplicate", "stale", "revoked"].contains(outcome)
                    else { throw RemoteBuzzEnrollmentError.invalid }
                    if state.deviceRevision == pending.revision {
                        try SleepWebhookKeychain.save(Data(), account: updateAccount)
                        registrationStatus = outcome == "stale" ? "Life has a newer device update" : "Life received device update"
                        if pending.op == "register" && state.enabled { requestInboxFetch(.reconnect) }
                        if pending.op == "revoke" && ["revoked", "duplicate"].contains(outcome) {
                            try SleepWebhookKeychain.save(Data(), account: credentialsAccount)
                            self.enrollment = nil; paired = false
                            status = "Life connection revoked"
                            return
                        }
                    }
                }
            }
            for id in state.receipts.filter({ $0.mayAttempt(now: now) && $0.receipt.enrollmentId == enrollment.enrollmentId }).map(\.id) {
                guard let index = state.receipts.firstIndex(where: { $0.id == id }) else { continue }
                var next = state
                next.receipts[index].attempts += 1; next.receipts[index].lastAttemptAt = now
                try persist(next)
                let receipt = state.receipts[index].receipt
                let ack = try await transport.send(JSONEncoder().encode(receipt), enrollment: enrollment)
                guard ack["version"] as? Int == 2, ack["receiptId"] as? String == receipt.receiptId,
                      ack["eventId"] as? String == receipt.eventId, ack["sequence"] as? Int == receipt.sequence,
                      ack["status"] as? String == "accepted", ["stored", "duplicate"].contains(ack["outcome"] as? String ?? "")
                else { throw RemoteBuzzEnrollmentError.invalid }
                guard let current = state.receipts.firstIndex(where: { $0.id == id }) else { continue }
                next = state; next.receipts[current].acknowledged = true
                try persist(next)
            }
        } catch { registrationStatus = "Life update not confirmed; bounded retry pending" }
    }
}
#endif
