#if os(iOS)
import SwiftUI
import StrandDesign

/// Website state is displayed as received. Planned values never become actuals by opening this view.
struct WorkoutTrackerSessionView: View {
    let session: WorkoutTrackerDashboard.Session
    let lifeRevision: Int?
    let readAt: Date?
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @ObservedObject private var frontend = WorkoutFrontendClient.shared
    private var newerCachedPage: WorkoutTrackerDashboard? {
        guard let page = tracker.state.frontendPage,
              page.lifeRevision >= (lifeRevision ?? 0),
              page.dashboard.sessions.contains(where: { $0.id == session.id && $0.mesocycleId == session.mesocycleId }) else { return nil }
        return page
    }
    private var current: WorkoutTrackerDashboard.Session {
        newerCachedPage?.dashboard.sessions.first { $0.id == session.id && $0.mesocycleId == session.mesocycleId } ?? session
    }
    private var revision: Int? { newerCachedPage?.lifeRevision ?? lifeRevision }
    private var snapshotReadAt: Date? { newerCachedPage == nil ? readAt : tracker.state.frontendReadAt }
    @AppStorage(UnitPrefs.systemKey) private var units = UnitSystem.metric.rawValue
    @State private var dirtySetIDs: Set<Int> = []
    @State private var showingShare = false
    @State private var showingSchedule = false
    private var system: UnitSystem { UnitSystem(rawValue: units) ?? .metric }

    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(current.title), subtitle: LocalizedStringKey(current.scheduledDate.isEmpty ? "Unscheduled" : current.scheduledDate)) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        HStack(spacing: NoopMetrics.space2) {
                            Label(current.status.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: current.status == "completed" ? "checkmark.circle.fill" : "calendar")
                                .font(StrandFont.subhead)
                            Spacer(minLength: NoopMetrics.space2)
                            if let revision {
                                NavigationLink { WorkoutTrackerSessionEditor(session: current, revision: revision) } label: {
                                    Image(systemName: "square.and.pencil")
                                }.buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Edit workout notes and metrics")
                                    .disabled(!dirtySetIDs.isEmpty)
                            }
                        }
                        if !current.notes.isEmpty { Text(current.notes).font(StrandFont.body) }
                        if !current.readiness.isEmpty { Text("Readiness: \(current.readiness)").font(StrandFont.subhead) }
                        if !current.rating.isEmpty { Text("Rating: \(current.rating)").font(StrandFont.subhead) }
                    }
                }
                ForEach(current.exercises) { exercise in
                    WorkoutInlineExerciseCard(session: current, exercise: exercise,
                        library: tracker.state.frontendPage?.dashboard.exerciseLibrary ?? [], revision: revision,
                        system: system, refresh: refresh, dirtyChanged: { id, dirty in
                            if dirty { dirtySetIDs.insert(id) } else { dirtySetIDs.remove(id) }
                        }, hasUnsavedEdits: !dirtySetIDs.isEmpty)
                }
                if !current.metrics.isEmpty {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Saved workout metrics").font(StrandFont.headline)
                            ForEach(current.metrics.keys.sorted(), id: \.self) { key in
                                if let value = current.metrics[key] { Text("\(key): \(value.displayText)").font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                }
                if current.status == "planned", current.scheduledDate.isEmpty, frontend.state.capabilities?.sessionDateScheduling == true {
                    Button { showingSchedule = true } label: { Label("Schedule workout", systemImage: "calendar.badge.plus") }
                        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                }
                if current.status == "completed" {
                    Button { showingShare = true } label: { Label("Share workout", systemImage: "square.and.arrow.up") }
                        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                }
                if !dirtySetIDs.isEmpty {
                    Text("Save edited sets before finishing or reopening the workout.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                }
                if let revision { completion(revision: revision).disabled(!dirtySetIDs.isEmpty) }
                if let snapshotReadAt {
                    Text("Life · updated \(snapshotReadAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .task(id: session.id) {
            if frontend.state.enabled { try? await frontend.checkCapabilities() }
            try? await refresh()
        }
        .refreshable { try? await refresh() }
        .sheet(isPresented: $showingSchedule) {
            if let revision {
                WorkoutDateScheduleSheet(row: .init(id: current.id, mesocycleId: current.mesocycleId,
                    weekNumber: current.weekNumber, sessionKey: current.sessionKey, kind: current.kind, title: current.title,
                    scheduledDate: current.scheduledDate, status: current.status, completedAt: current.completedAt,
                    exerciseCount: current.exercises.count, completedSetCount: current.exercises.reduce(0) { $0 + $1.sets.filter(\.completed).count },
                    totalSetCount: current.exercises.reduce(0) { $0 + $1.sets.count }), revision: revision, refresh: refresh)
            }
        }
        .sheet(isPresented: $showingShare) {
            WorkoutShareSheet(title: current.title, content: shareCard)
        }
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            Text("Dhoop · \(current.title)").font(StrandFont.title2)
            Text(current.scheduledDate.isEmpty ? (current.completedAt.isEmpty ? "Date unavailable" : current.completedAt) : current.scheduledDate)
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text("\(current.exercises.count) exercises · \(current.exercises.reduce(0) { $0 + $1.sets.filter(\.completed).count }) completed sets")
                .font(StrandFont.headline)
            ForEach(Array(current.exercises.prefix(6))) { exercise in
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text(exercise.name).font(StrandFont.headline)
                        Text("\(exercise.sets.filter(\.completed).count) completed sets").font(StrandFont.subhead)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if current.exercises.count > 6 { Text("+\(current.exercises.count - 6) more exercises").font(StrandFont.caption) }
            Text("Source: Life workout log. A WHOOP heart-rate trace is not attached to this log.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }.padding(NoopMetrics.space4).background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary)
    }

    @ViewBuilder private func completion(revision: Int) -> some View {
        if frontend.state.capabilities?.sessionCompletion == true {
            if current.status == "completed" {
                WorkoutFrontendSubmitSection(title: "Reopen workout", action: "update_session", revision: revision, command: {
                    ["action": .string("update_session"), "mesocycleId": .number(Double(current.mesocycleId)),
                     "sessionId": .number(Double(current.id)), "status": .string("planned")]
                }, refresh: refresh).id("reopen-\(revision)")
            } else if ["planned", "in_progress"].contains(current.status), !current.scheduledDate.isEmpty {
                WorkoutFrontendSubmitSection(title: "Finish workout", action: "update_session", revision: revision, command: {
                    ["action": .string("update_session"), "mesocycleId": .number(Double(current.mesocycleId)),
                     "sessionId": .number(Double(current.id)), "status": .string("completed")]
                }, refresh: refresh).id("finish-\(revision)")
            } else if current.status == "planned" {
                Text("Schedule a date before finishing this workout.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private func refresh() async throws { try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id) }


}

extension WorkoutTrackerValue {
    var displayText: String {
        switch self {
        case .null: return "Unavailable"
        case .bool(let value): return value ? "Yes" : "No"
        case .number(let value): return value.formatted()
        case .string(let value): return value
        case .array(let values): return values.map(\.displayText).joined(separator: ", ")
        case .object(let values): return values.keys.sorted().map { "\($0): \(values[$0]?.displayText ?? "Unavailable")" }.joined(separator: " · ")
        }
    }
}
#endif
