import Foundation

struct SleepRangeReading: Identifiable {
    let total: DashboardDailyReading
    let deep: Double?
    let rem: Double?
    let light: Double?
    var id: String { total.day }
}

/// One dated duration owns its stages; a fallback from another source must not fill them.
enum SleepRangeProjection {
    static func readings(totals: [DashboardDailyReading], deep: [DashboardDailyReading],
                         rem: [DashboardDailyReading], light: [DashboardDailyReading],
                         window: MetricDateWindow) -> [SleepRangeReading] {
        var byDay: [String: DashboardDailyReading] = [:]
        for row in HeartDashboardProjection.bounded(totals, from: window.fromDay, through: window.toDay)
            where row.value > 0 && HeartDashboardProjection.date(row.day) != nil {
            if byDay[row.day] == nil { byDay[row.day] = row }
        }
        func stage(_ rows: [DashboardDailyReading], owner: DashboardDailyReading) -> Double? {
            rows.first { $0.day == owner.day && $0.source == owner.source && $0.value.isFinite && $0.value >= 0 }?.value
        }
        return byDay.values.sorted { $0.day < $1.day }.map { owner in
            SleepRangeReading(total: owner, deep: stage(deep, owner: owner),
                rem: stage(rem, owner: owner), light: stage(light, owner: owner))
        }
    }

    static func mean(_ values: [Double?]) -> Double? {
        let valid = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        return valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
    }

    static func clockMeanMinutes(_ minutes: [Double]) -> Int? {
        let valid = minutes.filter { $0.isFinite && $0 >= 0 && $0 < 1440 }
        guard !valid.isEmpty else { return nil }
        let angles = valid.map { $0 / 1440 * 2 * Double.pi }
        let x = angles.reduce(0) { $0 + cos($1) }, y = angles.reduce(0) { $0 + sin($1) }
        guard hypot(x, y) / Double(valid.count) > 0.000001 else { return nil }
        let angle = atan2(y, x)
        return Int(((angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi) * 1440).rounded()) % 1440
    }
}
