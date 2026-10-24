#if os(iOS)
import SwiftUI
import StrandDesign

struct CalendarDayTimelineView<Footer: View>: View {
    let timeline: CalendarDayTimeline
    let events: [CalendarReaderEvent]
    let captureNow: Date?
    let focusRevision: Int
    let onSelect: (CalendarReaderEvent) -> Void
    let onRefresh: () async -> Void
    @ViewBuilder var footer: () -> Footer
    @ScaledMetric(relativeTo: .body) private var hourHeight = NoopMetrics.calendarHourHeight
    @ScaledMetric(relativeTo: .caption) private var gutter = NoopMetrics.calendarTimeGutter
    @ScaledMetric(relativeTo: .body) private var eventMinimumWidth = NoopMetrics.calendarEventMinimumWidth
    private var placements: [CalendarDayTimeline.Placement] {
        timeline.placements(events, minimumDuration: Double(NoopMetrics.minimumTouchTarget / hourHeight) * 3600)
    }
    var body: some View {
        GeometryReader { viewport in
            let columns = placements.map(\.columnCount).max() ?? 1
            let width = max(viewport.size.width - NoopMetrics.screenHPadding * 2,
                gutter + CGFloat(columns) * eventMinimumWidth)
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            allDayStrip.padding(.horizontal, NoopMetrics.screenHPadding)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        if events.isEmpty {
                            Text("No events on this day.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        }
                        grid(width: width)
                        footer()
                    }
                    .frame(width: width, alignment: .leading)
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.top, NoopMetrics.space3)
                    .padding(.bottom, NoopMetrics.tabBarClearance)
                    .responsiveScrollTouches()
                }
                .refreshable { await onRefresh() }
                .task {
                    await Task.yield()
                    proxy.scrollTo(timeline.initialHour(now: captureNow ?? Date(), placements: placements), anchor: .topLeading)
                }
                .onChange(of: focusRevision) { _, _ in
                    proxy.scrollTo(timeline.initialHour(now: captureNow ?? Date(), placements: placements), anchor: .topLeading)
                }
            }
            }
        }
    }
    @ViewBuilder private var allDayStrip: some View {
        let allDay = timeline.allDayEvents(events)
        if !allDay.isEmpty {
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                Text("All-day").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).frame(width: gutter, alignment: .trailing)
                VStack(spacing: NoopMetrics.space1) {
                    ForEach(allDay) { event in
                        Button { onSelect(event) } label: {
                            Text(verbatim: event.title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget, alignment: .leading)
                                .padding(.horizontal, NoopMetrics.space2)
                                .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: NoopMetrics.calendarEventRadius))
                        }.buttonStyle(NoopFeedbackButtonStyle())
                            .accessibilityLabel(Text(verbatim: event.title) + Text(" · ") + Text("All-day"))
                    }
                }
            }
        }
    }
    private func grid(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<timeline.hours, id: \.self) { hour in
                    HStack(alignment: .top, spacing: NoopMetrics.space2) {
                        Text(verbatim: hourLabel(hour)).font(StrandFont.caption).monospacedDigit()
                            .foregroundStyle(StrandPalette.textTertiary).frame(width: gutter, alignment: .trailing)
                            .offset(y: -NoopMetrics.space2)
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    }.frame(height: hourHeight, alignment: .top).id(hour).accessibilityHidden(true)
                }
            }
            ForEach(placements) { placement in
                let usable = width - gutter - NoopMetrics.space2
                let columnWidth = usable / CGFloat(placement.columnCount)
                let height = max(NoopMetrics.minimumTouchTarget, CGFloat((placement.end - placement.start) / 3600) * hourHeight - NoopMetrics.spaceHalf)
                Button { onSelect(placement.event) } label: {
                    CalendarTimelineEventBlock(event: placement.event, compact: height < hourHeight * 0.75)
                        .frame(width: columnWidth - NoopMetrics.space1, height: height, alignment: .topLeading)
                        .clipped()
                }
                .buttonStyle(NoopFeedbackButtonStyle())
                .accessibilityLabel(Text(verbatim: placement.event.title))
                .accessibilityValue(Text(verbatim: CalendarEventTime.label(placement.event)))
                .offset(x: gutter + NoopMetrics.space2 + CGFloat(placement.column) * columnWidth,
                    y: CGFloat(placement.start / 3600) * hourHeight)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = captureNow ?? context.date
                if let offset = timeline.offset(of: now) {
                    HStack(spacing: 0) {
                        Text(verbatim: timeLabel(now)).font(StrandFont.caption).monospacedDigit()
                            .frame(width: gutter, alignment: .trailing).padding(.trailing, NoopMetrics.space1)
                        Circle().frame(width: NoopMetrics.space2, height: NoopMetrics.space2)
                        Rectangle().frame(height: NoopMetrics.hairlineWidth * 2)
                    }
                    .foregroundStyle(StrandPalette.liquidHeart)
                    .offset(y: CGFloat(offset / 3600) * hourHeight - NoopMetrics.space2)
                    .accessibilityLabel(Text("Current time") + Text(verbatim: " " + timeLabel(now)))
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: CGFloat(timeline.hours) * hourHeight + NoopMetrics.minimumTouchTarget, alignment: .top)
    }
    private func hourLabel(_ hour: Int) -> String {
        let date = timeline.start.addingTimeInterval(Double(hour) * 3600)
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = CalendarReaderDates.zone
        if timeline.hours != 24 { return date.formatted(style.timeZone(.specificName(.short))) }
        return date.formatted(style)
    }
    private func timeLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute(); style.timeZone = CalendarReaderDates.zone
        return date.formatted(style)
    }
}

private struct CalendarTimelineEventBlock: View {
    let event: CalendarReaderEvent
    let compact: Bool
    private var tint: Color {
        if event.displayContext == "work" { return StrandPalette.textSecondary }
        if event.source == "local_projection" { return StrandPalette.metricPurple }
        return event.linkedTaskRefs.isEmpty ? StrandPalette.metricSteps : StrandPalette.metricCyan
    }
    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space1) {
            RoundedRectangle(cornerRadius: NoopMetrics.spaceHalf).fill(tint).frame(width: NoopMetrics.space1)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(verbatim: event.title).font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary).lineLimit(compact ? 1 : 2)
                if !compact {
                    CalendarEventTime(event: event).font(StrandFont.caption).foregroundStyle(tint).lineLimit(1)
                    if event.source == "local_projection" { Text("Pending sync").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                }
            }.padding(.vertical, NoopMetrics.space1)
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(StrandPalette.calendarEventFillOpacity))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.calendarEventRadius).strokeBorder(tint, lineWidth: NoopMetrics.hairlineWidth))
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.calendarEventRadius))
    }
}
#endif
