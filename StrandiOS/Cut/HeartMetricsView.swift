import SwiftUI
import StrandDesign
import StrandAnalytics

/// The mockup's hierarchy, backed by dated records and one shared collection observation.
struct HeartMetricsView: View, Equatable {
    let model: AppModel
    let deviceId: String
    let refreshToken: Int
    private var repo: Repository { model.repo }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var dashboard = HeartDashboardModel()
    @State private var observation: CollectionProof?
    @State private var battery: Double?
    @State private var showCollection = false
    @State private var expandedMetric: DashboardHistoryMetric?
    @State private var expandedAt = Date()
    @State private var rangeSelection = MetricRangeSelection()
    @State private var capturedAt = Date()
    @ScaledMetric(relativeTo: .title) private var metricSize = NoopMetrics.dashboardMetricNumber

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.deviceId == rhs.deviceId && lhs.refreshToken == rhs.refreshToken
    }
    private var loadIdentity: String { "\(deviceId)|\(refreshToken)" }

    var body: some View {
        VStack(spacing: NoopMetrics.sectionGap) {
            statusRow
            heartTile
            DashboardGridLayout(columns: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                                squareMinimum: !dynamicTypeSize.isAccessibilitySize) {
                hrvTile
                stepsTile
                ProteinLogCard(day: Repository.localDayKey(capturedAt), selection: $rangeSelection)
                vo2Tile
            }
            if let error = dashboard.error {
                Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showCollection) { DashboardCollectionSheet() }
        .sheet(item: $expandedMetric) { metric in
            MetricHistoryView(repo: repo, deviceId: deviceId, metric: metric, now: expandedAt, selection: $rangeSelection)
        }
        .task(id: loadIdentity) { await refresh() }
    }

    private func refresh() async {
        let now = Date()
        let id = deviceId
        if dashboard.data?.deviceId != id { observation = nil; battery = nil }
        await dashboard.refresh(repo: repo, historyDate: now, now: now)
        guard !Task.isCancelled, id == repo.deviceId else { return }
        let collection = WhoopCollectionModel()
        await collection.refresh(repo: repo, live: model.live, now: now)
        guard !Task.isCancelled, id == repo.deviceId else { return }
        capturedAt = now
        observation = collection.proof(live: model.live, now: Date(), deviceId: id)
        battery = model.live.reportedBattery(for: id)
    }

    private var statusRow: some View {
        Button { showCollection = true } label: {
            NoopCard(padding: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space3) {
                    Circle().fill(observation?.connected == true ? StrandPalette.statusPositive : StrandPalette.textTertiary)
                        .frame(width: NoopMetrics.space3, height: NoopMetrics.space3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("\(observation?.deviceName ?? "WHOOP") · \(observation?.connected == true ? "Connected at check" : "Connection not confirmed")")
                            .font(StrandFont.subhead)
                        Text(observation?.lastLiveHRAt.map { "Last HR received \(Date(timeIntervalSince1970: $0).formatted(.dateTime.hour().minute().second()))" } ?? "No readable HR at last check")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: NoopMetrics.space1)
                    if let battery {
                        Label("\(Int(battery.rounded()))%", systemImage: "battery.100").font(StrandFont.captionNumber)
                            .accessibilityLabel("Battery at last check \(Int(battery.rounded())) percent")
                    }
                    Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(minHeight: NoopMetrics.minimumTouchTarget).foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .buttonStyle(.plain).accessibilityElement(children: .combine)
        .accessibilityHint("Opens current device and collection evidence")
    }

    private var heartTile: some View {
        NoopCard(tint: StrandPalette.liquidHeart) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Button { expandedAt = Date(); expandedMetric = .heartRate } label: {
                    HStack {
                        Label("Heart rate", systemImage: "heart.fill").font(StrandFont.headline).foregroundStyle(StrandPalette.liquidHeart)
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                .buttonStyle(.plain).accessibilityLabel("Expand heart-rate history")
            let snapshot = data(capturedAt)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    numeric(snapshot?.averageHR.map(number) ?? "—", unit: "avg bpm")
                    historyDateLabel.fixedSize()
                }
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    numeric(snapshot?.averageHR.map(number) ?? "—", unit: "avg bpm")
                    historyDateLabel
                }
            }
            let lower = snapshot?.fromDay ?? Calendar.current.startOfDay(for: capturedAt)
            let upper = max(lower.addingTimeInterval(1), snapshot?.through ?? capturedAt)
            plot(snapshot?.measuredHR ?? [], domain: lower...upper, tint: StrandPalette.liquidHeart,
                 height: NoopMetrics.dashboardTrendHeight, label: "Saved heart-rate preview, one-minute averages with gaps", compact: true,
                 empty: snapshot == nil ? "Loading history…" : "No saved readings")
            Text(snapshot.map { "\($0.hrSampleCount.formatted()) saved readings" } ?? "Reading stored history…")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            InlineHeartRateCapture(expectedDeviceId: deviceId, enabled: expandedMetric == nil)
            }
        }
    }

    private var historyDateLabel: some View {
        Text(data(capturedAt).map { dateLabel($0.historyDay) } ?? dateLabel(Repository.localDayKey(capturedAt)))
            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
    }

    private var hrvTile: some View {
        metricTile(.hrv, icon: "waveform.path.ecg", tint: StrandPalette.metricCyan) {
            numeric(data(capturedAt)?.hrv.map { number($0.value) } ?? "—", unit: "ms")
            metricCaption(data(capturedAt)?.hrv, empty: "Needs R–R and sleep data")
            plot(dailyPoints(data(capturedAt)?.hrvMonth ?? []), domain: monthDomain(capturedAt),
                 tint: StrandPalette.metricCyan, height: NoopMetrics.dashboardTileChartHeight,
                 label: "Thirty-day HRV preview; missing days and source changes remain gaps", compact: true, empty: "No HRV history")
        }
    }

    private var stepsTile: some View {
        metricTile(.steps, icon: "figure.walk", tint: StrandPalette.metricCyan) {
            numeric(data(capturedAt)?.steps.map { number($0.value) } ?? "—", unit: "")
            metricCaption(data(capturedAt)?.steps, empty: "No steps record today")
            plot(dailyPoints(data(capturedAt)?.stepsWeek ?? []), domain: weekDomain(capturedAt),
                 tint: StrandPalette.metricCyan, style: .bars,
                 range: 0...max(1, (data(capturedAt)?.stepsWeek.map(\.value).max() ?? 0) * 1.1),
                 height: NoopMetrics.dashboardTileChartHeight,
                 label: "Seven-day steps preview; missing days have no bars", compact: true, empty: "No steps history")
        }
    }

    private var vo2Tile: some View {
        metricTile(.vo2, icon: "chart.bar.fill", tint: StrandPalette.metricCyan) {
            numeric(data(capturedAt)?.vo2.map { $0.value.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "mL/kg/min")
            metricCaption(data(capturedAt)?.vo2, empty: "No VO₂ max record")
            let history = vo2History(capturedAt)
            plot(history.points, domain: history.domain, tint: StrandPalette.metricCyan,
                 height: NoopMetrics.dashboardTileChartHeight,
                 label: "VO₂ max preview; method and source changes remain gaps", compact: true, empty: "Needs a measurement or estimate")
        }
    }

    private func metricTile<Content: View>(_ metric: DashboardHistoryMetric, icon: String, tint: Color, fillHeight: Bool = true,
                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        Button { expandedAt = Date(); expandedMetric = metric } label: {
            NoopCard(tint: tint, fillHeight: fillHeight) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack(alignment: .top, spacing: NoopMetrics.space1) {
                        Label(metric.title, systemImage: icon).font(StrandFont.subhead).foregroundStyle(tint)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).accessibilityHidden(true)
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens expanded \(metric.title) history and source details")
    }

    private func metricCaption(_ reading: DashboardDailyReading?, empty: String) -> some View {
        Text(reading.map(caption) ?? empty).font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func vo2History(_ now: Date) -> (points: [TrendPoint], domain: ClosedRange<Date>) {
        let rows = data(now)?.vo2History ?? []
        let end = rows.last.flatMap { HeartDashboardProjection.date($0.day) } ?? now
        let start = Calendar.current.date(byAdding: .day, value: -89, to: end) ?? end
        let points = dailyPoints(rows.filter { (HeartDashboardProjection.date($0.day) ?? .distantPast) >= start })
        return (points, start...end.addingTimeInterval(86_400))
    }

    private func title(_ text: String, _ icon: String, _ tint: Color) -> some View {
        Label(text, systemImage: icon).font(StrandFont.headline).foregroundStyle(tint)
    }
    private func numeric(_ value: String, unit: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(value).font(StrandFont.number(metricSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(value).font(StrandFont.number(metricSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    private func dateLabel(_ day: String) -> String {
        HeartDashboardProjection.date(day)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? day
    }
    private func caption(_ reading: DashboardDailyReading) -> String { "\(HeartDashboardModel.source(reading)) · \(dateLabel(reading.day))" }
    private func weekDomain(_ now: Date) -> ClosedRange<Date> {
        let end = Calendar.current.startOfDay(for: now)
        return (Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end)...(Calendar.current.date(byAdding: .day, value: 1, to: end) ?? now)
    }
    private func monthDomain(_ now: Date) -> ClosedRange<Date> {
        let end = Calendar.current.startOfDay(for: now)
        return (Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end)...(Calendar.current.date(byAdding: .day, value: 1, to: end) ?? now)
    }
    private func data(_ now: Date) -> HeartDashboardSnapshot? {
        guard let data = dashboard.data, data.deviceId == deviceId,
              data.calendarDay == Repository.localDayKey(now), data.historyDay == data.calendarDay else { return nil }
        return data
    }
    private func dailyPoints(_ rows: [DashboardDailyReading], gapSeconds: Double = 90_000) -> [TrendPoint] {
        let samples = rows.compactMap { row -> DashboardTraceSample? in
            guard let date = HeartDashboardProjection.date(row.day) else { return nil }
            return DashboardTraceSample(time: date.timeIntervalSince1970, value: row.value,
                provenance: "\(row.source)|\(row.key)|\(row.method ?? "unknown")")
        }
        return HeartDashboardProjection.trace(samples, from: -.greatestFiniteMagnitude, through: .greatestFiniteMagnitude, gapSeconds: gapSeconds)
            .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) }
    }
    @ViewBuilder private func plot(_ points: [TrendPoint], domain: ClosedRange<Date>, tint: Color,
                                   style: DashboardChart.Style = .line, range: ClosedRange<Double>? = nil,
                                   height: CGFloat = NoopMetrics.dashboardTrendHeight, label: String,
                                   dailyLabels: Bool = false, compact: Bool = false, empty: String) -> some View {
        if points.isEmpty {
            Text(empty).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: min(height, NoopMetrics.dashboardTrendHeight), alignment: .leading)
        } else {
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let padding = max(1, (maxValue - minValue) * 0.15)
            DashboardChart(points: points, domain: domain, range: range ?? max(0, minValue - padding)...(maxValue + padding),
                           tint: tint, style: style, height: height, label: label, dailyLabels: dailyLabels, compact: compact)
        }
    }
}
