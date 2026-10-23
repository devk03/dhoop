#if os(iOS)
import SwiftUI
import StrandDesign

/// Set edits only touch the durable workout draft; network delivery belongs to Save/Finish workout.
struct WorkoutInlineSetRow: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let row: WorkoutTrackerDashboard.SetLog
    let system: UnitSystem
    let showRIR: Bool
    @ObservedObject var drafts: WorkoutSessionDraftController
    var editingEnabled = true
    var showHistory: (() -> Void)? = nil
    private var mode: WorkoutTrackerLoadMode? { .init(rawValue: exercise.loadMode) }
    private var entry: WorkoutInlineSetDraft { drafts.state.entry(row.id) ?? .init(row: row, massScale: drafts.state.massScale) }
    private func binding(_ keyPath: WritableKeyPath<WorkoutInlineSetDraft, String>) -> Binding<String> {
        Binding(get: { entry[keyPath: keyPath] }, set: { value in
            var updated = entry; updated[keyPath: keyPath] = value; drafts.edit(updated)
        })
    }
    var body: some View {
        if let mode {
            WorkoutSetEntryRow(number: row.setNumber, kind: row.setType,
                loadUnit: mode.hasMass ? (system == .imperial ? "lb" : "kg") : nil,
                loadHint: (row.plannedLoad / drafts.state.massScale).formatted(.number.grouping(.never).precision(.fractionLength(0...2))),
                repsHint: mode == .duration ? nil : String(row.plannedReps), completed: entry.completed,
                dirty: false, showRIR: showRIR,
                load: binding(\.load), reps: binding(\.reps), rir: binding(\.rir), save: {
                    var value = entry; value.completed.toggle()
                    if !value.completed { value.load = ""; value.reps = ""; value.rir = "" }
                    drafts.edit(value)
                }, editingEnabled: editingEnabled && drafts.canEdit, showHistory: showHistory, savedLocally: true,
                showColumnLabels: row.id == exercise.sets.first?.id)
        } else { Text("Unsupported load mode. View this set in Life.").font(StrandFont.caption) }
    }
}
#endif
