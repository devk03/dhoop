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
    @State private var showRIR = false
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
                            Toggle("Show RIR", isOn: $showRIR)
                            if let revision {
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
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: NoopMetrics.space2) {
                        Text("Set").frame(minWidth: NoopMetrics.minimumTouchTarget, alignment: .leading)
                        if mode?.hasMass == true { Text(system == .imperial ? "lb" : "kg").frame(maxWidth: .infinity, alignment: .leading) }
                        if mode != .duration { Text("Reps").frame(maxWidth: .infinity, alignment: .leading) }
                        Text("Done").frame(minWidth: NoopMetrics.minimumTouchTarget, alignment: .center)
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(exercise.sets) { row in
                    if let revision {
                        WorkoutInlineSetRow(session: session, exercise: exercise, row: row,
                            system: system, showRIR: showRIR, drafts: drafts, editingEnabled: editingEnabled,
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
