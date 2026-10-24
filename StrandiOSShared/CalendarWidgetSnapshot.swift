import Foundation

/// Calendar-only, credential-free widget cache. A missing day is never reported as an empty schedule.
public struct CalendarWidgetSnapshot: Codable, Equatable {
    public static let storageKey = "dhoop.calendar.widget.v1"
    public static let widgetKind = "DhoopCalendarWidget"
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    public var version = 1
    public var days: [Day] = []
    public struct Event: Codable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let start: Date?
        public let end: Date?
        public let allDay: Bool
        public let organizer: String?
        public let pending: Bool
        public let localProjection: Bool
        public init(id: String, title: String, start: Date?, end: Date?, allDay: Bool, organizer: String?, pending: Bool, localProjection: Bool) {
            self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay
            self.organizer = organizer; self.pending = pending; self.localProjection = localProjection
        }
    }
    public struct Day: Codable, Equatable {
        public let date: String
        public let readAt: Date
        public let complete: Bool
        public let events: [Event]
        public init(date: String, readAt: Date, complete: Bool, events: [Event]) {
            self.date = date; self.readAt = readAt; self.complete = complete; self.events = events
        }
        public func upcoming(at now: Date) -> [Event] { events.filter { $0.allDay || $0.end.map { $0 > now } == true } }
    }
    public init(days: [Day] = []) { self.days = days }
    public static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    public func current(at now: Date) -> Day? {
        guard version == 1, days.count <= 7, Set(days.map(\.date)).count == days.count else { return nil }
        return days.first { $0.date == Self.dayKey(now) && $0.readAt <= now.addingTimeInterval(60) && $0.events.count <= 100 }
    }
    public static func link(day: String, eventID: String? = nil) -> URL? {
        var value = URLComponents(); value.scheme = "dhoop"; value.host = "calendar"
        value.queryItems = [URLQueryItem(name: "date", value: day)]
        if let eventID { value.queryItems?.append(.init(name: "eventId", value: eventID)) }
        return value.url
    }
    public func loadDefaults(_ defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: Self.storageKey), data.count <= 512 * 1024 else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
