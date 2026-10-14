#if os(iOS)
import SwiftUI
import StrandDesign

@MainActor
struct WorkoutTrackerRoutinesView: View {
    @ObservedObject private var client = WorkoutTrackerClient.shared
    @EnvironmentObject private var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    private struct RoutineSummary: Identifiable {
        let id: Int
        let title: String
        let status: String
        let block: Int?
        let scheduledDate: String?
    }
    private var rows: [RoutineSummary] {
        if let index = client.state.index {
            return index.sessions.map { .init(id: $0.sessionId, title: $0.title, status: $0.status, block: $0.block, scheduledDate: $0.scheduledDate) }
        }
        return client.state.manifests.values.sorted { $0.sessionId < $1.sessionId }.map {
            .init(id: $0.sessionId, title: $0.title, status: $0.status, block: nil, scheduledDate: $0.scheduledDate)
        }
    }
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
                if !rows.isEmpty {
                    if let cycle = client.state.index?.cycle { Text(cycle.name).font(StrandFont.headline) }
                    ForEach(rows) { row in routineCard(row) }
                } else {
                    Text("No tracker routines have been read. Local routines are still available in Strength.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
    private func routineCard(_ row: RoutineSummary) -> some View {
        let cached = client.state.manifests[String(row.id)]
        let eligible = (try? client.cachedManifest(sessionId: row.id)) != nil
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text(row.title).font(StrandFont.headline)
                if let block = row.block { Text("Block \(block) · \(row.status)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                else { Text(row.status).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                if let date = row.scheduledDate { Text(date).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                NoopAsyncButton("Read latest and start", systemImage: "arrow.clockwise") {
                    let manifest = try await client.manifest(sessionId: row.id)
                    try start(try client.captureBinding(manifest: manifest))
                }.disabled(row.status != "planned" || session.isActive || client.busy || !client.state.enabled)
                if let cached {
                    if cached.title != row.title { Text("Cached title: \(cached.title)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    if let date = client.state.manifestReadAt[String(row.id)] {
                        Text("Cached plan · fetched \(date.formatted(date: .abbreviated, time: .shortened))").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    } else { Text("Cached plan · fetch time unknown").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    NoopAsyncButton("Start cached plan", systemImage: "internaldrive", kind: .secondary) {
                        try start(try client.cachedCaptureBinding(sessionId: row.id))
                    }.disabled(!eligible || session.isActive || client.busy)
                    Text(client.state.enabled ? "Uses this saved plan without a read now. Tracker writes are checked separately." : "Connection is off. Recording stays local until you enable delivery.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if let block = client.state.cachedPlanBlocks[String(row.id)] {
                        Text(block.message).font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
    private func start(_ binding: WorkoutTrackerCaptureBinding) throws {
        let manifest = binding.manifest
        guard !manifest.exerciseOccurrences.isEmpty, manifest.exerciseOccurrences.allSatisfy({ $0.loadMode != .duration && !$0.sets.isEmpty }) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let plan = manifest.exerciseOccurrences.map {
            LiftPlanItem(exercise: $0.name, targetSets: $0.sets.count, restSec: $0.restTargetSeconds,
                         note: $0.loadMode.explanation, sourceLoadMode: $0.loadMode)
        }
        guard session.start(plan: plan, programId: nil, programName: manifest.title, trackerBinding: binding) else { throw WorkoutTrackerContractError.unavailableCapture }
        for (exerciseIndex, occurrence) in manifest.exerciseOccurrences.enumerated() {
            for (setIndex, set) in occurrence.sets.enumerated() where set.setType == "warmup" {
                session.setWarmup(LiftSlot(exerciseIndex: exerciseIndex, setIndex: setIndex + 1), true)
            }
        }
        dismiss()
    }
}
#endif
