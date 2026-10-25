#if os(iOS)
import SwiftUI
import StrandDesign

struct DayHubView: View {
    let snapshot: DayHubSnapshot?
    let now: Date
    var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var food: DayHubSnapshot.Food? { snapshot?.food(at: now) }
    private var workouts: DayHubSnapshot.Workouts? { snapshot?.workouts(at: now) }
    private var sleep: DayHubSnapshot.Sleep? { snapshot?.sleep }
    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? NoopMetrics.space3 : NoopMetrics.space2) {
            HStack {
                Text("Today").font(expanded ? StrandFont.title1 : StrandFont.headline)
                Spacer(minLength: NoopMetrics.space1)
                Text(now, format: .dateTime.month(.abbreviated).day()).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            DayHubCalendarView(days: snapshot?.calendarDays ?? [], now: now, expanded: expanded)
            if expanded || typeSize.isAccessibilitySize {
                foodRow
                if let food, expanded {
                    Text("\(food.estimatedEntries) of \(food.entries) entries estimated").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text("Logged subtotal, not complete daily intake.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                workoutCard
                sleepCard
            } else {
                foodRow
                HStack(alignment: .top, spacing: NoopMetrics.space2) {
                    workoutCard.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    sleepCard.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.foregroundStyle(StrandPalette.textPrimary)
    }
    private func surface<V: View>(_ content: V) -> some View {
        content.padding(expanded ? NoopMetrics.space3 : NoopMetrics.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: NoopMetrics.calendarEventRadius))
    }
    private var foodRow: some View {
        Link(destination: DayHubSnapshot.link("food")) {
            surface(Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) { foodMetrics }
                } else {
                    HStack(alignment: .top, spacing: NoopMetrics.space2) { foodMetrics }
                }
            }.fixedSize(horizontal: false, vertical: true))
        }.buttonStyle(.plain).accessibilityHint("Open food log")
    }
    @ViewBuilder private var foodMetrics: some View {
        foodMetric("Protein", value: food.map { $0.protein.formatted(.number.precision(.fractionLength(0...1))) } ?? "—", unit: "g", tint: StrandPalette.metricProtein)
        foodMetric("Estimated calories", value: food?.calories.map { "≈" + $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", unit: "kcal", tint: StrandPalette.metricSteps)
    }
    private func foodMetric(_ title: LocalizedStringKey, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).lineLimit(expanded ? nil : 1)
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(verbatim: value).font(StrandFont.number(expanded ? NoopMetrics.dashboardTileNumber : NoopMetrics.dayHubCompactNumber, weight: .semibold)).foregroundStyle(tint)
                Text(verbatim: unit).font(StrandFont.caption)
            }.monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var primaryWorkout: DayHubSnapshot.Workout? {
        let rows = workouts?.rows ?? []
        return rows.first { $0.status == "in_progress" } ?? rows.first { $0.status == "planned" } ?? rows.first
    }
    private var workoutCard: some View {
        Link(destination: DayHubSnapshot.link("workouts")) {
            surface(VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Label("Workout", systemImage: "dumbbell").font(StrandFont.caption).foregroundStyle(StrandPalette.metricHRV)
                Text(primaryWorkout?.title ?? String(localized: workouts?.complete == true ? "No workout scheduled" : "Open Exercises to update"))
                    .font(StrandFont.subhead.weight(.semibold)).lineLimit(expanded ? nil : 1)
                if let row = primaryWorkout {
                    HStack(spacing: NoopMetrics.space1) {
                        Image(systemName: row.status == "completed" ? "checkmark.circle.fill" : row.status == "in_progress" ? "play.circle" : "circle")
                        Text(verbatim: workoutStatus(row.status))
                        if !expanded, let readAt = workouts?.readAt {
                            Spacer(minLength: NoopMetrics.space1)
                            Text(readAt, style: .time).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if expanded, let timing = row.timing, !timing.isEmpty { Text(verbatim: timing).font(StrandFont.caption) }
                }
                if expanded, let workouts {
                    ForEach(workouts.rows.filter { $0.id != primaryWorkout?.id }) { row in
                        HStack { Text(verbatim: row.title); Spacer(); Image(systemName: row.status == "completed" ? "checkmark.circle.fill" : "circle") }
                            .font(StrandFont.subhead).accessibilityLabel(Text(verbatim: row.title + ", " + workoutStatus(row.status)))
                    }
                    if !workouts.complete { Text("More in Exercises").font(StrandFont.caption) }
                    sourceTime(workouts.readAt)
                }
            }.frame(minHeight: NoopMetrics.minimumTouchTarget, alignment: .topLeading))
        }.buttonStyle(.plain).accessibilityHint("Open Exercises")
    }
    private func workoutStatus(_ value: String) -> String {
        switch value {
        case "completed": return String(localized: "Done")
        case "in_progress": return String(localized: "In progress")
        case "skipped": return String(localized: "Skipped")
        default: return String(localized: "Planned")
        }
    }
    private var sleepCard: some View {
        Link(destination: DayHubSnapshot.link("sleep")) {
            surface(HStack(spacing: NoopMetrics.space2) {
                ZStack {
                    sleepRing(sleep?.whoopMinutes, tint: StrandPalette.metricHRV)
                    sleepRing(sleep?.eightSleepMinutes, tint: StrandPalette.metricSteps).padding(NoopMetrics.dayHubRingInset)
                    Image(systemName: "moon.fill").font(StrandFont.caption).foregroundStyle(StrandPalette.metricHRV)
                }.frame(width: NoopMetrics.dayHubRingDiameter, height: NoopMetrics.dayHubRingDiameter).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                    HStack(spacing: NoopMetrics.space1) {
                        Text("Sleep")
                        if let sleep { Text(verbatim: String(sleep.wakeDay.suffix(5))) }
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    providerReading("WHOOP", minutes: sleep?.whoopMinutes).font(StrandFont.caption.weight(.semibold))
                    providerReading("8sleep", minutes: sleep?.eightSleepMinutes).font(StrandFont.caption.weight(.semibold))
                    if expanded, let sleep {
                        Text(verbatim: sleep.wakeDay).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if let method = sleep.whoopMethod { Text(verbatim: method).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
                    }
                }
            }.frame(minHeight: NoopMetrics.minimumTouchTarget, alignment: .topLeading))
        }.buttonStyle(.plain).accessibilityHint("Open sleep comparison")
    }
    private func sleepRing(_ minutes: Double?, tint: Color) -> some View {
        ZStack {
            Circle().stroke(StrandPalette.hairline, lineWidth: NoopMetrics.space1)
            Circle().trim(from: 0, to: min(1, max(0, (minutes ?? 0) / 495)))
                .stroke(tint, style: .init(lineWidth: NoopMetrics.space1, lineCap: .round)).rotationEffect(.degrees(-90))
        }.padding(NoopMetrics.spaceHalf)
    }
    private func providerReading(_ provider: String, minutes: Double?) -> Text { Text(verbatim: provider + " " + duration(minutes)) }
    private func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes >= 0 else { return "—" }
        let value = Int(minutes.rounded()); return "\(value / 60)h\(String(format: "%02d", value % 60))"
    }
    private func sourceTime(_ date: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoopMetrics.space1) { Text("Updated"); Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()) }
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) { Text("Updated"); Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()) }
        }.font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
    }
}

