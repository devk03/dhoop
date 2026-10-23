#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutProgressionPreferencesView: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let revision: Int
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @ObservedObject private var frontend = WorkoutFrontendClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutProgressionPreferenceDraft
    init(session: WorkoutTrackerDashboard.Session, exercise: WorkoutTrackerDashboard.Exercise, revision: Int) {
        self.session = session; self.exercise = exercise; self.revision = revision
        _draft = State(initialValue: .init(exercise: exercise))
    }
    var body: some View {
        ScreenScaffold(title: "Progression", subtitle: LocalizedStringKey(exercise.name)) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                        Toggle("Automatic rep range", isOn: $draft.automatic).toggleStyle(NoopSwitchStyle())
                        if !draft.automatic {
                            Stepper(value: Binding(get: { draft.minimum }, set: { draft.minimum = $0; draft.maximum = max($0, draft.maximum) }), in: 1...30) {
                                LabeledContent("Minimum reps", value: "\(draft.minimum)")
                            }
                            Stepper(value: Binding(get: { draft.maximum }, set: { draft.maximum = $0; draft.minimum = min($0, draft.minimum) }), in: 1...30) {
                                LabeledContent("Maximum reps", value: "\(draft.maximum)")
                            }
                        }
                        Stepper(value: $draft.targetRIR, in: 0...5) {
                            LabeledContent("Target RIR", value: "\(draft.targetRIR)")
                        }
                        Text("RIR is the number of extra reps you could have completed. Leave set RIR blank when unknown.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }.font(StrandFont.body)
                }
                Text(draft.automatic ? LocalizedStringKey("Life chooses the rep range from your recent logged work. Missing RIR stays unknown.") : LocalizedStringKey("Your chosen rep range stays pinned until you turn automatic back on."))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Label("Upcoming targets update in Life. Past results stay unchanged.", systemImage: "calendar")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Life recomputes upcoming targets nightly from your saved workout history.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                WorkoutFrontendSubmitSection(title: "Save preferences", action: "update_progression_preferences", revision: revision, command: {
                    guard frontend.state.capabilities?.progressionPreferences == true else { throw WorkoutFrontendClient.Failure.disabled }
                    return try draft.command(mesocycleId: session.mesocycleId, sessionExerciseId: exercise.id)
                }, refresh: {
                    try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id)
                    dismiss()
                }).disabled(frontend.state.capabilities?.progressionPreferences != true)
            }
        }
    }
}
#endif
