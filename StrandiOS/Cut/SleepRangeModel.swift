import Foundation
import Combine
import WhoopStore

struct SleepRangeSnapshot {
    let deviceId: String
    let window: MetricDateWindow
    let readings: [SleepRangeReading]
    let mainWindows: [String: (start: Int, end: Int)]
    var averageSleep: Double? { SleepRangeProjection.mean(readings.map { $0.total.value }) }
}

@MainActor
final class SleepRangeModel: ObservableObject {
    @Published private(set) var snapshot: SleepRangeSnapshot?
    @Published private(set) var error: String?
    private var generation = 0

    func load(repo: Repository, window: MetricDateWindow) async {
        generation += 1
        let current = generation, id = repo.deviceId
        snapshot = nil; error = nil
        guard let store = await repo.storeHandle() else {
            guard current == generation, !Task.isCancelled, id == repo.deviceId else { return }
            error = "Local storage is unavailable"; return
        }
        async let total = repo.resolvedSeries(key: "sleep_total_min", source: Repository.whoopSource, from: window.fromDay, to: window.toDay)
        async let deep = repo.resolvedSeries(key: "sleep_deep_min", source: Repository.whoopSource, from: window.fromDay, to: window.toDay)
        async let rem = repo.resolvedSeries(key: "sleep_rem_min", source: Repository.whoopSource, from: window.fromDay, to: window.toDay)
        async let light = repo.resolvedSeries(key: "sleep_light_min", source: Repository.whoopSource, from: window.fromDay, to: window.toDay)
        func map(_ rows: [ResolvedMetricPoint]) -> [DashboardDailyReading] {
            rows.map { DashboardDailyReading(day: $0.day, value: $0.value, source: $0.source, key: $0.sourceKey) }
        }
        let records = await SleepRangeProjection.readings(totals: map(total.points), deep: map(deep.points),
            rem: map(rem.points), light: map(light.points), window: window)
        // Bound presentation-only main-window learning; range changes must not scan years of staging JSON.
        let habitual = await repo.habitualMidsleepSec(days: 30)
        var clocks: [String: (start: Int, end: Int)] = [:]
        do {
            for source in Set(records.map { $0.total.source }) {
                let sessions = try await store.sleepSessionsByWake(deviceId: source,
                    from: Int(window.start.timeIntervalSince1970), to: Int(window.through.timeIntervalSince1970))
                    .filter { $0.endTs > $0.effectiveStartTs }
                let byDay = Dictionary(grouping: sessions) {
                    Repository.localDayKey(Date(timeIntervalSince1970: Double($0.endTs)))
                }
                for record in records where record.total.source == source {
                    if let group = byDay[record.total.day], let span = SleepView.mainNightSpan(group, habitualMidsleepSec: habitual) {
                        clocks[record.total.day] = span
                    }
                }
            }
        } catch {
            guard current == generation, !Task.isCancelled, id == repo.deviceId else { return }
            self.error = "Sleep timing could not be read: \(error.localizedDescription)"
        }
        guard current == generation, !Task.isCancelled, id == repo.deviceId else { return }
        snapshot = SleepRangeSnapshot(deviceId: id, window: window, readings: records, mainWindows: clocks)
    }
}
