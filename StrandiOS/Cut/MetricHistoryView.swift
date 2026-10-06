import SwiftUI
import StrandDesign

struct MetricHistoryView: View {
    @EnvironmentObject private var profile: ProfileStore
    @State private var fitnessInputs: FitnessInputStatus?
    @State private var selectedSourceID = ""
    @ObservedObject var repo: Repository
    let deviceId: String
    let metric: DashboardHistoryMetric
    let now: Date
    @Binding var selection: MetricRangeSelection
    @StateObject private var history = MetricRangeModel()
    @State private var refreshedAt: Date?
    private var referenceDate: Date { refreshedAt ?? now }
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var window: MetricDateWindow { selection.window(now: referenceDate) }
    private var result: MetricRangeSnapshot? {
        guard let result = history.snapshot, result.deviceId == deviceId, result.metric == metric,
              window.canDisplaySnapshot(result.window) else { return nil }
        return result
    }

    private var selectedGroup: MetricAverageGroup? {
        let groups = result?.groups ?? []
        return groups.first { $0.id == selectedSourceID }
            ?? groups.first { $0.isMeasuredHeartRate }
            ?? groups.max { $0.readings.count < $1.readings.count }
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                MetricRangeControl(selection: $selection, now: referenceDate)
                if metric == .vo2, let result, result.availability.firstDay == nil, let inputs = fitnessInputs {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text(inputs.summary).font(StrandFont.headline)
                            Text(inputs.detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                if let result, result.groups.count > 1 {
                    Picker("Data source", selection: Binding(get: { selectedGroup?.id ?? "" }, set: { selectedSourceID = $0 })) {
                        ForEach(result.groups) { group in
                            Text("\(source(group)) · \(group.readings.count) days").tag(group.id)
                        }
                    }.pickerStyle(.menu).font(StrandFont.subhead)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                NoopCard(tint: tint) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text(metric == .heartRate ? "Average recorded HR" : "Average \(metric.title)")
                            .font(StrandFont.headline).foregroundStyle(tint)
                        metricValue(selectedGroup?.displayedMean(sampleWeightedHR: result?.hrMean))
                        if let result {
                            Text(window.coverage(selectedGroup?.readings.count ?? 0))
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            if selectedGroup?.isMeasuredHeartRate == true {
                                Text("\(result.hrCount.formatted()) measured readings · sample-weighted average")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            } else if let group = selectedGroup {
                                Text(groupDescription(group)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            if let group = selectedGroup {
                                Text(recordedDates(group)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            rangeChart(selectedGroup?.readings ?? [])
                            if history.isRefreshing { ProgressView("Updating saved history…").font(StrandFont.caption) }
                            if let error = history.error {
                                Text("Showing the previous snapshot. \(error)").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                            }
                        } else if let error = history.error {
                            Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                        } else {
                            ProgressView("Reading saved history…")
                        }
                    }
                }
                if let result {
                    if result.availability.hasHiddenDays {
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                Text("More saved history").font(StrandFont.headline)
                                if result.availability.earlierDays > 0 {
                                    Text("\(result.availability.earlierDays.formatted()) recorded days before this range")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                if result.availability.laterDays > 0 {
                                    Text("\(result.availability.laterDays.formatted()) recorded days after this range")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                if let first = result.availability.firstDay, let last = result.availability.lastDay {
                                    Text("Saved dates: \(dateLabel(first)) – \(dateLabel(last))")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                Button("Show all history") { selection.preset = .all }
                                    .font(StrandFont.subhead)
                                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                            }
                        }
                    }
                }
                if let resting = result?.resting {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text("Latest resting HR · \(resting.value.formatted(.number.precision(.fractionLength(0)))) bpm")
                                .font(StrandFont.subhead)
                            Text("\(HeartDashboardModel.source(resting)) · \(resting.day)")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(metric == .heartRate ? "Measured samples use a sample-weighted average. Stored daily averages use equal weight per recorded day and stay separate. Missing intervals are not filled." : metric == .steps ? "Unrecorded days are excluded." : "Unrecorded days are excluded. Different methods are averaged separately.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if window.toDay == Repository.localDayKey(referenceDate), result?.groups.contains(where: { $0.readings.contains(where: { $0.day == window.toDay }) }) == true {
                    Text("Includes today’s partial data.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: repo.refreshSeq) { _, _ in refreshedAt = Date() }
        .task(id: "\(deviceId)|\(metric.rawValue)|\(window.identity)|\(repo.refreshSeq)") {
            await history.load(repo: repo, deviceId: deviceId, metric: metric, window: window)
            if metric == .vo2 {
                let days = try? await repo.recentFitnessDailyMetrics(now: referenceDate)
                guard !Task.isCancelled, repo.deviceId == deviceId else { return }
                fitnessInputs = days.map { FitnessInputStatus(days: $0, age: profile.age, sex: profile.sex) }
            }
        }
    }

    private func recordedDates(_ group: MetricAverageGroup) -> String {
        guard let first = group.readings.first, let last = group.readings.last else { return "" }
        return first.day == last.day ? "Recorded \(dateLabel(first.day))" : "Recorded \(dateLabel(first.day)) – \(dateLabel(last.day))"
    }

    private var tint: Color {
        switch metric {
        case .heartRate: StrandPalette.liquidHeart
        case .hrv: StrandPalette.metricHRV
        case .steps: StrandPalette.metricSteps
        case .vo2: StrandPalette.metricVO2
        }
    }
    private func formatted(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(metric == .vo2 ? 1 : 0))) }
    private func metricValue(_ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(value.map(formatted) ?? "—").font(StrandFont.number(numberSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
            Text(metric.unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func dateLabel(_ day: String) -> String {
        HeartDashboardProjection.date(day)?.formatted(date: .abbreviated, time: .omitted) ?? day
    }
    private func groupDescription(_ group: MetricAverageGroup) -> String {
        metric == .heartRate && !group.isMeasuredHeartRate ? "\(source(group)) · day-weighted average" : source(group)
    }
    private func source(_ group: MetricAverageGroup) -> String {
        let sources = Set(group.readings.map(HeartDashboardModel.source)).sorted()
        return sources.count == 1 ? sources[0] : "Mixed sources · \(sources.joined(separator: ", "))"
    }
    @ViewBuilder private func rangeChart(_ rows: [DashboardDailyReading]) -> some View {
        if rows.isEmpty {
            Text("No recorded data in this range").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        } else {
            let samples = rows.compactMap { row -> DashboardTraceSample? in
                guard let date = HeartDashboardProjection.date(row.day) else { return nil }
                return DashboardTraceSample(time: date.timeIntervalSince1970, value: row.value, provenance: "\(row.source)|\(row.key)|\(row.method ?? "unknown")")
            }
            let trace = HeartDashboardProjection.trace(samples,
                from: window.start.timeIntervalSince1970, through: window.through.timeIntervalSince1970, gapSeconds: 90_000)
                .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) }
            let points = DashboardTraceSampling.reduce(trace)
            let segments = Dictionary(trace.map { ($0.date, $0.segment) }, uniquingKeysWith: { first, _ in first })
            let start = window.days == nil ? (points.first?.date ?? window.end) : window.start
            let upper = max(start.addingTimeInterval(1), window.through)
            let values = rows.map(\.value)
            let lower = values.min() ?? 0, higher = values.max() ?? 1
            let padding = max(1, (higher - lower) * 0.15)
            DashboardChart(points: points, domain: start...upper,
                range: metric == .steps ? 0...max(1, higher * 1.1) : max(0, lower - padding)...(higher + padding),
                tint: tint, style: metric == .steps ? .bars : .line, height: rows.count == 1 ? NoopMetrics.dashboardTrendHeight : NoopMetrics.chartHeight,
                label: "Recorded \(metric.title) history in the selected range; missing days remain gaps",
                inspectionData: rows.compactMap { row in
                    guard let date = HeartDashboardProjection.date(row.day) else { return nil }
                    let unit = metric == .steps ? "steps" : metric == .heartRate ? "bpm" : metric == .hrv ? "ms" : "mL/kg/min"
                    return ChartScrubDatum(id: "\(row.source)|\(row.day)", x: date.timeIntervalSince1970, y: row.value,
                        value: "\(row.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)",
                        context: "\(date.formatted(date: .abbreviated, time: .omitted)) · \(HeartDashboardModel.source(row))", segment: segments[date] ?? "default")
                })
        }
    }
}
