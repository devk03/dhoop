import Foundation

/// An app countdown, separate from wake-alarm definitions and WHOOP alarm slots.
struct DhoopTimerSession: Codable, Equatable {
    enum Phase: String, Codable { case idle, running, paused, completed, cancelled }
    var version = 1
    private(set) var phase: Phase = .idle
    private(set) var duration = 600
    private(set) var remaining: TimeInterval = 600
    private(set) var deadline: Date?
    private(set) var deviceID: String?
    private(set) var cueID: String?
    private(set) var phoneBackup = false
    var inProgress: Bool { phase == .running || phase == .paused }
    var valid: Bool {
        version == 1 && (1...86399).contains(duration) && remaining.isFinite && remaining >= 0 && remaining <= Double(duration)
            && (deadline?.timeIntervalSince1970.isFinite ?? true)
            && (phase != .running || (deadline != nil && deviceID?.isEmpty == false && cueID != nil))
            && (phase == .running || deadline == nil)
    }
    func remaining(at now: Date) -> TimeInterval {
        phase == .running ? min(Double(duration), max(0, deadline?.timeIntervalSince(now) ?? 0))
            : phase == .paused || phase == .idle ? remaining : 0
    }
    mutating func start(seconds: Int, deviceID: String, backup: Bool, now: Date) -> Bool {
        guard !inProgress, (1...86399).contains(seconds), !deviceID.isEmpty else { return false }
        self = DhoopTimerSession(); duration = seconds; remaining = Double(seconds); self.deviceID = deviceID
        phoneBackup = backup; phase = .running; deadline = now.addingTimeInterval(remaining)
        cueID = "alarm-timer." + UUID().uuidString; return true
    }
    mutating func pause(now: Date) -> Bool {
        guard phase == .running, remaining(at: now) > 0 else { return false }
        remaining = remaining(at: now); phase = .paused; deadline = nil; cueID = nil; return true
    }
    mutating func resume(now: Date) -> Bool {
        guard phase == .paused, remaining > 0 else { return false }
        phase = .running; deadline = now.addingTimeInterval(remaining)
        cueID = "alarm-timer." + UUID().uuidString; return true
    }
    mutating func cancel() -> Bool {
        guard inProgress else { return false }; phase = .cancelled; deadline = nil; cueID = nil; return true
    }
    mutating func complete(now: Date) -> Bool {
        guard phase == .running, let deadline, now >= deadline else { return false }
        phase = .completed; self.deadline = nil; remaining = 0; return true
    }
}

struct DhoopTimerFile {
    let url: URL
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dhoop/Timers/session-v1.json")) { self.url = url }
    func load() throws -> DhoopTimerSession {
        do {
            let value = try JSONDecoder().decode(DhoopTimerSession.self, from: Data(contentsOf: url))
            guard value.valid else { throw CocoaError(.fileReadCorruptFile) }; return value
        } catch CocoaError.fileReadNoSuchFile { return DhoopTimerSession() }
    }
    func save(_ value: DhoopTimerSession) throws {
        guard value.valid else { throw CocoaError(.fileWriteInvalidFileName) }
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true; try directory.setResourceValues(resources)
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
