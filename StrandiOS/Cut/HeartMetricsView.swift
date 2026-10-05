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
    @State private var historyDate = Date()
    @State private var showHistoryDate = false
    @State private var battery: Double?
    @State private var showCollection = false
    @State private var showLive = false
    @State private var showDetailLive = false
    @State private var expandedMetric: Metric?

    private enum Metric: String, Identifiable {
        case heartRate, hrv, steps, vo2
        var id: String { rawValue }
        var title: String {
            switch self {
            case .heartRate: return "Heart rate"
            case .hrv: return "HRV"
            case .steps: return "Steps"
            case .vo2: return "VO₂ max"
            }
        }
    }
    @State private var capturedAt = Date()
    @ScaledMetric(relativeTo: .title) private var metricSize = NoopMetrics.dashboardMetricNumber

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.deviceId == rhs.deviceId && lhs.refreshToken == rhs.refreshToken
    }
    private var loadIdentity: String { "\(deviceId)|\(refreshToken)|\(Repository.localDayKey(historyDate))" }

    var body: some View {
        VStack(spacing: NoopMetrics.sectionGap) {
            statusRow
            liveButton
                .frame(maxWidth: .infinity, alignment: .leading)
            heartTile
            DashboardGridLayout(columns: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                                squareMinimum: !dynamicTypeSize.isAccessibilitySize) {
                hrvTile
                stepsTile
                ProteinLogCard(day: Repository.localDayKey(capturedAt))
                vo2Tile
            }
            if let error = dashboard.error {
                Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showCollection) { DashboardCollectionSheet() }
        .sheet(isPresented: $showLive) { HeartRateSessionSheet(expectedDeviceId: deviceId) }
        .sheet(item: $expandedMetric) { metric in metricDetail(metric) }
        .task(id: loadIdentity) { await refresh() }
    }

    private func refresh() async {
        let now = Date()
        let id = deviceId
        if dashboard.data?.deviceId != id { observation = nil; battery = nil }
        await dashboard.refresh(repo: repo, historyDate: historyDate, now: now)
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
        metricTile(.heartRate, icon: "heart.fill", tint: StrandPalette.liquidHeart, fillHeight: false) {
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
            let lower = snapshot?.fromDay ?? Calendar.current.startOfDay(for: historyDate)
            let upper = max(lower.addingTimeInterval(1), snapshot?.through ?? capturedAt)
            plot(snapshot?.measuredHR ?? [], domain: lower...upper, tint: StrandPalette.liquidHeart,
                 height: NoopMetrics.dashboardTrendHeight, label: "Saved heart-rate preview, one-minute averages with gaps", compact: true,
                 empty: snapshot == nil ? "Loading history…" : "No saved readings")
            Text(snapshot.map { "\($0.hrSampleCount.formatted()) saved readings" } ?? "Reading stored history…")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private var historyDateLabel: some View {
        Text(data(capturedAt).map { dateLabel($0.historyDay) } ?? dateLabel(Repository.localDayKey(historyDate)))
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

    private func metricTile<Content: View>(_ metric: Metric, icon: String, tint: Color, fillHeight: Bool = true,
                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        Button { expandedMetric = metric } label: {
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

    private func metricDetail(_ metric: Metric) -> some View {
        NavigationStack {
            ScreenScaffold(title: nil, lazy: false) {
                switch metric {
                case .heartRate:
                    heartCard
                    Button { showDetailLive = true } label: { Label("Live HR · 60s", systemImage: "waveform.path.ecg") }
                        .font(StrandFont.subhead).buttonStyle(.bordered).tint(StrandPalette.liquidHeart)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                    Text("Saved WHOOP readings · one-minute averages. Missing intervals remain gaps.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if let resting = data(capturedAt)?.restingHR {
                        Text("Resting HR source: \(HeartDashboardModel.source(resting))")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                case .hrv:
                    hrvCard(now: capturedAt)
                    recordList(data(capturedAt)?.hrvMonth ?? [], unit: "ms")
                case .steps:
                    stepsCard(now: capturedAt)
                    recordList(data(capturedAt)?.stepsWeek ?? [], unit: "steps")
                case .vo2:
                    vo2Card(now: capturedAt)
                    recordList(data(capturedAt)?.vo2History ?? [], unit: "mL/kg/min", decimals: 1)
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { expandedMetric = nil } } }
        }
        .sheet(isPresented: $showDetailLive) { HeartRateSessionSheet(expectedDeviceId: deviceId) }
        .sheet(isPresented: $showHistoryDate) {
            NavigationStack {
                Form { DatePicker("Heart-rate history date", selection: $historyDate, in: ...Date(), displayedComponents: .date) }
                    .navigationTitle("Heart-rate history")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistoryDate = false } } }
            }
        }
    }

    private func recordList(_ rows: [DashboardDailyReading], unit: String, decimals: Int = 0) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Recorded history").font(StrandFont.headline)
                if rows.isEmpty {
                    Text("No records in this window").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(rows.reversed(), id: \.day) { reading in
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("\(reading.value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)")
                            .font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                        Text(caption(reading)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func vo2History(_ now: Date) -> (points: [TrendPoint], domain: ClosedRange<Date>) {
        let rows = data(now)?.vo2History ?? []
        let end = rows.last.flatMap { HeartDashboardProjection.date($0.day) } ?? now
        let start = Calendar.current.date(byAdding: .day, value: -89, to: end) ?? end
        let points = dailyPoints(rows.filter { (HeartDashboardProjection.date($0.day) ?? .distantPast) >= start })
        return (points, start...end.addingTimeInterval(86_400))
    }

    private var heartCard: some View {
        NoopCard(tint: StrandPalette.liquidHeart) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack { title("Heart rate", "heart.fill", StrandPalette.liquidHeart); Spacer(); historyButton }
                let snapshot = data(capturedAt)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(snapshot?.averageHR.map(number) ?? "—").font(StrandFont.number(metricSize, weight: .bold))
                    Text("avg bpm").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    if let resting = snapshot?.restingHR {
                        VStack(alignment: .trailing, spacing: NoopMetrics.space1) {
                            Text("Resting \(number(resting.value)) bpm").font(StrandFont.captionNumber)
                            Text(dateLabel(resting.day)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Resting HR \(number(resting.value)) beats per minute, \(caption(resting))")
                    }
                }
                .foregroundStyle(StrandPalette.textPrimary)
                let lower = snapshot?.fromDay ?? Calendar.current.startOfDay(for: historyDate)
                let upper = max(lower.addingTimeInterval(1), snapshot?.through ?? capturedAt)
                plot(snapshot?.measuredHR ?? [], domain: lower...upper, tint: StrandPalette.liquidHeart,
                     height: NoopMetrics.chartHeight, label: "Historical measured HR, one-minute averages with missing readings kept as gaps",
                     empty: snapshot == nil ? "Loading saved heart-rate history…" : "No saved HR readings for this date")
                Text(snapshot.map { "\($0.hrSampleCount.formatted()) saved readings · 1-minute averages · \(dateLabel($0.historyDay))" } ?? "Reading stored history…")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var historyButton: some View {
        Button { showHistoryDate = true } label: {
            Label(historyDate.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                .font(StrandFont.caption).frame(minHeight: NoopMetrics.minimumTouchTarget)
        }
        .buttonStyle(.plain).foregroundStyle(StrandPalette.textSecondary)
        .accessibilityLabel("Choose historical heart-rate date")
    }

    private var liveButton: some View {
        Button { showLive = true } label: {
            Label("Live · 60s", systemImage: "waveform.path.ecg")
                .font(StrandFont.caption).frame(minHeight: NoopMetrics.minimumTouchTarget)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(StrandPalette.liquidHeart)
        .accessibilityHint("Opens a separate live heart-rate session that ends automatically after sixty seconds")
    }

    private func hrvCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    title("HRV", "waveform.path.ecg", StrandPalette.metricCyan)
                    numeric(data(now)?.hrv.map { number($0.value) } ?? "—", unit: "ms")
                    Text(data(now)?.hrv.map(caption) ?? "Needs suitable R–R and sleep data")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                plot(dailyPoints(data(now)?.hrvMonth ?? []), domain: monthDomain(now), tint: StrandPalette.metricCyan,
                     height: NoopMetrics.chartHeight, label: "Thirty-day HRV records; source and method changes break the line", empty: "No HRV history in this window")
            }
        }
    }

    private func stepsCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    title("Steps", "figure.walk", StrandPalette.metricCyan)
                    numeric(data(now)?.steps.map { number($0.value) } ?? "—", unit: "")
                    Text(data(now)?.steps.map(caption) ?? "No steps record today")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                plot(dailyPoints(data(now)?.stepsWeek ?? []), domain: weekDomain(now), tint: StrandPalette.metricCyan,
                     style: .bars, range: 0...max(1, (data(now)?.stepsWeek.map(\.value).max() ?? 0) * 1.1),
                     height: NoopMetrics.chartHeight, label: "Seven-day steps; missing days have no bars", dailyLabels: true, empty: "No steps history yet")
            }
        }
    }

    private func vo2Card(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    title("VO₂ max", "chart.bar.fill", StrandPalette.metricCyan)
                    numeric(data(now)?.vo2.map { $0.value.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "mL/kg/min")
                    Text(data(now)?.vo2.map(caption) ?? "No VO₂ max record available")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                let history = vo2History(now)
                plot(history.points, domain: history.domain, tint: StrandPalette.metricCyan,
                     height: NoopMetrics.chartHeight, label: "VO₂ max records; estimator and source changes break the line", empty: "Available after a recorded measurement or supported estimate")
            }
        }
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
              data.calendarDay == Repository.localDayKey(now), data.historyDay == Repository.localDayKey(historyDate) else { return nil }
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
