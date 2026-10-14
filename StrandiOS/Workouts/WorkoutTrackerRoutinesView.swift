#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutTrackerRoutinesView: View {
    @ObservedObject private var client = WorkoutTrackerClient.shared
    @EnvironmentObject private var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScreenScaffold(title: "Tracker routines", subtitle: "Life owns the plan. Dhoop records what you do.") {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text(client.state.message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Refresh routines", systemImage: "arrow.clockwise", kind: .secondary) { try await client.refreshIndex() }
                    .disabled(!client.state.enabled || client.busy)
                if !client.state.enabled {
                    NavigationLink("Set up workout tracker") { WorkoutTrackerSettingsView() }
                        .buttonStyle(NoopButtonStyle(.secondary))
                }
                if let index = client.state.index {
                    if let cycle = index.cycle { Text(cycle.name).font(StrandFont.headline) }
                    ForEach(index.sessions) { row in
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                Text(row.title).font(StrandFont.headline)
                                Text("Block \(row.block) · \(row.status)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                if let date = row.scheduledDate { Text(date).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                                NoopAsyncButton("Start tracker workout", systemImage: "play.fill") {
                                    let manifest = try await client.manifest(sessionId: row.sessionId)
                                    let binding = try WorkoutTrackerCaptureBinding(manifest: manifest)
                                    guard !manifest.exerciseOccurrences.isEmpty,
                                          manifest.exerciseOccurrences.allSatisfy({ $0.loadMode != .duration && !$0.sets.isEmpty }) else {
                                        throw WorkoutTrackerContractError.invalidSnapshot
                                    }
                                    let plan = manifest.exerciseOccurrences.map { occurrence in
                                        LiftPlanItem(exercise: occurrence.name, targetSets: occurrence.sets.count,
                                            restSec: occurrence.restTargetSeconds, note: loadLabel(occurrence.loadMode))
                                    }
                                    guard session.start(plan: plan, programId: nil, programName: manifest.title, trackerBinding: binding) else {
                                        throw WorkoutTrackerContractError.unavailableCapture
                                    }
                                    for (exerciseIndex, occurrence) in manifest.exerciseOccurrences.enumerated() {
                                        for (setIndex, set) in occurrence.sets.enumerated() where set.setType == "warmup" {
                                            session.setWarmup(LiftSlot(exerciseIndex: exerciseIndex, setIndex: setIndex + 1), true)
                                        }
                                    }
                                    dismiss()
                                }.disabled(row.status != "planned" || session.isActive || client.busy || !client.state.enabled)
                            }
                        }
                    }
                } else {
                    Text("No tracker routines have been read. Local routines are still available in Strength.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
    private func loadLabel(_ mode: WorkoutTrackerLoadMode) -> String {
        switch mode {
        case .dumbbellEach: return "Load is per hand."
        case .bodyweightAdded: return "Log added load, excluding body weight."
        case .bodyweight: return "Bodyweight repetitions; no mass load."
        case .duration: return "Duration measurement."
        default: return "Log total load."
        }
    }
}
#endif
