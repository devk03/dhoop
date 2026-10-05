import Foundation

/// Static dashboard snapshots refresh at most every fifteen minutes, or at the next local day.
enum DashboardSnapshotCadence {
    static let interval: TimeInterval = 15 * 60
    static func delay(after snapshot: Date, now: Date, calendar: Calendar = .current) -> TimeInterval {
        guard now >= snapshot else { return 0 }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: snapshot)) ?? snapshot.addingTimeInterval(interval)
        let deadline = min(snapshot.addingTimeInterval(interval), nextDay)
        return max(0, deadline.timeIntervalSince(now))
    }
}
