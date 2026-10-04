import Foundation
import Combine
import StrandAnalytics
import StrandDesign
import WhoopStore

struct HeartDashboardSnapshot {
    let deviceId: String
    let calendarDay: String
    let scoreDay: String
    let fromDay: Date
    let through: Date
    let measuredHR: [TrendPoint]
    let strain: Double?
    let strainSource: String
    let strainWeek: [DashboardDailyReading]
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

    func refresh(repo: Repository, profile: ProfileStore, now: Date = Date()) async {
        generation += 1
        let generation = generation
        let id = repo.deviceId
        if data?.deviceId != id { data = nil; error = nil }
        let day = Repository.localDayKey(now)
        let scoreDay = repo.today?.day ?? Repository.logicalDayKey(now)
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        let weekStart = Repository.localDayKey(calendar.date(byAdding: .day, value: -6, to: midnight) ?? midnight)
        let monthStart = Repository.localDayKey(calendar.date(byAdding: .day, value: -29, to: midnight) ?? midnight)
        let mode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey))
        let maxHR = profile.effortHRmax
        let sex = profile.sex
        let resting = repo.today?.day == scoreDay ? repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR : StrainScorer.defaultRestingHR
        guard let store = await repo.storeHandle() else { error = "Local storage is unavailable"; return }
        async let rawHR = store.measuredHeartRateSamples(deviceId: id, from: Int(midnight.timeIntervalSince1970), to: Int(now.timeIntervalSince1970))
        async let strains = repo.resolvedSeries(key: "strain", source: Repository.whoopSource, from: weekStart, to: day)
        async let hrvs = repo.resolvedSeries(key: "hrv", source: Repository.whoopSource, from: "0000-01-01", to: day)
        async let rests = repo.resolvedSeries(key: "rhr", source: Repository.whoopSource, from: "0000-01-01", to: day)
        async let steps = repo.resolvedSteps(from: weekStart, to: day)
        async let vo2Estimates = repo.resolvedSeries(key: "vo2max_est", source: Repository.whoopSource, from: "0000-01-01", to: day)
        async let appleVo2 = repo.resolvedSeries(key: "vo2max", source: Repository.appleHealthSource, from: "0000-01-01", to: day)
        let logicalDate = Repository.logicalDay(now)
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: Repository.whoopSource) : []
        let onset = markers.last { $0.day <= scoreDay && $0.value.isFinite && $0.value <= now.timeIntervalSince1970 }.map { Int($0.value.rounded()) }
        let fallback = Int(calendar.startOfDay(for: logicalDate).timeIntervalSince1970)
        let effortFrom = mode == .sleepOnset ? onset ?? fallback : fallback
        let nextKey = Repository.localDayKey(calendar.date(byAdding: .day, value: 1, to: logicalDate) ?? logicalDate)
        let nextOnset = markers.last { $0.day == nextKey && $0.value.isFinite }.map { Int($0.value) }
        let effortTo = min(Int(now.timeIntervalSince1970), nextOnset ?? Int(now.timeIntervalSince1970))
        async let effortHR = repo.hrSamples(deviceIds: [id], from: effortFrom, to: max(effortFrom, effortTo - 1), limit: 200_000)

        let strainRows = HeartDashboardProjection.bounded(map((await strains).points), from: weekStart, through: day)
        let stored = strainRows.last { $0.day == scoreDay }
        let calculated = StrainScorer.strain(await effortHR, maxHR: maxHR, restingHR: resting,
                                            method: PuffinExperiment.effortMethod, sex: sex)
        let strain = StrainScorer.effectiveEffort(live: calculated, stored: stored?.value)
        let strainSource = calculated != nil && (calculated ?? 0) >= (stored?.value ?? 0)
            ? "On-device estimate" : stored.map(Self.source) ?? "Needs more heart-rate data"
        var strainWeek = strainRows
        if let strain {
            strainWeek.removeAll { $0.day == scoreDay }
            strainWeek.append(DashboardDailyReading(day: scoreDay, value: strain, source: id + "-noop", key: "strain"))
            strainWeek.sort { $0.day < $1.day }
        }
        let allHRV = HeartDashboardProjection.bounded(map((await hrvs).points), from: "0000-01-01", through: day)
        // WHOOP nightly records take priority over Apple daily SDNN; those are different observations.
        let nightlyHRV = allHRV.filter { $0.source != Repository.appleHealthSource }
        let hrvRows = nightlyHRV.isEmpty ? allHRV : nightlyHRV
        let restingRows = map((await rests).points)
        let stepRows = HeartDashboardProjection.bounded(map((await steps).points), from: weekStart, through: day)
        var vo2ByDay: [String: DashboardDailyReading] = [:]
        for point in (await vo2Estimates).points where point.day <= day && point.value.isFinite && point.value > 0 {
            let tag = await repo.scoreProvenanceTag(resolvedSource: point.source, day: point.day, metricKey: "vo2max_est")
            vo2ByDay[point.day] = DashboardDailyReading(day: point.day, value: point.value, source: point.source,
                                                       key: point.sourceKey, method: tag ?? "unknown")
        }
        for point in (await appleVo2).points where point.day <= day && point.value.isFinite && point.value > 0 {
            vo2ByDay[point.day] = DashboardDailyReading(day: point.day, value: point.value, source: point.source, key: point.sourceKey)
        }
        let vo2Rows = vo2ByDay.values.sorted { $0.day < $1.day }
        let raw: [TrendPoint]
        do {
            let samples = try await rawHR
            let traces = HeartDashboardProjection.trace(samples.map { DashboardTraceSample(time: Double($0.ts), value: Double($0.bpm)) },
                from: midnight.timeIntervalSince1970, through: now.timeIntervalSince1970, gapSeconds: 1)
            let all = traces.map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) }
            raw = hrGapRuns(segments: all.map(\.segment)).flatMap {
                ChartDownsample.minMaxBucketed(Array(all[$0]), threshold: ChartDownsample.markThreshold, targetCount: ChartDownsample.targetVertices)
            }
        } catch {
            guard generation == self.generation, id == repo.deviceId else { return }
            self.error = "Stored heart rate could not be read: \(error.localizedDescription)"
            return
        }
        guard generation == self.generation, !Task.isCancelled, id == repo.deviceId,
              day == Repository.localDayKey(Date()) else { return }
        self.data = HeartDashboardSnapshot(deviceId: id, calendarDay: day, scoreDay: scoreDay, fromDay: midnight, through: now,
            measuredHR: raw, strain: strain, strainSource: strainSource, strainWeek: strainWeek,
            hrv: HeartDashboardProjection.latest(hrvRows, through: day),
            hrvMonth: HeartDashboardProjection.bounded(hrvRows, from: monthStart, through: day),
            restingHR: HeartDashboardProjection.latest(restingRows, through: day),
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
