import Foundation

struct HistoricalHeartRateReading: Equatable, Sendable {
    let time: TimeInterval
    let averageBPM: Double
    let count: Int
    let segment: String
}

struct HistoricalHeartRateSummary: Sendable {
    let averageBPM: Double?
    let sampleCount: Int
    let readings: [HistoricalHeartRateReading]
}

/// Minute averages use observed samples only. Each gap run remains separate, including within a minute.
enum HistoricalHeartRateProjection {
    static func summarize(_ samples: [DashboardTraceSample], from: TimeInterval, through: TimeInterval) -> HistoricalHeartRateSummary {
        let trace = HeartDashboardProjection.trace(samples.filter { $0.value > 0 }, from: from, through: through, gapSeconds: 1)
        var readings: [HistoricalHeartRateReading] = []
        var group: [DashboardTracePoint] = []
        var minute: Int?
        var segment: String?
        func flush() {
            guard let last = group.last else { return }
            readings.append(HistoricalHeartRateReading(time: last.time,
                averageBPM: group.reduce(0) { $0 + $1.value } / Double(group.count), count: group.count, segment: last.segment))
            group = []
        }
        for point in trace {
            let bucket = Int(floor(point.time / 60))
            if minute != bucket || segment != point.segment { flush(); minute = bucket; segment = point.segment }
            group.append(point)
        }
        flush()
        return HistoricalHeartRateSummary(averageBPM: trace.isEmpty ? nil : trace.reduce(0) { $0 + $1.value } / Double(trace.count),
                                          sampleCount: trace.count, readings: readings)
    }
}
