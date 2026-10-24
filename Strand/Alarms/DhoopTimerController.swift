import Foundation
import Combine

/// Owns a single durable countdown. Uses shared connection buzzes, never firmware alarm storage.
@MainActor
final class DhoopTimerController: ObservableObject {
    static let owner = "alarm-timer"
    static let grace: TimeInterval = 10
    @Published private(set) var session = DhoopTimerSession()
    @Published private(set) var error: String?
    @Published private(set) var phoneStatus: String?
    private let file: DhoopTimerFile
    private let clock: () -> Date
    private var loaded = false
    private var coordinator: BuzzDeliveryCoordinator?
    private var changes: AnyCancellable?
    private var tick: Task<Void, Never>?
    private var foreground = false
    private var keepAwake: (Bool) -> Void = { _ in }
    var schedulePhone: (String, Date, Bool) async -> String? = { _, _, _ in nil }
    var cancelPhone: (String) -> Void = { _ in }
    var cue: BuzzDeliveryCoordinator.Cue? { coordinator?.cues.last { $0.id == session.cueID && $0.owner == Self.owner } }
    var deliveryText: String {
        if session.phase == .paused { return "Paused" }
        if session.phase == .cancelled { return "Timer cancelled" }
        switch cue?.status {
        case .requested, .responseReceived: return "Buzz requested"
        case .acknowledged: return "WHOOP acknowledged"
        case .confirmed: return "Buzz confirmed"
        case .notFelt: return "No buzz felt"
        case .unavailable: return session.inProgress ? "WHOOP unavailable · Pause and resume to re-arm" : "WHOOP unavailable"
        case .awaitingOwner: return "Pause and resume to re-arm WHOOP"
        case .missed: return "Buzz missed"
        case .suppressed: return "Buzz skipped"
        case .rejected: return "WHOOP rejected the buzz"
        default: return session.phase == .completed ? "Timer complete · No buzz verified"
            : session.phase == .running && cue == nil ? "WHOOP buzz is not armed" : "WHOOP · Keep Dhoop open"
        }
    }
    init(file: DhoopTimerFile = DhoopTimerFile(), clock: @escaping () -> Date = Date.init) {
        self.file = file; self.clock = clock
        do { session = try file.load(); loaded = true }
        catch { self.error = "Saved timer could not be read. Your data was preserved." }
    }
    func attach(coordinator: BuzzDeliveryCoordinator, foreground: Bool, keepAwake: @escaping (Bool) -> Void) {
        self.keepAwake(false); self.keepAwake = keepAwake; self.coordinator = coordinator; self.foreground = foreground
        changes = coordinator.$cues.sink { [weak self] _ in self?.objectWillChange.send() }
        if session.phase == .running, session.remaining(at: clock()) > 0,
           coordinator.link().ready, coordinator.link().deviceId == session.deviceID,
           coordinator.claim(Self.owner) { scheduleBuzz() }
        reconcile(); scheduleBackup(requestPermission: false); startTick(); updateAwake()
    }
    func setForeground(_ active: Bool) { foreground = active; reconcile(); updateAwake() }
    @discardableResult func start(seconds: Int, backup: Bool) -> Bool {
        guard loaded, !session.inProgress, let coordinator else { return fail("Timer could not be started.") }
        let link = coordinator.link()
        guard link.ready, !link.deviceId.isEmpty else { return fail("Connect WHOOP before starting the timer.") }
        guard coordinator.claim(Self.owner) else { return fail("Another session is using WHOOP buzzes.") }
        var next = session
        guard next.start(seconds: seconds, deviceID: link.deviceId, backup: backup, now: clock()), commit(next) else {
            coordinator.release(Self.owner); return false
        }
        phoneStatus = nil; scheduleBuzz(); scheduleBackup(requestPermission: true); startTick(); updateAwake(); return true
    }
    @discardableResult func pause() -> Bool {
        reconcile(); var next = session; let old = session.cueID
        guard next.pause(now: clock()), commit(next) else { return false }
        coordinator?.release(Self.owner); if let old { cancelPhone(old) }; tick?.cancel(); phoneStatus = nil; updateAwake(); return true
    }
    @discardableResult func resume() -> Bool {
        guard loaded, session.phase == .paused else { return fail("Timer is not paused.") }
        guard let coordinator, coordinator.link().ready, coordinator.link().deviceId == session.deviceID else {
            return fail("Reconnect the same WHOOP before resuming.")
        }
        guard coordinator.claim(Self.owner) else { return fail("Another session is using WHOOP buzzes.") }
        var next = session
        guard next.resume(now: clock()), commit(next) else { coordinator.release(Self.owner); return false }
        scheduleBuzz(); scheduleBackup(requestPermission: false); startTick(); updateAwake(); return true
    }
    @discardableResult func cancel() -> Bool {
        var next = session; let old = session.cueID
        guard next.cancel(), commit(next) else { return false }
        coordinator?.release(Self.owner); if let old { cancelPhone(old) }; tick?.cancel(); phoneStatus = nil; updateAwake(); return true
    }
    func reconcile() {
        guard loaded else { return }
        coordinator?.service(now: clock())
        var next = session
        if next.complete(now: clock()), commit(next) { coordinator?.release(Self.owner); tick?.cancel() }
        updateAwake()
    }
    private func scheduleBuzz() {
        guard session.phase == .running, let due = session.deadline, due > clock(),
              let id = session.cueID, let device = session.deviceID else { return }
        coordinator?.schedule(owner: Self.owner, id: id, deviceId: device, due: due, grace: Self.grace, loops: 1, now: clock())
        if coordinator?.storageError != nil { error = "Countdown started, but the WHOOP buzz could not be saved." }
    }
    private func scheduleBackup(requestPermission: Bool) {
        guard session.phoneBackup, session.phase == .running, let id = session.cueID, let due = session.deadline else { return }
        phoneStatus = "Checking iPhone backup"
        Task { [weak self] in
            guard let self else { return }
            let result = await schedulePhone(id, due, requestPermission)
            guard session.cueID == id, session.phase == .running else { cancelPhone(id); return }
            phoneStatus = result
        }
    }
    private func startTick() {
        tick?.cancel(); guard session.phase == .running else { return }
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.reconcile(); if self.session.phase != .running { return }
            }
        }
    }
    private func updateAwake() { keepAwake(foreground && session.phase == .running && session.remaining(at: clock()) > 0) }
    private func fail(_ message: String) -> Bool { error = message; return false }
    private func commit(_ next: DhoopTimerSession) -> Bool {
        do { try file.save(next); session = next; error = nil; return true }
        catch { return fail("Timer change could not be saved. Your previous timer is unchanged.") }
    }
}
