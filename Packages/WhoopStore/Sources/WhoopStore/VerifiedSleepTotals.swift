import Foundation
import GRDB

public struct VerifiedSleepTotal: Sendable, Equatable {
    public let day: String
    public let minutes: Double
    public let sourceId: String
    public let estimated: Bool
}

extension WhoopStore {
    /// Read sleep totals and computed-score provenance in ONE snapshot. Separate awaited reads could
    /// pair a pre-rescore Apple total with post-rescore WHOOP provenance. Source order defines priority.
    /// This read-only projection introduces no schema or analytics changes.
    public func verifiedWhoopSleepTotals(rawSourceIds: [String], from: String, to: String) async throws -> [VerifiedSleepTotal] {
        try syncRead { db in
            let raw = Array(NSOrderedSet(array: rawSourceIds.filter { !$0.hasSuffix("-noop") })) as? [String] ?? []
            var result: [String: VerifiedSleepTotal] = [:]
            for id in raw + raw.map({ $0 + "-noop" }) {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT days.day,
                      COALESCE(m.value, d.totalSleepMin) AS minutes, p.sourceId AS owner
                    FROM (
                      SELECT day FROM dailyMetric WHERE deviceId = ? AND day BETWEEN ? AND ?
                      UNION SELECT day FROM metricSeries WHERE deviceId = ? AND key = 'sleep_total_min' AND day BETWEEN ? AND ?
                    ) AS days
                    LEFT JOIN dailyMetric d ON d.deviceId = ? AND d.day = days.day
                    LEFT JOIN metricSeries m ON m.deviceId = ? AND m.day = days.day AND m.key = 'sleep_total_min'
                    LEFT JOIN scoreInputProvenance p ON p.deviceId = ? AND p.day = days.day AND p.key = 'sleep_performance'
                    ORDER BY days.day
                    """, arguments: [id, from, to, id, from, to, id, id, id])
                let estimated = id.hasSuffix("-noop")
                for row in rows {
                    let day: String = row["day"]
                    let owner: String? = row["owner"]
                    guard result[day] == nil, let minutes: Double = row["minutes"],
                          minutes.isFinite, minutes > 0, minutes <= 1440,
                          !estimated || owner.map(raw.contains) == true else { continue }
                    result[day] = VerifiedSleepTotal(day: day, minutes: minutes, sourceId: id, estimated: estimated)
                }
            }
            return result.values.sorted { $0.day < $1.day }
        }
    }
}
