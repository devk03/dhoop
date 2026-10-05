import Foundation

struct DashboardDailyReading: Equatable, Sendable {
    let day: String
    let value: Double
    let source: String
    let key: String
    var method: String? = nil
}

struct DashboardTraceSample: Equatable, Sendable {
    let time: TimeInterval
    let value: Double
    var provenance: String = ""
}

struct DashboardTracePoint: Equatable, Sendable {
    let time: TimeInterval
    let value: Double
    let segment: String
}

/// Calendar/source bounds live outside the views so future, missing and incompatible data stay visible.
enum HeartDashboardProjection {
    static func bounded(_ readings: [DashboardDailyReading], from: String, through: String) -> [DashboardDailyReading] {
        readings.filter { $0.day >= from && $0.day <= through && $0.value.isFinite && $0.value >= 0 }
            .sorted { $0.day < $1.day }
    }

    static func latest(_ readings: [DashboardDailyReading], through: String) -> DashboardDailyReading? {
        bounded(readings, from: "0000-01-01", through: through).last { $0.value > 0 }
    }

    static func trace(_ samples: [DashboardTraceSample], from: TimeInterval, through: TimeInterval,
                      gapSeconds: TimeInterval) -> [DashboardTracePoint] {
        let samples = samples.filter { $0.time >= from && $0.time <= through && $0.time.isFinite && $0.value.isFinite }
            .sorted { $0.time < $1.time }
        var segment = 0
        return samples.enumerated().map { i, point in
            if i > 0, point.time - samples[i - 1].time > gapSeconds || point.provenance != samples[i - 1].provenance {
                segment += 1
            }
            return DashboardTracePoint(time: point.time, value: point.value, segment: String(segment))
        }
    }

    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let dayNumber = Int(parts[2]) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard let date = gregorian.date(from: DateComponents(year: year, month: month, day: dayNumber)) else { return nil }
        let check = gregorian.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == dayNumber else { return nil }
        return date
    }
}
