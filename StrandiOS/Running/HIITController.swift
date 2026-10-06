import Foundation
import Combine
import UIKit

@MainActor
final class HIITController: ObservableObject {
    @Published var plan = HIITPlan()
    @Published private(set) var selectedKind: HIITWorkoutKind = .hiit
    @Published private(set) var historyRevision = 0
    @Published var cuesEnabled = true {
        didSet { if !cuesEnabled { app?.ble.buzzDelivery.cancel(owner: buzzOwner) } }
    }
    @Published private(set) var session: HIITSession?
    @Published private(set) var currentBPM: Int?
    @Published private(set) var message: String?
    private var app: AppModel?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: DispatchSourceTimer?
    private var ownsStream = false
    private var working: HIITSession?
    private var lastReceipt = 0.0
    private var anchorUptime: Double?
    private var anchorElapsed = 0.0
    private var lastTick: Double?
    private var lastSave = 0.0
    private var lastPublish = 0.0
    private var cueGeneration = UUID()
    private var cueAnchor = Date()
    private let buzzOwner = "interval-workout"
    private let directory: URL
    var hasSession: Bool { working != nil }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DhoopHIIT", isDirectory: true)
        if let data = UserDefaults.standard.data(forKey: "dhoop.hiit.plan.v1"),
           let value = try? JSONDecoder().decode(HIITPlan.self, from: data), value.isValid { plan = value }
        cuesEnabled = UserDefaults.standard.object(forKey: "dhoop.hiit.cues") as? Bool ?? true
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("workout-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            if let data = try? Data(contentsOf: directory.appendingPathComponent("active.json")),
               var restored = try? JSONDecoder().decode(HIITSession.self, from: data),
               !files.contains(where: { $0.lastPathComponent.hasSuffix("-\(restored.id.uuidString).json") }) {
                restored.pause(); working = restored; session = restored
                selectedKind = restored.kind ?? .hiit; plan = restored.plan
                message = "Interval workout restored paused. Resume when ready, or save the session."
            }
        } catch { message = "Interval storage unavailable: \(error.localizedDescription)" }
    }

    deinit {
        timer?.cancel()
        if ownsStream { let owner = app; Task { @MainActor in owner?.ble.buzzDelivery.release("interval-workout"); owner?.stopRealtimeHR() } }
    }

    func configure(app: AppModel) {
        guard self.app !== app else { return }
        pause(reason: "HIIT paused because the app source changed.")
        self.app = app; subscriptions.removeAll()
        app.live.$connected.filter { !$0 }.sink { [weak self] _ in
            self?.pause(reason: "Paused: WHOOP disconnected. Reconnect and resume; old cues were cancelled.")
        }.store(in: &subscriptions)
        app.live.readableHeartRateReceipts.sink { [weak self] _ in self?.tick() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.persist() }.store(in: &subscriptions)
    }

    func selectKind(_ kind: HIITWorkoutKind) {
        guard !hasSession, selectedKind != kind else { return }
        if let data = try? JSONEncoder().encode(plan) { UserDefaults.standard.set(data, forKey: configurationKey) }
        selectedKind = kind
        if let data = UserDefaults.standard.data(forKey: configurationKey),
           let saved = try? JSONDecoder().decode(HIITPlan.self, from: data), saved.isValid { plan = saved }
        else { plan = kind == .hiit ? HIITPlan() : HIITPlan(rounds: 4, workSeconds: 240, restSeconds: 120, warmupSeconds: 300, cooldownSeconds: 300) }
    }
    private var configurationKey: String { selectedKind == .hiit ? "dhoop.hiit.plan.v1" : "dhoop.intervals.plan.v1" }

    func start(zones: [RunningZoneTarget], otherSessionActive: Bool) {
        if app?.activeWorkout != nil { message = "End the other active workout before starting HIIT."; return }
        guard !hasSession, !otherSessionActive, ready, app?.activeWorkout == nil,
              let app, let run = HIITSession(deviceId: app.repo.deviceId, plan: plan, zones: zones, kind: selectedKind) else { return }
        guard app.ble.buzzDelivery.claim(buzzOwner) else { message = "Finish or pause the other WHOOP cue session first."; return }
        working = run; session = run; lastReceipt = run.startedAt.timeIntervalSince1970
        if let data = try? JSONEncoder().encode(plan) { UserDefaults.standard.set(data, forKey: configurationKey) }
        UserDefaults.standard.set(cuesEnabled, forKey: "dhoop.hiit.cues")
        acquire(); cue(run.interval); persist()
    }
    func resume() {
        guard ready, app?.activeWorkout == nil, var run = working, run.state == .paused, run.deviceId == app?.repo.deviceId else { return }
        guard app?.ble.buzzDelivery.claim(buzzOwner) == true else { message = "Another WHOOP cue session is active."; return }
        run.resume(); working = run; session = run; lastReceipt = Date().timeIntervalSince1970
        acquire(); cue(run.interval); persist()
    }
    func pause(reason: String = "Paused. Resume when ready.") {
        guard var run = working, run.state == .running else { return }
        run.pause(); working = run; session = run; currentBPM = nil
        release(); message = reason; persist()
    }
    func save() {
        guard var run = working else { return }
        run.pause(); working = run; session = run; currentBPM = nil
        release(); persist()
        run.finish()
        do {
            let cleanupError = try HIITWorkoutFiles(directory: directory).save(run)
            historyRevision += 1
            working = nil; session = nil; currentBPM = nil
            message = cleanupError.map { "\(selectedKind.title) saved. Draft cleanup could not finish: \($0)" }
                ?? "\(selectedKind.title) saved on this phone."
        } catch { message = "Could not save workout: \(error.localizedDescription). Your session remains open." }
    }

    func deleteWorkout(at url: URL, id: UUID) throws {
        guard working?.id != id else { throw CocoaError(.fileWriteFileExists) }
        try HIITWorkoutFiles(directory: directory).deleteWorkout(at: url, id: id)
        historyRevision += 1
    }

    func discard(id: UUID) {
        guard working?.id == id else { return }
        pause()
        do {
            try HIITWorkoutFiles(directory: directory).discardDraft(id: id)
            release(); working = nil; session = nil; currentBPM = nil
            message = "Workout discarded. Heart-rate history was kept."
        } catch { message = "Could not discard workout: \(error.localizedDescription). Your session remains paused." }
    }
    private var ready: Bool {
        guard let app else { return false }
        return app.live.activeIsWhoop && app.live.connected && app.live.bonded
            && app.live.connectedWhoopDeviceId == app.repo.deviceId
    }
    private func acquire() {
        guard !ownsStream, let app, let run = working else { return }
        ownsStream = true; anchorElapsed = run.elapsed
        cueGeneration = UUID(); cueAnchor = Date().addingTimeInterval(-run.elapsed)
        anchorUptime = ProcessInfo.processInfo.systemUptime; lastTick = anchorUptime
        app.startRealtimeHR()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(50)); timer.resume(); self.timer = timer
    }
    private func release() {
        app?.ble.buzzDelivery.release(buzzOwner)
        timer?.cancel(); timer = nil; anchorUptime = nil; lastTick = nil
        if ownsStream { ownsStream = false; app?.stopRealtimeHR() }
    }
    private func tick() {
        guard let app, var run = working, run.state == .running, let anchorUptime else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard app.activeWorkout == nil else { pause(reason: "Paused because another workout started."); return }
        guard ready, run.deviceId == app.repo.deviceId, app.live.worn else {
            pause(reason: "Paused: reconnect and wear the same WHOOP before resuming."); return
        }
        let elapsed = anchorElapsed + max(0, uptime - anchorUptime)
        // A gap inside a phase does not fabricate effort. A missed boundary cannot be replayed late.
        if let boundary = run.interval?.end, elapsed > Double(boundary) + 2 {
            pause(reason: "Paused: an interval cue deadline was missed. No late cues will be replayed."); return
        }
        lastTick = uptime
        let changed = run.advance(to: elapsed)
        let now = Date().timeIntervalSince1970
        let evidence = app.live.heartRateEvidence
        if evidence.sourceDeviceId == run.deviceId {
            for sample in evidence.samples where sample.receivedAt > lastReceipt {
                lastReceipt = sample.receivedAt
                run.observe(RunningHeartRateSample(deviceId: run.deviceId, bpm: sample.bpm, receivedAt: sample.receivedAt),
                    elapsed: elapsed - (now - sample.receivedAt), now: now)
            }
        } else { run.breakContinuity() }
        if let latest = run.points.last, now >= latest.receivedAt, now - latest.receivedAt <= RunningZoneSession.maximumGap {
            if currentBPM != latest.bpm { currentBPM = latest.bpm }
        } else { if currentBPM != nil { currentBPM = nil }; run.breakContinuity() }
        working = run
        if changed { cue(run.interval) }
        if uptime - lastPublish >= 1 || changed { session = run; lastPublish = uptime }
        if run.state == .completed {
            release(); currentBPM = nil; session = run
            message = "Intervals complete. Save your workout to review effort."; persist()
        } else if uptime - lastSave >= 5 { persist(); lastSave = uptime }
    }
    private func cue(_ interval: HIITInterval?) {
        guard cuesEnabled else { message = "Interval vibration cues are off."; return }
        guard let app, ready, app.live.encryptedBond, app.live.worn, HapticPrefs.enabled(HapticPrefs.workout) else {
            message = "Vibration unavailable. Check your connection and workout haptics setting."; return
        }
        // Existing reversible pattern; loop count controls length, not distinct individual pulses.
        let loops: UInt8 = interval == nil ? 3 : interval?.kind == .work ? 1 : 2
        let index = interval?.index ?? working?.plan.intervals.count ?? 0
        let due = interval.map { cueAnchor.addingTimeInterval(Double($0.start)) } ?? Date()
        app.requestBuzz(owner: buzzOwner, id: "\(cueGeneration)|\(index)", loops: loops,
            due: due < Date().addingTimeInterval(-2) ? Date() : due, gate: HapticPrefs.workout)
        if let run = working, let current = run.interval {
            let next = run.plan.intervals.first { $0.index == current.index + 1 }
            app.requestBuzz(owner: buzzOwner, id: "\(cueGeneration)|\(current.index + 1)",
                loops: next == nil ? 3 : next?.kind == .work ? 1 : 2,
                due: cueAnchor.addingTimeInterval(Double(current.end)), gate: HapticPrefs.workout)
        }
        message = app.ble.buzzDelivery.storageError ?? "\(interval?.label ?? "Complete") · See WHOOP alert delivery for the cue result"
    }
    private func persist() {
        guard let working else { return }
        do { try JSONEncoder().encode(working).write(to: directory.appendingPathComponent("active.json"), options: .atomic) }
        catch { message = "Workout save failed: \(error.localizedDescription)" }
    }
}
