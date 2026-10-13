import Foundation

/// Bounds recovery traffic; never supplies iOS background runtime or changes buzz expiry.
struct RemoteBuzzInboxPolicy {
    enum Trigger: String { case foreground, foregroundTimer, bluetooth, reconnect, manual }
    private(set) var lastAttempt: Date?
    private(set) var failures = 0
    private(set) var emptyChecks = 0
    var delay: TimeInterval {
        failures > 0 ? min(300, 15 * pow(2, Double(min(failures, 5))))
            : emptyChecks > 0 ? 30 : 15
    }
    mutating func begin(_ trigger: Trigger, now: Date) -> Bool {
        let urgent = trigger == .foreground || trigger == .reconnect || trigger == .manual
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < (urgent ? 5 : delay) { return false }
        lastAttempt = now
        return true
    }
    mutating func finish(success: Bool, commandCount: Int) {
        if !success { failures = min(5, failures + 1); return }
        failures = 0
        emptyChecks = commandCount > 0 ? 0 : min(2, emptyChecks + 1)
    }
}
