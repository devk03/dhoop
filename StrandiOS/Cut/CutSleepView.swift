import SwiftUI
import Charts
import StrandDesign

struct CutSleepView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var history = SleepRangeModel()
    @State private var selection = MetricRangeSelection()
    @State private var capturedAt = Date()
    @State private var refreshToken = 0
    @State private var showHealth = false
    @AppStorage("dhoop.sleep.appleComparisonSource") private var providerID = ""
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var window: MetricDateWindow { selection.window(now: capturedAt) }
    private var result: SleepRangeSnapshot? {
        guard let value = history.snapshot, value.deviceId == repo.deviceId, window.canDisplaySnapshot(value.window) else { return nil }
        return value
    }
    private var whoop: [SleepComparisonDay] { result?.whoop ?? [] }
    private var appleProvider: SleepComparisonProvider? {
        let choices = result?.apple ?? []
        return choices.first { $0.id == providerID } ?? choices.first { $0.isEightSleep } ?? choices.first
    }
    private var comparisonName: String { appleProvider?.displayName ?? "8sleep" }
    private var comparisonDetail: String {
        guard let provider = appleProvider else { return "No readable sleep" }
        return provider.isEightSleep ? "Via Apple Health" : provider.detail
    }
    private var apple: [SleepComparisonDay] { appleProvider?.days ?? [] }
    private var pairs: [SleepComparisonProjection.Pair] { SleepComparisonProjection.matched(whoop, apple) }
    private var grid: DashboardGridLayout { DashboardGridLayout(columns: typeSize >= .xxxLarge ? 1 : 2) }
    private var whoopMethod: String {
        let kinds = Set(whoop.map(\.method))
        return kinds.count == 1 ? kinds.first! : kinds.isEmpty ? "No sleep in range" : "Records + estimates"
    }

    var body: some View {
        ScreenScaffold(title: nil, onRefresh: refresh, lazy: false) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack {
                Text("Sleep").font(StrandFont.title1)
                Spacer(minLength: NoopMetrics.space2)
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget) }
                    .accessibilityLabel("Refresh sleep comparison").disabled(history.snapshot == nil && history.error == nil)
            }
            MetricRangeControl(selection: $selection, now: capturedAt)
            if history.isRefreshing { ProgressView(result == nil ? "Reading sleep sources…" : "Updating saved sleep…").font(StrandFont.caption) }
            grid {
                sourceCard("WHOOP", icon: "waveform.path", rows: whoop, detail: whoopMethod, tint: StrandPalette.metricPurple)
                sourceCard(comparisonName, icon: "bed.double", rows: apple, detail: comparisonDetail, tint: StrandPalette.metricCyan)
            }
            if let result, result.apple.count > 1 {
                Picker("Comparison sleep source", selection: Binding(get: { appleProvider?.id ?? "" }, set: { providerID = $0 })) {
                    ForEach(result.apple) { Text($0.displayName).tag($0.id) }
                }.pickerStyle(.menu).font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
            comparisonSummary
            if window.days != 1 && Set((whoop + apple).map(\.day)).count > 1 { trendCard }
            stagesCard
            if whoop.isEmpty && result != nil {
                Label("No WHOOP-attributed sleep for these dates. Sync after wearing overnight; older estimates with unknown sources are excluded.", systemImage: "moon.zzz")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if let error = history.error { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
            if let message = result?.healthMessage {
                Text(message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Button("Apple Health access") { showHealth = true }.font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
            notes
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { capturedAt = Date() }
        .task(id: "\(repo.deviceId)|\(window.identity)|\(refreshToken)|\(repo.refreshSeq)") { await history.load(repo: repo, window: window) }
        .sheet(isPresented: $showHealth, onDismiss: refresh) {
            NavigationStack {
                AppleHealthView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHealth = false } } }
            }
        }
    }
    private func refresh() { ble.syncNow(); capturedAt = Date(); refreshToken += 1 }
    private func sourceCard(_ title: String, icon: String, rows: [SleepComparisonDay], detail: String, tint: Color) -> some View {
        NoopCard(tint: tint, fillHeight: true) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label(title, systemImage: icon).font(StrandFont.subhead).foregroundStyle(tint)
                let average = SleepComparisonProjection.mean(rows.map(\.total))
                Text(average.map { sleepHM($0).replacingOccurrences(of: "h ", with: "h") } ?? "—")
                    .font(StrandFont.number(numberSize, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityLabel(average.map(sleepHM) ?? "Unavailable")
                Text(detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(window.coverage(rows.count)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if window.days != 1 { Text("Average recorded sleep").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
    private var comparisonSummary: some View {
        NoopCard {
            HStack(alignment: .top, spacing: NoopMetrics.space3) {
                Image(systemName: "equal.circle").foregroundStyle(StrandPalette.textSecondary)
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    if let difference = SleepComparisonProjection.mean(pairs.map { abs($0.apple.total - $0.whoop.total) }), !pairs.isEmpty {
                        let signed = pairs.reduce(0.0) { $0 + $1.apple.total - $1.whoop.total } / Double(pairs.count)
                        Text(abs(signed) < 0.5 ? "Same average sleep duration" : "\(comparisonName) recorded \(sleepHM(abs(signed))) \(signed > 0 ? "more" : "less")")
                            .font(StrandFont.headline)
                        Text("\(pairs.count) matched \(pairs.count == 1 ? "date" : "dates")\(pairs.count > 1 ? " · average difference" : "")")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if difference > abs(signed) + 1 {
                            Text("Typical absolute gap · \(sleepHM(difference))").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                    } else if result == nil && history.error == nil {
                        Text("Reading both sources…").font(StrandFont.headline)
                    } else {
                        Text("No overlapping sleep dates").font(StrandFont.headline)
                        Text("Both sources need a record on the same date to compare.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }
    private var stagesCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Sleep stages").font(StrandFont.headline)
                Text(pairs.isEmpty ? "Available records · sources shown separately" : "Stage averages use dates with both stage values")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                stageRow("Deep", key: \.deep)
                Divider()
                stageRow("REM", key: \.rem)
                Divider()
                stageRow("Light / Core", key: \.light)
                Divider()
                stageRow("Unclassified", key: \.unspecified)
            }
        }
    }
    private func stageRow(_ title: String, key: KeyPath<SleepComparisonDay, Double?>) -> some View {
        let comparable = pairs.filter { $0.whoop[keyPath: key] != nil && $0.apple[keyPath: key] != nil }
        let left = pairs.isEmpty ? whoop.compactMap { $0[keyPath: key] } : comparable.compactMap { $0.whoop[keyPath: key] }
        let right = pairs.isEmpty ? apple.compactMap { $0[keyPath: key] } : comparable.compactMap { $0.apple[keyPath: key] }
        let maximum = max(1, max(SleepComparisonProjection.mean(whoop.map(\.total)) ?? 0, SleepComparisonProjection.mean(apple.map(\.total)) ?? 0))
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack {
                Text(title).font(StrandFont.subhead)
                Spacer(minLength: NoopMetrics.space1)
                if !pairs.isEmpty { Text("\(comparable.count) matched").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            }
            DashboardGridLayout(columns: typeSize >= .xxxLarge ? 1 : 2, squareMinimum: false) {
                stageValue("WHOOP", values: left, maximum: maximum, tint: StrandPalette.metricPurple)
                stageValue(comparisonName, values: right, maximum: maximum, tint: StrandPalette.metricCyan)
            }
        }
    }
    private func stageValue(_ title: String, values: [Double], maximum: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            HStack {
                Text(title).foregroundStyle(tint)
                Spacer(minLength: NoopMetrics.space1)
                Text(SleepComparisonProjection.mean(values).map(sleepHM) ?? "—").monospacedDigit()
            }.font(StrandFont.caption)
            if let mean = SleepComparisonProjection.mean(values) { ProgressView(value: min(mean, maximum), total: maximum).tint(tint) }
            if window.days != 1 {
                Text("\(values.count) \(values.count == 1 ? "record" : "records")").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }.accessibilityElement(children: .combine)
    }
    private var trendCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Recorded sleep duration").font(StrandFont.headline)
                let whoopPoints = chartPoints(whoop, prefix: "whoop")
                let applePoints = chartPoints(apple, prefix: "apple")
                let singletons = Set(Dictionary(grouping: whoopPoints + applePoints, by: \.segment).filter { $0.value.count == 1 }.keys)
                Chart {
                    ForEach(whoopPoints) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("Hours", p.value), series: .value("Segment", p.segment), stacking: .unstacked)
                            .foregroundStyle(StrandChartStyle.area(StrandPalette.metricPurple)).interpolationMethod(.linear)
                            .alignsMarkStylesWithPlotArea()
                        LineMark(x: .value("Date", p.date), y: .value("Hours", p.value), series: .value("Segment", p.segment))
                            .foregroundStyle(StrandPalette.metricPurple).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: StrandChartStyle.lineWidth, lineCap: .round))
                        if whoopPoints.count <= StrandChartStyle.sparsePointLimit || singletons.contains(p.segment) {
                            PointMark(x: .value("Date", p.date), y: .value("Hours", p.value))
                                .foregroundStyle(StrandPalette.metricPurple).symbolSize(StrandChartStyle.pointArea)
                        }
                    }
                    ForEach(applePoints) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("Hours", p.value), series: .value("Segment", p.segment), stacking: .unstacked)
                            .foregroundStyle(StrandChartStyle.area(StrandPalette.metricCyan)).interpolationMethod(.linear)
                            .alignsMarkStylesWithPlotArea()
                        LineMark(x: .value("Date", p.date), y: .value("Hours", p.value), series: .value("Segment", p.segment))
                            .foregroundStyle(StrandPalette.metricCyan).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: StrandChartStyle.lineWidth, lineCap: .round))
                        if applePoints.count <= StrandChartStyle.sparsePointLimit || singletons.contains(p.segment) {
                            PointMark(x: .value("Date", p.date), y: .value("Hours", p.value))
                                .foregroundStyle(StrandPalette.metricCyan).symbolSize(StrandChartStyle.pointArea)
                        }
                    }
                }
                .chartLegend(.hidden).chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(StrandChartStyle.gridOpacity))
                    AxisValueLabel().font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                } }
                .chartPlotStyle { $0.clipped() }
                .frame(height: NoopMetrics.dashboardTraceHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep duration by date. WHOOP \(whoop.count) records, \(comparisonName) \(apple.count) records. Missing dates remain gaps.")
                .chartInspection(sleepInspection, label: "WHOOP and \(comparisonName) sleep duration", tint: StrandPalette.metricCyan)
                HStack(spacing: NoopMetrics.space3) {
                    Label("WHOOP", systemImage: "circle.fill").foregroundStyle(StrandPalette.metricPurple)
                    Label(comparisonName, systemImage: "circle.fill").foregroundStyle(StrandPalette.metricCyan)
                }.font(StrandFont.caption)
            }
        }
    }
    private var sleepInspection: [ChartScrubDatum] {
        [whoop, apple].enumerated().flatMap { index, rows in
            var previous: (date: Date, source: String)?
            var segment = 0
            return rows.compactMap { row -> ChartScrubDatum? in
                guard let date = HeartDashboardProjection.date(row.day) else { return nil }
                if let previous, date.timeIntervalSince(previous.date) > 90_000 || previous.source != row.sourceID { segment += 1 }
                previous = (date, row.sourceID)
                let source = index == 0 ? "WHOOP · \(row.method)" : "\(comparisonName) · via Apple Health"
                return ChartScrubDatum(id: "\(index)|\(row.sourceID)|\(row.day)", x: date.timeIntervalSince1970, y: row.total / 60,
                    value: "\(source): \(sleepHM(row.total))", context: date.formatted(date: .abbreviated, time: .omitted), series: String(index), segment: String(segment))
            }
        }
    }
    private func chartPoints(_ rows: [SleepComparisonDay], prefix: String) -> [TrendPoint] {
        let samples = rows.compactMap { row -> DashboardTraceSample? in
            guard let date = HeartDashboardProjection.date(row.day) else { return nil }
            return DashboardTraceSample(time: date.timeIntervalSince1970, value: row.total / 60, provenance: "\(prefix)|\(row.sourceID)")
        }
        return DashboardTraceSampling.reduce(HeartDashboardProjection.trace(samples, from: window.start.timeIntervalSince1970, through: window.through.timeIntervalSince1970, gapSeconds: 90_000)
            .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: "\(prefix)|\($0.segment)") })
    }
    private var notes: some View {
        NoopCard {
            DisclosureGroup("About this comparison") {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("WHOOP records and Dhoop estimates stay separate from \(comparisonName) sleep received via Apple Health. Dhoop estimates are local algorithms, not WHOOP's official sleep scores. Computed records without recorded WHOOP input provenance are excluded.")
                    Text("Apple providers are kept separate and overlapping samples from one provider count once. Nearby stage fragments form a sleep period; totals include recorded sleep periods ending on that date, including naps. Awake gaps are not filled. Unknown or conflicting stages stay unclassified.")
                    Text("Dates can match while devices disagree on sleep boundaries. Differences show agreement, not which device is physiologically correct. Older saved Apple totals may combine providers and use segment-end dates.")
                    if let provider = appleProvider { Text("HealthKit source: \(provider.name)\n\(provider.detail)").textSelection(.enabled) }
                    Text("WHOOP sources: \(Set(whoop.map(\.sourceID)).sorted().joined(separator: ", "))")
                }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).padding(.top, NoopMetrics.space2)
            }.font(StrandFont.subhead)
        }
    }

}

func sleepHM(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
}
func sleepClock(_ ts: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
}
