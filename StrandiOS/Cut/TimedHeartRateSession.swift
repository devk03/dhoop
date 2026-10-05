import Foundation
import Combine

/// Owns one temporary live-feed interest, independently of received samples and other HR consumers.
@MainActor
final class TimedHeartRateSession: ObservableObject {
    static let durationSeconds: TimeInterval = 60
    @Published private(set) var deviceId: String?
    @Published private(set) var deadlineUptime: TimeInterval?
    private(set) var sessionId: UUID?
    private var release: (() -> Void)?
    private var timer: Task<Void, Never>?

    var isActive: Bool { release != nil }

    @discardableResult
    func start(deviceId: String, atUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
               request: () -> Void, release: @escaping () -> Void) -> Bool {
        guard !isActive, !deviceId.isEmpty, atUptime.isFinite, atUptime >= 0 else { return false }
        let id = UUID()
        self.sessionId = id
        self.deviceId = deviceId
        self.deadlineUptime = atUptime + Self.durationSeconds
        self.release = release
        request()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.sessionId == id, let deadline = self.deadlineUptime else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now >= deadline { self.expireIfNeeded(sessionId: id, atUptime: now); return }
                do { try await Task.sleep(nanoseconds: UInt64(min(1, deadline - now) * 1_000_000_000)) }
                catch { return }
            }
        }
        return true
    }

    func remainingSeconds(atUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        guard let deadlineUptime, atUptime.isFinite else { return 0 }
        return Int(ceil(min(Self.durationSeconds, max(0, deadlineUptime - atUptime))))
    }

    func expireIfNeeded(sessionId expected: UUID? = nil,
                        atUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard expected == nil || expected == sessionId,
              let deadlineUptime, atUptime.isFinite, atUptime >= deadlineUptime else { return }
        stop()
    }

    /// A bond/history event may re-arm the existing interest, but cannot extend its lifetime.
    func rearmIfValid(deviceId: String, connected: Bool, isWhoop: Bool,
                      atUptime: TimeInterval = ProcessInfo.processInfo.systemUptime, rearm: () -> Void) {
        expireIfNeeded(atUptime: atUptime)
        guard isActive else { return }
        guard self.deviceId == deviceId, connected, isWhoop else { stop(); return }
        rearm()
    }

    func stop() {
        timer?.cancel(); timer = nil
        let release = self.release
        self.release = nil
        deadlineUptime = nil; deviceId = nil; sessionId = nil
        release?()
    }
}
