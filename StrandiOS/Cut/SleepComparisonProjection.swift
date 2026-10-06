import Foundation

struct SleepComparisonSample: Sendable {
    enum Stage: String, Sendable { case deep, rem, core, unspecified, awake }
    let sourceID: String
    let sourceName: String
    let start: Double
    let end: Double
    let stage: Stage
}

struct SleepComparisonDay: Identifiable, Sendable {
    let day: String
    let sourceID: String
    let method: String
    let total: Double
    let deep: Double?
    let rem: Double?
    let light: Double?
    let unspecified: Double?
    var id: String { day }
}

struct SleepComparisonProvider: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let days: [SleepComparisonDay]

    var isEightSleep: Bool {
        let normalizedName = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let normalizedID = id.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalizedName.contains("eightsleep") || normalizedName.contains("8sleep")
            || normalizedID.contains("eightsleep") || normalizedID.contains("8sleep")
    }
    var displayName: String { isEightSleep ? "8sleep" : name }
}

/// Presentation-only source partitions and interval unions; no persisted sleep score is changed.
enum SleepComparisonProjection {
    struct Pair {
        let whoop: SleepComparisonDay
        let apple: SleepComparisonDay
    }
    static func matched(_ whoop: [SleepComparisonDay], _ apple: [SleepComparisonDay]) -> [Pair] {
        let right = Dictionary(apple.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return whoop.compactMap { lhs in right[lhs.day].map { Pair(whoop: lhs, apple: $0) } }
    }
    static func isAppWriteback(sourceID: String, ownBundleID: String?, syncID: String?, externalID: String?) -> Bool {
        sourceID == ownBundleID || syncID?.hasPrefix("noop:") == true || externalID?.hasPrefix("noop:") == true
    }
    static func hasWhoopOwner(_ owner: String?, rawIDs: Set<String>) -> Bool {
        guard let owner else { return false }
        return rawIDs.contains(owner)
    }
    static func mean(_ values: [Double?]) -> Double? { SleepRangeProjection.mean(values) }
    static func preferred(_ groups: [[SleepComparisonDay]], window: MetricDateWindow) -> [SleepComparisonDay] {
        var days: [String: SleepComparisonDay] = [:]
        for group in groups {
            for row in group where row.day >= window.fromDay && row.day <= window.toDay && row.total.isFinite && row.total > 0 {
                if days[row.day] == nil { days[row.day] = row }
            }
        }
        return days.values.sorted { $0.day < $1.day }
    }
    static func healthProviders(_ samples: [SleepComparisonSample], window: MetricDateWindow,
                                calendar: Calendar = .current, observedThrough: Date? = nil) -> [SleepComparisonProvider] {
        let valid = samples.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && $0.end <= (observedThrough ?? window.through).timeIntervalSince1970 }
        return Dictionary(grouping: valid, by: \.sourceID).map { id, rows in
            let sorted = rows.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
            // Nearby stage fragments share a wake-date episode; actual gaps are never filled.
            // Later naps remain separate episodes, then contribute to that date's recorded total.
            var episodes: [[SleepComparisonSample]] = [], current: [SleepComparisonSample] = []
            var end = -Double.infinity
            for sample in sorted {
                if !current.isEmpty && sample.start - end > 90 * 60 { episodes.append(current); current = []; end = -Double.infinity }
                current.append(sample); end = max(end, sample.end)
            }
            if !current.isEmpty { episodes.append(current) }
            var totals: [String: [Double]] = [:]
            for episode in episodes {
                let asleep = episode.filter { $0.stage != .awake }
                guard let wake = asleep.map(\.end).max() else { continue }
                let date = Date(timeIntervalSince1970: wake)
                let dc = calendar.dateComponents([.year, .month, .day], from: date)
                let day = String(format: "%04d-%02d-%02d", dc.year!, dc.month!, dc.day!)
                guard day >= window.fromDay, day <= window.toDay else { continue }
                var sums = unionMinutes(episode)
                if let previous = totals[day] { sums = zip(previous, sums).map(+) }
                totals[day] = sums
            }
            let days = totals.keys.sorted().compactMap { day -> SleepComparisonDay? in
                let v = totals[day]!
                guard v[0] > 0 else { return nil }
                // A source supplying only unspecified sleep cannot prove zero REM/deep/core.
                let staged = v[1] + v[2] + v[3] > 0
                return SleepComparisonDay(day: day, sourceID: id, method: "HealthKit provider", total: v[0],
                    deep: staged ? v[1] : nil, rem: staged ? v[2] : nil, light: staged ? v[3] : nil, unspecified: v[4])
            }
            return SleepComparisonProvider(id: id, name: sorted.first?.sourceName ?? id, detail: id, days: days)
        }.filter { !$0.days.isEmpty }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private static func unionMinutes(_ samples: [SleepComparisonSample]) -> [Double] {
        typealias Stage = SleepComparisonSample.Stage
        var events: [Double: [(Stage, Int)]] = [:]
        for s in samples { events[s.start, default: []].append((s.stage, 1)); events[s.end, default: []].append((s.stage, -1)) }
        let times = events.keys.sorted()
        var active: [Stage: Int] = [:], result = [Double](repeating: 0, count: 5)
        for (i, t) in times.enumerated() {
            for (stage, delta) in events[t]! { active[stage, default: 0] += delta }
            guard i + 1 < times.count else { continue }
            let duration = (times[i + 1] - t) / 60
            let stages = [Stage.deep, .rem, .core].filter { active[$0, default: 0] > 0 }
            guard active[.awake, default: 0] == 0,
                  !stages.isEmpty || active[.unspecified, default: 0] > 0 else { continue }
            result[0] += duration
            // Explicit awake overrides broad asleep intervals. Conflicting precise asleep
            // stages remain unclassified rather than choosing a stage winner.
            if stages.count == 1 {
                let index = stages[0] == .deep ? 1 : stages[0] == .rem ? 2 : 3
                result[index] += duration
            } else { result[4] += duration }
        }
        return result
    }
}
