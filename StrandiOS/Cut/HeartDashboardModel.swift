import Foundation
import Combine
import StrandAnalytics
import StrandDesign
import WhoopStore

struct HeartDashboardSnapshot {
    let deviceId: String
    let calendarDay: String
    let historyDay: String
    let averageHR: Double?
    let hrSampleCount: Int
    let fromDay: Date
    let through: Date
    let measuredHR: [TrendPoint]
    let hrv: DashboardDailyReading?
    let hrvMonth: [DashboardDailyReading]
    let restingHR: DashboardDailyReading?
    let steps: DashboardDailyReading?
    let stepsWeek: [DashboardDailyReading]
    let vo2: DashboardDailyReading?
    let vo2History: [DashboardDailyReading]
}

@MainActor
final class HeartDashboardModel: ObservableObject {
    @Published private(set) var data: HeartDashboardSnapshot?
    @Published private(set) var error: String?
    private var generation = 0

    func refresh(repo: Repository, historyDate: Date, now: Date = Date()) async {
        generation += 1
        let generation = generation
        let id = repo.deviceId
        if data?.deviceId != id { data = nil; error = nil }
        let day = Repository.localDayKey(now)
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        let weekStart = Repository.localDayKey(calendar.date(byAdding: .day, value: -6, to: midnight) ?? midnight)
        let monthStart = Repository.localDayKey(calendar.date(byAdding: .day, value: -29, to: midnight) ?? midnight)
        guard let store = await repo.storeHandle() else { error = "Local storage is unavailable"; return }
        let historyStart = calendar.startOfDay(for: historyDate)
        let historyDay = Repository.localDayKey(historyStart)
        let historyEnd = min(now, (calendar.date(byAdding: .day, value: 1, to: historyStart) ?? now).addingTimeInterval(-1))
        async let rawHR = store.measuredHeartRateSamples(deviceId: id, from: Int(historyStart.timeIntervalSince1970), to: Int(historyEnd.timeIntervalSince1970))
        async let hrvs = repo.resolvedSeries(key: "hrv", source: Repository.whoopSource, from: "0000-01-01", to: day)
        async let rests = repo.resolvedSeries(key: "rhr", source: Repository.whoopSource, from: "0000-01-01", to: day)
        async let steps = repo.resolvedSteps(from: weekStart, to: day)
        async let vo2Estimates = repo.resolvedSeries(key: "vo2max_est", source: Repository.whoopSource, from: "0000-01-01", to: day)
        async let appleVo2 = repo.resolvedSeries(key: "vo2max", source: Repository.appleHealthSource, from: "0000-01-01", to: day)
        let allHRV = HeartDashboardProjection.bounded(map((await hrvs).points), from: "0000-01-01", through: day)
        // WHOOP nightly records take priority over Apple daily SDNN; those are different observations.
        let nightlyHRV = allHRV.filter { $0.source != Repository.appleHealthSource }
        let hrvRows = nightlyHRV.isEmpty ? allHRV : nightlyHRV
        let restingRows = map((await rests).points)
        let stepRows = HeartDashboardProjection.bounded(map((await steps).points), from: weekStart, through: day)
        let estimatePoints = (await vo2Estimates).points.filter { $0.day <= day && $0.value.isFinite && $0.value > 0 }
        let applePoints = (await appleVo2).points.filter { $0.day <= day && $0.value.isFinite && $0.value > 0 }
        let latestVo2Day = (estimatePoints + applePoints).map(\.day).max() ?? day
        let latestVo2Date = HeartDashboardProjection.date(latestVo2Day) ?? now
        let vo2From = Repository.localDayKey(calendar.date(byAdding: .day, value: -89, to: latestVo2Date) ?? latestVo2Date)
        var vo2ByDay: [String: DashboardDailyReading] = [:]
        for point in estimatePoints where point.day >= vo2From {
            let tag = await repo.scoreProvenanceTag(resolvedSource: point.source, day: point.day, metricKey: "vo2max_est")
            vo2ByDay[point.day] = DashboardDailyReading(day: point.day, value: point.value, source: point.source,
                                                       key: point.sourceKey, method: tag ?? "unknown")
        }
        for point in applePoints where point.day >= vo2From {
            vo2ByDay[point.day] = DashboardDailyReading(day: point.day, value: point.value, source: point.source, key: point.sourceKey)
        }
        let vo2Rows = vo2ByDay.values.sorted { $0.day < $1.day }
        let raw: [TrendPoint]
        let summary: HistoricalHeartRateSummary
        do {
            let samples = try await rawHR
            summary = await Task.detached(priority: .userInitiated) {
                HistoricalHeartRateProjection.summarize(samples.map { DashboardTraceSample(time: Double($0.ts), value: Double($0.bpm)) },
                    from: historyStart.timeIntervalSince1970, through: historyEnd.timeIntervalSince1970)
            }.value
            raw = DashboardTraceSampling.reduce(summary.readings.map {
                TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.averageBPM, segment: $0.segment)
            })
        } catch {
            guard generation == self.generation, id == repo.deviceId else { return }
            self.error = "Stored heart rate could not be read: \(error.localizedDescription)"
            return
        }
        guard generation == self.generation, !Task.isCancelled, id == repo.deviceId,
              day == Repository.localDayKey(Date()) else { return }
        self.data = HeartDashboardSnapshot(deviceId: id, calendarDay: day, historyDay: historyDay, averageHR: summary.averageBPM, hrSampleCount: summary.sampleCount, fromDay: historyStart, through: historyEnd,
            measuredHR: raw,
            hrv: HeartDashboardProjection.latest(hrvRows, through: day),
            hrvMonth: HeartDashboardProjection.bounded(hrvRows, from: monthStart, through: day),
            restingHR: HeartDashboardProjection.latest(restingRows, through: historyDay),
            steps: stepRows.last { $0.day == day }, stepsWeek: stepRows,
            vo2: vo2Rows.last, vo2History: vo2Rows)
        self.error = nil
    }

    private func map(_ points: [ResolvedMetricPoint]) -> [DashboardDailyReading] {
        points.map { DashboardDailyReading(day: $0.day, value: $0.value, source: $0.source, key: $0.sourceKey) }
    }

    static func source(_ reading: DashboardDailyReading) -> String {
        if reading.key == "vo2max_est" {
            let method = vo2MaxEstimatorDisplayName(reading.method.flatMap(Vo2MaxEstimator.init(rawValue:)))
            return "Estimated · \(method)"
        }
        if reading.source == Repository.appleHealthSource {
            return reading.key == "hrv" ? "Apple Health · daily SDNN" : "Apple Health"
        }
        if reading.source.hasSuffix("-noop") {
            if reading.key == "hrv" { return "Local HRV · method unverified" }
            return reading.key == "steps" ? "On-device total" : "On-device estimate"
        }
        return reading.key == "hrv" ? "WHOOP record · rMSSD" : "WHOOP record"
    }
}
