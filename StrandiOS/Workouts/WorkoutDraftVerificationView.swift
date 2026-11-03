#if DEBUG && os(iOS) && targetEnvironment(simulator)
import SwiftUI
import StrandDesign

/// Explicit simulator-only component proof. No real credentials, HTTP calls, health data, or app DB seeds.
@MainActor
private final class WorkoutDraftVerificationModel: ObservableObject {
    final class Evidence {
        var posts = 0
        var reads = 0
        var earlierPosts = 0
        var revision = 4
        var saved: WorkoutTrackerDashboard.Session?
        var library: [WorkoutTrackerDashboard.LibraryItem] = []
    }
    @Published var ready = false
    let frontend: WorkoutFrontendClient
    let drafts: WorkoutSessionDraftController
    let evidence: Evidence
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let lower = arguments.contains("--workout-ui-lower")
        let argument = arguments.first(where: { $0.hasPrefix("--workout-ui-run=") }) ?? "--workout-ui-run=default"
        let run = argument.dropFirst("--workout-ui-run=".count).filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("workout-ui-\(run)" + (lower ? "-lower" : ""))
        let commandStore = WorkoutFrontendFileStore(url: root.appendingPathComponent("commands.json"))
        let priorInstallation = (try? commandStore.load())?.installationId
        let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev",
            installationId: priorInstallation ?? UUID(uuidString: String(run)) ?? UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, credential: String(repeating: "f", count: 64))
        let counts = Evidence(); evidence = counts
        let defaults: [WorkoutTrackerDashboard.LibraryItem] = [
            .init(exerciseKey: lower ? "leg_press" : "cable_press", name: lower ? "Leg press" : "Cable press",
                  movementPattern: lower ? "squat" : "push", loadMode: "machine", unit: "lb", increment: 5, repMin: 8, repMax: 12, notes: ""),
            .init(exerciseKey: lower ? "seated_leg_curl" : "seated_cable_row", name: lower ? "Seated leg curl" : "Seated cable row",
                  movementPattern: lower ? "knee_flexion" : "pull", loadMode: "machine", unit: "lb", increment: 5, repMin: 10, repMax: 15, notes: "")]
        counts.library = (try? Data(contentsOf: root.appendingPathComponent("library.json"))).flatMap { try? JSONDecoder().decode([WorkoutTrackerDashboard.LibraryItem].self, from: $0) } ?? defaults
        let legacyID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let legacy = WorkoutFrontendIntent(operationId: legacyID, expectedLifeRevision: 1,
            command: ["action": .string("update_set"), "sessionId": .number(9), "setId": .number(90), "completed": .bool(true)])
        if arguments.contains("--workout-ui-legacy-blocker"), !FileManager.default.fileExists(atPath: commandStore.url.path) {
            var state = WorkoutFrontendState(); state.enabled = true; state.origin = config.origin; state.installationId = config.installationId
            state.operations = [.init(intent: legacy, bytes: (try? JSONEncoder().encode(legacy)) ?? Data(), origin: config.origin,
                installationId: config.installationId, createdAt: Date(), state: .uncertain, receipt: nil, attemptedAt: Date())]
            try? commandStore.save(state)
        }
        func receipt(_ intent: WorkoutFrontendIntent, state: String, revision: Int) throws -> Data {
            var result: [String: Any] = ["schemaVersion": 1, "operationId": intent.operationId.uuidString.lowercased(),
                "state": state, "lifeRevision": revision]
            if state != "not_observed" {
                result["request"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(intent))
                result["requestHash"] = String(repeating: "a", count: 64); result["receiptLifeRevision"] = revision
                if state == "committed" {
                    let sessionID: Double
                    if case .number(let id) = intent.command["sessionId"] { sessionID = id } else { sessionID = lower ? 20 : 10 }
                    result["result"] = ["mesocycleId": 1, "sessionId": sessionID, "invalidate": "workout_tracker"]
                }
            }
            return try JSONSerialization.data(withJSONObject: result)
        }
        let client = WorkoutFrontendClient(store: commandStore, send: { endpoint, data, _ in
            if endpoint == .frontendCapabilities {
                return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true,
                    "frontendStart": false, "sessionCompletion": true, "sessionBatchSave": true, "customExerciseSubstitution": true,
                    "lifeRevision": counts.revision, "actions": ["update_session", "update_set", "substitute_exercise"]])
            }
            if case .frontendReceipt(let id) = endpoint {
                if let stored = try? Data(contentsOf: root.appendingPathComponent("receipt-" + id.uuidString + ".json")) { return stored }
                if id == legacyID {
                    return try receipt(legacy, state: counts.earlierPosts == 0 ? "not_observed" : "rejected", revision: counts.revision)
                }
                if arguments.contains("--workout-ui-stale-once"), let data = try? Data(contentsOf: root.appendingPathComponent("rejected.json")),
                   let rejected = try? JSONDecoder().decode(WorkoutFrontendIntent.self, from: data), rejected.operationId == id {
                    counts.revision = 6; return try receipt(rejected, state: "rejected", revision: 6)
                }
                return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "operationId": id.uuidString.lowercased(), "state": "not_observed", "lifeRevision": counts.revision])
            }
            guard endpoint == .frontendCommand, let data else { throw WorkoutSyncTransportError.invalidResponse }
            let intent = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: data)
            if intent.operationId == legacyID { counts.earlierPosts += 1; counts.revision = 5; throw WorkoutSyncTransportError.http(409) }
            if arguments.contains("--workout-ui-offline") { throw URLError(.notConnectedToInternet) }
            counts.posts += 1
            if let stored = try? Data(contentsOf: root.appendingPathComponent("receipt-" + intent.operationId.uuidString + ".json")) {
                let prior = try JSONDecoder().decode(WorkoutFrontendReceipt.self, from: stored); try prior.validate(for: intent, prior: nil)
                return stored
            }
            if arguments.contains("--workout-ui-stale-once"), intent.expectedLifeRevision < 6 {
                try data.write(to: root.appendingPathComponent("rejected.json"), options: .atomic)
                counts.revision = 6; throw WorkoutSyncTransportError.http(409)
            }
            try await Task.sleep(nanoseconds: arguments.contains("--workout-ui-slow") ? 2_000_000_000 : 400_000_000)
            counts.revision = intent.expectedLifeRevision + 1
            if var saved = counts.saved {
                if case .array(let updates) = intent.command["sets"] {
                    for value in updates {
                        guard case .object(let fields) = value, case .number(let id) = fields["setId"] else { continue }
                        for i in saved.exercises.indices {
                            for j in saved.exercises[i].sets.indices where saved.exercises[i].sets[j].id == Int(id) {
                                if let load = fields["actualLoad"] { if case .number(let n) = load { saved.exercises[i].sets[j].actualLoad = n } else { saved.exercises[i].sets[j].actualLoad = nil } }
                                if let reps = fields["actualReps"] { if case .number(let n) = reps { saved.exercises[i].sets[j].actualReps = Int(n) } else { saved.exercises[i].sets[j].actualReps = nil } }
                                if let rir = fields["rir"] { if case .number(let n) = rir { saved.exercises[i].sets[j].rir = n } else { saved.exercises[i].sets[j].rir = nil } }
                                if case .bool(let done) = fields["completed"] { saved.exercises[i].sets[j].completed = done }
                            }
                        }
                    }
                }
                if case .string(let status) = intent.command["status"] { saved.status = status }
                if intent.command["action"] == .string("substitute_exercise") {
                    guard case .string(let replacement) = intent.command["replacementExerciseKey"],
                          case .number(let exerciseID) = intent.command["sessionExerciseId"],
                          let index = saved.exercises.firstIndex(where: { $0.id == Int(exerciseID) }) else { throw WorkoutSyncTransportError.invalidResponse }
                    var item = counts.library.first { $0.exerciseKey == replacement }
                    if let definition = intent.command["replacementExercise"] {
                        let decoded = try JSONDecoder().decode(WorkoutCustomExerciseDefinition.self, from: JSONEncoder().encode(definition)).normalized()
                        item = .init(exerciseKey: replacement, name: decoded.name, movementPattern: decoded.movementPattern, loadMode: decoded.loadMode,
                            unit: decoded.unit, increment: decoded.increment, repMin: decoded.repMin, repMax: decoded.repMax, notes: decoded.notes)
                        if !counts.library.contains(where: { $0.exerciseKey == replacement }), let item { counts.library.append(item) }
                    }
                    guard let item, item.movementPattern == saved.exercises[index].movementPattern else { throw WorkoutSyncTransportError.invalidResponse }
                    if !saved.exercises[index].sets.contains(where: \.completed) {
                        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved.exercises[index])) as? [String: Any] else { throw WorkoutTrackerContractError.invalidSnapshot }
                        object["exerciseKey"] = item.exerciseKey; object["name"] = item.name; object["loadMode"] = item.loadMode
                        object["notes"] = item.notes; object["repMin"] = item.repMin; object["repMax"] = item.repMax
                        saved.exercises[index] = try JSONDecoder().decode(WorkoutTrackerDashboard.Exercise.self, from: JSONSerialization.data(withJSONObject: object))
                    }
                    try JSONEncoder().encode(counts.library).write(to: root.appendingPathComponent("library.json"), options: .atomic)
                }
                counts.saved = saved
                try JSONEncoder().encode(saved).write(to: root.appendingPathComponent("server.json"), options: .atomic)
                try JSONEncoder().encode(counts.revision).write(to: root.appendingPathComponent("revision.json"), options: .atomic)
            }
            let accepted = try receipt(intent, state: "committed", revision: counts.revision)
            try accepted.write(to: root.appendingPathComponent("receipt-" + intent.operationId.uuidString + ".json"), options: .atomic)
            let lostReply = root.appendingPathComponent("reply-dropped-once.json")
            if arguments.contains("--workout-ui-drop-reply-once"), !FileManager.default.fileExists(atPath: lostReply.path) {
                try Data("true".utf8).write(to: lostReply, options: .atomic); throw URLError(.timedOut)
            }
            return accepted
        }, readCredential: { config }, saveCredential: { _ in })
        frontend = client
        func exercise(id: Int, key: String, name: String, order: Int, mode: String, movement: String, load: Double, setOffset: Int) -> WorkoutTrackerDashboard.Exercise {
            let rows = (1...3).map { WorkoutTrackerDashboard.SetLog(id: setOffset + $0, setNumber: $0, setType: "work", plannedLoad: load,
                plannedReps: 8, actualLoad: nil, actualReps: nil, rir: nil, completed: false) }
            return .init(id: id, exerciseKey: key, name: name, orderIndex: order, loadMode: mode, progressionType: "double",
                plannedSets: 3, plannedReps: 8, plannedLoad: load, targetRir: 2, notes: "", slotKey: key,
                movementPattern: movement, originalExerciseKey: "", originalExerciseName: "", isPriming: false, sets: rows)
        }
        let first = exercise(id: 11, key: lower ? "squat" : "bench", name: lower ? "Back squat" : "Bench press", order: 1,
            mode: "barbell", movement: lower ? "squat" : "push", load: lower ? 185 : 135, setOffset: 0)
        let second = exercise(id: 22, key: lower ? "lying_leg_curl" : "chest_supported_row", name: lower ? "Lying leg curl" : "Chest-supported row", order: 2,
            mode: "machine", movement: lower ? "knee_flexion" : "pull", load: lower ? 70 : 95, setOffset: 3)
        let session = WorkoutTrackerDashboard.Session(id: lower ? 20 : 10, mesocycleId: 1, weekNumber: 2, sessionKey: lower ? "lower" : "upper", kind: "strength",
            title: lower ? "Lower A" : "Upper A", scheduledDate: "2026-10-20", orderIndex: 1, status: "planned", readiness: "", rating: "", notes: "",
            metrics: [:], sheetItemId: "", linkedSessionId: nil, completedAt: "", exercises: [first, second], finisher: nil)
        counts.saved = (try? Data(contentsOf: root.appendingPathComponent("server.json"))).flatMap { try? JSONDecoder().decode(WorkoutTrackerDashboard.Session.self, from: $0) } ?? session
        counts.revision = (try? Data(contentsOf: root.appendingPathComponent("revision.json"))).flatMap { try? JSONDecoder().decode(Int.self, from: $0) } ?? counts.revision
        drafts = WorkoutSessionDraftController(initial: .init(origin: config.origin, installationId: config.installationId,
            baseline: session, revision: 4, massScale: 1, localeIdentifier: "en_US"), store: .init(url: root.appendingPathComponent("draft.json")), frontend: client)
    }
    func prepare() async {
        do {
            if frontend.state.origin == nil {
                try frontend.configure(origin: drafts.state.origin, installationId: drafts.state.installationId, token: String(repeating: "f", count: 64))
            }
            if !frontend.state.enabled { try frontend.setEnabled(true) }
            try await frontend.checkCapabilities(); ready = true
        } catch { ready = false }
    }
    func renderReplacementIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--workout-replacement-render-proof"), ready,
              let session = evidence.saved, let exercise = session.exercises.first else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-workout-replacement-ui")
        let scope = WorkoutFrontendScope(origin: drafts.state.origin, installationId: UUID())
        let identity = WorkoutReplacementDraftScope(origin: scope.origin, installationID: scope.installationId,
            programID: session.mesocycleId, sessionID: session.id, exerciseID: exercise.id)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = WorkoutReplacementDraftStore(url: root.appendingPathComponent("Dhoop/WorkoutReplacementDrafts/" + scope.installationId.uuidString.lowercased()).appendingPathComponent("\(session.id)-\(exercise.id).json"))
        var input = WorkoutReplacementDraft(scope: identity, exercise: exercise, library: [])
        input.custom = true; input.name = exercise.movementPattern == "squat" ? "Paused squat" : "Cable chest press"
        input.loadMode = exercise.movementPattern == "push" ? "machine" : exercise.loadMode
        input.notes = "Use a comfortable range of motion."
        do {
            try file.save(input); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let config = WorkoutSyncConfiguration(enabled: true, origin: scope.origin, installationId: scope.installationId, credential: String(repeating: "f", count: 64))
            let renderedClient = WorkoutFrontendClient(store: .init(url: folder.appendingPathComponent(UUID().uuidString + ".json")), send: { _, _, _ in
                try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true, "frontendStart": false,
                    "customExerciseSubstitution": true, "lifeRevision": 4, "actions": ["substitute_exercise"]])
            }, readCredential: { config }, saveCredential: { _ in })
            try renderedClient.configure(origin: scope.origin, installationId: scope.installationId, token: config.credential)
            try renderedClient.setEnabled(true); try await renderedClient.checkCapabilities()
            for width in [390.0, 320.0] {
                try await CalendarReaderRenderProof.capture(NavigationStack {
                    ScreenScaffold(title: "Replace exercise") {
                        WorkoutExerciseReplacementEditor(session: session, exercise: exercise, library: [], revision: self.evidence.revision,
                            scope: scope, refresh: {}, client: renderedClient)
                    }
                }, name: "custom-\(Int(width))", width: width, height: 1000, folder: folder)
            }
        } catch { }
    }

    func renderSheetIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--workout-sheet-render-proof"), ready else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-workout-sheets")
        let kind = drafts.state.baseline.sessionKey
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for width in [390.0, 320.0] {
                try await CalendarReaderRenderProof.capture(WorkoutDraftVerificationContent(model: self, drafts: drafts),
                    name: kind + "-" + String(Int(width)), width: width, height: 1000, folder: folder)
            }
            try await CalendarReaderRenderProof.capture(WorkoutDraftVerificationContent(model: self, drafts: drafts),
                name: kind + "-accessibility3", width: 390, height: 1200, type: .accessibility3, folder: folder)
        } catch { }
    }

    func read() async throws -> WorkoutSessionDraft.Remote {
        evidence.reads += 1
        if ProcessInfo.processInfo.arguments.contains("--workout-ui-offline") { throw URLError(.notConnectedToInternet) }
        return .init(session: evidence.saved ?? drafts.state.baseline, revision: evidence.revision)
    }
}
struct WorkoutDraftVerificationView: View {
    @StateObject private var model = WorkoutDraftVerificationModel()
    var body: some View {
        Group {
            if model.ready { WorkoutDraftVerificationContent(model: model, drafts: model.drafts) }
            else { ProgressView { Text(verbatim: "Preparing isolated workout proof") } }
        }.task { await model.prepare(); await model.renderReplacementIfRequested(); await model.renderSheetIfRequested() }
    }
}
private struct WorkoutDraftVerificationContent: View {
    @ObservedObject var model: WorkoutDraftVerificationModel
    @ObservedObject var drafts: WorkoutSessionDraftController
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: LocalizedStringKey(drafts.state.baseline.title), subtitle: "Design verification · Demo data") {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    Text(verbatim: "No real HTTP requests or WHOOP recordings").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: "Demo posts: \(model.evidence.posts)").font(StrandFont.caption).accessibilityIdentifier("workout-demo-post-count")
                    Text(verbatim: "Earlier change resolved: \(model.frontend.state.operations.first(where: { $0.id.uuidString.lowercased().hasPrefix("22222222") })?.state == .rejected)")
                        .font(StrandFont.caption)
                    Text(verbatim: (drafts.state.pending?.id ?? model.frontend.state.operations.last?.id)?.uuidString.lowercased() ?? "none")
                        .font(StrandFont.caption).accessibilityIdentifier("workout-demo-operation-id")
                    ForEach(drafts.state.baseline.exercises) { exercise in
                        WorkoutInlineExerciseCard(session: drafts.state.baseline, exercise: exercise, library: model.evidence.library,
                            revision: drafts.state.revision, system: .imperial, refresh: { try drafts.receive(await model.read()) }, drafts: drafts, hasUnsavedEdits: drafts.state.isProtected, frontend: model.frontend)
                    }
                    Text("Edits stay on your phone until you save the workout.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }.safeAreaInset(edge: .bottom) {
                WorkoutSessionDraftActions(drafts: drafts, frontend: model.frontend, refresh: model.read)
            }
        }
    }
}
#endif
