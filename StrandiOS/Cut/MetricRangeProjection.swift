import Foundation

struct MetricRangeSelection: Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case today, week, month, quarter, all, custom
        var id: String { rawValue }
        var shortTitle: String {
            switch self { case .today: "Today"; case .week: "7D"; case .month: "30D"; case .quarter: "90D"; case .all: "All"; case .custom: "Custom" }
        }
        var title: String {
            switch self {
            case .today: return "Today"
            case .week: return "7 days"
            case .month: return "30 days"
            case .quarter: return "90 days"
            case .all: return "All history"
            case .custom: return "Custom dates"
            }
        }
    }
    var preset: Preset = .week
    var customStart: Date
    var customEnd: Date
    init(now: Date = Date()) {
        customStart = Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now
        customEnd = now
    }

    mutating func selectDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) {
        let day = min(calendar.startOfDay(for: date), calendar.startOfDay(for: now))
        customStart = day
        customEnd = day
        preset = calendar.isDate(day, inSameDayAs: now) ? .today : .custom
    }

    func window(now: Date, calendar input: Calendar = .current) -> MetricDateWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        let today = calendar.startOfDay(for: now)
        let end = preset == .custom ? min(today, calendar.startOfDay(for: customEnd)) : today
        let start: Date
        switch preset {
        case .today: start = end
        case .week: start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        case .month: start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        case .quarter: start = calendar.date(byAdding: .day, value: -89, to: end) ?? end
        case .all: start = calendar.date(from: DateComponents(year: 1, month: 1, day: 1)) ?? end
        case .custom: start = min(end, calendar.startOfDay(for: customStart))
        }
        let through = min(now, (calendar.date(byAdding: .day, value: 1, to: end) ?? now).addingTimeInterval(-1))
        return MetricDateWindow(start: start, end: end, through: through,
            fromDay: Self.day(start, calendar: calendar), toDay: Self.day(end, calendar: calendar),
            days: preset == .all ? nil : (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

struct MetricDateWindow: Equatable {
    let start: Date
    let end: Date
    let through: Date
    let fromDay: String
    let toDay: String
    let days: Int?
    var isSingleDay: Bool { fromDay == toDay }
    var identity: String { "\(fromDay)|\(toDay)|\(Int(start.timeIntervalSince1970))|\(Int(through.timeIntervalSince1970))" }
    /// A refresh may retain an older snapshot of the same calendar range, never another range or future data.
    func canDisplaySnapshot(_ old: MetricDateWindow) -> Bool {
        start == old.start && end == old.end && fromDay == old.fromDay && toDay == old.toDay && old.through <= through
    }
    func coverage(_ observed: Int) -> String {
        days.map { "\(observed) of \($0) recorded days" } ?? "\(observed) recorded day\(observed == 1 ? "" : "s")"
    }
    var label: String {
        days == nil ? "All recorded history" : "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct MetricAverageGroup: Identifiable {
    let id: String
    let readings: [DashboardDailyReading]
    var mean: Double { readings.reduce(0) { $0 + $1.value } / Double(readings.count) }
    var isMeasuredHeartRate: Bool { readings.first?.key == "measuredHR" }
    func displayedMean(sampleWeightedHR: Double?) -> Double? {
        isMeasuredHeartRate ? sampleWeightedHR : mean
    }
}

struct MetricHistoryAvailability: Equatable {
    let earlierDays: Int
    let laterDays: Int
    let firstDay: String?
    let lastDay: String?
    var hasHiddenDays: Bool { earlierDays > 0 || laterDays > 0 }
}

/// Missing days never add zero; incompatible methods never acquire a shared average.
enum MetricRangeProjection {
    /// Count recorded calendar days, not sources, so overlapping methods do not inflate coverage.
    static func availability(_ readings: [DashboardDailyReading], window: MetricDateWindow,
                             through day: String, allowZero: Bool = false) -> MetricHistoryAvailability {
        let days = Set(readings.filter {
            $0.day <= day && valid($0, allowZero: allowZero)
        }.map(\.day)).sorted()
        return MetricHistoryAvailability(earlierDays: days.filter { $0 < window.fromDay }.count,
            laterDays: days.filter { $0 > window.toDay }.count, firstDay: days.first, lastDay: days.last)
    }

    private static func valid(_ row: DashboardDailyReading, allowZero: Bool) -> Bool {
        HeartDashboardProjection.date(row.day) != nil && row.value.isFinite
            && (allowZero ? row.value >= 0 : row.value > 0)
    }

    static func weightedMean(_ days: [(sum: Double, count: Int)]) -> Double? {
        let valid = days.filter { $0.count > 0 && $0.sum.isFinite && $0.sum >= 0 }
        let count = valid.reduce(0) { $0 + $1.count }
        guard count > 0 else { return nil }
        return valid.reduce(0) { $0 + $1.sum } / Double(count)
    }

    static func groups(_ readings: [DashboardDailyReading], window: MetricDateWindow,
                       separateMethods: Bool, allowZero: Bool = false) -> [MetricAverageGroup] {
        var groups: [String: [String: DashboardDailyReading]] = [:]
        for row in readings where row.day >= window.fromDay && row.day <= window.toDay
            && valid(row, allowZero: allowZero) {
            let key = separateMethods ? "\(row.source)|\(row.key)|\(row.method ?? "unknown")" : "combined"
            if groups[key]?[row.day] == nil { groups[key, default: [:]][row.day] = row }
        }
        return groups.map { MetricAverageGroup(id: $0.key, readings: $0.value.values.sorted { $0.day < $1.day }) }
            .sorted { lhs, rhs in
                if lhs.isMeasuredHeartRate != rhs.isMeasuredHeartRate { return lhs.isMeasuredHeartRate }
                let l = lhs.readings.last!.day, r = rhs.readings.last!.day
                return l == r ? lhs.id < rhs.id : l > r
            }
    }

    static func loggedProtein(standalone: [(day: String, grams: Double)], food: [(day: String, grams: Double?)]) -> [DashboardDailyReading] {
        var totals: [String: Double] = [:]
        for row in standalone where row.grams.isFinite && row.grams >= 0 { totals[row.day, default: 0] += row.grams }
        for row in food {
            if let grams = row.grams, grams.isFinite, grams >= 0 { totals[row.day, default: 0] += grams }
        }
        return totals.map { DashboardDailyReading(day: $0.key, value: $0.value, source: "Logged protein", key: "protein") }
            .sorted { $0.day < $1.day }
    }
}
