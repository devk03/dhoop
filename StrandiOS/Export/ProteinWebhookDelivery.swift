import Foundation

struct ProteinWebhookSummary: Codable, Equatable, Sendable {
    let day: String
    let proteinGrams: Double?
    let entryCount: Int
    let timeZone: String
    var isValid: Bool {
        guard SleepWebhookSummary(wakeDate: day, sleepMinutes: 1, method: "whoop_import", timeZone: timeZone).isValid else { return false }
        if let grams = proteinGrams { return grams.isFinite && grams >= 0 && grams <= 1000 && entryCount > 0 && entryCount <= 100000 }
        return entryCount == 0
    }
}

struct ProteinWebhookEvent: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let kind: String
    let eventId: String
    let installationId: String
    let revision: Int
    let day: String
    let proteinGrams: Double?
    let entryCount: Int
    let source: String
    let coverage: String
    let timeZone: String
    let generationDate: String
    var summary: ProteinWebhookSummary { .init(day: day, proteinGrams: proteinGrams, entryCount: entryCount, timeZone: timeZone) }
    enum CodingKeys: String, CodingKey { case schemaVersion, kind, eventId, installationId, revision, day, proteinGrams, entryCount, source, coverage, timeZone, generationDate }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(kind, forKey: .kind)
        try c.encode(eventId, forKey: .eventId); try c.encode(installationId, forKey: .installationId)
        try c.encode(revision, forKey: .revision); try c.encode(day, forKey: .day)
        if let proteinGrams { try c.encode(proteinGrams, forKey: .proteinGrams) } else { try c.encodeNil(forKey: .proteinGrams) }
        try c.encode(entryCount, forKey: .entryCount); try c.encode(source, forKey: .source)
        try c.encode(coverage, forKey: .coverage); try c.encode(timeZone, forKey: .timeZone)
        try c.encode(generationDate, forKey: .generationDate)
    }
}

struct ProteinWebhookAcknowledgement: Decodable {
    let schemaVersion: Int; let kind: String; let eventId: String; let installationId: String
    let revision: Int; let day: String; let status: String; let outcome: String?
}

extension SleepWebhookDelivery {
    struct ProteinPending: Codable, Sendable { let event: ProteinWebhookEvent; let bytes: Data }
    var hasPending: Bool { pending != nil || proteinPending != nil }

    mutating func prepareProtein(_ summary: ProteinWebhookSummary, now: Date = Date()) throws -> ProteinPending? {
        if let proteinPending { return proteinPending }
        guard summary.isValid else { throw SleepWebhookFailure.invalidSummary }
        guard proteinAcknowledged?[summary.day] != summary else { return nil }
        guard revision >= 0, revision < 9_007_199_254_740_990 else { throw SleepWebhookFailure.invalidState }
        revision += 1
        let event = ProteinWebhookEvent(schemaVersion: 2, kind: "protein", eventId: UUID().uuidString.lowercased(),
            installationId: installationId, revision: revision, day: summary.day, proteinGrams: summary.proteinGrams,
            entryCount: summary.entryCount, source: "dhoop", coverage: "logged_entries", timeZone: summary.timeZone,
            generationDate: ISO8601DateFormatter().string(from: now))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let next = ProteinPending(event: event, bytes: try encoder.encode(event))
        proteinPending = next
        return next
    }
    mutating func acceptProtein(_ bytes: Data, now: Date = Date()) throws {
        guard let proteinPending, bytes.count <= 16384,
              let ack = try? JSONDecoder().decode(ProteinWebhookAcknowledgement.self, from: bytes),
              ack.schemaVersion == 2, ack.kind == "protein", ack.eventId == proteinPending.event.eventId,
              ack.installationId == installationId, ack.revision == proteinPending.event.revision,
              ack.day == proteinPending.event.day, ack.status == "accepted" else { throw SleepWebhookFailure.invalidAcknowledgement }
        if proteinAcknowledged == nil { proteinAcknowledged = [:] }
        proteinAcknowledged?[ack.day] = proteinPending.event.summary
        // A year's receipts allow explicit removals to reconcile beyond the initial seven-day scan.
        for day in (proteinAcknowledged ?? [:]).keys.sorted().dropLast(366) { proteinAcknowledged?[day] = nil }
        lastAcceptedProtein = proteinPending.event; proteinAcceptedAt = now
        proteinOutcome = ["stored", "cleared", "duplicate", "stale", "manual_preserved"].contains(ack.outcome ?? "") ? ack.outcome : nil
        self.proteinPending = nil
    }
}

