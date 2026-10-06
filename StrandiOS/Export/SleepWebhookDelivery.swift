import Foundation

/// Separate, summary-only export contract. This is not the upstream raw-stream push protocol.
struct SleepWebhookSummary: Codable, Equatable, Sendable {
    let wakeDate: String
    let sleepMinutes: Double
    let method: String
    let timeZone: String

    var isValid: Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard wakeDate.count == 10, wakeDate >= "0001-01-02", let date = formatter.date(from: wakeDate), formatter.string(from: date) == wakeDate else { return false }
        return sleepMinutes.isFinite && sleepMinutes > 0 && sleepMinutes <= 1440
            && ["dhoop_estimate", "whoop_import"].contains(method)
            && timeZone == "America/Los_Angeles"
    }
}

struct SleepWebhookEvent: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let eventId: String
    let installationId: String
    let revision: Int
    let wakeDate: String
    let sleepMinutes: Double
    let source: String
    let method: String
    let timeZone: String
    let generationDate: String

    var summary: SleepWebhookSummary {
        SleepWebhookSummary(wakeDate: wakeDate, sleepMinutes: sleepMinutes, method: method, timeZone: timeZone)
    }
}

struct SleepWebhookAcknowledgement: Decodable {
    let schemaVersion: Int
    let eventId: String
    let installationId: String
    let revision: Int
    let wakeDate: String
    let status: String
    let outcome: String?
}

enum SleepWebhookFailure: Error {
    case invalidConfiguration, invalidSummary, invalidAcknowledgement, invalidState
    case storage, credentials, http(Int), responseTooLarge, travelPause, expiredSetup
}

/// Durable single-flight outbox: checkpoint before HTTP; acknowledge only an exact receipt.
/// A failed request keeps the same event ID, revision and bytes across process restarts.
struct SleepWebhookDelivery: Codable, Sendable {
    struct Pending: Codable, Sendable {
        let event: SleepWebhookEvent
        let bytes: Data
    }
    var installationId = UUID().uuidString.lowercased()
    var revision = 0
    var endpoint = ""
    var acknowledged: [String: SleepWebhookSummary] = [:]
    var pending: Pending?
    var lastAcceptedAt: Date?
    var lastOutcome: String?
    var lastAcceptedEvent: SleepWebhookEvent?
    // Optional fields preserve v1 checkpoint decoding, including exact in-flight sleep bytes.
    var proteinPending: ProteinPending?
    var proteinAcknowledged: [String: ProteinWebhookSummary]?
    var lastAcceptedProtein: ProteinWebhookEvent?
    var proteinAcceptedAt: Date?
    var proteinOutcome: String?

    static func endpointURL(_ value: String) -> URL? {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              let url = components.url else { return nil }
        return url
    }

    mutating func configure(endpoint value: String) throws {
        guard Self.endpointURL(value) != nil else { throw SleepWebhookFailure.invalidConfiguration }
        if endpoint != value {
            endpoint = value
            // Revisions belong to the installation, not a destination. Returning to an old endpoint
            // must never send a lower revision than it has already seen.
            acknowledged = [:]; pending = nil; lastAcceptedAt = nil; lastOutcome = nil; lastAcceptedEvent = nil
            proteinPending = nil; proteinAcknowledged = nil; lastAcceptedProtein = nil; proteinAcceptedAt = nil; proteinOutcome = nil
        }
    }

    mutating func prepare(_ summary: SleepWebhookSummary, now: Date = Date()) throws -> Pending? {
        if let pending { return pending }
        guard summary.isValid else { throw SleepWebhookFailure.invalidSummary }
        guard acknowledged[summary.wakeDate] != summary else { return nil }
        guard revision >= 0, revision < 9_007_199_254_740_990 else { throw SleepWebhookFailure.invalidState }
        revision += 1
        let event = SleepWebhookEvent(schemaVersion: 1, eventId: UUID().uuidString.lowercased(),
            installationId: installationId, revision: revision, wakeDate: summary.wakeDate,
            sleepMinutes: summary.sleepMinutes, source: "whoop", method: summary.method,
            timeZone: summary.timeZone, generationDate: ISO8601DateFormatter().string(from: now))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let next = Pending(event: event, bytes: try encoder.encode(event))
        pending = next
        return next
    }

    mutating func accept(_ bytes: Data, now: Date = Date()) throws {
        guard let pending, bytes.count <= 16_384,
              let ack = try? JSONDecoder().decode(SleepWebhookAcknowledgement.self, from: bytes),
              ack.schemaVersion == pending.event.schemaVersion, ack.eventId == pending.event.eventId,
              ack.installationId == installationId, ack.revision == pending.event.revision,
              ack.wakeDate == pending.event.wakeDate, ack.status == "accepted" else {
            throw SleepWebhookFailure.invalidAcknowledgement
        }
        acknowledged[pending.event.wakeDate] = pending.event.summary
        // Keep a small local receipt ledger. Older data remains in the health store.
        for day in acknowledged.keys.sorted().dropLast(31) { acknowledged[day] = nil }
        lastAcceptedEvent = pending.event
        self.pending = nil
        lastAcceptedAt = now
        lastOutcome = ["stored", "manual_preserved", "stale", "duplicate"].contains(ack.outcome ?? "") ? ack.outcome : nil
    }
}


