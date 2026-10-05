#if !os(watchOS)
import Foundation

/// One display budget across all observed runs. Boundaries and each run's extrema take priority.
public enum DashboardTraceSampling {
    public static func reduce(_ points: [TrendPoint], targetCount: Int = ChartDownsample.targetVertices) -> [TrendPoint] {
        guard points.count > targetCount else { return points }
        let runs = hrGapRuns(segments: points.map(\.segment))
        let floors = runs.map { min(4, $0.count) }
        let mandatory = floors.reduce(0, +)
        let budget = min(points.count, max(targetCount, mandatory))
        let spare = budget - mandatory
        let weights = zip(runs, floors).map { $0.0.count - $0.1 }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return points }
        var allocations = zip(floors, weights).map { $0.0 + spare * $0.1 / totalWeight }
        var remaining = budget - allocations.reduce(0, +)
        let order = runs.indices.sorted {
            let left = (spare * weights[$0]) % totalWeight
            let right = (spare * weights[$1]) % totalWeight
            return left == right ? $0 < $1 : left > right
        }
        for i in order where remaining > 0 && allocations[i] < runs[i].count {
            allocations[i] += 1; remaining -= 1
        }
        return runs.indices.flatMap { i in
            let run = Array(points[runs[i]])
            return run.count <= allocations[i] ? run
                : ChartDownsample.minMaxBucketed(run, threshold: 0, targetCount: allocations[i])
        }
    }
}
#endif
