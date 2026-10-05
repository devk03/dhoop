import Foundation
import Combine
import StrandDesign

enum DashboardHistoryMetric: String, Identifiable {
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
    var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .hrv: return "ms"
        case .steps: return "steps/day"
        case .vo2: return "mL/kg/min"
        }
    }
}

struct MetricRangeSnapshot {
    let deviceId: String
    let metric: DashboardHistoryMetric
    let window: MetricDateWindow
    let groups: [MetricAverageGroup]
    let hrMean: Double?
    let hrCount: Int
    let resting: DashboardDailyReading?
    var mean: Double? { metric == .heartRate ? hrMean : groups.first?.mean }
}

@MainActor
final class MetricRangeModel: ObservableObject {
    @Published private(set) var snapshot: MetricRangeSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    private var generation = 0

    func load(repo: Repository, deviceId: String, metric: DashboardHistoryMetric, window: MetricDateWindow) async {
        generation += 1
        let current = generation
        if snapshot?.deviceId != deviceId || snapshot?.metric != metric || snapshot.map({ !window.canDisplaySnapshot($0.window) }) == true { snapshot = nil }
        error = nil; isRefreshing = true
        defer { if current == generation { isRefreshing = false } }
        var readings: [DashboardDailyReading] = []
        var hrMean: Double?
        var hrCount = 0
        var resting: DashboardDailyReading?
        func map(_ rows: [ResolvedMetricPoint]) -> [DashboardDailyReading] {
            rows.map { DashboardDailyReading(day: $0.day, value: $0.value, source: $0.source, key: $0.sourceKey) }
        }
        do {
            switch metric {
            case .heartRate:
                guard let store = await repo.storeHandle() else { throw RangeError.storageUnavailable }
                let days = try await store.measuredHeartRateDays(deviceId: deviceId, from: Int(window.start.timeIntervalSince1970), to: Int(window.through.timeIntervalSince1970))
                hrCount = days.reduce(0) { $0 + $1.count }
                hrMean = MetricRangeProjection.weightedMean(days.map { ($0.sumBPM, $0.count) })
                readings = days.map { DashboardDailyReading(day: $0.day, value: $0.averageBPM, source: deviceId, key: "measuredHR") }
                let rests = await repo.resolvedSeries(key: "rhr", source: Repository.whoopSource, from: "0001-01-01", to: window.toDay)
                resting = HeartDashboardProjection.latest(map(rests.points), through: window.toDay)
            case .hrv:
                let rows = await repo.resolvedSeries(key: "hrv", source: Repository.whoopSource, from: window.fromDay, to: window.toDay)
                readings = map(rows.points)
            case .steps:
                readings = map((await repo.resolvedSteps(from: window.fromDay, to: window.toDay)).points)
            case .vo2:
                async let estimated = repo.resolvedSeries(key: "vo2max_est", source: Repository.whoopSource, from: window.fromDay, to: window.toDay)
                async let measured = repo.resolvedSeries(key: "vo2max", source: Repository.appleHealthSource, from: window.fromDay, to: window.toDay)
                for row in (await estimated).points {
                    let method = await repo.scoreProvenanceTag(resolvedSource: row.source, day: row.day, metricKey: "vo2max_est")
                    readings.append(DashboardDailyReading(day: row.day, value: row.value, source: row.source, key: row.sourceKey, method: method ?? "unknown"))
                }
                readings += map((await measured).points)
            }
            guard current == generation, !Task.isCancelled, repo.deviceId == deviceId else { return }
            snapshot = MetricRangeSnapshot(deviceId: deviceId, metric: metric, window: window,
                groups: MetricRangeProjection.groups(readings, window: window,
                    separateMethods: metric == .hrv || metric == .vo2, allowZero: metric == .steps),
                hrMean: hrMean, hrCount: hrCount, resting: resting)
        } catch {
            guard current == generation, !Task.isCancelled, repo.deviceId == deviceId else { return }
            self.error = "History could not be read: \(error.localizedDescription)"
        }
    }
    private enum RangeError: Error { case storageUnavailable }
}
