#if DEBUG && os(iOS) && targetEnvironment(simulator)
import SwiftUI
import StrandDesign

/// Explicit simulator-only component proof. No real credentials, HTTP calls, health data, or app DB seeds.
@MainActor
private final class WorkoutDraftVerificationModel: ObservableObject {
    final class Evidence {
        var posts = 0
        var reads = 0
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
        let client = WorkoutFrontendClient(store: .init(url: root.appendingPathComponent("commands.json")), send: { endpoint, data, _ in
            if endpoint == .frontendCapabilities {
                return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true,
                    "frontendStart": false, "sessionCompletion": true, "sessionBatchSave": true,
                    "lifeRevision": 4, "actions": ["update_session"]])
            }
            if case .frontendReceipt(let id) = endpoint {
                return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "operationId": id.uuidString.lowercased(), "state": "not_observed", "lifeRevision": 4])
            }
            guard endpoint == .frontendCommand, let data else { throw WorkoutSyncTransportError.invalidResponse }
            counts.posts += 1
            let intent = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: data)
            try await Task.sleep(nanoseconds: 400_000_000)
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "operationId": intent.operationId.uuidString.lowercased(),
                "request": JSONSerialization.jsonObject(with: data), "requestHash": String(repeating: "a", count: 64),
                "state": "committed", "receiptLifeRevision": intent.expectedLifeRevision + 1,
                "lifeRevision": intent.expectedLifeRevision + 1, "result": ["mesocycleId": 1, "sessionId": 10, "invalidate": "workout_tracker"]])
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
        return .init(session: drafts.state.baseline, revision: drafts.state.revision)
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
