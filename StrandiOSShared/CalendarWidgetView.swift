#if os(iOS)
import SwiftUI
import WidgetKit
import StrandDesign

struct CalendarWidgetEntry: TimelineEntry { let date: Date; let snapshot: CalendarWidgetSnapshot? }
struct CalendarWidgetView: View {
    let entry: CalendarWidgetEntry
    @Environment(\.widgetFamily) private var systemFamily
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    init(entry: CalendarWidgetEntry, family: WidgetFamily? = nil) { self.entry = entry; familyOverride = family }
    private var day: CalendarWidgetSnapshot.Day? { entry.snapshot?.current(at: entry.date) }
    private var dateStyle: Date.FormatStyle { var style = Date.FormatStyle.dateTime.day().month(.abbreviated); style.timeZone = CalendarWidgetSnapshot.timeZone; return style }
    private var timeStyle: Date.FormatStyle { var style = Date.FormatStyle.dateTime.hour().minute(); style.timeZone = CalendarWidgetSnapshot.timeZone; return style }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack {
                if family == .systemSmall { Image(systemName: "calendar").accessibilityLabel("Calendar") }
                else { Label("Calendar", systemImage: "calendar").font(StrandFont.subhead.weight(.semibold)) }
                Spacer(minLength: NoopMetrics.space1)
                Text(entry.date, format: dateStyle)
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if let day {
                let events = Array(day.upcoming(at: entry.date).prefix(family == .systemSmall ? 1 : family == .systemLarge ? 6 : 2))
                if events.isEmpty {
                    Text(day.complete ? "No more events today" : "Open Calendar for more events").font(StrandFont.subhead)
                }
                ForEach(events) { event in
                    if family == .systemSmall { row(event) }
                    else if let url = CalendarWidgetSnapshot.link(day: day.date, eventID: event.id) { Link(destination: url) { row(event) } }
                }
                Spacer(minLength: 0)
                HStack(spacing: NoopMetrics.space1) {
                    if family == .systemSmall { Image(systemName: "arrow.clockwise").accessibilityLabel("Updated") }
                    else { Text("Updated") }
                    if CalendarWidgetSnapshot.dayKey(day.readAt) != day.date {
                        Text(day.readAt, format: dateStyle)
                    }
                    Text(day.readAt, format: timeStyle)
                }.font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            } else {
                Spacer(minLength: 0)
                Text("Open Dhoop to update Calendar").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(StrandPalette.textPrimary)
        .widgetURL(CalendarWidgetSnapshot.link(day: day?.date ?? CalendarWidgetSnapshot.dayKey(entry.date),
            eventID: family == .systemSmall ? day?.upcoming(at: entry.date).first?.id : nil))
        .privacySensitive()
        .containerBackground(StrandPalette.surfaceBase, for: .widget)
    }
    private func row(_ event: CalendarWidgetSnapshot.Event) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            RoundedRectangle(cornerRadius: NoopMetrics.spaceHalf)
                .fill(event.localProjection ? StrandPalette.metricPurple : StrandPalette.metricCyan).frame(width: NoopMetrics.space1)
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                HStack {
                    Text(verbatim: event.title).font(StrandFont.subhead.weight(.semibold)).lineLimit(family == .systemSmall ? 2 : 1)
                    if event.pending { Image(systemName: "envelope.badge").foregroundStyle(StrandPalette.metricSteps).accessibilityLabel("Needs response") }
                }
                HStack(spacing: NoopMetrics.space1) {
                    if event.allDay { Text("All-day").font(StrandFont.caption) }
                    else if let start = event.start { Text(start, format: timeStyle).font(StrandFont.caption) }
                    if family != .systemSmall, let organizer = event.organizer {
                        Text(verbatim: organizer).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).lineLimit(1)
                    }
                }
                if family == .systemSmall, let organizer = event.organizer { Text(verbatim: organizer).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#endif