extension SleepWebhookDelivery {
    func validate() throws {
        guard UUID(uuidString: installationId)?.uuidString.lowercased() == installationId,
              revision >= 0, revision <= 9_007_199_254_740_990,
              endpoint.isEmpty || Self.endpointURL(endpoint) != nil,
              acknowledged.count <= 31, acknowledged.allSatisfy({ $0.key == $0.value.wakeDate && $0.value.isValid }) else {
            throw SleepWebhookFailure.invalidState
        }
        guard (proteinAcknowledged?.count ?? 0) <= 366,
              (proteinAcknowledged ?? [:]).allSatisfy({ $0.key == $0.value.day && $0.value.isValid }) else { throw SleepWebhookFailure.invalidState }
        if let pending, let proteinPending {
            guard pending.event.eventId != proteinPending.event.eventId, pending.event.revision != proteinPending.event.revision else { throw SleepWebhookFailure.invalidState }
        }
        if let p = proteinPending {
            guard p.bytes.count <= 16_384, let decoded = try? JSONDecoder().decode(ProteinWebhookEvent.self, from: p.bytes),
                  decoded == p.event, decoded.installationId == installationId, decoded.revision <= revision,
                  decoded.revision > 0, decoded.schemaVersion == 2, decoded.kind == "protein", decoded.source == "dhoop",
                  decoded.coverage == "logged_entries", decoded.summary.isValid,
                  UUID(uuidString: decoded.eventId)?.uuidString.lowercased() == decoded.eventId,
                  decoded.generationDate.hasSuffix("Z"), ISO8601DateFormatter().date(from: decoded.generationDate) != nil else { throw SleepWebhookFailure.invalidState }
        }
        if let pending {
            guard pending.bytes.count <= 16_384,
                  let decoded = try? JSONDecoder().decode(SleepWebhookEvent.self, from: pending.bytes),
                  decoded == pending.event, decoded.installationId == installationId,
                  decoded.revision <= revision, decoded.revision > 0,
                  decoded.schemaVersion == 1, decoded.source == "whoop", decoded.summary.isValid,
                  UUID(uuidString: decoded.eventId)?.uuidString.lowercased() == decoded.eventId,
                  decoded.generationDate.hasSuffix("Z"), ISO8601DateFormatter().date(from: decoded.generationDate) != nil else {
                throw SleepWebhookFailure.invalidState
            }
        }
    }
}

struct SleepWebhookCheckpoint: Codable {
    var version = 1
    var delivery = SleepWebhookDelivery()
    var enabled = false
    var proteinEnabled: Bool?
    var proteinFailures: Int?
    var proteinNextAttempt: Date?
    var proteinMessage: String?
    var sleepBacklog: Bool?
    var proteinBacklog: Bool?
    var anyEnabled: Bool { enabled || proteinEnabled == true }
    var failures = 0
    var nextAttempt: Date?
    var message = "Not connected"

    func validate() throws {
        guard (version == 1 || version == 2), failures >= 0, (proteinFailures ?? 0) >= 0 else { throw SleepWebhookFailure.invalidState }
        try delivery.validate()
    }
}

/// No silent reset on malformed or unreadable state. The receiver relies on this installation's
/// durable identity and revision ordering. The caller only publishes state after save succeeds.
struct SleepWebhookFileStore {
    let url: URL
    func load() throws -> SleepWebhookCheckpoint {
        guard FileManager.default.fileExists(atPath: url.path) else { return SleepWebhookCheckpoint() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 131_072 else { throw SleepWebhookFailure.invalidState }
        let state = try JSONDecoder().decode(SleepWebhookCheckpoint.self, from: Data(contentsOf: url))
        try state.validate()
        return state
    }
    func save(_ state: SleepWebhookCheckpoint) throws {
        try state.validate()
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var protected = parent
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        let bytes = try JSONEncoder().encode(state)
        #if os(iOS)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
    }
}

enum SleepWebhookPolicy {
    static func canSend(enabled: Bool, timeZone: TimeZone, nextAttempt: Date?, now: Date) -> Bool {
        enabled && timeZone.identifier == "America/Los_Angeles" && (nextAttempt.map { now >= $0 } ?? true)
    }
    static func retryDelay(failures: Int) -> TimeInterval {
        min(6 * 3600, 60 * pow(2, Double(min(max(failures - 1, 0), 9))))
    }
}
