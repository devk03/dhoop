import Foundation

/// Credential-free display cache. Each source keeps its own read time and calendar date.
struct DayHubSnapshot: Codable, Equatable {
    static let storageKey = "dhoop.day-hub.v1"
    static let widgetKind = "DhoopDayHubWidget"
    static let calendarWidgetKind = "DhoopDayHubCalendarWidget"
    static let summaryWidgetKind = "DhoopDayHubSummaryWidget"
    static let widgetKinds = [widgetKind, calendarWidgetKind, summaryWidgetKind]
    var version = 1
    var savedAt: Date
    var timeZoneID: String
    var food: Food?
    var workouts: Workouts?
    var sleep: Sleep?
    var sleepDeviceID: String? = nil
    var calendarDays: [CalendarWidgetSnapshot.Day]
    struct Food: Codable, Equatable {
        let day: String
        let readAt: Date
        let protein: Double
        let calories: Double?
        let entries: Int
        let estimatedEntries: Int
    }
    struct Workout: Codable, Equatable, Identifiable {
        let id: Int
        let title: String
        let status: String
        let timing: String?
    }
    struct Workouts: Codable, Equatable {
        let day: String
        let readAt: Date
        let complete: Bool
        let rows: [Workout]
    }
    struct Sleep: Codable, Equatable {
        let wakeDay: String
        let readAt: Date
        let whoopMinutes: Double?
        let eightSleepMinutes: Double?
        let whoopMethod: String?
    }
    /// A failed read cannot erase a dated result from the same active database context.
    static func resolvedSleep(previous: Sleep?, cachedDeviceID: String?, activeDeviceID: String, fresh: Sleep?, healthReadable: Bool) -> Sleep? {
        guard cachedDeviceID == activeDeviceID else { return fresh }
        guard let fresh else { return previous }
        if !healthReadable, let previous, previous.wakeDay == fresh.wakeDay,
           fresh.eightSleepMinutes == nil, previous.eightSleepMinutes != nil {
            return Sleep(wakeDay: fresh.wakeDay, readAt: min(previous.readAt, fresh.readAt), whoopMinutes: fresh.whoopMinutes,
                eightSleepMinutes: previous.eightSleepMinutes, whoopMethod: fresh.whoopMethod)
        }
        return fresh
    }
    static func day(_ date: Date, zone: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    var zone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    func food(at now: Date) -> Food? { food.flatMap { $0.day == Self.day(now, zone: zone) && $0.readAt <= now.addingTimeInterval(60) ? $0 : nil } }
    func workouts(at now: Date) -> Workouts? { workouts.flatMap { $0.day == Self.day(now, zone: zone) && $0.readAt <= now.addingTimeInterval(60) ? $0 : nil } }
    static func load(_ defaults: UserDefaults?) -> Self? {
        guard let data = defaults?.data(forKey: storageKey), data.count <= 256 * 1024,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1,
              TimeZone(identifier: value.timeZoneID) != nil, value.calendarDays.count <= 3,
              value.calendarDays.allSatisfy({ $0.events.count <= 100 }),
              value.workouts.map({ $0.rows.count <= 80 }) ?? true else { return nil }
        return value
    }
    static func link(_ section: String = "overview") -> URL {
        var c = URLComponents(); c.scheme = "dhoop"; c.host = "day-hub"
        c.queryItems = [.init(name: "section", value: section)]; return c.url!
    }
}

/// Exactly three elapsed hours, including midnight and daylight-saving transitions.
struct DayHubWindow {
    struct Placement: Identifiable {
        let event: CalendarWidgetSnapshot.Event
        let day: String
        let start: Double
        let end: Double
        let column: Int
        let columns: Int
        var id: String { event.id }
    }
    let now: Date
    var start: Date { now.addingTimeInterval(-90 * 60) }
    var end: Date { now.addingTimeInterval(90 * 60) }
    /// Whole-hour labels within the exact window; elapsed stepping keeps DST instants distinct.
    var hourTicks: [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarWidgetSnapshot.timeZone
        guard let hour = calendar.dateInterval(of: .hour, for: start)?.start else { return [] }
        var tick = hour < start ? hour.addingTimeInterval(3600) : hour
        var result: [Date] = []
        while tick < end {
            result.append(tick)
            tick = tick.addingTimeInterval(3600)
        }
        return result
    }
    var requiredDays: Set<String> {
        [CalendarWidgetSnapshot.dayKey(start), CalendarWidgetSnapshot.dayKey(end.addingTimeInterval(-0.001))]
    }
    func complete(_ days: [CalendarWidgetSnapshot.Day]) -> Bool {
        requiredDays.allSatisfy { key in days.contains { $0.date == key && $0.complete && $0.readAt <= now.addingTimeInterval(60) } }
    }
    func placements(_ days: [CalendarWidgetSnapshot.Day]) -> [Placement] {
        var seen = Set<String>()
        typealias Row = (event: CalendarWidgetSnapshot.Event, day: String, start: Double, end: Double)
        var rows: [Row] = []
        let required = requiredDays
        for day in days where required.contains(day.date) && day.readAt <= now.addingTimeInterval(60) {
            for event in day.events {
                guard !event.allDay, let a = event.start, let b = event.end, a < b, a < end, b > start,
                      seen.insert(event.id).inserted else { continue }
                let clippedStart: Double = max(0.0, a.timeIntervalSince(start))
                let clippedEnd: Double = min(10800.0, b.timeIntervalSince(start))
                rows.append((event, day.date, clippedStart, clippedEnd))
            }
        }
        rows.sort { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end > b.end }
            return a.event.id < b.event.id
        }
        var result: [Placement] = [], group: [(CalendarWidgetSnapshot.Event, String, Double, Double, Int)] = []
        var ends: [Double] = [], groupEnd = 0.0
        func flush() {
            result += group.map { .init(event: $0.0, day: $0.1, start: $0.2, end: $0.3, column: $0.4, columns: ends.count) }
            group = []; ends = []; groupEnd = 0
        }
        for row in rows {
            if !group.isEmpty && row.2 >= groupEnd { flush() }
            let col = ends.firstIndex { $0 <= row.2 } ?? ends.count
            if col == ends.count { ends.append(row.3) } else { ends[col] = row.3 }
            group.append((row.0, row.1, row.2, row.3, col)); groupEnd = max(groupEnd, row.3)
        }
        flush(); return result
    }
    // Cache-only timeline entries move the window without polling or waking the strap.
    static func timelineDates(from now: Date) -> [Date] {
        [now] + (1...72).map { now.addingTimeInterval(Double($0) * 300) }
    }
}
