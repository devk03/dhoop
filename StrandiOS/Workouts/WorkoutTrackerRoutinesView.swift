#if os(iOS)
import SwiftUI
import StrandDesign

@MainActor
struct WorkoutTrackerRoutinesView: View {
    var embedded = false
    @State private var readError: String?
    @State private var selectedCycle: Int?
    @State private var showingCanonical: WorkoutTrackerDashboard.Session?
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
        Group {
            if embedded { content }
            else { ScreenScaffold(title: "Strength", subtitle: "Your Life workout tracker.") { content } }
        }
        .task {
            selectedCycle = client.state.frontendPage?.dashboard.activeMesocycle?.id
            if client.state.enabled && client.state.frontendPage == nil && !client.busy {
                do { try await client.refreshDashboard() }
                catch { readError = error.localizedDescription }
            }
        }
        .sheet(item: $showingCanonical) { row in
            NavigationStack {
                WorkoutTrackerSessionView(session: row, lifeRevision: client.state.frontendPage?.lifeRevision,
                    readAt: client.state.frontendReadAt)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Label("Life workout tracker", systemImage: "link").font(StrandFont.headline)
                    Text("Programs, workouts and history use the same tracker as the website and its MCP.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    if let page = client.state.frontendPage, let at = client.state.frontendReadAt {
                        Text("Website snapshot · \(at.formatted(date: .abbreviated, time: .shortened)) · revision \(page.lifeRevision)")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let error = readError {
                        Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical)
                    }
                    if let page = client.state.frontendPage, !page.dashboard.mesocycles.isEmpty {
                        Picker("Program to read", selection: $selectedCycle) {
                            Text("Current program").tag(Int?.none)
                            ForEach(page.dashboard.mesocycles) { cycle in Text(cycle.name).tag(Optional(cycle.id)) }
                        }.disabled(client.busy)
                    }
                    NoopAsyncButton("Refresh website workouts", systemImage: "arrow.clockwise", kind: .secondary) {
                        do { try await client.refreshDashboard(mesocycleId: selectedCycle); readError = nil }
                        catch { readError = error.localizedDescription; throw error }
                    }.disabled(!client.state.enabled || client.busy)
                    NavigationLink("Connection & pending changes") { WorkoutTrackerSettingsView() }
                        .buttonStyle(NoopButtonStyle(.secondary))
                }
            }
            if let page = client.state.frontendPage {
                if let cycle = page.dashboard.activeMesocycle { Text(cycle.name).font(StrandFont.title2) }
                NavigationLink("Program settings & benchmarks") { WorkoutTrackerProgramEditor(page: page) }
                    .buttonStyle(NoopButtonStyle(.secondary))
                if page.dashboard.sessions.isEmpty {
                    Text("No website workouts in this snapshot.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(page.dashboard.sessions) { row in
                    Button { showingCanonical = row } label: {
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.title).font(StrandFont.headline)
                                    Spacer(minLength: NoopMetrics.space2)
                                    Image(systemName: "chevron.right").font(StrandFont.caption)
                                }
                                Text(row.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.metricCyan)
                                Text(row.scheduledDate.isEmpty ? "Unscheduled" : row.scheduledDate)
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Text("\(row.exercises.count) exercises · \(row.exercises.reduce(0) { $0 + $1.sets.count }) planned sets")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(NoopFeedbackButtonStyle())
                }
                HStack(spacing: NoopMetrics.space3) {
                    NoopAsyncButton("Previous page", systemImage: "chevron.left", kind: .secondary) {
                        try await client.refreshDashboard(mesocycleId: page.dashboard.activeMesocycle?.id,
                            cursor: max(0, page.pagination.cursor - page.pagination.limit))
                    }.disabled(page.pagination.cursor == 0 || client.busy || !client.state.enabled)
                    NoopAsyncButton("Next page", systemImage: "chevron.right", kind: .secondary) {
                        guard let next = page.pagination.nextCursor else { return }
                        try await client.refreshDashboard(mesocycleId: page.dashboard.activeMesocycle?.id, cursor: next)
                    }.disabled(page.pagination.nextCursor == nil || client.busy || !client.state.enabled)
                }
                Text("\(page.dashboard.sessions.count) of \(page.pagination.totalSessions) website workouts")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text("No website snapshot has been read. Connect the workout tracker, then refresh. Cached WHOOP recordings remain available.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            if !rows.isEmpty {
                DisclosureGroup("WHOOP recording plans") {
                    Text("These are cached website prescriptions for physical recording. Recording a plan does not confirm that a website workout was started or completed.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    ForEach(rows) { row in routineCard(row) }
                }
            }
            NavigationLink("WHOOP recordings on this phone") { LiftLogView(recordingsOnly: true) }
                .buttonStyle(NoopButtonStyle(.secondary))
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
                NoopAsyncButton("Read plan and record WHOOP", systemImage: "arrow.clockwise") {
                    let manifest = try await client.manifest(sessionId: row.id)
                    try start(try client.captureBinding(manifest: manifest))
                }.disabled(row.status != "planned" || session.isActive || client.busy || !client.state.enabled)
                if let cached {
                    if cached.title != row.title { Text("Cached title: \(cached.title)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    if let date = client.state.manifestReadAt[String(row.id)] {
                        Text("Cached plan · fetched \(date.formatted(date: .abbreviated, time: .shortened))").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    } else { Text("Cached plan · fetch time unknown").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    NoopAsyncButton("Record cached plan", systemImage: "internaldrive", kind: .secondary) {
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
        if !embedded { dismiss() }
    }
}
#endif
