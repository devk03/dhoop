import SwiftUI
import StrandDesign

struct ProteinLogCard: View {
    let day: String
    @State private var openedAt = Date()
    @Binding var selection: MetricRangeSelection
    @State private var logDay: String
    init(day: String, selection: Binding<MetricRangeSelection>) {
        self.day = day
        self._selection = selection; _logDay = State(initialValue: day)
    }
    @StateObject private var protein = ProteinLogStore()
    @ObservedObject private var food = CutPlanStore.shared
    @State private var showEditor = false
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardTileNumber

    private var loggedReadings: [DashboardDailyReading] {
        guard !protein.storageUnavailable else { return [] }
        return MetricRangeProjection.loggedProtein(standalone: protein.entries.map { ($0.day, $0.grams) },
            food: food.food.flatMap { day, entries in entries.map { (day, $0.protein) } })
    }
    private var weekReadings: [DashboardDailyReading] {
        guard let today = HeartDashboardProjection.date(day),
              let start = Calendar.current.date(byAdding: .day, value: -6, to: today) else { return [] }
        return HeartDashboardProjection.bounded(loggedReadings, from: Repository.localDayKey(start), through: day)
    }

    var body: some View {
        let grams = loggedReadings.first { $0.day == logDay }?.value
        let loggedDate = HeartDashboardProjection.date(logDay)?.formatted(.dateTime.month(.abbreviated).day()) ?? logDay
        NoopCard(padding: NoopMetrics.space3, tint: StrandPalette.metricProtein, fillHeight: true) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Button { openProtein() } label: {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack {
                            Text("Protein").font(StrandFont.subhead).fontWeight(.semibold)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                        Text(grams.map { "\($0.formatted(.number.precision(.fractionLength(0)))) g" } ?? "—")
                            .font(StrandFont.number(numberSize, weight: .semibold))
                    }.foregroundStyle(StrandPalette.textPrimary).frame(minHeight: NoopMetrics.minimumTouchTarget).contentShape(Rectangle())
                }.buttonStyle(NoopFeedbackButtonStyle()).accessibilityLabel("Expand protein history").accessibilityValue(protein.storageUnavailable ? "Protein log unavailable" : grams.map { "\($0.formatted()) grams logged" } ?? "No protein logged for this date")
                if protein.storageUnavailable { Text("Protein log unavailable").font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical) }
                Text(protein.storageUnavailable ? "Saved entries need a successful read" : grams == nil ? "No protein logged for this date" : (protein.targetGrams.map { "Logged \(loggedDate) · target \($0.formatted(.number.precision(.fractionLength(0)))) g" } ?? "Logged \(loggedDate)"))
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let target = protein.targetGrams, let grams, !protein.storageUnavailable {
                    ProgressView(value: min(grams, target), total: target).tint(StrandPalette.metricProtein)
                }
                if let today = HeartDashboardProjection.date(day), let start = Calendar.current.date(byAdding: .day, value: -6, to: today) {
                    let rows = weekReadings
                    if rows.isEmpty {
                        Text(protein.storageUnavailable ? "History could not be read" : "No protein logged this week").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(minHeight: NoopMetrics.dashboardTileChartHeight, alignment: .leading)
                    } else {
                        DashboardChart(points: rows.compactMap { row in
                            HeartDashboardProjection.date(row.day).map { TrendPoint(date: $0, value: row.value) }
                        }, domain: start...today.addingTimeInterval(86_400), range: 0...max(1, (rows.map(\.value).max() ?? 0) * 1.1),
                            tint: StrandPalette.metricProtein, style: .bars, height: NoopMetrics.dashboardTileChartHeight,
                            label: "Protein logged over seven days; unlogged days have no bars", compact: true,
                            valueFormat: { "\($0.formatted()) g logged" })
                    }
                }
                Button { openProtein() } label: {
                    Label("Log protein", systemImage: "plus").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.metricProtein)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                }.buttonStyle(NoopFeedbackButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .onAppear { try? protein.reload() }
        .onChange(of: day) { _, value in logDay = value }
        .sheet(isPresented: $showEditor, onDismiss: { logDay = Repository.localDayKey(Date()) }) { ProteinHistoryView(store: protein, selection: $selection, now: openedAt) }
    }

    private func openProtein() {
        openedAt = Date(); logDay = Repository.localDayKey(openedAt)
        selection.preset = .today; showEditor = true
    }
}

