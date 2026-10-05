import SwiftUI
import StrandDesign

struct MetricHistoryView: View {
    let repo: Repository
    let deviceId: String
    let metric: DashboardHistoryMetric
    let now: Date
    @Binding var selection: MetricRangeSelection
    @StateObject private var history = MetricRangeModel()
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var window: MetricDateWindow { selection.window(now: now) }
    private var result: MetricRangeSnapshot? {
        guard let result = history.snapshot, result.deviceId == deviceId, result.metric == metric,
              result.window == window else { return nil }
        return result
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                MetricRangeControl(selection: $selection, now: now)
                NoopCard(tint: tint) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text(metric == .heartRate ? "Average recorded HR" : "Average \(metric.title.lowercased())")
                            .font(StrandFont.headline).foregroundStyle(tint)
                        metricValue(result?.mean)
                        if let result {
                            Text(window.coverage(result.groups.first?.readings.count ?? 0))
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            if metric == .heartRate {
                                Text("\(result.hrCount.formatted()) measured readings · sample-weighted average")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            } else if let group = result.groups.first {
                                Text(source(group)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            rangeChart(result.groups.first?.readings ?? [])
                        } else if let error = history.error {
                            Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                        } else {
                            ProgressView("Reading saved history…")
                        }
                    }
                }
                if let result, result.groups.count > 1 {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Other methods in this range").font(StrandFont.headline)
                            ForEach(result.groups.dropFirst()) { group in
                                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                    Text("\(formatted(group.mean)) \(metric.unit)").font(StrandFont.bodyNumber)
                                    Text("\(source(group)) · \(window.coverage(group.readings.count))")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                .accessibilityElement(children: .combine)
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
                Text(metric == .heartRate ? "Only recorded measurements contribute. Missing intervals are not filled. The trend shows daily averages." : metric == .steps ? "Unrecorded days are excluded." : "Unrecorded days are excluded. Different methods are averaged separately.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if window.toDay == Repository.localDayKey(now) {
                    Text("Includes today’s partial data.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: "\(deviceId)|\(metric.rawValue)|\(window.identity)") {
            await history.load(repo: repo, deviceId: deviceId, metric: metric, window: window)
        }
    }

    private var tint: Color { metric == .heartRate ? StrandPalette.liquidHeart : StrandPalette.metricCyan }
    private func formatted(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(metric == .vo2 ? 1 : 0))) }
    private func metricValue(_ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(value.map(formatted) ?? "—").font(StrandFont.number(numberSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
            Text(metric.unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
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
            let points = DashboardTraceSampling.reduce(HeartDashboardProjection.trace(samples,
                from: window.start.timeIntervalSince1970, through: window.through.timeIntervalSince1970, gapSeconds: 90_000)
                .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) })
            let start = window.days == nil ? (points.first?.date ?? window.end) : window.start
            let upper = max(start.addingTimeInterval(1), window.through)
            let values = rows.map(\.value)
            let lower = values.min() ?? 0, higher = values.max() ?? 1
            let padding = max(1, (higher - lower) * 0.15)
            DashboardChart(points: points, domain: start...upper,
                range: metric == .steps ? 0...max(1, higher * 1.1) : max(0, lower - padding)...(higher + padding),
                tint: tint, style: metric == .steps ? .bars : .line, height: NoopMetrics.chartHeight,
                label: "Recorded \(metric.title) history in the selected range; missing days remain gaps")
        }
    }
}
