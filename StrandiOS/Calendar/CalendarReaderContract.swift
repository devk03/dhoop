import Foundation

enum CalendarReaderFailure: Error, LocalizedError, Equatable {
    case configuration, disabled, invalidResponse, snapshotChanged, historyChanged, http(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Calendar connection is not configured."
        case .disabled: return "Calendar reading is off."
        case .invalidResponse: return "Calendar data could not be verified."
        case .snapshotChanged: return "Calendar changed. Refresh the day."
        case .historyChanged: return "Progress changed. Refresh the event before loading older updates."
        case .http(let status):
            switch status {
            case 401, 403: return "Calendar access could not be verified. Check the connection."
            case 404: return "This event is no longer available on this day. Refresh the calendar."
            case 413: return "This context is too large to load. Its contents have not been changed."
            default: return "Calendar could not be refreshed. Try again when connected."
            }
        }
    }
}

enum CalendarReaderDates {
    static let zone = TimeZone(identifier: "America/Los_Angeles")!
    static func instant(_ text: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = f.date(from: text) { return value }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }
    static func date(_ day: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm"; f.isLenient = false
        guard day.count == 10, let value = f.date(from: day + " 12:00"), key(value) == day else { return nil }
        return value
    }
    static func key(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func display(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
        style.timeZone = zone; return date.formatted(style)
    }
    static func shifted(_ day: String, by days: Int) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        return date(day).flatMap { c.date(byAdding: .day, value: days, to: $0) }.map(key) ?? day
    }
    static func safeLink(_ value: String) -> URL? {
        guard let u = URL(string: value), let c = URLComponents(url: u, resolvingAgainstBaseURL: false),
              c.user == nil, c.password == nil else { return nil }
        if c.scheme == "https", c.host?.isEmpty == false { return u }
        if c.scheme == "codex", c.host == "threads", UUID(uuidString: String(c.path.dropFirst())) != nil,
           c.query == nil, c.fragment == nil { return u }
        return nil
    }
}

struct CalendarReaderConfiguration: Codable, Equatable {
    var enabled = false
    let origin: String
    let installationId: UUID
    let readToken: String
    let accessClientId: String?
    let accessClientSecret: String?
    var valid: Bool {
        guard (try? CalendarReaderEndpoint.day("2026-01-01", nil).url(origin: origin)) != nil,
              readToken.range(of: #"^[A-Za-z0-9_-]{43,1024}$"#, options: .regularExpression) != nil else { return false }
        if accessClientId == nil && accessClientSecret == nil { return true }
        guard let id = accessClientId, let secret = accessClientSecret else { return false }
        return id.range(of: #"^[A-Za-z0-9._-]{10,256}$"#, options: .regularExpression) != nil &&
            secret.range(of: #"^[A-Za-z0-9_+./=-]{20,1024}$"#, options: .regularExpression) != nil
    }
}

enum CalendarReaderEndpoint: Equatable {
    case day(String, String?)
    case event(String, String, String?, Int?)
    func url(origin: String) throws -> URL {
        guard var p = URLComponents(string: origin), p.scheme == "https", p.host == "track.kunjadia.dev",
              p.user == nil, p.password == nil, p.query == nil, p.fragment == nil,
              p.port == nil || p.port == 443, p.path.isEmpty || p.path == "/" else { throw CalendarReaderFailure.configuration }
        var q: [URLQueryItem]
        switch self {
        case .day(let date, let cursor):
            guard CalendarReaderDates.date(date) != nil,
                  cursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true else { throw CalendarReaderFailure.configuration }
            p.path = "/api/integrations/dhoop/calendar/day"; q = [.init(name: "date", value: date)]
            if let cursor { q.append(.init(name: "cursor", value: cursor)) }
        case .event(let date, let id, let ref, let before):
            guard CalendarReaderDates.date(date) != nil, !id.isEmpty, id.utf8.count <= 1024,
                  ref.map({ !$0.isEmpty && $0.utf8.count <= 2000 }) ?? true,
                  before.map({ $0 > 0 && ref != nil }) ?? true else { throw CalendarReaderFailure.configuration }
            p.path = "/api/integrations/dhoop/calendar/event"; q = [.init(name: "date", value: date), .init(name: "eventId", value: id)]
            if let ref { q.append(.init(name: "taskRef", value: ref)) }
            if let before { q.append(.init(name: "beforeVersion", value: String(before))) }
        }
        p.queryItems = q
        guard let url = p.url else { throw CalendarReaderFailure.configuration }; return url
    }
}

struct CalendarReaderEvent: Decodable, Equatable, Identifiable {
    let eventId: String
    let title: String
    let startAt: String?
    let endAt: String?
    let startDate: String?
    let endDate: String?
    let allDay: Bool
    let source: String
    let status: String
    let displayContext: String?
    let entityKey: String?
    let linkedTaskRefs: [String]
    let description: String?
    var etag: String? = nil
    var invitation: CalendarInvitation? = nil
    var id: String { eventId }
    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 1024, ["google", "local_projection"].contains(source), status != "cancelled",
              displayContext == nil || displayContext == "work", Set(linkedTaskRefs).count == linkedTaskRefs.count,
              linkedTaskRefs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 2000 }) else { throw CalendarReaderFailure.invalidResponse }
        if allDay {
            guard startAt == nil, endAt == nil, let startDate, let endDate,
                  CalendarReaderDates.date(startDate) != nil, CalendarReaderDates.date(endDate) != nil, endDate > startDate
            else { throw CalendarReaderFailure.invalidResponse }
        } else {
            guard startDate == nil, endDate == nil, let a = startAt.flatMap(CalendarReaderDates.instant),
                  let b = endAt.flatMap(CalendarReaderDates.instant), b > a else { throw CalendarReaderFailure.invalidResponse }
        }
    }
}

