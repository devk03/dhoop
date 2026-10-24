import Foundation

/// Display-only day geometry. Real instants preserve both repeated hours when daylight saving ends.
struct CalendarDayTimeline {
    struct Placement: Identifiable {
        let event: CalendarReaderEvent
        let start: TimeInterval
        let end: TimeInterval
        let column: Int
        let columnCount: Int
        var id: String { event.id }
    }
    let start: Date
    let end: Date
    var hours: Int { Int(end.timeIntervalSince(start) / 3600) }
    init?(day: String) {
        guard let date = CalendarReaderDates.date(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = CalendarReaderDates.zone
        start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        end = next
    }
    func offset(of date: Date) -> TimeInterval? {
        guard date >= start && date < end else { return nil }
        return date.timeIntervalSince(start)
    }
    func allDayEvents(_ events: [CalendarReaderEvent]) -> [CalendarReaderEvent] {
        let day = CalendarReaderDates.key(start)
        return events.filter { $0.allDay && $0.startDate.map { $0 <= day } == true && $0.endDate.map { $0 > day } == true }
    }
    func placements(_ events: [CalendarReaderEvent], minimumDuration: TimeInterval) -> [Placement] {
        let duration = end.timeIntervalSince(start)
        let timed = events.compactMap { event -> (CalendarReaderEvent, TimeInterval, TimeInterval)? in
            guard !event.allDay, let a = event.startAt.flatMap(CalendarReaderDates.instant),
                  let b = event.endAt.flatMap(CalendarReaderDates.instant), a < end, b > start else { return nil }
            return (event, max(0, a.timeIntervalSince(start)), min(duration, b.timeIntervalSince(start)))
        }.sorted { $0.1 == $1.1 ? ($0.2 == $1.2 ? $0.0.id < $1.0.id : $0.2 > $1.2) : $0.1 < $1.1 }
        var result: [Placement] = [], group: [(CalendarReaderEvent, TimeInterval, TimeInterval, Int)] = []
        var columnEnds: [TimeInterval] = [], groupEnd: TimeInterval = 0
        func flush() {
            result += group.map { Placement(event: $0.0, start: $0.1, end: $0.2, column: $0.3, columnCount: columnEnds.count) }
            group = []; columnEnds = []; groupEnd = 0
        }
        for (event, a, b) in timed {
            if !group.isEmpty && a >= groupEnd { flush() }
            let visualEnd = max(b, a + max(0, minimumDuration))
            let column = columnEnds.firstIndex { $0 <= a } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(visualEnd) } else { columnEnds[column] = visualEnd }
            group.append((event, a, b, column)); groupEnd = max(groupEnd, visualEnd)
        }
        flush(); return result
    }
    func initialHour(now: Date, placements: [Placement]) -> Int {
        if let now = offset(of: now) { return max(0, Int(now / 3600) - 1) }
        return max(0, Int((placements.first?.start ?? 9 * 3600) / 3600) - 1)
    }
}
