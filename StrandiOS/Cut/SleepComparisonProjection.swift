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
    var timelines: [SleepComparisonTimeline] = []
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

/// A dated source episode. Empty intervals mean only its boundaries/aggregate are available.
struct SleepComparisonTimeline: Identifiable, Sendable {
    let day: String
    let sourceID: String
    let sourceName: String
    let method: String
    let start: Double
    let end: Double
    let intervals: [SleepStageInterval]
    var id: String { "\(sourceID)|\(start)|\(end)" }
    var asleepMinutes: Double? {
        guard !intervals.isEmpty else { return nil }
        return intervals.filter { $0.stage != .awake }.reduce(0) { $0 + ($1.end - $1.start) / 60 }
    }
}

struct SleepStageInterval: Identifiable, Equatable, Sendable {
    let start: Double
    let end: Double
    let stage: SleepComparisonSample.Stage
    var id: String { "\(start)|\(end)|\(stage.rawValue)" }
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
            var timelines: [String: [SleepComparisonTimeline]] = [:]
            for episode in episodes {
                let asleep = episode.filter { $0.stage != .awake }
                guard let wake = asleep.map(\.end).max() else { continue }
                let date = Date(timeIntervalSince1970: wake)
                let dc = calendar.dateComponents([.year, .month, .day], from: date)
                let day = String(format: "%04d-%02d-%02d", dc.year!, dc.month!, dc.day!)
                guard day >= window.fromDay, day <= window.toDay else { continue }
                let intervals = normalizedIntervals(episode)
                timelines[day, default: []].append(SleepComparisonTimeline(day: day, sourceID: id,
                    sourceName: episode.first?.sourceName ?? id, method: "Apple Health stages",
                    start: episode.map(\.start).min()!, end: episode.map(\.end).max()!, intervals: intervals))
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
                    deep: staged ? v[1] : nil, rem: staged ? v[2] : nil, light: staged ? v[3] : nil, unspecified: v[4], timelines: timelines[day] ?? [])
            }
            return SleepComparisonProvider(id: id, name: sorted.first?.sourceName ?? id, detail: id, days: days)
        }.filter { !$0.days.isEmpty }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Decode timestamped stages only. CSV duration dictionaries never become a chronology.
    static func storedTimeline(json: String?, start: Double, end: Double, sourceID: String,
                               method: String, calendar: Calendar = .current) -> SleepComparisonTimeline? {
        guard start.isFinite, end.isFinite, end > start else { return nil }
        struct Segment: Decodable { let start: Double; let end: Double; let stage: String }
        let records = json?.data(using: .utf8).flatMap { try? JSONDecoder().decode([Segment].self, from: $0) } ?? []
        let samples = records.compactMap { record -> SleepComparisonSample? in
            guard record.start.isFinite, record.end.isFinite else { return nil }
            let lower = max(start, record.start), upper = min(end, record.end)
            guard upper > lower else { return nil }
            let stage: SleepComparisonSample.Stage
            switch record.stage.lowercased() {
            case "wake", "awake": stage = .awake
            case "light", "core": stage = .core
            case "deep": stage = .deep
            case "rem": stage = .rem
            default: stage = .unspecified
            }
            return SleepComparisonSample(sourceID: sourceID, sourceName: "WHOOP", start: lower, end: upper, stage: stage)
        }
        return SleepComparisonTimeline(day: wakeDay(end, calendar: calendar), sourceID: sourceID, sourceName: "WHOOP",
            method: method, start: start, end: end, intervals: normalizedIntervals(samples))
    }

    static func wakeDay(_ timestamp: Double, calendar: Calendar = .current) -> String {
        let dc = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: timestamp))
        return String(format: "%04d-%02d-%02d", dc.year!, dc.month!, dc.day!)
    }

    /// Selection stays inside the global range and falls back to its latest recorded wake date.
    static func selectedNight(_ selected: String, available: [String], window: MetricDateWindow) -> String? {
        let days = available.filter { $0 >= window.fromDay && $0 <= window.toDay }
        return days.contains(selected) ? selected : days.max()
    }

    /// Union duplicate samples without filling holes. Awake wins; conflicting precise stages remain unknown.
    static func normalizedIntervals(_ samples: [SleepComparisonSample]) -> [SleepStageInterval] {
        typealias Stage = SleepComparisonSample.Stage
        var events: [Double: [(Stage, Int)]] = [:]
        for s in samples where s.start.isFinite && s.end.isFinite && s.end > s.start {
            events[s.start, default: []].append((s.stage, 1)); events[s.end, default: []].append((s.stage, -1))
        }
        let times = events.keys.sorted()
        var active: [Stage: Int] = [:], result: [SleepStageInterval] = []
        for (i, t) in times.enumerated() {
            for (stage, delta) in events[t]! { active[stage, default: 0] += delta }
            guard i + 1 < times.count else { continue }
            let precise = [Stage.deep, .rem, .core].filter { active[$0, default: 0] > 0 }
            let stage: Stage
            if active[.awake, default: 0] > 0 { stage = .awake }
            else if precise.count == 1 { stage = precise[0] }
            else if !precise.isEmpty || active[.unspecified, default: 0] > 0 { stage = .unspecified }
            else { continue }
            // Adjacent identical observations can share a bar, but even a one-second hole stays a hole.
            if let last = result.last, last.stage == stage, last.end == t {
                result[result.count - 1] = SleepStageInterval(start: last.start, end: times[i + 1], stage: stage)
            } else { result.append(SleepStageInterval(start: t, end: times[i + 1], stage: stage)) }
        }
        return result
    }

    private static func unionMinutes(_ samples: [SleepComparisonSample]) -> [Double] {
        var result = [Double](repeating: 0, count: 5)
        for interval in normalizedIntervals(samples) where interval.stage != .awake {
            let duration = (interval.end - interval.start) / 60
            result[0] += duration
            let index = interval.stage == .deep ? 1 : interval.stage == .rem ? 2 : interval.stage == .core ? 3 : 4
            result[index] += duration
        }
        return result
    }
}
