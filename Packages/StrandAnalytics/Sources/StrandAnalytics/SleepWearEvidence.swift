/// Resolves a missing wrist-on event from sustained decoded HR, not connection or motion packets.
/// The inferred boundary is analysis-only; recorded device events remain unchanged.
public enum SleepWearEvidence {
    public static func confirmedWearStart(samples: [(ts: Int, bpm: Int)], after: Int, through: Int) -> Int? {
        // Duplicate timestamps cannot manufacture coverage. Conflicting invalid values are conservative.
        var validBySecond: [Int: Bool] = [:]
        for sample in samples where sample.ts > after && sample.ts <= through {
            let valid = (30...220).contains(sample.bpm)
            validBySecond[sample.ts] = (validBySecond[sample.ts] ?? true) && valid
        }
        var seconds: [Int] = []
        var first = 0
        for ts in validBySecond.keys.sorted() {
            guard validBySecond[ts] == true else { seconds.removeAll(keepingCapacity: true); first = 0; continue }
            if let last = seconds.last, ts - last > 5 { seconds.removeAll(keepingCapacity: true); first = 0 }
            seconds.append(ts)
            // Keep the closest boundary at least 60 seconds behind the newest sample.
            while first + 1 < seconds.count && seconds[first + 1] <= ts - 60 { first += 1 }
            let span = ts - seconds[first]
            if span >= 60 && (seconds.count - first) * 5 >= (span + 1) * 4 {
                return seconds[first]
            }
        }
        return nil
    }
}