private struct ProteinHistoryView: View {
    @ObservedObject var store: ProteinLogStore
    @ObservedObject private var food = CutPlanStore.shared
    @Binding var selection: MetricRangeSelection
    let now: Date
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var window: MetricDateWindow { selection.window(now: now) }
    private var rows: [DashboardDailyReading] {
        MetricRangeProjection.loggedProtein(
            standalone: store.entries.map { ($0.day, $0.grams) },
            food: food.food.flatMap { day, entries in entries.map { (day, $0.protein) } })
    }
    private var average: MetricAverageGroup? {
        store.storageUnavailable ? nil : MetricRangeProjection.groups(rows, window: window, separateMethods: false, allowZero: true).first
    }
    private var calorieEstimates: [Double?] {
        guard !store.storageUnavailable else { return [] }
        return store.entries.filter { $0.day >= window.fromDay && $0.day <= window.toDay }.map(\.calories)
            + food.food.filter { $0.key >= window.fromDay && $0.key <= window.toDay }.values.flatMap { $0.map { Double($0.kcal) } }
    }
    private var calorieDayTotals: [Double] {
        guard !store.storageUnavailable else { return [] }
        let days = Set(store.entries.map(\.day) + Array(food.food.keys)).filter { $0 >= window.fromDay && $0 <= window.toDay }
        return days.compactMap { key in
            NutritionCalorieSummary(estimates: store.entries.filter { $0.day == key }.map(\.calories)
                + (food.food[key] ?? []).map { Double($0.kcal) }).calories
        }
    }
    private struct DayEntry: Identifiable {
        let id: String
        let name: String
        let grams: Double?
        let calories: Double?
        let time: Date?
        let removableId: UUID?
    }
    private var dayEntries: [DayEntry] {
        let standalone = (store.storageUnavailable ? [] : store.entries).filter { $0.day == window.fromDay }.map {
            DayEntry(id: "protein|\($0.id)", name: $0.name, grams: $0.grams, calories: $0.calories, time: $0.loggedAt, removableId: $0.id)
        }
        let meals = (food.food[window.fromDay] ?? []).map { entry in
            DayEntry(id: "food|\(entry.id)", name: entry.name, grams: entry.protein, calories: Double(entry.kcal), time: entry.at, removableId: nil)
        }
        return (standalone + meals).sorted {
            if $0.time != $1.time { return ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
            return $0.id < $1.id
        }
    }
    private func proteinRow(name: String, grams: Double?, calories: Double?, time: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(name).font(StrandFont.subhead)
                Text(time.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Time not recorded")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space1)
            VStack(alignment: .trailing, spacing: NoopMetrics.space1) {
                Text(grams.map { "\($0.formatted()) g" } ?? String(localized: "Protein unknown")).font(StrandFont.bodyNumber)
                Text(calories.map { "\($0.formatted()) kcal" } ?? String(localized: "Calories unknown"))
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }.accessibilityElement(children: .combine)
    }
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                FoodInlineEntry(store: store, day: window.isSingleDay ? window.fromDay : Repository.localDayKey(now))
                MetricRangeControl(selection: $selection, now: now)
                if !store.storageUnavailable {
                    FoodCalorieSummaryCard(estimates: calorieEstimates, dayTotals: calorieDayTotals, singleDay: window.isSingleDay, proteinGrams: average?.mean)
                }
                NutritionGoalEditor(day: window.isSingleDay ? window.fromDay : Repository.localDayKey(now))
                if !window.isSingleDay { NoopCard(tint: StrandPalette.metricProtein) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text(window.isSingleDay ? "Protein logged" : "Average logged protein").font(StrandFont.headline).foregroundStyle(StrandPalette.metricProtein)
                        Text(average.map { $0.mean.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                            .font(StrandFont.number(numberSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                        Text("\(window.isSingleDay ? "g" : "g/day") · \(window.coverage(average?.readings.count ?? 0))")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if let target = store.targetGrams {
                            Text("Optional target · \(target.formatted()) g/day").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        if let average, !window.isSingleDay {
                            let values = average.readings.map(\.value)
                            let points = average.readings.compactMap { row -> TrendPoint? in
                                guard let date = HeartDashboardProjection.date(row.day) else { return nil }
                                return TrendPoint(date: date, value: row.value)
                            }
                            let start = window.days == nil ? (points.first?.date ?? window.end) : window.start
                            DashboardChart(points: DashboardTraceSampling.reduce(points), domain: start...max(start.addingTimeInterval(1), window.through),
                                range: 0...max(1, (values.max() ?? 0) * 1.1), tint: StrandPalette.metricProtein,
                                style: .bars, height: NoopMetrics.chartHeight,
                                label: "Protein grams logged on recorded days in the selected range; unlogged days have no bars",
                                inspectionData: points.map { ChartScrubDatum(id: String($0.date.timeIntervalSince1970), x: $0.date.timeIntervalSince1970, y: $0.value,
                                    value: "\($0.value.formatted()) g logged", context: $0.date.formatted(date: .abbreviated, time: .omitted), series: "Protein log") })
                        } else if average == nil {
                            Text(store.storageUnavailable ? "Protein history is unavailable" : "No protein logged in this range").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                }
                if window.isSingleDay {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Entries").font(StrandFont.headline)
                            ForEach(dayEntries) { entry in
                                HStack(spacing: NoopMetrics.space2) {
                                    proteinRow(name: entry.name, grams: entry.grams, calories: entry.calories, time: entry.time)
                                    if let id = entry.removableId {
                                        NoopAsyncButton("", systemImage: "minus.circle", kind: .tertiary) { try store.remove(id) }
                                            .disabled(store.storageUnavailable)
                                            .frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                                            .accessibilityLabel("Remove food")
                                    }
                                }
                            }
                            if average == nil {
                                Text(store.storageUnavailable ? "Only readable food entries can be shown" : "No entries for this day").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                }
                Text("Includes known protein from protein-only and food entries. Unlogged days are excluded; logged grams do not imply complete intake tracking.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if window.toDay == Repository.localDayKey(now) {
                    Text("Includes today’s partial log.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .navigationTitle("Food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
