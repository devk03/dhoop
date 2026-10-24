import WidgetKit
import SwiftUI
import StrandDesign

struct CalendarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry { .init(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetEntry>) -> Void) {
        let entry = load(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = CalendarWidgetSnapshot.timeZone
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date))!
        let changes = entry.snapshot?.days.flatMap { day in
            day.events.flatMap { [$0.start, $0.end].compactMap { $0 } }
        }.filter { $0 > entry.date } ?? []
        let days = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: entry.date)) }
        let dates = Array(Set(changes + days + [entry.date])).sorted().prefix(1408)
        completion(Timeline(entries: dates.map { .init(date: $0, snapshot: entry.snapshot) }, policy: .after(midnight)))
    }
    private func load() -> CalendarWidgetEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        return .init(date: Date(), snapshot: defaults.flatMap { CalendarWidgetSnapshot().loadDefaults($0) })
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CalendarWidgetSnapshot.widgetKind, provider: CalendarWidgetProvider()) { CalendarWidgetView(entry: $0) }
            .configurationDisplayName("Calendar")
            .description("Upcoming events and invitations from your last Life sync. Tap to open Dhoop.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
