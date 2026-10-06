import Foundation

/// A wall-clock timer independent of cardio, live HR, and physiological storage.
struct MeditationSession: Codable, Equatable {
    static let duration: TimeInterval = 15 * 60
    static let alertGrace: TimeInterval = 10

    enum Phase: String, Codable { case idle, running, paused, completed, cancelled }
    enum CompletionAlert: String, Codable {
        // A request is not proof that the strap physically vibrated.
        case buzzRequested, strapUnavailable, missedWhileAway
    }

    private(set) var phase: Phase = .idle
    private(set) var id = UUID()
    private(set) var deviceId: String?
    private(set) var deadline: Date?
    private(set) var pausedRemaining: TimeInterval = duration
    private(set) var notificationId: String?
    private(set) var completedAt: Date?
    private(set) var completionAlert: CompletionAlert?

    var isInProgress: Bool { phase == .running || phase == .paused }

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .running: return min(Self.duration, max(0, deadline?.timeIntervalSince(now) ?? 0))
        case .paused: return pausedRemaining
        case .idle: return Self.duration
        case .completed, .cancelled: return 0
        }
    }

    @discardableResult
    mutating func start(at now: Date, deviceId: String?) -> Bool {
        guard !isInProgress else { return false }
        self = MeditationSession()
        self.deviceId = deviceId
        phase = .running
        deadline = now.addingTimeInterval(Self.duration)
        notificationId = "meditation.\(UUID().uuidString)"
        return true
    }

    @discardableResult
    mutating func pause(at now: Date) -> Bool {
        guard phase == .running, remaining(at: now) > 0 else { return false }
        pausedRemaining = remaining(at: now)
        phase = .paused
        deadline = nil
        notificationId = nil
        return true
    }

    @discardableResult
    mutating func resume(at now: Date) -> Bool {
        guard phase == .paused else { return false }
        phase = .running
        deadline = now.addingTimeInterval(pausedRemaining)
        notificationId = "meditation.\(UUID().uuidString)"
        return true
    }

    @discardableResult
    mutating func cancel() -> Bool {
        guard isInProgress else { return false }
        phase = .cancelled
        deadline = nil
        notificationId = nil
        return true
    }

    /// Returns a disposition once per session. Persist it before attempting the external effect.
    mutating func completeIfDue(at now: Date, foreground: Bool, strapReady: Bool) -> CompletionAlert? {
        guard phase == .running, let deadline, now >= deadline else { return nil }
        let alert: CompletionAlert
        if !foreground || now.timeIntervalSince(deadline) > Self.alertGrace {
            alert = .missedWhileAway
        } else if strapReady {
            alert = .buzzRequested
        } else {
            alert = .strapUnavailable
        }
        phase = .completed
        completedAt = deadline
        completionAlert = alert
        self.deadline = nil
        notificationId = nil
        return alert
    }
}