struct DayHubCalendarView: View {
    let days: [CalendarWidgetSnapshot.Day]
    let now: Date
    var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var window: DayHubWindow { .init(now: now) }
    private var height: CGFloat { expanded ? NoopMetrics.dayHubCalendarExpanded : NoopMetrics.dayHubCalendarCompact }
    private var timeStyle: Date.FormatStyle { var v = Date.FormatStyle.dateTime.hour().minute(); v.timeZone = CalendarWidgetSnapshot.timeZone; return v }
    private var axisStyle: Date.FormatStyle {
        var value = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        value.timeZone = CalendarWidgetSnapshot.timeZone; return value
    }
    private var rangeLabel: some View {
        HStack(spacing: NoopMetrics.space1) {
            Text(window.start, format: timeStyle); Text("–"); Text(window.end, format: timeStyle)
            if TimeZone.current != CalendarWidgetSnapshot.timeZone { Text(verbatim: CalendarWidgetSnapshot.timeZone.abbreviation(for: now) ?? CalendarWidgetSnapshot.timeZone.identifier) }
        }.fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder private var calendarFreshness: some View {
        if let read = days.filter({ window.requiredDays.contains($0.date) }).map(\.readAt).min() {
            HStack(spacing: NoopMetrics.space1) {
                Image(systemName: "arrow.clockwise")
                if CalendarWidgetSnapshot.dayKey(read) != CalendarWidgetSnapshot.dayKey(now) { Text(read, format: .dateTime.month(.abbreviated).day()) }
                Text(read, format: timeStyle)
            }.fixedSize(horizontal: true, vertical: false)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoopMetrics.space1) { rangeLabel; Spacer(minLength: 0); calendarFreshness }
                VStack(alignment: .leading, spacing: NoopMetrics.space1) { rangeLabel; calendarFreshness }
            }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            GeometryReader { proxy in
                let gutter = NoopMetrics.dayHubTimeGutter
                let width = max(1, proxy.size.width - gutter)
                let placed = window.placements(days)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<7, id: \.self) { tick in
                        let y = CGFloat(tick) / 6 * height
                        HStack(spacing: NoopMetrics.space1) {
                            Text(window.start.addingTimeInterval(Double(tick) * 1800), format: axisStyle)
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).lineLimit(1).frame(width: gutter, alignment: .leading)
                            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                        }.offset(y: max(0, min(height - NoopMetrics.space3, y)))
                        .opacity(expanded || tick % 2 == 0 ? 1 : 0)
                    }
                    ForEach(placed.prefix(expanded ? 40 : 8)) { p in
                        let x = gutter + CGFloat(p.column) * width / CGFloat(p.columns)
                        let y = CGFloat(p.start / 10800) * height
                        let h = max(NoopMetrics.spaceHalf, CGFloat((p.end - p.start) / 10800) * height)
                        Link(destination: CalendarWidgetSnapshot.link(day: p.day, eventID: p.event.id)!) {
                            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                                Text(verbatim: p.event.title).font(StrandFont.caption.weight(.semibold)).lineLimit(expanded ? 2 : 1)
                                if expanded, let organizer = p.event.organizer { Text(verbatim: organizer).font(StrandFont.caption).lineLimit(1) }
                            }.padding(NoopMetrics.space1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(StrandPalette.metricSteps.opacity(0.22), in: RoundedRectangle(cornerRadius: NoopMetrics.space1))
                                .overlay(alignment: .leading) { Rectangle().fill(StrandPalette.metricSteps).frame(width: NoopMetrics.spaceHalf) }
                        }.buttonStyle(.plain).frame(width: max(1, width / CGFloat(p.columns) - NoopMetrics.spaceHalf), height: h).clipped().offset(x: x, y: y)
                            .accessibilityLabel(Text(verbatim: p.event.title)).accessibilityValue(Text(p.event.start ?? now, format: timeStyle))
                    }
                    HStack(spacing: 0) {
                        Circle().fill(StrandPalette.liquidHeart).frame(width: NoopMetrics.space2, height: NoopMetrics.space2)
                        Rectangle().fill(StrandPalette.liquidHeart).frame(height: NoopMetrics.hairlineWidth)
                    }.offset(x: gutter - NoopMetrics.space1, y: height / 2)
                    if placed.isEmpty {
                        Text(window.complete(days) ? "No events in this window" : "Open Calendar to update")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).padding(.leading, gutter).padding(.top, NoopMetrics.space3)
                    }
                }.frame(width: proxy.size.width, height: height, alignment: .topLeading).clipped()
            }.frame(height: height)
                .dynamicTypeSize(typeSize.isAccessibilitySize ? .large : typeSize)
            if expanded {
                ForEach(window.placements(days)) { p in
                    Link(destination: CalendarWidgetSnapshot.link(day: p.day, eventID: p.event.id)!) {
                        HStack(spacing: NoopMetrics.space2) {
                            Text(p.event.start ?? now, format: timeStyle).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            Text(verbatim: p.event.title).font(StrandFont.subhead)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(StrandFont.caption)
                        }.frame(minHeight: NoopMetrics.minimumTouchTarget).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if !window.complete(days), !window.placements(days).isEmpty {
                Text("Calendar may be incomplete").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }.accessibilityElement(children: .contain)
    }
}
#endif
