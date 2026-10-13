import Foundation

struct RemoteBuzzReceipt: Codable, Equatable, Identifiable {
    let version: Int
    let op: String
    let receiptId: String
    let enrollmentId: String
    let generation: Int
    let installationId: String
    let eventId: String
    let sequence: Int
    let observedAt: Int
    let stage: String
    let outcome: String
    let transport: String?
    let appState: String?
    var id: String { receiptId }
    init(receiptId: String, enrollmentId: String, generation: Int, installationId: String,
         eventId: String, sequence: Int, observedAt: Int, stage: String, outcome: String,
         transport: String? = nil, appState: String? = nil) {
        version = 2; op = "receipt"
        self.receiptId = receiptId; self.enrollmentId = enrollmentId; self.generation = generation
        self.installationId = installationId; self.eventId = eventId; self.sequence = sequence
        self.observedAt = observedAt; self.stage = stage; self.outcome = outcome
        self.transport = transport; self.appState = appState
    }
    static let outcomes: [String: Set<String>] = [
        "phone_received": ["received", "duplicate", "disabled", "expired", "disconnected", "suppressed"],
        "strap_requested": ["requested", "unavailable"],
        "strap_response": ["response_received", "acknowledged", "rejected"],
        "wearer_confirmed": ["felt", "not_felt"]
    ]
}

struct RemoteBuzzState: Codable, Equatable {
    struct Event: Codable, Equatable, Identifiable {
        let id: String
        let enrollmentId: String
        let generation: Int
        let receivedAt: Int
        let expiresAt: Int
        let outcome: String
    }
    struct PendingReceipt: Codable, Equatable, Identifiable {
        let receipt: RemoteBuzzReceipt
        var attempts = 0
        var acknowledged = false
        var lastAttemptAt: Int?
        var id: String { receipt.receiptId }
        func mayAttempt(now: Int) -> Bool {
            !acknowledged && attempts < 10 && now >= receipt.observedAt
                && now - receipt.observedAt < 3600
                && (lastAttemptAt.map { now - $0 >= 30 } ?? true)
        }
    }
    var enabled = false
    var revoked = false
    var deviceRevision = 0
    var receiptSequence = 0
    var events: [Event] = []
    var receipts: [PendingReceipt] = []

    func valid() -> Bool {
        let maximum = 9_007_199_254_740_991
        guard deviceRevision >= 0, deviceRevision <= maximum,
              receiptSequence >= 0, receiptSequence <= maximum,
              Set(events.map { $0.enrollmentId + "|" + $0.id }).count == events.count,
              Set(receipts.map(\.id)).count == receipts.count,
              Set(receipts.map(\.receipt.sequence)).count == receipts.count else { return false }
        let eventKeys = Set(events.map { "\($0.enrollmentId)|\($0.generation)|\($0.id)" })
        return events.allSatisfy { event in
            RemoteBuzzV2.uuid(event.id) && RemoteBuzzV2.uuid(event.enrollmentId) && event.generation == 1
                && event.receivedAt >= 3600 && event.receivedAt <= maximum && event.expiresAt >= 0
                && RemoteBuzzReceipt.outcomes["phone_received"]?.contains(event.outcome) == true
        } && receipts.allSatisfy { pending in
            let receipt = pending.receipt
            return receipt.version == 2 && receipt.op == "receipt" && RemoteBuzzV2.uuid(receipt.receiptId)
                && RemoteBuzzV2.uuid(receipt.installationId) && receipt.sequence > 0
                && receipt.sequence <= receiptSequence && receipt.observedAt >= 0 && receipt.observedAt <= maximum
                && pending.attempts >= 0 && pending.attempts <= 10
                && (pending.lastAttemptAt.map { $0 >= 0 && $0 <= maximum } ?? true)
                && RemoteBuzzReceipt.outcomes[receipt.stage]?.contains(receipt.outcome) == true
                && (receipt.transport == nil || (receipt.stage == "phone_received" && ["apns", "inbox"].contains(receipt.transport!)))
                && (receipt.appState == nil || (receipt.stage == "phone_received" && ["foreground", "background", "inactive"].contains(receipt.appState!)))
                && eventKeys.contains("\(receipt.enrollmentId)|\(receipt.generation)|\(receipt.eventId)")
        }
    }

