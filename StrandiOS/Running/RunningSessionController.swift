import Foundation
import Combine
import UIKit

/// Owns an explicitly started run across tab changes; Today never subscribes to this object.
@MainActor
final class RunningSessionController: ObservableObject {
    let hiit = HIITController()
    @Published private(set) var session: RunningZoneSession?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var currentBPM: Int?
    @Published private(set) var zones: [RunningZoneTarget] = []
    @Published private(set) var baselineDescription = "Reading dated resting heart rate…"
    @Published private(set) var statusMessage: String?
    @Published private(set) var buzzTestMessage: String?
    @Published private(set) var summaries: [RunningSessionSummary] = []
    @Published private(set) var isConnected = false
    @Published private(set) var strapAlertsReady = false
    @Published var selectedZone: Int = 2
    @Published var targetMinutes: Int = 20
    @Published var useManualTarget = false
    @Published var manualLowerBPM: Int = 120
    @Published var manualUpperBPM: Int = 140
    @Published var alertsEnabled: Bool = true {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alerts) }
    }

    private enum Keys {
        static let draft = "dhoop.running.activeDraft.v1"
        static let summaries = "dhoop.running.summaries.v1"
        static let zone = "dhoop.running.zone"
        static let minutes = "dhoop.running.goalMinutes"
        static let manual = "dhoop.running.manualTarget"
        static let lower = "dhoop.running.lowerBPM"
        static let upper = "dhoop.running.upperBPM"
        static let alerts = "dhoop.running.zoneAlerts"
    }
    private struct Draft: Codable {
        var session: RunningZoneSession
        let elapsedSeconds: TimeInterval
    }
    private let defaults: UserDefaults
    private var app: AppModel?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: DispatchSourceTimer?
    private var ownsStream = false
    private var processingScheduled = false
    private var lastConsumedAt: TimeInterval?
    private var elapsedBeforeResume: TimeInterval = 0
    private var runningSinceUptime: TimeInterval?
    private var lastPersistUptime: TimeInterval = 0
    private var baselineGeneration = 0
    private var configuredDeviceId: String?
    private var workingSession: RunningZoneSession?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedZone = max(1, min(5, defaults.object(forKey: Keys.zone) as? Int ?? 2))
        targetMinutes = max(1, min(180, defaults.object(forKey: Keys.minutes) as? Int ?? 20))
        useManualTarget = defaults.object(forKey: Keys.manual) as? Bool ?? false
        manualLowerBPM = max(30, min(219, defaults.object(forKey: Keys.lower) as? Int ?? 120))
        manualUpperBPM = max(manualLowerBPM + 1, min(220, defaults.object(forKey: Keys.upper) as? Int ?? 140))
        alertsEnabled = defaults.object(forKey: Keys.alerts) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.summaries),
           let saved = try? JSONDecoder().decode([RunningSessionSummary].self, from: data) { summaries = saved }
        if let data = defaults.data(forKey: Keys.draft),
           var draft = try? JSONDecoder().decode(Draft.self, from: data) {
            // A process relaunch proves no intervening observations. It never resumes streaming.
            draft.session.pause()
            workingSession = draft.session; session = draft.session
            elapsedBeforeResume = draft.elapsedSeconds; elapsedSeconds = draft.elapsedSeconds
            statusMessage = draft.session.phase == .completed
                ? "Completed goal restored. End and save your run."
                : "Saved session restored paused. Resume when you are ready."
        }
    }

    deinit {
        timer?.cancel()
        if ownsStream {
            let owner = app
            Task { @MainActor in owner?.stopRealtimeHR() }
        }
    }

    var isRunning: Bool { session?.phase == .running }
    var hasSession: Bool { session != nil || hiit.hasSession }
    var chosenTarget: RunningZoneTarget? {
        if useManualTarget || zones.isEmpty {
            let target = RunningZoneTarget(name: "BPM target", lowerBPM: manualLowerBPM,
                upperBPM: manualUpperBPM + 1, method: "Manual BPM target")
            return target.isValid ? target : nil
        }
        return zones.first { $0.name == "Zone \(selectedZone)" }
    }
    var workoutHapticsEnabled: Bool { HapticPrefs.enabled(HapticPrefs.workout) }

    /// Calling this from an appearance only attaches once; hidden tabs retain the same controller.
    func configure(app: AppModel) {
        hiit.configure(app: app)
        if self.app !== app {
            pause(reason: "Session paused because the app source changed.")
            self.app = app
            subscriptions.removeAll()
            app.live.objectWillChange.sink { [weak self] _ in
                // Published properties send before assignment; coalesce and read after the mutation.
                self?.scheduleProcess()
            }.store(in: &subscriptions)
            app.live.readableHeartRateReceipts.sink { [weak self] _ in
                self?.processIncoming()
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.persistBackgroundTransition() }
                }.store(in: &subscriptions)
            app.repo.objectWillChange.sink { [weak self] _ in self?.scheduleProcess() }.store(in: &subscriptions)
        }
        updateConnection()
        if configuredDeviceId != app.repo.deviceId {
            configuredDeviceId = app.repo.deviceId
            Task { [weak self] in await self?.refreshBaseline() }
        }
    }

    func refreshBaseline() async {
        guard let app else { return }
        baselineGeneration += 1
        let generation = baselineGeneration
        let id = app.repo.deviceId
        let custom = app.profile.customHRZoneLowerBounds
        let maximum = app.profile.effortHRmax
        let manualMax = app.profile.hrMaxOverride > 0
        if let custom {
            zones = RunningZoneTarget.customZones(lowerBounds: custom)
            baselineDescription = "Configured custom BPM zones. They may differ from WHOOP's current HRR zones."
            return
        }
        let day = Repository.localDayKey(Date())
        let rows = await app.repo.resolvedSeries(key: "rhr", source: Repository.whoopSource, from: "0000-01-01", to: day)
        guard !Task.isCancelled, generation == baselineGeneration, id == app.repo.deviceId else { return }
        let resting = rows.points.filter { $0.day <= day && $0.value.isFinite && $0.value >= 30 }
            .max { $0.day < $1.day }
        if let maximum, let resting, maximum > resting.value {
            let date = HeartDashboardProjection.date(resting.day)?.formatted(date: .abbreviated, time: .omitted) ?? resting.day
            let source = resting.source == Repository.appleHealthSource ? "Apple Health" : resting.source.hasSuffix("-noop") ? "on-device estimate" : "WHOOP record"
            let detail = "Local HRR estimate · resting HR \(Int(resting.value.rounded())) bpm (\(date), \(source)) · maximum HR \(Int(maximum.rounded())) bpm (\(manualMax ? "manual" : "age estimate"))"
            zones = RunningZoneTarget.reserveZones(maxHR: maximum, restingHR: resting.value, method: detail)
            baselineDescription = detail + ". WHOOP's own personalized baseline may differ."
        } else {
            zones = []
            baselineDescription = "A dated resting HR and maximum HR are needed to estimate HRR zones. Choose an explicit BPM target below."
        }
    }

    func testBuzz() {
        updateConnection()
        guard strapAlertsReady, workoutHapticsEnabled, let app else {
            buzzTestMessage = "Test unavailable. Connect and wear WHOOP, and enable workout haptics."
            statusMessage = buzzTestMessage
            return
        }
        app.buzz(loops: 1, gate: HapticPrefs.workout)
        buzzTestMessage = "WHOOP buzz requested at \(Date().formatted(date: .omitted, time: .shortened))."
        statusMessage = buzzTestMessage
    }

    func start() {
        if app?.activeWorkout != nil { statusMessage = "End the other active workout before starting a zone run."; return }
        updateConnection()
        guard !hasSession, isConnected, let app, let target = chosenTarget,
              let run = RunningZoneSession(deviceId: app.repo.deviceId, target: target, goalSeconds: Double(targetMinutes * 60)) else { return }
        saveConfiguration()
        workingSession = run; session = run
        lastConsumedAt = run.startedAt.timeIntervalSince1970
        elapsedBeforeResume = 0; elapsedSeconds = 0; currentBPM = nil
        statusMessage = "Waiting for fresh readable WHOOP heart rate."
        acquireStream()
        persistDraft()
    }

    func resume() {
        updateConnection()
        guard isConnected, let app, app.activeWorkout == nil, !hiit.hasSession, var run = workingSession, run.phase == .paused,
              run.deviceId == app.repo.deviceId else {
            if workingSession != nil { statusMessage = "Connect the WHOOP used for this session before resuming." }
            return
        }
        run.resume(); workingSession = run; session = run
        lastConsumedAt = Date().timeIntervalSince1970
        statusMessage = "Waiting for fresh readable WHOOP heart rate."
        acquireStream(); persistDraft()
    }

    func pause(reason: String? = nil) {
        guard var run = workingSession, run.phase == .running else { releaseStream(); return }
        updateElapsed()
        elapsedBeforeResume = elapsedSeconds; runningSinceUptime = nil
        run.pause(); workingSession = run; session = run; currentBPM = nil
        statusMessage = reason ?? "Paused. Unobserved time does not count."
        releaseStream(); persistDraft()
    }

    func endAndSave() {
        guard var run = workingSession else { return }
        updateElapsed(); releaseStream()
        run.end()
        let summary = RunningSessionSummary(id: run.id, deviceId: run.deviceId, target: run.target,
            startedAt: run.startedAt, endedAt: Date(), elapsedSeconds: elapsedSeconds,
            inZoneSeconds: run.inZoneSeconds, goalSeconds: run.goalSeconds, observedSeconds: run.observedSeconds,
            readableSamples: run.readableSamples, averageBPM: run.averageBPM, maximumBPM: run.maximumBPM, goalMet: run.inZoneSeconds >= run.goalSeconds)
        summaries.insert(summary, at: 0)
        if let data = try? JSONEncoder().encode(summaries) { defaults.set(data, forKey: Keys.summaries) }
        // This clears only this feature's preferences draft, never a database or collected readings.
        defaults.removeObject(forKey: Keys.draft)
        workingSession = nil; session = nil; currentBPM = nil; runningSinceUptime = nil
        elapsedBeforeResume = 0; elapsedSeconds = 0
        statusMessage = summary.goalMet ? "Goal complete. Run saved on this phone." : "Run saved on this phone."
    }

    private func acquireStream() {
        guard !ownsStream, let app else { return }
        ownsStream = true; runningSinceUptime = ProcessInfo.processInfo.systemUptime
        app.startRealtimeHR()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.processAndPublish() } }
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100)); timer.resume()
        self.timer = timer
    }

    private func releaseStream() {
        timer?.cancel(); timer = nil
        guard ownsStream else { return }
        ownsStream = false; app?.stopRealtimeHR()
    }

    private func scheduleProcess() {
        guard !processingScheduled else { return }
        processingScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.processingScheduled = false
            self.processIncoming()
        }
    }

    private func updateConnection() {
        guard let app else { if isConnected { isConnected = false }; return }
        let live = app.live
        let valid = live.activeIsWhoop && live.connected && live.bonded && live.connectedWhoopDeviceId == app.repo.deviceId
        if isConnected != valid { isConnected = valid }
        let alertsReady = valid && live.encryptedBond && live.worn
        if strapAlertsReady != alertsReady { strapAlertsReady = alertsReady }
    }

    private func processIncoming() {
        updateConnection()
        guard let app, var run = workingSession, run.phase == .running else { return }
        guard app.activeWorkout == nil else { pause(reason: "Paused because another workout started."); return }
        guard isConnected, app.repo.deviceId == run.deviceId else {
            pause(reason: "Paused: WHOOP disconnected or the selected device changed.")
            if configuredDeviceId != app.repo.deviceId {
                configuredDeviceId = app.repo.deviceId
                Task { [weak self] in await self?.refreshBaseline() }
            }
            return
        }
        let live = app.live
        let evidence = live.heartRateEvidence
        if let source = evidence.sourceDeviceId, source != run.deviceId {
            pause(reason: "Paused: readable heart rate came from a different device.")
            return
        }
        // The receipt notification precedes the display property's assignment. The decoded receipt
        // itself is the readable evidence, including a first packet and unchanged BPM.
        guard evidence.sourceDeviceId == run.deviceId, live.worn else {
            run.breakContinuity(); workingSession = run
            return
        }
        let now = Date().timeIntervalSince1970
        let canBuzz = live.encryptedBond && live.worn && live.activeIsWhoop && live.connectedWhoopDeviceId == run.deviceId
        for sample in evidence.samples where sample.receivedAt > (lastConsumedAt ?? run.startedAt.timeIntervalSince1970) {
            lastConsumedAt = sample.receivedAt
            let observation = run.observe(RunningHeartRateSample(deviceId: run.deviceId, bpm: sample.bpm, receivedAt: sample.receivedAt),
                now: now, connected: isConnected && live.worn,
                alertsEnabled: alertsEnabled && HapticPrefs.enabled(HapticPrefs.workout), mayBuzz: canBuzz)
            if let alert = observation.alert {
                app.buzz(loops: 1, gate: HapticPrefs.workout)
                statusMessage = alert == .below ? "Below target · WHOOP buzz requested" : "Above target · WHOOP buzz requested"
            }
            if run.phase == .completed { break }
        }
        workingSession = run
        if ProcessInfo.processInfo.systemUptime - lastPersistUptime >= 5 {
            lastPersistUptime = ProcessInfo.processInfo.systemUptime
            updateElapsed(); persistDraft()
        }
        if run.phase == .completed {
            updateElapsed(); elapsedBeforeResume = elapsedSeconds; runningSinceUptime = nil
            releaseStream(); session = run
            currentBPM = nil; statusMessage = "In-zone goal complete. End and save your run."
            persistDraft()
        }
    }

    private func processAndPublish() {
        processIncoming()
        guard var run = workingSession, run.phase == .running else { return }
        let now = Date().timeIntervalSince1970
        let fresh = run.lastAcceptedAt.map { now >= $0 && now - $0 <= RunningZoneSession.maximumGap } ?? false
        if !fresh { run.breakContinuity(); workingSession = run }
        let bpm = fresh ? run.latestBPM : nil
        if currentBPM != bpm { currentBPM = bpm }
        // The Running view updates at most once a second. The Today view has no such subscription.
        if session != run { session = run }
        updateElapsed()
        if elapsedSeconds >= 24 * 60 * 60 {
            pause(reason: "Run paused at the 24-hour activity limit. End and save this session.")
            return
        }
        let displayStatus: String
        if let bpm {
            displayStatus = run.target.contains(bpm) ? "In target zone" : bpm < run.target.lowerBPM ? "Below target zone" : "Above target zone"
        } else { displayStatus = "Waiting for fresh readable WHOOP heart rate." }
        if statusMessage != displayStatus { statusMessage = displayStatus }
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastPersistUptime >= 5 { lastPersistUptime = uptime; persistDraft() }
    }

    private func updateElapsed() {
        guard let since = runningSinceUptime else { return }
        let elapsed = elapsedBeforeResume + max(0, ProcessInfo.processInfo.systemUptime - since)
        // No subsecond clock-driven UI updates.
        if Int(elapsedSeconds) != Int(elapsed) { elapsedSeconds = elapsed }
    }

    private func persistBackgroundTransition() {
        // An explicitly started run keeps receiving Bluetooth observations in the background.
        // Persist before suspension; unavailable intervals still never count toward the zone goal.
        updateElapsed()
        persistDraft()
    }

    private func persistDraft() {
        guard let workingSession else { return }
        if let data = try? JSONEncoder().encode(Draft(session: workingSession, elapsedSeconds: elapsedSeconds)) {
            defaults.set(data, forKey: Keys.draft)
        }
    }

    private func saveConfiguration() {
        defaults.set(selectedZone, forKey: Keys.zone); defaults.set(targetMinutes, forKey: Keys.minutes)
        defaults.set(useManualTarget, forKey: Keys.manual); defaults.set(manualLowerBPM, forKey: Keys.lower)
        defaults.set(manualUpperBPM, forKey: Keys.upper)
    }
}
