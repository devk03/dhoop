import SwiftUI
import StrandDesign

/// Sleep statistics use the same inclusive date-range control as the heart dashboard.
struct CutSleepView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var ble: BLEManager
    @StateObject private var history = SleepRangeModel()
    @State private var selection = MetricRangeSelection()
    @State private var capturedAt = Date()
    @State private var refreshToken = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var window: MetricDateWindow { selection.window(now: capturedAt) }
    private var result: SleepRangeSnapshot? {
        guard let result = history.snapshot, result.deviceId == repo.deviceId, result.window == window else { return nil }
        return result
    }
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space3)) : AnyLayout(DashboardPairLayout())
    }

    var body: some View {
        ScreenScaffold(title: "Sleep", onRefresh: { ble.syncNow(); capturedAt = Date(); refreshToken += 1 }) {
            MetricRangeControl(selection: $selection, now: capturedAt)
            averageCard
            if let latest = result?.readings.last { latestCard(latest) }
            if result != nil {
                timingCard
                stageAverages
            }
            if let error = history.error {
                Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
            }
            Text("Ranges follow recorded wake dates. Missing records are excluded from averages.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .onAppear { capturedAt = Date() }
        .task(id: "\(repo.deviceId)|\(window.identity)|\(refreshToken)") { await history.load(repo: repo, window: window) }
    }

    private var averageCard: some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Average recorded sleep").font(StrandFont.headline).foregroundStyle(StrandPalette.restColor)
                Text(result?.averageSleep.map(sleepHM) ?? "—")
                    .font(StrandFont.number(numberSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                if let result {
                    Text(window.coverage(result.readings.count)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text(sources(result.readings)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if result.readings.isEmpty {
                        Text("No sleep recorded in this range").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        sleepChart(result.readings)
                    }
                } else if history.error == nil {
                    ProgressView("Reading saved sleep…")
                }
                let need = SleepModel.debtNeedMin(days: repo.days)
                Text("Current sleep need · \(sleepHM(need))").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func latestCard(_ reading: SleepRangeReading) -> some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Latest record in range · \(displayDate(reading.total.day))").font(StrandFont.headline)
                Text(sleepHM(reading.total.value)).font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                Text(source(reading.total.source)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if let clock = result?.mainWindows[reading.total.day] {
                    Text("Main sleep window · \(sleepClock(clock.start)) → \(sleepClock(clock.end))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                layout {
                    stageValue("Deep", reading.deep, StrandPalette.sleepDeep)
                    stageValue("REM", reading.rem, StrandPalette.sleepREM)
                    stageValue("Light", reading.light, StrandPalette.sleepLight)
                }
            }
        }
    }

    private var timingCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Average main sleep timing").font(StrandFont.headline)
                let clocks = Array(result?.mainWindows.values ?? Dictionary<String, (start: Int, end: Int)>().values)
                layout {
                    stageValue("Bedtime", nil, StrandPalette.restColor, value: meanClock(clocks.map(\.start)))
                    stageValue("Wake", nil, StrandPalette.restColor, value: meanClock(clocks.map(\.end)))
                }
                Text("\(clocks.count) recorded dates with matching-source sleep windows")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private var stageAverages: some View {
        let groups = Dictionary(grouping: result?.readings ?? [], by: { $0.total.source })
        return ForEach(groups.keys.sorted(), id: \.self) { id in
            let records = groups[id] ?? []
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("Average stages · \(source(id))").font(StrandFont.headline)
                    layout {
                        stageAverage("Deep", values: records.map(\.deep), tint: StrandPalette.sleepDeep)
                        stageAverage("REM", values: records.map(\.rem), tint: StrandPalette.sleepREM)
                        stageAverage("Light", values: records.map(\.light), tint: StrandPalette.sleepLight)
                    }
                    Text("Stages stay with their recorded source; unavailable stages remain unknown.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func stageAverage(_ title: String, values: [Double?], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            stageValue(title, SleepRangeProjection.mean(values), tint)
            Text("\(values.compactMap { $0 }.count) recorded dates").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func stageValue(_ title: String, _ minutes: Double?, _ tint: Color, value: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(tint)
            Text(value ?? minutes.map(sleepHM) ?? "—").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
        }
        .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private func source(_ id: String) -> String {
        if id == Repository.appleHealthSource { return "Apple Health" }
        if id.hasSuffix("-noop") { return "On-device estimates" }
        return "WHOOP records"
    }
    private func sources(_ records: [SleepRangeReading]) -> String {
        let labels = Set(records.map { source($0.total.source) }).sorted()
        return labels.count > 1 ? "Mixed sources · \(labels.joined(separator: ", "))" : labels.first ?? "Source unavailable"
    }
    private func displayDate(_ day: String) -> String {
        HeartDashboardProjection.date(day)?.formatted(date: .abbreviated, time: .omitted) ?? day
    }
    private func meanClock(_ timestamps: [Int]) -> String {
        let minutes = timestamps.map { ts -> Double in
            let fields = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(ts)))
            return Double((fields.hour ?? 0) * 60 + (fields.minute ?? 0))
        }
        guard let mean = SleepRangeProjection.clockMeanMinutes(minutes) else { return "—" }
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = TimeZone(secondsFromGMT: 0)!
        return Date(timeIntervalSince1970: Double(mean * 60)).formatted(format)
    }
    private func sleepChart(_ records: [SleepRangeReading]) -> some View {
        let points = records.compactMap { row -> TrendPoint? in
            guard let date = HeartDashboardProjection.date(row.total.day) else { return nil }
            return TrendPoint(date: date, value: row.total.value / 60, segment: row.total.source)
        }
        let start = window.days == nil ? (points.first?.date ?? window.end) : window.start
        let high = max(1, (points.map(\.value).max() ?? 0) * 1.1)
        return DashboardChart(points: DashboardTraceSampling.reduce(points), domain: start...max(start.addingTimeInterval(1), window.through),
            range: 0...high, tint: StrandPalette.restColor, style: .bars, height: NoopMetrics.chartHeight,
            label: "Recorded sleep hours by wake date in the selected range; missing dates have no bars")
    }
}

func sleepHM(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
}

func sleepClock(_ ts: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
}