struct CalendarReaderDay: Decodable, Equatable {
    struct Page: Decodable, Equatable { let hasMore: Bool; let nextCursor: String? }
    let schemaVersion: Int
    let date: String
    let timeZone: String
    let readAt: String
    let readOnly: Bool
    let snapshot: String
    let events: [CalendarReaderEvent]
    let page: Page
    func validate(date expected: String) throws {
        guard schemaVersion == 1, readOnly, date == expected, CalendarReaderDates.date(date) != nil,
              timeZone == CalendarReaderDates.zone.identifier, CalendarReaderDates.instant(readAt) != nil,
              !snapshot.isEmpty, snapshot.utf8.count <= 4096, events.count <= 100,
              Set(events.map(\.id)).count == events.count, page.hasMore == (page.nextCursor != nil),
              page.nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 && !events.isEmpty }) ?? true else { throw CalendarReaderFailure.invalidResponse }
        try events.forEach { try $0.validate() }
    }
}

struct CalendarReaderDayChain: Equatable {
    private(set) var first: CalendarReaderDay?
    private(set) var events: [CalendarReaderEvent] = []
    private(set) var cursor: String?
    mutating func accept(_ page: CalendarReaderDay, date: String, requestedCursor: String?) throws {
        try page.validate(date: date)
        if let requestedCursor {
            guard let first, first.date == date else { throw CalendarReaderFailure.invalidResponse }
            guard first.snapshot == page.snapshot else { throw CalendarReaderFailure.snapshotChanged }
            guard events.count + page.events.count <= 5000 else { throw CalendarReaderFailure.http(413) }
            guard cursor == requestedCursor,
                  Set(events.map(\.id)).isDisjoint(with: Set(page.events.map(\.id))),
                  page.page.nextCursor != requestedCursor else { throw CalendarReaderFailure.invalidResponse }
            events += page.events
        } else { first = page; events = page.events }
        cursor = page.page.nextCursor
    }
}

