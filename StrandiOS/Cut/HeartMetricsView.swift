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
    @ScaledMetric(relativeTo: .title) private var metricSize = NoopMetrics.dashboardTileNumber

    @ScaledMetric(relativeTo: .title) private var heartSize = NoopMetrics.dashboardHeartNumber

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.deviceId == rhs.deviceId && lhs.refreshToken == rhs.refreshToken
    }
    private var loadIdentity: String { "\(deviceId)|\(refreshToken)" }

    var body: some View {
        VStack(spacing: NoopMetrics.space3) {
            statusRow
            heartTile
            DashboardGridLayout(columns: dynamicTypeSize >= .xxxLarge ? 1 : 2,
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
        await dashboard.refresh(repo: repo, profile: model.profile, historyDate: now, now: now)
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
            NoopCard(padding: NoopMetrics.space2) {
                HStack(spacing: NoopMetrics.space3) {
                    Circle().fill(observation?.connected == true ? StrandPalette.statusPositive : StrandPalette.textTertiary)
                        .frame(width: NoopMetrics.space2, height: NoopMetrics.space2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                        Text("WHOOP").font(StrandFont.subhead).fontWeight(.semibold)
                        Text(observationDetail).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: NoopMetrics.space1)
                    if let battery {
                        Label("\(Int(battery.rounded()))%", systemImage: "battery.100").font(StrandFont.captionNumber)
                            .accessibilityLabel("Battery at last check \(Int(battery.rounded())) percent")
                    }
                    Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }.foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .buttonStyle(.plain).frame(minHeight: NoopMetrics.minimumTouchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityValue(observation?.connected == true ? "Connected at last check" : "Connection not confirmed at last check")
        .accessibilityHint("Opens device identity, sample freshness and collection evidence")
    }

    private var observationDetail: String {
        guard let observation else { return "Checking saved data…" }
        guard let stored = observation.latestStoredHR, Double(stored) <= observation.capturedAt else {
            return "No saved HR at last check"
        }
        let date = Date(timeIntervalSince1970: Double(stored))
        let checkDate = Date(timeIntervalSince1970: observation.capturedAt)
        let saved = date.formatted(date: Calendar.current.isDate(date, inSameDayAs: checkDate) ? .omitted : .abbreviated, time: .shortened)
        return "Saved HR · \(saved)"
    }

    private var heartTile: some View {
        let snapshot = data(capturedAt)
        return NoopCard(padding: NoopMetrics.space3, tint: StrandPalette.liquidHeart) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Button { expandedAt = Date(); expandedMetric = .heartRate } label: {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack {
                            Text("Heart rate").font(StrandFont.subhead).fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                            numeric(snapshot?.averageHR.map(number) ?? "—", unit: "avg bpm", hero: true)
                            Text("Today").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }.foregroundStyle(StrandPalette.textPrimary).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Expand heart-rate history").accessibilityValue("\(snapshot?.averageHR.map(number) ?? "Unavailable") average bpm")
                let lower = snapshot?.fromDay ?? Calendar.current.startOfDay(for: capturedAt)
                let upper = max(lower.addingTimeInterval(1), snapshot?.through ?? capturedAt)
                plot(snapshot?.measuredHR ?? [], domain: lower...upper, tint: StrandPalette.liquidHeart,
                     height: NoopMetrics.dashboardHeartChartHeight, label: "Saved heart-rate preview, one-minute averages with gaps", unit: "bpm",
                     empty: snapshot == nil ? "Loading history…" : snapshot?.hrReadError != nil ? "History unavailable" : "No saved readings today")
                if let error = snapshot?.hrReadError { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                InlineHeartRateCapture(expectedDeviceId: deviceId, enabled: expandedMetric == nil,
                    savedSummary: snapshot?.hrSampleCount.flatMap { $0 > 0 ? "\($0.formatted()) readings saved" : nil })
            }
        }
    }

    private var hrvTile: some View {
        metricTile(.hrv, value: data(capturedAt)?.hrv.map { number($0.value) } ?? "—", unit: "ms", tint: StrandPalette.metricHRV) {
            plot(dailyPoints(data(capturedAt)?.hrvMonth ?? []), domain: monthDomain(capturedAt),
                 tint: StrandPalette.metricHRV, height: NoopMetrics.dashboardTileChartHeight,
                 label: "Thirty-day HRV preview; missing days and source changes remain gaps", compact: true, unit: "ms", readings: data(capturedAt)?.hrvMonth ?? [], empty: "No recent HRV")
            metricCaption(data(capturedAt)?.hrv, empty: "Needs overnight readings")
            if let count = data(capturedAt)?.hrvSavedDays, count > (data(capturedAt)?.hrvMonth.count ?? 0) {
                Button("\(count.formatted()) saved days · View all") {
                    rangeSelection.preset = .all; expandedAt = Date(); expandedMetric = .hrv
                }.font(StrandFont.caption).frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
        }
    }

    private var stepsTile: some View {
        metricTile(.steps, value: data(capturedAt)?.steps.map { number($0.value) } ?? "—", unit: "", tint: StrandPalette.metricSteps) {
            plot(dailyPoints(data(capturedAt)?.stepsWeek ?? []), domain: weekDomain(capturedAt),
                 tint: StrandPalette.metricSteps, style: .bars,
                 range: 0...max(1, (data(capturedAt)?.stepsWeek.map(\.value).max() ?? 0) * 1.1),
                 height: NoopMetrics.dashboardTileChartHeight,
                 label: "Seven-day steps preview; missing days have no bars", compact: true, unit: "steps", readings: data(capturedAt)?.stepsWeek ?? [], empty: "No recent steps")
            metricCaption(data(capturedAt)?.steps, empty: "Today unavailable · 7d shown")
        }
    }

    private var vo2Tile: some View {
        metricTile(.vo2, value: data(capturedAt)?.vo2.map { $0.value.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                   unit: data(capturedAt)?.vo2 == nil ? "" : "mL/kg/min", tint: StrandPalette.metricVO2) {
            let history = vo2History(capturedAt)
            plot(history.points, domain: history.domain, tint: StrandPalette.metricVO2,
                 height: NoopMetrics.dashboardTileChartHeight,
                 label: "VO₂ max preview; method and source changes remain gaps", compact: true, unit: "mL/kg/min", readings: data(capturedAt)?.vo2History ?? [], empty: "No recorded value yet")
            if let reading = data(capturedAt)?.vo2 { metricCaption(reading, empty: "") }
            else if let inputs = data(capturedAt)?.fitnessInputs {
                Text(inputs.summary).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityHint(inputs.detail)
            } else if data(capturedAt) != nil {
                Text("Readiness unavailable · retry refresh").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func metricTile<Content: View>(_ metric: DashboardHistoryMetric, value: String, unit: String, tint: Color,
                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        NoopCard(padding: NoopMetrics.space3, tint: tint, fillHeight: true) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Button { expandedAt = Date(); expandedMetric = metric } label: {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack {
                            Text(metric.title).font(StrandFont.subhead).fontWeight(.semibold)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }.foregroundStyle(StrandPalette.textPrimary)
                        numeric(value, unit: unit)
                    }.frame(minHeight: NoopMetrics.minimumTouchTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Expand \(metric.title) history").accessibilityValue("\(value) \(unit)")
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricCaption(_ reading: DashboardDailyReading?, empty: String) -> some View {
        let text: String
        if let reading {
            let source = reading.source.hasSuffix("-noop") ? "Estimate" : reading.source == Repository.appleHealthSource ? "Health" : "WHOOP"
            let date = HeartDashboardProjection.date(reading.day)
            let sameYear = date.map { Calendar.current.component(.year, from: $0) == Calendar.current.component(.year, from: capturedAt) } ?? false
            let dateText = date.map { sameYear ? $0.formatted(.dateTime.month(.abbreviated).day()) : $0.formatted(date: .abbreviated, time: .omitted) } ?? reading.day
            text = "\(source) · \(dateText)"
        } else { text = empty }
        return Text(text).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true).accessibilityLabel(reading.map(caption) ?? empty)
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
    private func numeric(_ value: String, unit: String, hero: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(value).font(StrandFont.number(hero ? heartSize : metricSize, weight: .semibold)).foregroundStyle(StrandPalette.textPrimary)
                Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(value).font(StrandFont.number(hero ? heartSize : metricSize, weight: .semibold)).foregroundStyle(StrandPalette.textPrimary)
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
                                   dailyLabels: Bool = false, compact: Bool = false, unit: String = "", readings: [DashboardDailyReading] = [], empty: String) -> some View {
        if points.isEmpty {
            Text(empty).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: min(height, NoopMetrics.dashboardTrendHeight), alignment: .leading)
        } else {
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let padding = max(1, (maxValue - minValue) * 0.15)
            let sources = Dictionary(readings.map { ($0.day, HeartDashboardModel.source($0)) }, uniquingKeysWith: { first, _ in first })
            DashboardChart(points: DashboardTraceSampling.reduce(points), domain: domain, range: range ?? max(0, minValue - padding)...(maxValue + padding),
                           tint: tint, style: style, height: height, label: label, dailyLabels: dailyLabels, compact: compact,
                           inspectionData: points.map { point in
                               let source = sources[Repository.localDayKey(point.date)] ?? (unit == "bpm" ? "WHOOP · one-minute average" : "Recorded")
                               return ChartScrubDatum(id: "\(point.date.timeIntervalSince1970)|\(point.segment)", x: point.date.timeIntervalSince1970, y: point.value,
                                   value: "\(point.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)",
                                   context: "\(point.date.formatted(date: .abbreviated, time: unit == "bpm" ? .shortened : .omitted)) · \(source)", segment: point.segment)
                           })
        }
    }
}
