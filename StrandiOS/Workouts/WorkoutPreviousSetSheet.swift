#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutPreviousSetSheet: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let row: WorkoutTrackerDashboard.SetLog
    let revision: Int
    let system: UnitSystem
    @Environment(\.dismiss) private var dismiss
    @State private var report: WorkoutPreviousSetReport?
    @State private var failed = false
    @State private var previous: WorkoutPreviousSetPage.Previous?
    @State private var editingPrevious = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    if let report {
                        WorkoutPreviousSetContent(report: report)
                        if previous != nil {
                            Button("Open workout to edit") { editingPrevious = true }
                                .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                        } else {
                            NavigationLink("Lifting history") { ScreenScaffold(title: "Lifting history") { WorkoutHistoryView(strengthOnly: true) } }
                                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                        }
                    }
                    else if failed {
                        Text("Last week's results could not be loaded. Your current set is unchanged.")
                            .font(StrandFont.body)
                        NoopAsyncButton("Try again", systemImage: "arrow.clockwise", kind: .secondary) { try await load() }
                    } else {
                        ProgressView("Loading last week's set…").font(StrandFont.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(NoopMetrics.space4)
            }.background(NoopVisualStyle.canvas)
                .navigationTitle("Last week").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.buttonStyle(NoopButtonStyle(.secondary))
                    }
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .task { try? await load() }
            .sheet(isPresented: $editingPrevious) {
                if let previous { WorkoutHistorySessionSheet(mesocycleId: previous.mesocycleId, sessionId: previous.sessionId) }
            }
    }

    private func load() async throws {
        failed = false
        do {
            let page = try await WorkoutTrackerClient.shared.readPreviousSet(session: session, exercise: exercise, set: row, minimumRevision: revision)
            try Task.checkCancellation()
            report = page.report(exerciseName: exercise.name, system: system)
            previous = page.previous
        } catch {
            if !Task.isCancelled { failed = true }
            throw error
        }
    }
}
#endif
