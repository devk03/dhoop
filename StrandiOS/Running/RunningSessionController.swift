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
    @Published private(set) var isLoadingBaseline = true
    @Published private(set) var baselineDescription = "Reading dated resting heart rate…"
    @Published private(set) var statusMessage: String?
    @Published private(set) var buzzTestMessage: String?
    @Published private(set) var summaries: [RunningSessionSummary] = []
    @Published private(set) var isSaving = false
    @Published private(set) var completionBuzzActive = false
    @Published private(set) var isConnected = false
    @Published private(set) var strapAlertsReady = false
    @Published var selectedZone: Int = 2 {
        didSet { defaults.set(selectedZone, forKey: Keys.zone) }
    }
    @Published var targetMinutes: Int = 20 {
        didSet { defaults.set(targetMinutes, forKey: Keys.minutes) }
    }
    @Published var useManualTarget = true {
        didSet { defaults.set(useManualTarget, forKey: Keys.manual) }
    }
    @Published var manualLowerBPM: Int = 120 {
        didSet { defaults.set(manualLowerBPM, forKey: Keys.lower) }
    }
    @Published var manualUpperBPM: Int = 140 {
        didSet { defaults.set(manualUpperBPM, forKey: Keys.upper) }
    }
    @Published var completionAlertsEnabled: Bool = true {
        didSet {
            defaults.set(completionAlertsEnabled, forKey: Keys.completionAlerts)
            if !completionAlertsEnabled { stopCompletionBuzz() }
        }
    }

    private enum Keys {
        static let draft = RunningSessionStorage.draftKey
        static let summaries = RunningSessionStorage.summariesKey
        static let zone = "dhoop.running.zone"
        static let minutes = "dhoop.running.goalMinutes"
        static let manual = "dhoop.running.manualTarget"
        static let lower = "dhoop.running.lowerBPM"
        static let upper = "dhoop.running.upperBPM"
        static let completionAlerts = "dhoop.running.completionAlerts.v1"
    }
    private typealias Draft = RunningSessionStorage.Draft
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
    private var recoveringSummaries = false
    private var completionCleanup: Task<Void, Never>?
    private var completionOwner: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedZone = max(1, min(5, defaults.object(forKey: Keys.zone) as? Int ?? 2))
        targetMinutes = max(1, min(180, defaults.object(forKey: Keys.minutes) as? Int ?? 20))
        // The previous default was inferred HRR zones. The wearer now prefers a personal BPM
        // range; migrate that old unset/default choice once while retaining later explicit choices.
        let targetPreferenceVersionKey = "dhoop.running.targetPreferenceVersion"
        if defaults.integer(forKey: targetPreferenceVersionKey) < 1 {
            useManualTarget = true
            defaults.set(true, forKey: Keys.manual)
            defaults.set(1, forKey: targetPreferenceVersionKey)
        } else {
            useManualTarget = defaults.object(forKey: Keys.manual) as? Bool ?? true
        }
        manualLowerBPM = max(30, min(220, defaults.object(forKey: Keys.lower) as? Int ?? 120))
        manualUpperBPM = max(manualLowerBPM, min(220, defaults.object(forKey: Keys.upper) as? Int ?? 140))
        completionAlertsEnabled = defaults.object(forKey: Keys.completionAlerts) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.summaries),
           let saved = try? JSONDecoder().decode([RunningSessionSummary].self, from: data) { summaries = saved }
        if let data = defaults.data(forKey: Keys.draft),
           var draft = try? JSONDecoder().decode(Draft.self, from: data),
           !summaries.contains(where: { $0.id == draft.session.id }) {
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
        completionCleanup?.cancel()
        let completionApp = app, completionID = completionOwner
        Task { @MainActor in if let completionID { completionApp?.ble.buzzDelivery.release(completionID) } }
        if ownsStream {
            let owner = app
            Task { @MainActor in owner?.ble.buzzDelivery.release("zone-run"); owner?.stopRealtimeHR() }
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
    var startBlockedReason: String? {
        if hasSession || app?.activeWorkout != nil { return "Finish the active workout before starting another." }
        if !isConnected { return "Connect and pair your WHOOP to start." }
        if isLoadingBaseline && !useManualTarget { return "Reading your target heart-rate range…" }
        if chosenTarget == nil { return "Choose a valid target heart-rate range." }
        return nil
    }
    var canStart: Bool { startBlockedReason == nil }

    var workoutHapticsEnabled: Bool { HapticPrefs.enabled(HapticPrefs.workout) }

    /// Calling this from an appearance only attaches once; hidden tabs retain the same controller.
    func configure(app: AppModel) {
        hiit.configure(app: app)
        if self.app !== app {
            pause(reason: "Session paused because the app source changed.")
            self.app = app
            recoverSummaries()
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

    private func recoverSummaries() {
        guard !recoveringSummaries, !isSaving else { return }
        recoveringSummaries = true
        let preferences = defaults
        Task { @MainActor in
            defer { recoveringSummaries = false }
            do {
                let rows = try await Task.detached(priority: .utility) {
                    try RunningSessionStorage(defaults: preferences).loadSummaries()
                }.value
                guard !isSaving else { return }
                summaries = rows
                if let id = workingSession?.id, rows.contains(where: { $0.id == id }) {
                    workingSession = nil; session = nil; currentBPM = nil
                    elapsedBeforeResume = 0; elapsedSeconds = 0; runningSinceUptime = nil
                    statusMessage = "Saved workout recovered. Its old draft was not resumed."
                }
            } catch { statusMessage = "Workout history could not be read. Existing records were preserved." }
        }
    }

    func refreshBaseline() async {
        guard let app else { return }
        baselineGeneration += 1
        let generation = baselineGeneration
        isLoadingBaseline = true
        defer { if generation == baselineGeneration { isLoadingBaseline = false } }
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
        app.requestBuzz(owner: "manual-test", loops: 1, gate: HapticPrefs.workout)
        buzzTestMessage = "WHOOP buzz requested at \(Date().formatted(date: .omitted, time: .shortened))."
        statusMessage = buzzTestMessage
    }

    func start() {
        updateConnection()
        if let reason = startBlockedReason { statusMessage = reason; return }
        guard let app, let target = chosenTarget,
              let run = RunningZoneSession(deviceId: app.repo.deviceId, target: target, goalSeconds: Double(targetMinutes * 60)) else { return }
        guard app.ble.buzzDelivery.claim("zone-run") else { statusMessage = "Finish or pause the other WHOOP cue session first."; return }
        saveConfiguration()
        workingSession = run; session = run
        lastConsumedAt = run.startedAt.timeIntervalSince1970
        elapsedBeforeResume = 0; elapsedSeconds = 0; currentBPM = nil
        statusMessage = "Waiting for fresh readable WHOOP heart rate."
        acquireStream()
        persistDraft()
    }

    func resume() {
        guard !isSaving else { return }
        updateConnection()
        guard isConnected, let app, app.activeWorkout == nil, !hiit.hasSession, var run = workingSession, run.phase == .paused,
              run.deviceId == app.repo.deviceId else {
            if workingSession != nil { statusMessage = "Connect the WHOOP used for this session before resuming." }
            return
        }
        guard app.ble.buzzDelivery.claim("zone-run") else { statusMessage = "Another WHOOP cue session is active."; return }
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
        guard !isSaving, var run = workingSession else { return }
        stopCompletionBuzz()
        updateElapsed(); releaseStream()
        run.pause(); workingSession = run; session = run; currentBPM = nil
        elapsedBeforeResume = elapsedSeconds; runningSinceUptime = nil
        run.end()
        let summary = RunningSessionSummary(id: run.id, deviceId: run.deviceId, target: run.target,
            startedAt: run.startedAt, endedAt: run.completedAt ?? (run.phase == .completed ? run.lastAcceptedAt.map { Date(timeIntervalSince1970: $0) } : nil) ?? Date(), elapsedSeconds: elapsedSeconds,
            inZoneSeconds: run.inZoneSeconds, goalSeconds: run.goalSeconds, observedSeconds: run.observedSeconds,
            readableSamples: run.readableSamples, averageBPM: run.averageBPM, maximumBPM: run.maximumBPM, goalMet: run.inZoneSeconds >= run.goalSeconds)
        persistDraft()
        isSaving = true; statusMessage = "Saving workout…"
        let preferences = defaults
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let saved = try await Task.detached(priority: .userInitiated) {
                    try RunningSessionStorage(defaults: preferences).saveSummary(summary)
                }.value
                guard workingSession?.id == summary.id else { return }
                summaries = saved
                let cleanupWarning: String?
                do { try RunningSessionStorage(defaults: preferences).discardDraft(id: summary.id); cleanupWarning = nil }
                catch { cleanupWarning = "Run saved. Draft cleanup was not confirmed; the archived run will not resume." }
                workingSession = nil; session = nil; currentBPM = nil; runningSinceUptime = nil
                elapsedBeforeResume = 0; elapsedSeconds = 0
                statusMessage = cleanupWarning ?? (summary.goalMet ? "Goal complete. Run saved on this phone." : "Run saved on this phone.")
            } catch { statusMessage = "Could not finish saving: \(error.localizedDescription). Your session remains paused." }
        }
    }

    func deleteSummary(id: UUID) throws {
        guard !isSaving, workingSession?.id != id else { throw CocoaError(.fileWriteFileExists) }
        summaries = try RunningSessionStorage(defaults: defaults).deleteSummary(id: id)
    }

    func discard(id: UUID) {
        guard !isSaving, workingSession?.id == id else { return }
        stopCompletionBuzz()
        pause()
        do {
            try RunningSessionStorage(defaults: defaults).discardDraft(id: id)
            releaseStream()
            workingSession = nil; session = nil; currentBPM = nil; runningSinceUptime = nil
            elapsedBeforeResume = 0; elapsedSeconds = 0
            statusMessage = "Workout discarded. Heart-rate history was kept."
        } catch { statusMessage = "Could not discard workout: \(error.localizedDescription). Your session remains paused." }
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
        app?.ble.buzzDelivery.release("zone-run")
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
        if completionBuzzActive, !strapAlertsReady || workingSession?.deviceId != app?.repo.deviceId {
            stopCompletionBuzz()
            statusMessage = "Completion cues stopped because WHOOP is unavailable. No reconnect replay."
        }
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
                alertsEnabled: false, mayBuzz: canBuzz)
            if let alert = observation.alert {
                app.requestBuzz(owner: "zone-run", id: "zone|\(run.id)|\(sample.receivedAt)",
                    loops: 1, gate: HapticPrefs.workout, sampleAt: Date(timeIntervalSince1970: sample.receivedAt))
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
            currentBPM = nil; statusMessage = "Goal reached. Save your run."
            persistDraft()
            beginCompletionBuzz(run)
        }
    }

    private func beginCompletionBuzz(_ run: RunningZoneSession) {
        stopCompletionBuzz()
        let owner = RunningCompletionCues.owner + "|" + UUID().uuidString
        guard completionAlertsEnabled, workoutHapticsEnabled, strapAlertsReady, let app,
              app.repo.deviceId == run.deviceId, app.ble.buzzDelivery.claim(owner) else {
            statusMessage = "Goal reached. Completion buzzes are off or WHOOP is unavailable. Save your workout."
            return
        }
        completionOwner = owner; completionBuzzActive = true
        let now = Date()
        for (index, due) in RunningCompletionCues.dates(from: now).enumerated() {
            app.requestBuzz(owner: owner, id: "\(owner)|\(run.id)|\(index)",
                loops: 1, due: due, grace: 2, gate: HapticPrefs.workout)
        }
        statusMessage = "Goal reached. Completion cues scheduled every ten seconds, for up to three minutes."
        completionCleanup = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
            guard self?.completionOwner == owner else { return }
            self?.stopCompletionBuzz()
        }
    }

    func stopCompletionBuzz() {
        completionCleanup?.cancel(); completionCleanup = nil
        if let owner = completionOwner {
            app?.ble.buzzDelivery.cancel(owner: owner)
            app?.ble.buzzDelivery.release(owner)
        }
        completionOwner = nil
        completionBuzzActive = false
    }

    func acknowledgeCompletion() {
        guard let run = workingSession, run.phase == .completed else { return }
        if let cue = app?.ble.buzzDelivery.cues.filter({
            $0.owner.hasPrefix(RunningCompletionCues.owner + "|")
                && $0.id.contains("|\(run.id)|") && $0.requestedAt != nil
        }).max(by: { ($0.requestedAt ?? .distantPast) < ($1.requestedAt ?? .distantPast) }) {
            app?.ble.buzzDelivery.confirm(id: cue.id)
        }
        stopCompletionBuzz()
        statusMessage = "Completion cues stopped. Save your workout when ready."
    }

    func adjustTimeGoal(minutes: Int) {
        guard !isSaving, (1...180).contains(minutes), var run = workingSession else { return }
        let wasCompleted = run.phase == .completed
        guard run.setGoal(seconds: Double(minutes * 60), now: Date()) else { return }
        stopCompletionBuzz()
        targetMinutes = minutes; workingSession = run; session = run
        defaults.set(minutes, forKey: Keys.minutes)
        if run.phase == .completed {
            updateElapsed(); elapsedBeforeResume = elapsedSeconds; runningSinceUptime = nil
            releaseStream(); currentBPM = nil
            if !wasCompleted { beginCompletionBuzz(run) }
        } else if wasCompleted { statusMessage = "Time goal increased. Resume to collect more time in range." }
        else { statusMessage = "Time goal updated. Your observed time in range was kept." }
        persistDraft()
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
