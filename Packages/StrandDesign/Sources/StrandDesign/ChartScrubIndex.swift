import Foundation

/// Exact recorded values available for inspection, independent of rendered downsampling.
public struct ChartScrubDatum: Identifiable, Sendable {
    public let id: String
    public let x: Double
    public let y: Double
    public let value: String
    public let context: String
    public let series: String
    public let segment: String
    public init(id: String, x: Double, y: Double, value: String, context: String, series: String = "", segment: String = "default") {
        self.id = id; self.x = x; self.y = y; self.value = value; self.context = context; self.series = series; self.segment = segment
    }
}

public struct ChartScrubSelection {
    public let x: Double
    public let data: [ChartScrubDatum]
    public let isGap: Bool
}

/// Binary search over unique x positions; series without a value on the selected x stay absent.
public struct ChartScrubIndex {
    public let positions: [Double]
    private let groups: [Double: [ChartScrubDatum]]
    private let bySeries: [String: [ChartScrubDatum]]
    public init(_ data: [ChartScrubDatum]) {
        groups = Dictionary(grouping: data.filter { $0.x.isFinite && $0.y.isFinite }, by: \.x)
        positions = groups.keys.sorted()
        bySeries = Dictionary(grouping: data.filter { $0.x.isFinite && $0.y.isFinite }, by: \.series)
            .mapValues { $0.sorted { $0.x < $1.x } }
    }
    public func selection(at x: Double, bucketUnit: Calendar.Component?, calendar: Calendar = .current) -> ChartScrubSelection? {
        guard let bucketUnit else { return selection(at: x) }
        guard x.isFinite, let interval = calendar.dateInterval(of: bucketUnit, for: Date(timeIntervalSince1970: x)) else { return nil }
        return selection(at: interval.start.timeIntervalSince1970, exact: true)
    }

    public func selection(at x: Double, exact: Bool = false) -> ChartScrubSelection? {
        guard x.isFinite, !positions.isEmpty else { return nil }
        if exact { return ChartScrubSelection(x: x, data: groups[x] ?? [], isGap: groups[x] == nil) }
        var low = 0, high = positions.count
        while low < high {
            let mid = (low + high) / 2
            if positions[mid] < x { low = mid + 1 } else { high = mid }
        }
        let next = min(low, positions.count - 1), previous = max(0, low - 1)
        let chosen = abs(positions[previous] - x) <= abs(positions[next] - x) ? previous : next
        let data = groups[positions[chosen]] ?? []
        let gap = data.contains { datum in
            let series = bySeries[datum.series] ?? []
            var low = 0, high = series.count
            while low < high {
                let mid = (low + high) / 2
                if series[mid].x < x { low = mid + 1 } else { high = mid }
            }
            guard low > 0, low < series.count, series[low].x != x else { return false }
            return series[low - 1].segment != series[low].segment
        }
        return ChartScrubSelection(x: positions[chosen], data: data, isGap: gap)
    }
    public func adjacent(to x: Double?, forward: Bool) -> Double? {
        guard !positions.isEmpty else { return nil }
        guard let x, let current = selection(at: x), let index = positions.firstIndex(of: current.x) else {
            return forward ? positions.first : positions.last
        }
        return positions[min(positions.count - 1, max(0, index + (forward ? 1 : -1)))]
    }
}