struct CalendarReaderProgress: Decodable, Equatable {
    struct Entry: Decodable, Equatable, Identifiable {
        let id: String
        let version: Int
        let workDate: String
        let fromDate: String
        let toDate: String
        let category: String
        let accomplished: String
        let nextStep: String
        let createdAt: String
    }
    let version: Int
    let latest: Entry?
    var entries: [Entry]
    let total: Int
    var nextBeforeVersion: Int?
    func validate(before: Int? = nil) throws {
        guard version >= 0, total >= entries.count, entries.count <= 30,
              before != nil || ((total == 0) == entries.isEmpty),
              Set(entries.map(\.id)).count == entries.count, Set(entries.map(\.version)).count == entries.count,
              zip(entries, entries.dropFirst()).allSatisfy({ $0.0.version > $0.1.version }),
              entries.allSatisfy({ !$0.id.isEmpty && $0.version > 0 && $0.version <= version && $0.version < (before ?? Int.max) &&
                  CalendarReaderDates.date($0.workDate) != nil && CalendarReaderDates.date($0.fromDate) != nil &&
                  CalendarReaderDates.date($0.toDate) != nil && CalendarReaderDates.instant($0.createdAt) != nil }),
              (version == 0 && latest == nil) || (latest?.version == version),
              nextBeforeVersion.map({ $0 > 0 && $0 == entries.last?.version }) ?? true else { throw CalendarReaderFailure.invalidResponse }
    }
    mutating func append(_ older: Self, before: Int) throws {
        try older.validate(before: before)
        guard version == older.version, total == older.total, latest == older.latest, nextBeforeVersion == before,
              !older.entries.isEmpty,
              Set(entries.map(\.id)).isDisjoint(with: older.entries.map(\.id)), entries.count + older.entries.count <= 5000 else { throw CalendarReaderFailure.historyChanged }
        entries += older.entries; nextBeforeVersion = older.nextBeforeVersion
    }
}

struct CalendarReaderDetail: Decodable, Equatable {
    struct TaskResult: Decodable, Equatable, Identifiable {
        struct Problem: Decodable, Equatable { let code: String; let message: String }
        struct TaskBody: Decodable, Equatable {
            let title: String; let note: String; let description: String; let done: Bool; let status: String; let date: String?
            let progress: CalendarReaderProgress?
        }
        struct Brief: Decodable, Equatable {
            let humanDescription: String; let humanDescriptionAuthor: String?; let agentDescription: String
            let instructions: String; let acceptanceCriteria: String; let repoUrl: String; let version: Int; let updatedAt: String?
        }
        let ref: String; let available: Bool; let url: String?; let task: TaskBody?; let brief: Brief?; let error: Problem?
        var id: String { ref }
    }
    let schemaVersion: Int; let date: String; let timeZone: String; let readAt: String; let readOnly: Bool
    let event: CalendarReaderEvent; let tasks: [TaskResult]
    func validate(date expected: String, eventId: String, taskRef: String? = nil, before: Int? = nil) throws {
        guard schemaVersion == 1, readOnly, date == expected, CalendarReaderDates.date(date) != nil,
              timeZone == CalendarReaderDates.zone.identifier, CalendarReaderDates.instant(readAt) != nil, event.id == eventId,
              Set(tasks.map(\.ref)).count == tasks.count,
              tasks.allSatisfy({ event.linkedTaskRefs.contains($0.ref) && (taskRef == nil || taskRef == $0.ref) }),
              Set(tasks.map(\.ref)) == Set(taskRef.map { [$0] } ?? event.linkedTaskRefs) else { throw CalendarReaderFailure.invalidResponse }
        try event.validate()
        for result in tasks {
            if result.available {
                guard let task = result.task, let brief = result.brief, result.error == nil,
                      [nil, "human", "agent"].contains(brief.humanDescriptionAuthor), brief.version >= 0,
                      task.date.map({ CalendarReaderDates.date($0) != nil }) ?? true else { throw CalendarReaderFailure.invalidResponse }
                try task.progress?.validate(before: before)
            } else if result.error == nil { throw CalendarReaderFailure.invalidResponse }
        }
    }
}
