#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutInlineSetRow: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let row: WorkoutTrackerDashboard.SetLog
    let revision: Int
    let system: UnitSystem
    let showRIR: Bool
    let refresh: () async throws -> Void
    let dirtyChanged: (Bool) -> Void
    var showHistory: (() -> Void)? = nil
    @ObservedObject private var frontend = WorkoutFrontendClient.shared
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var draft: WorkoutInlineSetDraft
    @State private var operationID: UUID?
    @State private var message: String?
    @State private var accepted = false
    @FocusState private var focused: Bool
    private var mode: WorkoutTrackerLoadMode? { .init(rawValue: exercise.loadMode) }
    private var sameConnection: Bool { tracker.state.origin != nil && tracker.state.installationId != nil && tracker.state.origin == frontend.state.origin && tracker.state.installationId == frontend.state.installationId }

    init(session: WorkoutTrackerDashboard.Session, exercise: WorkoutTrackerDashboard.Exercise,
         row: WorkoutTrackerDashboard.SetLog, revision: Int, system: UnitSystem, showRIR: Bool,
         refresh: @escaping () async throws -> Void, dirtyChanged: @escaping (Bool) -> Void,
         showHistory: (() -> Void)? = nil) {
        self.session = session; self.exercise = exercise; self.row = row; self.revision = revision
        self.system = system; self.showRIR = showRIR; self.refresh = refresh; self.dirtyChanged = dirtyChanged; self.showHistory = showHistory
        _draft = State(initialValue: .init(row: row, massScale: system == .imperial ? 1 : UnitFormatter.poundsPerKilogram))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if let mode {
                WorkoutSetEntryRow(number: row.setNumber, kind: row.setType,
                    loadUnit: mode.hasMass ? (system == .imperial ? "lb" : "kg") : nil,
                    loadHint: (row.plannedLoad / draft.massScale).formatted(.number.grouping(.never).precision(.fractionLength(0...2))),
                    repsHint: mode == .duration ? nil : String(row.plannedReps), completed: row.completed,
                    dirty: draft.isDirty, showRIR: showRIR,
                    load: $draft.load, reps: $draft.reps, rir: $draft.rir, save: save,
                    editingEnabled: sameConnection && frontend.supports("update_set") && operationID == nil && !draft.conflicts(with: row),
                    showHistory: showHistory)
                    .focused($focused)
            } else { Text("Unsupported load mode. View this set in Life.").font(StrandFont.caption) }
            if draft.conflicts(with: row) {
                Text("This set changed in Life. Your input is retained; review the current values before saving.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                Button("Use latest saved values") { adopt(row) }.buttonStyle(NoopButtonStyle(.secondary))
            }
            if let message { Text(message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).accessibilityAddTraits(.updatesFrequently) }
            if accepted {
                NoopAsyncButton("Refresh saved set", systemImage: "arrow.clockwise", kind: .secondary) {
                    try await refresh(); try adoptLatest()
                }
            }
            if frontend.unresolved?.id == operationID && operationID != nil {
                NavigationLink("Recover pending save") { WorkoutFrontendSettingsView() }.buttonStyle(NoopButtonStyle(.secondary))
            }
        }.onChange(of: draft.isDirty) { _, _ in dirtyChanged(draft.isDirty || operationID != nil) }
        .onChange(of: operationID) { _, _ in dirtyChanged(draft.isDirty || operationID != nil) }
        .onChange(of: row) { _, value in
            if operationID == nil && !draft.isDirty { adopt(value) }
        }
        .onChange(of: frontend.state.operations) { _, _ in
            // Recovery elsewhere must not allow a duplicate save with an unknown outcome.
            if let id = operationID, let item = frontend.state.operations.first(where: { $0.id == id }) {
                if item.state == .committed { accepted = true }
                else if item.state == .rejected || item.state == .cancelled { operationID = nil }
            }
        }
    }
    private func adopt(_ value: WorkoutTrackerDashboard.SetLog) {
        draft = .init(row: value, massScale: draft.massScale); operationID = nil; accepted = false; message = nil
    }
    private func adoptLatest() throws {
        guard let latest = tracker.state.frontendPage?.dashboard.sessions.first(where: { $0.id == session.id && $0.mesocycleId == session.mesocycleId })?
            .exercises.first(where: { $0.id == exercise.id })?.sets.first(where: { $0.id == row.id }) else { throw WorkoutTrackerContractError.invalidSnapshot }
        adopt(latest); message = "Saved in Life"
    }
    private func save() async throws {
        guard sameConnection, operationID == nil, let mode, !draft.conflicts(with: row) else { throw WorkoutFrontendClient.Failure.unresolved }
        focused = false
        let command = try draft.command(sessionID: session.id, programID: session.mesocycleId, mode: mode,
            completed: draft.isDirty ? true : !row.completed)
        let id = try frontend.prepare(command: command, revision: revision)
        operationID = id; message = "Saving…"
        do { try await frontend.submit(id) }
        catch { message = "Input retained. Recover the pending save before retrying."; throw error }
        accepted = true; message = "Saved in Life"
        do { try await refresh(); try adoptLatest() }
        catch { message = "Saved in Life. Refresh to read the updated set." }
    }
}
#endif