    // Caller authenticates HMAC and identity before entering this funnel. Persist the returned
    // state before dispatching BLE; a failed disk write must never result in a strap command.
    mutating func consume(_ command: RemoteBuzzCommandV2, enrollment: RemoteBuzzEnrollment,
                          now: Int, connected: Bool, exerciseOwnsBuzz: Bool,
                          transport: String? = nil, appState: String? = nil,
                          deferDisconnected: Bool = false) throws -> Bool {
        guard command.authenticated(by: enrollment), now >= 3600,
              now <= 9_007_199_254_740_991 else {
            throw RemoteBuzzEnrollmentError.invalid
        }
        if events.contains(where: { $0.id == command.eventId && $0.enrollmentId == command.enrollmentId }) {
            // A duplicate cannot dispatch again or create an unbounded receipt queue.
            return false
        }
        // A wake can precede Bluetooth restoration. Leave a still-fresh inbox request unconsumed;
        // a real reconnect may fetch it. Terminal outcomes and already-consumed events never replay.
        if deferDisconnected && enabled && !revoked && !connected && !exerciseOwnsBuzz
            && command.fresh(now: Date(timeIntervalSince1970: Double(now))) { return false }
        let outcome: String
        if !enabled || revoked { outcome = "disabled" }
        else if !command.fresh(now: Date(timeIntervalSince1970: Double(now))) { outcome = "expired" }
        else if exerciseOwnsBuzz { outcome = "suppressed" }
        else if !connected { outcome = "disconnected" }
        else { outcome = "received" }
        events.append(Event(id: command.eventId, enrollmentId: command.enrollmentId,
            generation: command.generation, receivedAt: now, expiresAt: command.expiresAt, outcome: outcome))
        try appendReceipt(eventId: command.eventId, enrollment: enrollment,
            stage: "phone_received", outcome: outcome, now: now, transport: transport, appState: appState)
        return outcome == "received"
    }

    mutating func appendReceipt(eventId: String, enrollment: RemoteBuzzEnrollment,
                                stage: String, outcome: String, now: Int,
                                transport: String? = nil, appState: String? = nil) throws {
        guard RemoteBuzzReceipt.outcomes[stage]?.contains(outcome) == true,
              events.contains(where: { $0.id == eventId && $0.enrollmentId == enrollment.enrollmentId
                  && $0.generation == enrollment.generation }),
              receiptSequence < 9_007_199_254_740_991 else { throw RemoteBuzzEnrollmentError.invalid }
        guard transport == nil || (stage == "phone_received" && ["apns", "inbox"].contains(transport!)),
              appState == nil || (stage == "phone_received" && ["foreground", "background", "inactive"].contains(appState!))
        else { throw RemoteBuzzEnrollmentError.invalid }
        guard !receipts.contains(where: { $0.receipt.eventId == eventId && $0.receipt.enrollmentId == enrollment.enrollmentId
            && $0.receipt.stage == stage && $0.receipt.outcome == outcome }) else { return }
        receiptSequence += 1
        receipts.append(PendingReceipt(receipt: RemoteBuzzReceipt(receiptId: UUID().uuidString.lowercased(),
            enrollmentId: enrollment.enrollmentId, generation: enrollment.generation,
            installationId: enrollment.installationId, eventId: eventId, sequence: receiptSequence,
            observedAt: now, stage: stage, outcome: outcome, transport: transport, appState: appState)))
    }
    mutating func nextRevision() throws -> Int {
        guard deviceRevision < 9_007_199_254_740_991 else { throw RemoteBuzzEnrollmentError.invalid }
        deviceRevision += 1
        return deviceRevision
    }
}

struct RemoteBuzzStateFile {
    let file: URL
    func load() throws -> RemoteBuzzState {
        guard FileManager.default.fileExists(atPath: file.path) else { return RemoteBuzzState() }
        let state = try JSONDecoder().decode(RemoteBuzzState.self, from: Data(contentsOf: file))
        guard state.valid() else { throw RemoteBuzzEnrollmentError.invalid }
        return state
    }
    func save(_ state: RemoteBuzzState) throws {
        guard state.valid() else { throw RemoteBuzzEnrollmentError.invalid }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directoryURL = directory
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try directoryURL.setResourceValues(resources)
        let data = try JSONEncoder().encode(state)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}
