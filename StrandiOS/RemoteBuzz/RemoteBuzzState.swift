import Foundation

struct RemoteBuzzReceipt: Codable, Equatable, Identifiable {
    let version = 2
    let op = "receipt"
    let receiptId: String
    let enrollmentId: String
    let generation: Int
    let installationId: String
    let eventId: String
    let sequence: Int
    let observedAt: Int
    let stage: String
    let outcome: String
    var id: String { receiptId }
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

    // Caller authenticates HMAC and identity before entering this funnel. Persist the returned
    // state before dispatching BLE; a failed disk write must never result in a strap command.
    mutating func consume(_ command: RemoteBuzzCommandV2, enrollment: RemoteBuzzEnrollment,
                          now: Int, connected: Bool, exerciseOwnsBuzz: Bool) throws -> Bool {
        guard command.authenticated(by: enrollment), now >= 3600,
              now <= 9_007_199_254_740_991 else {
            throw RemoteBuzzEnrollmentError.invalid
        }
        if events.contains(where: { $0.id == command.eventId && $0.enrollmentId == command.enrollmentId }) {
            // A duplicate cannot consume another rate slot or create an unbounded receipt queue.
            return false
        }
        let outcome: String
        if !enabled || revoked { outcome = "disabled" }
        else if !command.fresh(now: Date(timeIntervalSince1970: Double(now))) { outcome = "expired" }
        else if exerciseOwnsBuzz { outcome = "suppressed" }
        else if !connected { outcome = "disconnected" }
        else {
            let accepted = events.filter {
                $0.enrollmentId == enrollment.enrollmentId && $0.outcome == "received"
                    && $0.receivedAt > now - 3600
            }
            if accepted.count >= 3 || accepted.contains(where: { $0.receivedAt > now - 30 }) {
                outcome = "suppressed"
            } else { outcome = "received" }
        }
        events.append(Event(id: command.eventId, enrollmentId: command.enrollmentId,
            generation: command.generation, receivedAt: now, expiresAt: command.expiresAt, outcome: outcome))
        try appendReceipt(eventId: command.eventId, enrollment: enrollment,
            stage: "phone_received", outcome: outcome, now: now)
        return outcome == "received"
    }

    mutating func appendReceipt(eventId: String, enrollment: RemoteBuzzEnrollment,
                                stage: String, outcome: String, now: Int) throws {
        guard RemoteBuzzReceipt.outcomes[stage]?.contains(outcome) == true,
              events.contains(where: { $0.id == eventId && $0.enrollmentId == enrollment.enrollmentId
                  && $0.generation == enrollment.generation }),
              receiptSequence < 9_007_199_254_740_991 else { throw RemoteBuzzEnrollmentError.invalid }
        guard !receipts.contains(where: { $0.receipt.eventId == eventId && $0.receipt.enrollmentId == enrollment.enrollmentId
            && $0.receipt.stage == stage && $0.receipt.outcome == outcome }) else { return }
        receiptSequence += 1
        receipts.append(PendingReceipt(receipt: RemoteBuzzReceipt(receiptId: UUID().uuidString.lowercased(),
            enrollmentId: enrollment.enrollmentId, generation: enrollment.generation,
            installationId: enrollment.installationId, eventId: eventId, sequence: receiptSequence,
            observedAt: now, stage: stage, outcome: outcome)))
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
        return try JSONDecoder().decode(RemoteBuzzState.self, from: Data(contentsOf: file))
    }
    func save(_ state: RemoteBuzzState) throws {
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
