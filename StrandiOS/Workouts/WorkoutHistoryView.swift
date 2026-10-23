import SwiftUI
import StrandDesign

@MainActor
struct WorkoutHistoryView: View {
    var strengthOnly = false
    var plannedProgramID: Int? = nil
    @ObservedObject private var client = WorkoutTrackerClient.shared
    @State private var chain = WorkoutHistoryPageChain()
    @State private var filters = WorkoutHistoryFilters()
    @State private var kind = "all"
    @State private var range = { var value = MetricRangeSelection(); value.preset = .all; return value }()
    @State private var capturedAt = Date()
    @StateObject private var refreshState = WorkoutRefreshController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var loadedConnection: String?
    private var busy: Bool { refreshState.busy }
    private var connectionIdentity: String { "\(client.state.origin ?? "")|\(client.state.installationId?.uuidString ?? "")|\(client.state.enabled)" }
    private var requestIdentity: String { "\(connectionIdentity)|\(requested)" }
    @State private var selected: WorkoutHistoryPage.Session?
    private var requested: WorkoutHistoryFilters {
        var value = filters
        if let plannedProgramID { value.mesocycleId = plannedProgramID; value.status = "planned" }
        value.kind = strengthOnly ? "strength" : (kind == "all" ? nil : kind)
        if range.preset != .all {
            let window = range.window(now: capturedAt)
            value.since = window.fromDay; value.until = window.toDay
        }
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text(plannedProgramID == nil ? "Life workouts" : "Planned lifting workouts").font(StrandFont.headline)
            if plannedProgramID == nil { Text("Tap a workout to edit its sets.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            MetricRangeControl(selection: $range, now: capturedAt).disabled(busy)
            HStack {
                if !strengthOnly { Picker("Activity", selection: $kind) {
                    Text("All activities").tag("all")
                    Text("Strength").tag("strength"); Text("Run").tag("run")
                    Text("Yoga").tag("yoga"); Text("Airbike").tag("airbike")
                }.disabled(busy) }
                Spacer(minLength: NoopMetrics.space2)
                NoopAsyncButton("Refresh", systemImage: "arrow.clockwise", kind: .secondary) { try await load(reset: true) }.disabled(busy || !client.state.enabled)
            }
            WorkoutRefreshFeedback(state: refreshState, retry: { try await load(reset: true) })
            if chain.requiresRefresh {
                Text("Workout changes are shown. Refresh before loading more history.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if let loaded = chain.filters, loaded != requested, !chain.sessions.isEmpty {
                Text("Previous results retained. Refresh to apply the selected filters.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
            }
            // Keep loaded rows mounted when presenting details; neither filters nor scroll is reset.
            ForEach(chain.sessions) { row in
                Button { selected = row } label: {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            HStack {
                                Text(row.title).font(StrandFont.headline)
                                Spacer(minLength: NoopMetrics.space2)
                                Image(systemName: "chevron.right").font(StrandFont.caption)
                            }
                            Text(row.scheduledDate.isEmpty ? (row.completedAt.isEmpty ? "Date unavailable" : row.completedAt) : row.scheduledDate)
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            Text("\(row.exerciseCount) exercises · \(row.completedSetCount)/\(row.totalSetCount) sets completed")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(NoopFeedbackButtonStyle())
            }
            if chain.nextCursor != nil {
                NoopAsyncButton("Load 20 older workouts", systemImage: "arrow.down", kind: .secondary, fullWidth: true) { try await load(reset: false) }
                    .disabled(busy || chain.requiresRefresh || requested != chain.filters || !client.state.enabled)
            }
            if chain.sessions.isEmpty && !busy && refreshState.errorMessage == nil && refreshState.lastSuccess != nil {
                Text("No workouts in this range.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            if !chain.sessions.isEmpty { Text("\(chain.sessions.count) loaded · newest first").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
        }
        .task(id: requestIdentity) {
            if loadedConnection != connectionIdentity { chain = .init(); refreshState.reset(); loadedConnection = connectionIdentity }
            try? await load(reset: true)
        }
        .onAppear { visible = true; capturedAt = Date(); Task { try? await load(reset: true) } }
        .onDisappear { visible = false; refreshState.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible && selected == nil { capturedAt = Date(); Task { try? await load(reset: true) } }
        }
        .sheet(item: $selected, onDismiss: {
            if loadedConnection == connectionIdentity, let page = client.state.frontendPage {
                for session in page.dashboard.sessions { chain.reconcile(session, readRevision: page.lifeRevision) }
            }
        }) { row in WorkoutHistorySessionSheet(row: row) }
    }
    private func load(reset: Bool) async throws {
        let query = requested, cursor = reset ? nil : chain.nextCursor
        let connection = connectionIdentity
        try await refreshState.refresh(identity: "\(connection)|\(query)|\(cursor ?? "first")") {
            let page = try await client.readHistory(filters: query, cursor: cursor)
            guard !Task.isCancelled, requested == query, connection == connectionIdentity else { throw CancellationError() }
            try chain.accept(page, requestedFilters: query, cursor: cursor)
            loadedConnection = connection
        }
    }
}

struct WorkoutHistorySessionSheet: View {
    let mesocycleId: Int
    let sessionId: Int
    init(row: WorkoutHistoryPage.Session) { self.mesocycleId = row.mesocycleId; self.sessionId = row.id }
    init(mesocycleId: Int, sessionId: Int) { self.mesocycleId = mesocycleId; self.sessionId = sessionId }
    @State private var page: WorkoutTrackerDashboard?
    @State private var error: String?
    @State private var readAt: Date?
    @State private var protectedEdits = false
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let page, let session = page.dashboard.sessions.first {
                    WorkoutTrackerSessionView(session: session, lifeRevision: page.lifeRevision, readAt: readAt,
                        refreshOnAppear: false, protectionChanged: { protectedEdits = $0 }, exerciseLibrary: page.dashboard.exerciseLibrary)
                } else if let error {
                    VStack(spacing: NoopMetrics.space3) {
                        Text(error).font(StrandFont.subhead)
                        NoopAsyncButton("Retry", systemImage: "arrow.clockwise") { try await load() }
                    }.padding(NoopMetrics.space4)
                } else { ProgressView("Reading workout…") }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Done") { if protectedEdits { confirmDiscard = true } else { dismiss() } }
            } }
            .task(id: "\(mesocycleId)-\(sessionId)") { try? await load() }
            .interactiveDismissDisabled(protectedEdits)
            .confirmationDialog("Close workout with local changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Keep changes and close") { dismiss() }
                Button("Keep editing", role: .cancel) { }
            }
        }
    }
    private func load() async throws {
        do {
            let result = try await WorkoutTrackerClient.shared.readHistorySession(mesocycleId: mesocycleId, sessionId: sessionId)
            try Task.checkCancellation()
            page = result; readAt = Date(); error = nil
        }
        catch { self.error = error.localizedDescription; throw error }
    }
}
