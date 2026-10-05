import SwiftUI
import StrandDesign
import StrandAnalytics

/// The mockup's hierarchy, backed by dated records and one shared collection observation.
struct HeartMetricsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @StateObject private var dashboard = HeartDashboardModel()
    @StateObject private var collection = WhoopCollectionModel()
    @State private var showCollection = false
    @State private var chartMode = "Today"
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = NoopMetrics.dashboardHeroNumber
    @ScaledMetric(relativeTo: .title) private var metricSize = NoopMetrics.dashboardMetricNumber

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var loadIdentity: String { "\(repo.deviceId)|\(repo.refreshSeq)|\(dayCycleModeRaw)|\(profile.hrMaxOverride)|\(profile.age)|\(profile.sex)" }
    private var pairLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: NoopMetrics.gap)) : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.gap))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = live.heartRateEvidence.status(connected: live.connected, isWhoop: live.activeIsWhoop,
                heartRate: live.heartRate, at: context.date.timeIntervalSince1970,
                silenceSeconds: LiveState.heartRateSilenceSeconds, expectedDeviceId: repo.deviceId, connectionDeviceId: live.connectedWhoopDeviceId)
            VStack(spacing: NoopMetrics.sectionGap) {
                statusRow(status)
                heartCard(status, now: context.date)
                pairLayout {
                    strainCard(now: context.date)
                    hrvCard(now: context.date)
                }
                stepsCard(now: context.date)
                ProteinLogCard()
                vo2Card(now: context.date)
                if let error = dashboard.error {
                    Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .sheet(isPresented: $showCollection) { WhoopCollectionCard(collection: collection) }
        .task(id: repo.deviceId) {
            while !Task.isCancelled {
                if scenePhase == .active { await collection.refresh(repo: repo, live: live) }
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
        .task(id: loadIdentity) {
            while !Task.isCancelled {
                if scenePhase == .active { await dashboard.refresh(repo: repo, profile: profile) }
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
    }

    private func statusRow(_ status: LiveHeartRateStatus) -> some View {
        Button { showCollection = true } label: {
            NoopCard(padding: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space3) {
                    Circle().fill(status.isReceiving ? StrandPalette.statusPositive : StrandPalette.textTertiary)
                        .frame(width: NoopMetrics.space3, height: NoopMetrics.space3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("\(collection.deviceName(for: repo.deviceId)) · \(status.isReceiving ? "Receiving HR" : !status.isWhoop ? "Other source selected" : status.connected ? "Connected" : "Disconnected")").font(StrandFont.subhead)
                        Text(age(status))
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: NoopMetrics.space1)
                    if let battery = live.reportedBattery(for: repo.deviceId) {
                        Label("\(Int(battery.rounded()))%", systemImage: "battery.100")
                            .font(StrandFont.captionNumber)
                            .accessibilityLabel("Last reported battery \(Int(battery.rounded())) percent")
                    }
                    Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(minHeight: NoopMetrics.minimumTouchTarget)
                .foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens device identity, streaming freshness and stored sample evidence")
    }

    private func heartCard(_ status: LiveHeartRateStatus, now: Date) -> some View {
        NoopCard(tint: StrandPalette.liquidHeart) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                ViewThatFits(in: .horizontal) {
                    HStack { title("Heart rate", "heart.fill", StrandPalette.liquidHeart); Spacer(); chartPicker }
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) { title("Heart rate", "heart.fill", StrandPalette.liquidHeart); chartPicker }
                }
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(status.bpm.map(String.init) ?? "—").font(StrandFont.number(heroSize, weight: .bold))
                    Text("bpm").font(StrandFont.title2).foregroundStyle(StrandPalette.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current heart rate")
                .accessibilityValue(status.bpm.map { "\($0) beats per minute, fresh live WHOOP sample" } ?? "Unavailable; no fresh readable sample")
                Text(status.isReceiving ? "Live · \(age(status))" : "Waiting for a fresh readable sample")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                if let resting = data(now)?.restingHR {
                    Text("Resting \(number(resting.value)) bpm · \(caption(resting))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let points = heartPoints(now: now)
                let lower = chartMode == "Live" ? now.addingTimeInterval(-LiveHeartRateEvidence.chartWindowSeconds) : Calendar.current.startOfDay(for: now)
                plot(points, domain: lower...max(lower.addingTimeInterval(1), now), tint: StrandPalette.liquidHeart,
                     height: NoopMetrics.dashboardTraceHeight, label: chartMode == "Live" ? "Actual live heart-rate receipts, last five minutes" : "Measured WHOOP heart rate today",
                     empty: chartMode == "Live" ? "No readable live samples in the last five minutes" : "No measured HR samples stored today")
                Text(chartMode == "Live" ? "Actual receipts · last 5 minutes · gaps kept" : "Measured samples · chart checked \(data(now)?.through.formatted(.dateTime.hour().minute().second()) ?? "not yet")")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                if let snapshot = collection.snapshot, snapshot.deviceId == repo.deviceId,
                   snapshot.fromTs == Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970) {
                    Label("\(snapshot.heartRate.count.formatted()) HR samples saved today", systemImage: "externaldrive.fill")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Label("Stored sample count not yet checked", systemImage: "externaldrive")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private var chartPicker: some View {
        Picker("Heart-rate timeline", selection: $chartMode) {
            Text("Today").tag("Today")
            Text("Live").tag("Live")
        }
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: NoopMetrics.minimumTouchTarget)
    }

    private func strainCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricAmber) {
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
                plot(points, domain: weekDomain(now), tint: StrandPalette.metricAmber, style: .bars,
                     range: 0...UnitFormatter.effortValue(100, scale: scale), label: "Seven-day strain, scale \(UnitFormatter.effortScaleMax(scale))", dailyLabels: true, empty: "No recorded strain yet")
                Text("7 days").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func hrvCard(now: Date) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
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
    private func age(_ status: LiveHeartRateStatus) -> String {
        guard let seconds = status.sampleAge else { return "No readable HR on this connection" }
        if seconds < 60 { return "Last readable HR \(Int(seconds))s ago" }
        if seconds < 3600 { return "Last readable HR \(Int(seconds / 60))m ago" }
        return "Last readable HR \(Int(seconds / 3600))h ago"
    }
    private func weekDomain(_ now: Date) -> ClosedRange<Date> {
        let end = Calendar.current.startOfDay(for: now)
        return (Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end)...(Calendar.current.date(byAdding: .day, value: 1, to: end) ?? now)
    }
    private func monthDomain(_ now: Date) -> ClosedRange<Date> {
        let end = Calendar.current.startOfDay(for: now)
        return (Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end)...(Calendar.current.date(byAdding: .day, value: 1, to: end) ?? now)
    }
    private func data(_ now: Date) -> HeartDashboardSnapshot? {
        guard let data = dashboard.data, data.deviceId == repo.deviceId,
              data.calendarDay == Repository.localDayKey(now) else { return nil }
        return data
    }
    private func heartPoints(now: Date) -> [TrendPoint] {
        if chartMode == "Today" { return data(now)?.measuredHR ?? [] }
        guard live.activeIsWhoop, live.heartRateEvidence.sourceDeviceId == repo.deviceId else { return [] }
        return HeartDashboardProjection.trace(live.heartRateEvidence.samples.map {
            DashboardTraceSample(time: $0.receivedAt, value: Double($0.bpm))
        }, from: now.timeIntervalSince1970 - LiveHeartRateEvidence.chartWindowSeconds,
           through: now.timeIntervalSince1970, gapSeconds: 1.5)
            .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) }
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
