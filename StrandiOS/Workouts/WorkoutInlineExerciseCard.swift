#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutInlineExerciseCard: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let library: [WorkoutTrackerDashboard.LibraryItem]
    let revision: Int?
    let system: UnitSystem
    let refresh: () async throws -> Void
    @ObservedObject var drafts: WorkoutSessionDraftController
    var editingEnabled = true
    var hasUnsavedEdits = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingSwap = false
    @State private var replacement = ""
    @State private var historySet: WorkoutTrackerDashboard.SetLog?
    private var mode: WorkoutTrackerLoadMode? { .init(rawValue: exercise.loadMode) }
    private var alternatives: [WorkoutTrackerDashboard.LibraryItem] {
        library.filter { $0.movementPattern == exercise.movementPattern && $0.exerciseKey != exercise.exerciseKey }
    }
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space2))
                layout {
                    Text(exercise.name).font(StrandFont.headline).frame(maxWidth: .infinity, alignment: .leading)
                    if revision != nil {
                        Button { showingSwap.toggle() } label: { Label("Swap", systemImage: "arrow.triangle.2.circlepath") }
                            .buttonStyle(NoopButtonStyle(.secondary)).disabled(hasUnsavedEdits)
                        Menu {
                            if let revision {
                                if let mode, mode != .duration, !exercise.isPriming, exercise.progressionPreference != nil {
                                    NavigationLink("Progression and rep range") {
                                        WorkoutProgressionPreferencesView(session: session, exercise: exercise, revision: revision)
                                    }.disabled(hasUnsavedEdits)
                                }
                                ForEach(exercise.sets) { row in
                                    NavigationLink("Set \(row.setNumber) · targets") {
                                        WorkoutTrackerSetEditor(session: session, exercise: exercise, row: row,
                                            revision: revision, system: system, targetsOnly: true)
                                    }.disabled(hasUnsavedEdits)
                                }
                                NavigationLink("Targets and program options") {
                                    WorkoutTrackerExerciseEditor(session: session, exercise: exercise, library: library, revision: revision)
                                }.disabled(hasUnsavedEdits)
                            }
                        } label: { Image(systemName: "ellipsis").frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget) }
                        .buttonStyle(NoopFeedbackButtonStyle()).accessibilityLabel("Options for \(exercise.name)")
                    }
                }
                if let mode {
                    Text(mode.explanation).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if mode != .duration { Text("Reps in reserve · optional").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                if !exercise.notes.isEmpty { Text(exercise.notes).font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true) }
                if !exercise.originalExerciseName.isEmpty && exercise.originalExerciseName != exercise.name {
                    Text("Replaces \(exercise.originalExerciseName)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if showingSwap, let revision {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Picker("Replace with", selection: $replacement) {
                            Text("Choose exercise").tag("")
                            ForEach(alternatives) { Text($0.name).tag($0.exerciseKey) }
                        }.pickerStyle(.menu)
                        if alternatives.isEmpty { Text("No replacements are available for this movement.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                        Text("Updates this exercise in your Life program; past completed work stays intact.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        WorkoutFrontendSubmitSection(title: "Save replacement", action: "substitute_exercise", revision: revision, command: {
                            guard alternatives.contains(where: { $0.exerciseKey == replacement }) else {
                                throw WorkoutFrontendInput.Invalid(message: "Choose an eligible replacement first.")
                            }
                            return ["action": .string("substitute_exercise"), "mesocycleId": .number(Double(session.mesocycleId)),
                                "sessionId": .number(Double(session.id)), "sessionExerciseId": .number(Double(exercise.id)), "replacementExerciseKey": .string(replacement)]
                        }, refresh: { try await refresh(); showingSwap = false; replacement = "" })
                        .disabled(replacement.isEmpty || hasUnsavedEdits)
                        .id("replace-\(exercise.exerciseKey)-\(revision)")
                    }
                }
                ForEach(exercise.sets) { row in
                    if let revision {
                        WorkoutInlineSetRow(session: session, exercise: exercise, row: row,
                            system: system, showRIR: mode != .duration, drafts: drafts, editingEnabled: editingEnabled,
                            showHistory: { historySet = row })
                            .id("\(row.id)-\(system.rawValue)")
                    } else {
                        Text("Set \(row.setNumber) · \(row.completed ? "Completed" : "Not completed")").font(StrandFont.body)
                    }
                }
                if mode != .duration { Text("Empty fields show targets, not logged actuals.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            }
        }.sheet(item: $historySet) { row in
            WorkoutPreviousSetSheet(session: session, exercise: exercise, row: row, revision: revision ?? 0, system: system)
                .id("\(session.id)-\(session.weekNumber)-\(exercise.id)-\(exercise.exerciseKey)-\(exercise.loadMode)-\(row.id)-\(row.setType)-\(row.setNumber)-\(system.rawValue)")
        }
    }
}
#endif