/// Absence is not zero. Only previously exported days can produce a null retraction.
enum ProteinWebhookProjection {
    struct Entry { let day: String; let grams: Double }
    static func summaries(entries: [Entry], acknowledged: [String: ProteinWebhookSummary], from: String, to: String) throws -> [ProteinWebhookSummary] {
        var groups: [String: (grams: Double, count: Int)] = [:]
        for entry in entries {
            guard entry.grams.isFinite, entry.grams >= 0 else { throw SleepWebhookFailure.invalidSummary }
            let old = groups[entry.day] ?? (0, 0)
            groups[entry.day] = (old.grams + entry.grams, old.count + 1)
        }
        let days = Set(groups.keys.filter { $0 >= from && $0 <= to }).union(acknowledged.keys)
        return try days.sorted(by: >).map { day in
            let group = groups[day]
            let summary = ProteinWebhookSummary(day: day, proteinGrams: group?.grams, entryCount: group?.count ?? 0, timeZone: "America/Los_Angeles")
            guard summary.isValid else { throw SleepWebhookFailure.invalidSummary }
            return summary
        }
    }
    /// Read saved logs rather than another view's stale ProteinLogStore instance. Malformed data must
    /// never decode as an empty collection and retract real website values.
    @MainActor static func savedEntries(defaults: UserDefaults = .standard) throws -> [Entry] {
        let standalone: [ProteinLogStore.Entry]
        if let data = defaults.data(forKey: ProteinLogStore.entriesKey) {
            standalone = try JSONDecoder().decode([ProteinLogStore.Entry].self, from: data)
        } else if defaults.object(forKey: ProteinLogStore.entriesKey) != nil { throw SleepWebhookFailure.invalidState }
        else { standalone = [] }
        struct Food: Decodable { let protein: Double? }
        let food: [String: [Food]]
        if let data = defaults.data(forKey: "cut.food") { food = try JSONDecoder().decode([String: [Food]].self, from: data) }
        else if defaults.object(forKey: "cut.food") != nil { throw SleepWebhookFailure.invalidState }
        else { food = [:] }
        return standalone.map { Entry(day: $0.day, grams: $0.grams) } + food.flatMap { day, values in
            values.compactMap { value in value.protein.map { Entry(day: day, grams: $0) } }
        }
    }
}

extension SleepWebhookPolicy {
    static func completedDays(now: Date, calendar input: Calendar = .current) -> (from: String, through: String) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = input.timeZone
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let start = calendar.date(byAdding: .day, value: -6, to: yesterday)!
        func key(_ date: Date) -> String {
            let p = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
        }
        return (key(start), key(yesterday))
    }
    static func nextDailyOpportunity(now: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return midnight.addingTimeInterval(5 * 60)
    }
}


extension SleepWebhookPolicy {
    static func nextOpportunity(state: SleepWebhookCheckpoint, now: Date, calendar: Calendar = .current) -> Date {
        var dates = [nextDailyOpportunity(now: now, calendar: calendar)]
        let end = completedDays(now: now, calendar: calendar).through
        if state.enabled {
            if let retry = state.nextAttempt { dates.append(max(now.addingTimeInterval(60), retry)) }
            else if let pending = state.delivery.pending, pending.event.wakeDate <= end { dates.append(now.addingTimeInterval(60)) }
            if state.sleepBacklog == true { dates.append(now.addingTimeInterval(900)) }
        }
        if state.proteinEnabled == true {
            if let retry = state.proteinNextAttempt { dates.append(max(now.addingTimeInterval(60), retry)) }
            else if let pending = state.delivery.proteinPending, pending.event.day <= end { dates.append(now.addingTimeInterval(60)) }
            if state.proteinBacklog == true { dates.append(now.addingTimeInterval(900)) }
        }
        return dates.min()!
    }
}
