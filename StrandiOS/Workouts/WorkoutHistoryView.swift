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
    @State private var busy = false
    @State private var error: String?
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
            if let error { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
            if chain.requiresRefresh {
                Text("Workout changes are shown. Refresh before loading more history.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if busy { ProgressView("Reading workouts…") }
            if let loaded = chain.filters, loaded != requested, !chain.sessions.isEmpty {
                Text("Previous results retained. Refresh to apply the selected filters.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
            }
            if !busy && chain.sessions.isEmpty {
                Text(plannedProgramID == nil ? "No completed Life workouts in this range." : "No planned lifting workouts in this range.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
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
            Text("\(chain.sessions.count) loaded · newest first").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .task(id: requested) { if !busy { try? await load(reset: true) } }
        .sheet(item: $selected, onDismiss: {
            if let page = client.state.frontendPage {
                for session in page.dashboard.sessions { chain.reconcile(session, readRevision: page.lifeRevision) }
            }
        }) { row in WorkoutHistorySessionSheet(row: row) }
    }
    private func load(reset: Bool) async throws {
        guard !busy else { return }
        let query = requested, cursor = reset ? nil : chain.nextCursor
        busy = true; error = nil
        defer { busy = false }
        do {
            let page = try await client.readHistory(filters: query, cursor: cursor)
            guard !Task.isCancelled, requested == query else { return }
            try chain.accept(page, requestedFilters: query, cursor: cursor)
        } catch is CancellationError { throw CancellationError() }
        catch { self.error = error.localizedDescription; throw error }
    }
}

struct WorkoutHistorySessionSheet: View {
    let row: WorkoutHistoryPage.Session
    @State private var page: WorkoutTrackerDashboard?
    @State private var error: String?
    @State private var readAt: Date?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let page, let session = page.dashboard.sessions.first {
                    WorkoutTrackerSessionView(session: session, lifeRevision: page.lifeRevision, readAt: readAt)
                } else if let error {
                    VStack(spacing: NoopMetrics.space3) {
                        Text(error).font(StrandFont.subhead)
                        NoopAsyncButton("Retry", systemImage: "arrow.clockwise") { try await load() }
                    }.padding(NoopMetrics.space4)
                } else { ProgressView("Reading workout…") }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task(id: row.id) { try? await load() }
        }
    }
    private func load() async throws {
        do { page = try await WorkoutTrackerClient.shared.readHistorySession(row); readAt = Date(); error = nil }
        catch { self.error = error.localizedDescription; throw error }
    }
}
