import Foundation

/// A finite app-side completion sequence. A scheduled cue is not a strap-side alarm.
enum RunningCompletionCues {
    static let interval: TimeInterval = 10
    static let duration: TimeInterval = 180
    static let owner = "zone-run-complete"
    static func dates(from now: Date) -> [Date] {
        guard now.timeIntervalSince1970.isFinite else { return [] }
        return (0..<18).map { now.addingTimeInterval(Double($0) * interval) }
    }
}
