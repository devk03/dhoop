import SwiftUI
import StrandDesign
import StrandAnalytics

/// The mockup's hierarchy, backed by dated records and one shared collection observation.
struct HeartMetricsView: View, Equatable {
    let model: AppModel
    let deviceId: String
    let refreshToken: Int
    private var repo: Repository { model.repo }
    private var profile: ProfileStore { model.profile }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @StateObject private var dashboard = HeartDashboardModel()
    @State private var observation: CollectionProof?
    @State private var storedCount: Int?
    @State private var battery: Double?
    @State private var showCollection = false
    @State private var showLive = false
    @State private var capturedAt = Date()
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = NoopMetrics.dashboardHeroNumber
    @ScaledMetric(relativeTo: .title) private var metricSize = NoopMetrics.dashboardMetricNumber

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.deviceId == rhs.deviceId && lhs.refreshToken == rhs.refreshToken
    }
    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var loadIdentity: String { "\(deviceId)|\(refreshToken)|\(dayCycleModeRaw)" }
    private var pairLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: NoopMetrics.gap)) : AnyLayout(DashboardPairLayout())
    }

    var body: some View {
        VStack(spacing: NoopMetrics.sectionGap) {
            statusRow
            heartCard
            pairLayout {
                strainCard(now: capturedAt)
                hrvCard(now: capturedAt)
            }
            stepsCard(now: capturedAt)
            ProteinLogCard(day: Repository.localDayKey(capturedAt))
            vo2Card(now: capturedAt)
            if let error = dashboard.error {
                Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showCollection) { DashboardCollectionSheet() }
        .sheet(isPresented: $showLive) { HeartRateSessionSheet(expectedDeviceId: deviceId) }
        .task(id: loadIdentity) { await refresh() }
    }

    private func refresh() async {
        let now = Date()
        let id = deviceId
        if dashboard.data?.deviceId != id { observation = nil; storedCount = nil; battery = nil }
        await dashboard.refresh(repo: repo, profile: profile, now: now)
        guard !Task.isCancelled, id == repo.deviceId else { return }
        let collection = WhoopCollectionModel()
        await collection.refresh(repo: repo, live: model.live, now: now)
        guard !Task.isCancelled, id == repo.deviceId else { return }
        capturedAt = now
        observation = collection.proof(live: model.live, now: Date(), deviceId: id)
        storedCount = collection.snapshot?.heartRate.count
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

    private var heartCard: some View {
        NoopCard(tint: StrandPalette.liquidHeart) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                ViewThatFits(in: .horizontal) {
                    HStack { title("Heart rate", "heart.fill", StrandPalette.liquidHeart); Spacer(); liveButton }
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) { title("Heart rate", "heart.fill", StrandPalette.liquidHeart); liveButton }
                }
                let latest = data(capturedAt)?.measuredHR.last
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(latest.map { number($0.value) } ?? "—").font(StrandFont.number(heroSize, weight: .bold))
                    Text("bpm").font(StrandFont.title2).foregroundStyle(StrandPalette.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Latest saved measured heart rate")
                .accessibilityValue(latest.map { "\(number($0.value)) beats per minute, saved \($0.date.formatted())" } ?? "No measured heart rate saved today")
                Text(latest.map { "Last saved HR · \($0.date.formatted(.dateTime.hour().minute().second()))" } ?? "No measured HR saved today")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                if let resting = data(capturedAt)?.restingHR {
                    Text("Resting \(number(resting.value)) bpm · \(caption(resting))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                let lower = Calendar.current.startOfDay(for: capturedAt)
                plot(data(capturedAt)?.measuredHR ?? [], domain: lower...max(lower.addingTimeInterval(1), capturedAt),
                     tint: StrandPalette.liquidHeart, height: NoopMetrics.dashboardTraceHeight,
                     label: "Measured WHOOP heart rate today, saved snapshot", empty: "No measured HR samples stored today")
                Text("Snapshot · \(capturedAt.formatted(.dateTime.hour().minute().second())) · pull to refresh")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                Label(storedCount.map { "\($0.formatted()) HR samples saved today" } ?? "Stored sample count not yet checked", systemImage: "externaldrive.fill")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private var liveButton: some View {
        Button { showLive = true } label: {
            Label("Live · 60 seconds", systemImage: "waveform.path.ecg")
                .font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(StrandPalette.liquidHeart)
        .accessibilityHint("Opens a separate live heart-rate session that ends automatically after sixty seconds")
    }

    private func strainCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricAmber, fillHeight: !dynamicTypeSize.isAccessibilitySize) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                title("Strain", "flame.fill", StrandPalette.metricAmber)
                numeric(data(now)?.strain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "—", unit: "/\(UnitFormatter.effortScaleMax(scale))")
                Text(data(now)?.strainSource ?? "Needs more heart-rate data")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let scoreDay = data(now)?.scoreDay {
                    Text(dateLabel(scoreDay)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                let points = dailyPoints(data(now)?.strainWeek ?? []).map {
                    TrendPoint(date: $0.date, value: UnitFormatter.effortValue($0.value, scale: scale), segment: $0.segment)
                }
                Spacer(minLength: NoopMetrics.space1)
                plot(points, domain: weekDomain(now), tint: StrandPalette.metricAmber, style: .bars,
                     range: 0...UnitFormatter.effortValue(100, scale: scale), label: "Seven-day strain, scale \(UnitFormatter.effortScaleMax(scale))", dailyLabels: true, empty: "No recorded strain yet")
                Text("7 days").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func hrvCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan, fillHeight: !dynamicTypeSize.isAccessibilitySize) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                title("HRV", "waveform.path.ecg", StrandPalette.metricCyan)
                numeric(data(now)?.hrv.map { number($0.value) } ?? "—", unit: "ms")
                if let hrv = data(now)?.hrv {
                    Text(HeartDashboardModel.source(hrv)).font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Text(dateLabel(hrv.day)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text("Needs suitable R–R and sleep data").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NoopMetrics.space1)
                plot(dailyPoints(data(now)?.hrvMonth ?? []), domain: monthDomain(now), tint: StrandPalette.metricCyan,
                     label: "Thirty-day HRV records; source and method changes break the line", empty: "No HRV records in this 30-day window")
                Text("30 days · recorded values").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func stepsCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            pairLayout {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    title("Steps", "figure.walk", StrandPalette.metricCyan)
                    numeric(data(now)?.steps.map { number($0.value) } ?? "—", unit: "")
                    Text(data(now)?.steps.map(caption) ?? "No steps record today")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                plot(dailyPoints(data(now)?.stepsWeek ?? []), domain: weekDomain(now), tint: StrandPalette.metricCyan,
                     style: .bars, range: 0...max(1, (data(now)?.stepsWeek.map(\.value).max() ?? 0) * 1.1),
                     label: "Seven-day steps; missing days have no bars", dailyLabels: true, empty: "No steps history yet")
            }
        }
    }

    private func vo2Card(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            pairLayout {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    title("VO₂ max", "chart.bar.fill", StrandPalette.metricCyan)
                    numeric(data(now)?.vo2.map { $0.value.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "mL/kg/min")
                    Text(data(now)?.vo2.map(caption) ?? "No VO₂ max record available")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                let rows = data(now)?.vo2History ?? []
                let end = rows.last.flatMap { HeartDashboardProjection.date($0.day) } ?? now
                let start = Calendar.current.date(byAdding: .day, value: -89, to: end) ?? end
                let points = dailyPoints(rows.filter { (HeartDashboardProjection.date($0.day) ?? .distantPast) >= start })
                plot(points, domain: start...end.addingTimeInterval(86_400), tint: StrandPalette.metricCyan,
                     label: "VO₂ max records; estimator and source changes break the line", empty: "Available after a recorded measurement or supported estimate")
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
              data.calendarDay == Repository.localDayKey(now) else { return nil }
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
                                   dailyLabels: Bool = false, empty: String) -> some View {
        if points.isEmpty {
            Text(empty).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        } else {
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let padding = max(1, (maxValue - minValue) * 0.15)
            DashboardChart(points: points, domain: domain, range: range ?? max(0, minValue - padding)...(maxValue + padding),
                           tint: tint, style: style, height: height, label: label, dailyLabels: dailyLabels)
        }
    }
}
