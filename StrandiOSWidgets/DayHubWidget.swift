import SwiftUI
import WidgetKit
import StrandDesign

struct DayHubEntry: TimelineEntry { let date: Date; let snapshot: DayHubSnapshot? }
struct DayHubProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayHubEntry { .init(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (DayHubEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayHubEntry>) -> Void) {
        let current = load()
        completion(Timeline(entries: DayHubWindow.timelineDates(from: current.date).map { .init(date: $0, snapshot: current.snapshot) }, policy: .atEnd))
    }
    private func load() -> DayHubEntry { .init(date: Date(), snapshot: DayHubSnapshot.load(UserDefaults(suiteName: WidgetSnapshot.suiteName))) }
}
struct DayHubWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayHubSnapshot.widgetKind, provider: DayHubProvider()) { entry in
            DayHubView(snapshot: entry.snapshot, now: entry.date)
                .widgetURL(DayHubSnapshot.link()).privacySensitive()
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }.configurationDisplayName("Day Hub")
            .description("Your three-hour calendar, food totals, workout and sleep together. Tap to open the full overview.")
            .supportedFamilies([.systemLarge])
    }
}

/// The paired large calendar and medium summary read the same cache and timeline provider.
struct DayHubCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayHubSnapshot.calendarWidgetKind, provider: DayHubProvider()) { entry in
            DayHubView(snapshot: entry.snapshot, now: entry.date, presentation: .calendar)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .widgetURL(DayHubSnapshot.link()).privacySensitive()
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }.configurationDisplayName("Day Hub Calendar")
            .description("Place above Day Hub Summary for a dashboard-only Home Screen page.")
            .supportedFamilies([.systemLarge])
    }
}
struct DayHubSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayHubSnapshot.summaryWidgetKind, provider: DayHubProvider()) { entry in
            DayHubView(snapshot: entry.snapshot, now: entry.date, presentation: .summary)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .widgetURL(DayHubSnapshot.link()).privacySensitive()
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }.configurationDisplayName("Day Hub Summary")
            .description("Place below Day Hub Calendar for food, workout status and sleep.")
            .supportedFamilies([.systemMedium])
    }
}
