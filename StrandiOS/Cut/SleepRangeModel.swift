import Foundation
import Combine
import WhoopStore

struct SleepRangeSnapshot {
    let deviceId: String
    let window: MetricDateWindow
    let whoop: [SleepComparisonDay]
    let apple: [SleepComparisonProvider]
    let healthMessage: String?
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
            guard current == generation, !Task.isCancelled else { return }
            error = "Local storage is unavailable"; return
        }
        async let health = healthRead(window: window)
        do {
            let ids = await repo.sleepComparisonSourceIds()
            let rawIDs = Set(ids.filter { !$0.hasSuffix("-noop") })
            var groups: [[SleepComparisonDay]] = []
            for source in ids {
                if Task.isCancelled { return }
                let rows = try await stored(store: store, id: source, window: window, apple: false)
                if source.hasSuffix("-noop") {
                    var verified: [SleepComparisonDay] = []
                    for row in rows {
                        let owner = try await store.scoreInputSource(deviceId: source, day: row.day, key: "sleep_performance")
                        if SleepComparisonProjection.hasWhoopOwner(owner, rawIDs: rawIDs) { verified.append(row) }
                    }
                    groups.append(verified)
                } else { groups.append(rows) }
            }
            let whoop = SleepComparisonProjection.preferred(groups, window: window)
            let (providers, healthError) = await health
            var apple = providers
            var message = healthError
            if providers.isEmpty {
                let cached = try await stored(store: store, id: Repository.appleHealthSource, window: window, apple: true)
                if !cached.isEmpty {
                    apple = [SleepComparisonProvider(id: "saved-apple-health", name: "Saved Apple Health",
                        detail: "Provider unavailable · legacy daily totals", days: cached)]
                    message = "Saved Apple totals may combine providers. Enable sleep access for a provider-specific comparison."
                        + (healthError.map { " \($0)" } ?? "")
                } else if message == nil {
                    message = "No readable Apple sleep in this range. Check sleep access in Health and the source app's sync."
                }
            }
            guard current == generation, !Task.isCancelled, id == repo.deviceId else { return }
            snapshot = SleepRangeSnapshot(deviceId: id, window: window, whoop: whoop, apple: apple, healthMessage: message)
        } catch {
            guard current == generation, !Task.isCancelled, id == repo.deviceId else { return }
            self.error = "Sleep could not be read: \(error.localizedDescription)"
        }
    }
    private func healthRead(window: MetricDateWindow) async -> ([SleepComparisonProvider], String?) {
        do { return (try await SleepComparisonHealthReader.read(window: window), nil) }
        catch { return ([], "Health read failed: \(error.localizedDescription)") }
    }
    private func stored(store: WhoopStore, id: String, window: MetricDateWindow, apple: Bool) async throws -> [SleepComparisonDay] {
        let daily = try await store.dailyMetrics(deviceId: id, from: window.fromDay, to: window.toDay)
        let keys = apple ? ["asleep_min", "deep_min", "rem_min", "core_min"] : ["sleep_total_min", "sleep_deep_min", "sleep_rem_min", "sleep_light_min"]
        var fields: [[String: Double]] = []
        for key in keys {
            let values = try await store.metricSeries(deviceId: id, key: key, from: window.fromDay, to: window.toDay)
            fields.append(Dictionary(values.filter { $0.value.isFinite && $0.value >= 0 }.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last }))
        }
        for d in daily {
            for (i, value) in [d.totalSleepMin, d.deepMin, d.remMin, d.lightMin].enumerated() {
                if fields[i][d.day] == nil, let value, value.isFinite, value >= 0 { fields[i][d.day] = value }
            }
        }
        return fields[0].keys.sorted().compactMap { day in
            guard day >= window.fromDay, day <= window.toDay, let total = fields[0][day], total > 0 else { return nil }
            let deep = fields[1][day], rem = fields[2][day], light = fields[3][day]
            var unknown: Double?
            if let deep, let rem, let light, deep + rem + light <= total { unknown = total - deep - rem - light }
            return SleepComparisonDay(day: day, sourceID: id, method: apple ? "Saved daily aggregate" : id.hasSuffix("-noop") ? "Dhoop estimate" : "Imported WHOOP record",
                total: total, deep: deep, rem: rem, light: light, unspecified: unknown)
        }
    }
}
