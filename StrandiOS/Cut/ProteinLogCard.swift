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
    @State private var showLog = false
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardTileNumber

    private var weekReadings: [DashboardDailyReading] {
        guard let today = HeartDashboardProjection.date(day),
              let start = Calendar.current.date(byAdding: .day, value: -6, to: today) else { return [] }
        return HeartDashboardProjection.bounded(MetricRangeProjection.loggedProtein(
            standalone: protein.entries.map { ($0.day, $0.grams) },
            food: food.food.flatMap { day, entries in entries.map { (day, $0.protein) } }),
            from: Repository.localDayKey(start), through: day)
    }

    var body: some View {
        let grams = protein.total(day: logDay, foodProtein: food.protein(day: logDay))
        let loggedDate = HeartDashboardProjection.date(logDay)?.formatted(.dateTime.month(.abbreviated).day()) ?? logDay
        NoopCard(padding: NoopMetrics.space3, tint: StrandPalette.metricProtein, fillHeight: true) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Button { openedAt = Date(); logDay = Repository.localDayKey(openedAt); showEditor = true } label: {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack {
                            Text("Protein").font(StrandFont.subhead).fontWeight(.semibold)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                        Text("\(grams.formatted(.number.precision(.fractionLength(0)))) g")
                            .font(StrandFont.number(numberSize, weight: .semibold))
                    }.foregroundStyle(StrandPalette.textPrimary).frame(minHeight: NoopMetrics.minimumTouchTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Expand protein history").accessibilityValue("\(grams.formatted()) grams logged")
                Text(protein.targetGrams.map { "Logged \(loggedDate) · target \($0.formatted(.number.precision(.fractionLength(0)))) g" } ?? "Logged \(loggedDate)")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let target = protein.targetGrams {
                    ProgressView(value: min(grams, target), total: target).tint(StrandPalette.metricProtein)
                }
                if let today = HeartDashboardProjection.date(day), let start = Calendar.current.date(byAdding: .day, value: -6, to: today) {
                    let rows = weekReadings
                    if rows.isEmpty {
                        Text("No protein logged this week").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
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
                Button { showLog = true } label: {
                    Label("Log protein", systemImage: "plus").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.metricProtein)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: day) { _, value in logDay = value }
        .sheet(isPresented: $showEditor, onDismiss: { logDay = Repository.localDayKey(Date()) }) { ProteinHistoryView(store: protein, selection: $selection, now: openedAt) }
        .sheet(isPresented: $showLog, onDismiss: { logDay = Repository.localDayKey(Date()) }) { ProteinEntrySheet(store: protein) }
    }
}

private struct ProteinHistoryView: View {
    @ObservedObject var store: ProteinLogStore
    @ObservedObject private var food = CutPlanStore.shared
    @Binding var selection: MetricRangeSelection
    let now: Date
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var window: MetricDateWindow { selection.window(now: now) }
    private var rows: [DashboardDailyReading] {
        MetricRangeProjection.loggedProtein(
            standalone: store.entries.map { ($0.day, $0.grams) },
            food: food.food.flatMap { day, entries in entries.map { (day, $0.protein) } })
    }
    private var average: MetricAverageGroup? {
        MetricRangeProjection.groups(rows, window: window, separateMethods: false, allowZero: true).first
    }
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                MetricRangeControl(selection: $selection, now: now)
                NoopCard(tint: StrandPalette.metricProtein) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Average logged protein").font(StrandFont.headline).foregroundStyle(StrandPalette.metricProtein)
                        Text(average.map { $0.mean.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                            .font(StrandFont.number(numberSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                        Text("g/day · \(window.coverage(average?.readings.count ?? 0))")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if let target = store.targetGrams {
                            Text("Optional target · \(target.formatted()) g/day").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        if let average {
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
                        } else {
                            Text("No protein logged in this range").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                Button { showEditor = true } label: { Label("Log protein", systemImage: "plus") }
                    .font(StrandFont.subhead).buttonStyle(.bordered).tint(StrandPalette.metricProtein)
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                Text("Includes known protein from protein-only and food entries. Unlogged days are excluded; logged grams do not imply complete intake tracking.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if window.toDay == Repository.localDayKey(now) {
                    Text("Includes today’s partial log.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .navigationTitle("Protein").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(isPresented: $showEditor) { ProteinEntrySheet(store: store) }
    }
}

private struct ProteinEntrySheet: View {
    @ObservedObject var store: ProteinLogStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var food = CutPlanStore.shared
    @State private var grams = ""
    @State private var name = ""
    @State private var target = ""

    private func parsed(_ value: String) -> Double? {
        guard let value = Double(value.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Logged today") {
                    let day = Repository.localDayKey(Date())
                    let total = store.total(day: day, foodProtein: food.protein(day: day))
                    Text("\(total.formatted(.number.precision(.fractionLength(0)))) g protein")
                        .font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                    if let target = store.targetGrams {
                        Text("Target \(target.formatted(.number.precision(.fractionLength(0)))) g")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        ProgressView(value: min(total, target), total: target).tint(StrandPalette.metricProtein)
                    }
                    if food.protein(day: day) > 0 {
                        Text("Includes \(food.protein(day: day).formatted()) g from your food log.")
                    }
                    ForEach(store.entries.filter { $0.day == day }) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text("\(entry.grams.formatted()) g").font(StrandFont.bodyNumber)
                            Button { store.remove(entry.id) } label: { Image(systemName: "minus.circle") }
                                .frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                                .accessibilityLabel("Remove \(entry.name)")
                        }
                    }
                }
                Section("Log protein") {
                    TextField("Food or meal (optional)", text: $name)
                    TextField("Protein, grams", text: $grams).keyboardType(.decimalPad)
                    Button("Add protein") {
                        guard let value = parsed(grams) else { return }
                        store.add(grams: value, name: name, day: Repository.localDayKey(Date()))
                        dismiss()
                    }
                    .disabled(parsed(grams) == nil)
                }
                Section {
                    TextField("Daily target, grams (optional)", text: $target).keyboardType(.decimalPad)
                    Button("Save target") { store.targetGrams = parsed(target); dismiss() }
                        .disabled(!target.isEmpty && parsed(target) == nil)
                } header: {
                    Text("Your protein target")
                } footer: {
                    Text("Choose a fixed number of grams, or leave blank to track without a target. This is independent of your weight.")
                }
            }
            .navigationTitle("Protein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { target = store.targetGrams.map { String($0) } ?? "" }
        }
    }
}
