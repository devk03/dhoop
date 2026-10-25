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
