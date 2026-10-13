import Foundation

public struct AlarmScheduleRule: Codable, Equatable, Sendable {
    public var minute: Int
    /// Calendar weekday numbering: Sunday=1. Empty means one-time, never every day.
    public var weekdays: Set<Int>
    public var oneTimeEpoch: Int?
    public var skippedEpochs: Set<Int>
    /// nil follows the device's local zone; a named zone remains fixed to that wall time.
    public var timeZoneID: String?
    public init(minute: Int, weekdays: Set<Int> = [], oneTimeEpoch: Int? = nil,
                skippedEpochs: Set<Int> = [], timeZoneID: String? = nil) {
        self.minute = minute; self.weekdays = weekdays; self.oneTimeEpoch = oneTimeEpoch
        self.skippedEpochs = skippedEpochs; self.timeZoneID = timeZoneID
    }
    public var valid: Bool {
        (0..<1440).contains(minute) && weekdays.allSatisfy { (1...7).contains($0) }
            && (oneTimeEpoch == nil || oneTimeEpoch! > 0)
            && skippedEpochs.allSatisfy { $0 > 0 }
            && (timeZoneID == nil || TimeZone(identifier: timeZoneID!) != nil)
    }
}

public struct PlannedAlarmOccurrence: Equatable, Sendable {
    public let epoch: Int
    public let definitionIDs: [String]
    public init(epoch: Int, definitionIDs: [String]) { self.epoch = epoch; self.definitionIDs = definitionIDs }
}

/// Finite dated schedule, not firmware recurrence. Kotlin twin: AlarmOccurrencePlanner.
public enum AlarmOccurrencePlanner {
    public static func dates(rule: AlarmScheduleRule, after now: Date, limit: Int = 6,
                             calendar: Calendar = .current) -> [Int] {
        guard rule.valid, limit > 0 else { return [] }
        if rule.weekdays.isEmpty {
            guard let epoch = rule.oneTimeEpoch, epoch > Int(now.timeIntervalSince1970),
                  !rule.skippedEpochs.contains(epoch) else { return [] }
            return [epoch]
        }
        var cal = calendar
        if let id = rule.timeZoneID, let zone = TimeZone(identifier: id) { cal.timeZone = zone }
        var result: [Int] = []
        let day = cal.startOfDay(for: now)
        // A bounded horizon covers six weekly occurrences without an infinite recurrence loop.
        for offset in 0..<64 {
            guard let date = cal.date(byAdding: .day, value: offset, to: day),
                  rule.weekdays.contains(cal.component(.weekday, from: date)),
                  let due = cal.date(bySettingHour: rule.minute / 60, minute: rule.minute % 60,
                                     second: 0, of: date, matchingPolicy: .nextTime,
                                     repeatedTimePolicy: .first, direction: .forward),
                  cal.isDate(due, inSameDayAs: date) else { continue }
            let epoch = Int(due.timeIntervalSince1970)
            if due > now && !rule.skippedEpochs.contains(epoch) { result.append(epoch) }
            if result.count == min(limit, 6) { break }
        }
        return result
    }
    public static func nextWallTime(minute: Int, after now: Date, calendar: Calendar = .current) -> Int? {
        guard (0..<1440).contains(minute), let date = calendar.nextDate(after: now,
            matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { return nil }
        return Int(date.timeIntervalSince1970)
    }
    public static func plan(rules: [String: AlarmScheduleRule], after now: Date,
                            calendar: Calendar = .current) -> [PlannedAlarmOccurrence] {
        var grouped: [Int: [String]] = [:]
        for id in rules.keys.sorted() {
            for epoch in dates(rule: rules[id]!, after: now, calendar: calendar) {
                grouped[epoch, default: []].append(id)
            }
        }
        return grouped.keys.sorted().map { .init(epoch: $0, definitionIDs: grouped[$0]!.sorted()) }
    }
}
