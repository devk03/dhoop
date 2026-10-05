/// Resolves a missing wrist-on event from sustained decoded HR, not connection or motion packets.
/// The inferred boundary is analysis-only; recorded device events remain unchanged.
public enum SleepWearEvidence {
    public static func confirmedWearStart(samples: [(ts: Int, bpm: Int)], after: Int, through: Int) -> Int? {
        confirmedWearStart(ordered: canonicalSamples(samples).filter { $0.ts > after && $0.ts <= through }[...])
    }

    /// Resolve each off interval independently so a later event cannot erase earlier wear evidence.
    public static func offWristIntervals(events: [(ts: Int, isOff: Bool)], samples: [(ts: Int, bpm: Int)],
                                         through: Int) -> [(start: Int, end: Int)] {
        var eventBySecond: [Int: Bool] = [:]
        for event in events where event.ts <= through {
            eventBySecond[event.ts] = (eventBySecond[event.ts] ?? false) || event.isOff
        }
        guard eventBySecond.values.contains(true) else { return [] }
        let readings = canonicalSamples(samples)
        var cursor = 0
        var offStart: Int?
        var result: [(start: Int, end: Int)] = []
        func close(_ start: Int, _ end: Int, includingEnd: Bool = false) {
            guard end > start else { return }
            while cursor < readings.count && readings[cursor].ts <= start { cursor += 1 }
            let first = cursor
            while cursor < readings.count && (includingEnd ? readings[cursor].ts <= end : readings[cursor].ts < end) { cursor += 1 }
            let resolvedEnd = confirmedWearStart(ordered: readings[first..<cursor]) ?? end
            if let last = result.last, last.end == start { result[result.count - 1].end = resolvedEnd }
            else { result.append((start, resolvedEnd)) }
        }
        for ts in eventBySecond.keys.sorted() {
            if let start = offStart { close(start, ts) }
            offStart = eventBySecond[ts] == true ? ts : nil
        }
        if let start = offStart { close(start, through, includingEnd: true) }
        return result
    }

    private static func canonicalSamples(_ samples: [(ts: Int, bpm: Int)]) -> [(ts: Int, valid: Bool)] {
        // Duplicate timestamps cannot manufacture coverage. Conflicting invalid values are conservative.
        var validBySecond: [Int: Bool] = [:]
        for sample in samples {
            let valid = (30...220).contains(sample.bpm)
            validBySecond[sample.ts] = (validBySecond[sample.ts] ?? true) && valid
        }
        return validBySecond.keys.sorted().map { ($0, validBySecond[$0]!) }
    }

    private static func confirmedWearStart(ordered: ArraySlice<(ts: Int, valid: Bool)>) -> Int? {
        var seconds: [Int] = []
        var first = 0
        for sample in ordered {
            let ts = sample.ts
            guard sample.valid else { seconds.removeAll(keepingCapacity: true); first = 0; continue }
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
