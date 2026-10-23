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
    }
    @Published var ready = false
    let frontend: WorkoutFrontendClient
    let drafts: WorkoutSessionDraftController
    let evidence: Evidence
    init() {
        let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--workout-ui-run=") }) ?? "--workout-ui-run=default"
        let run = argument.dropFirst("--workout-ui-run=".count).filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("workout-ui-\(run)")
        let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev",
            installationId: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, credential: String(repeating: "f", count: 64))
        let counts = Evidence(); evidence = counts
        let arguments = ProcessInfo.processInfo.arguments
        let legacyID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let legacy = WorkoutFrontendIntent(operationId: legacyID, expectedLifeRevision: 1,
            command: ["action": .string("update_set"), "sessionId": .number(9), "setId": .number(90), "completed": .bool(true)])
        let commandStore = WorkoutFrontendFileStore(url: root.appendingPathComponent("commands.json"))
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
                if state == "committed" { result["result"] = ["mesocycleId": 1, "sessionId": 10, "invalidate": "workout_tracker"] }
            }
            return try JSONSerialization.data(withJSONObject: result)
        }
        let client = WorkoutFrontendClient(store: commandStore, send: { endpoint, data, _ in
            if endpoint == .frontendCapabilities {
                return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true,
                    "frontendStart": false, "sessionCompletion": true, "sessionBatchSave": true,
                    "lifeRevision": counts.revision, "actions": ["update_session", "update_set"]])
            }
            if case .frontendReceipt(let id) = endpoint {
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
            if arguments.contains("--workout-ui-stale-once"), intent.expectedLifeRevision < 6 {
                try data.write(to: root.appendingPathComponent("rejected.json"), options: .atomic)
                counts.revision = 6; throw WorkoutSyncTransportError.http(409)
            }
            try await Task.sleep(nanoseconds: 400_000_000)
            counts.revision = intent.expectedLifeRevision + 1
            if var saved = counts.saved {
                saved.exercises[0].sets[0].actualLoad = 135; saved.exercises[0].sets[0].actualReps = 8
                saved.exercises[0].sets[0].completed = true; counts.saved = saved
            }
            return try receipt(intent, state: "committed", revision: counts.revision)
        }, readCredential: { config }, saveCredential: { _ in })
        frontend = client
        let rows = (1...3).map { WorkoutTrackerDashboard.SetLog(id: $0, setNumber: $0, setType: "work", plannedLoad: 135,
            plannedReps: 8, actualLoad: nil, actualReps: nil, rir: nil, completed: false) }
        let exercise = WorkoutTrackerDashboard.Exercise(id: 11, exerciseKey: "bench", name: "Bench press", orderIndex: 1,
            loadMode: "barbell", progressionType: "double", plannedSets: 3, plannedReps: 8, plannedLoad: 135, targetRir: 2,
            notes: "", slotKey: "press", movementPattern: "push", originalExerciseKey: "", originalExerciseName: "", isPriming: false, sets: rows)
        let session = WorkoutTrackerDashboard.Session(id: 10, mesocycleId: 1, weekNumber: 2, sessionKey: "upper", kind: "strength",
            title: "Upper A", scheduledDate: "2026-10-20", orderIndex: 1, status: "planned", readiness: "", rating: "", notes: "",
            metrics: [:], sheetItemId: "", linkedSessionId: nil, completedAt: "", exercises: [exercise], finisher: nil)
        counts.saved = session
        drafts = WorkoutSessionDraftController(initial: .init(origin: config.origin, installationId: config.installationId,
            baseline: session, revision: 4, massScale: 1, localeIdentifier: "en_US"), store: .init(url: root.appendingPathComponent("draft.json")), frontend: client)
    }
    func prepare() async {
        do {
            if frontend.state.origin == nil {
                try frontend.configure(origin: "https://track.kunjadia.dev", installationId: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, token: String(repeating: "f", count: 64))
            }
            if !frontend.state.enabled { try frontend.setEnabled(true) }
            try await frontend.checkCapabilities(); ready = true
        } catch { ready = false }
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
        }.task { await model.prepare() }
    }
}
private struct WorkoutDraftVerificationContent: View {
    @ObservedObject var model: WorkoutDraftVerificationModel
    @ObservedObject var drafts: WorkoutSessionDraftController
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: "Upper A", subtitle: "Design verification · Demo data") {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    Text(verbatim: "No real HTTP requests or WHOOP recordings").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: "Demo posts: \(model.evidence.posts)").font(StrandFont.caption).accessibilityIdentifier("workout-demo-post-count")
                    Text(verbatim: "Earlier change resolved: \(model.frontend.state.operations.first(where: { $0.id.uuidString.lowercased().hasPrefix("22222222") })?.state == .rejected)")
                        .font(StrandFont.caption)
                    Text(verbatim: (drafts.state.pending?.id ?? model.frontend.state.operations.last?.id)?.uuidString.lowercased() ?? "none")
                        .font(StrandFont.caption).accessibilityIdentifier("workout-demo-operation-id")
                    ForEach(drafts.state.baseline.exercises) { exercise in
                        WorkoutInlineExerciseCard(session: drafts.state.baseline, exercise: exercise, library: [],
                            revision: drafts.state.revision, system: .imperial, refresh: {}, drafts: drafts, hasUnsavedEdits: drafts.state.isProtected)
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
