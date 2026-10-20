#if os(iOS)
import SwiftUI
import StrandDesign

/// Website state is displayed as received. Planned values never become actuals by opening this view.
struct WorkoutTrackerSessionView: View {
    let session: WorkoutTrackerDashboard.Session
    let lifeRevision: Int?
    let readAt: Date?
    var refreshOnAppear = true
    var protectionChanged: (Bool) -> Void = { _ in }
    var exerciseLibrary: [WorkoutTrackerDashboard.LibraryItem] = []
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @ObservedObject private var frontend = WorkoutFrontendClient.shared
    @State private var snapshot: WorkoutEditableSnapshot?
    private var current: WorkoutTrackerDashboard.Session { snapshot?.current.session ?? session }
    private var revision: Int? { snapshot?.current.revision ?? lifeRevision }
    private var snapshotReadAt: Date? { snapshot?.current.readAt ?? readAt }
    @StateObject private var refreshState = WorkoutRefreshController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var showDiscard = false
    @State private var draftGeneration = 0
    @State private var openedContext: String?
    @State private var editingSystem: UnitSystem?
    private var connectionChanged: Bool { openedContext.map { $0 != connectionIdentity } ?? false }
    @AppStorage(UnitPrefs.systemKey) private var units = UnitSystem.metric.rawValue
    @State private var dirtySetIDs: Set<Int> = []
    @State private var showingShare = false
    @State private var showingSchedule = false
    private var system: UnitSystem { editingSystem ?? UnitSystem(rawValue: units) ?? .metric }

    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(current.title), subtitle: LocalizedStringKey(current.scheduledDate.isEmpty ? "Unscheduled" : current.scheduledDate), onRefresh: { try? await refresh() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                WorkoutRefreshFeedback(state: refreshState, retry: refresh)
                if connectionChanged {
                    Text("The connection changed. Close and reopen this workout before saving. Your edits are retained here.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning)
                }
                if snapshot?.pending != nil {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Life has newer workout data. Your edits are retained.").font(StrandFont.subhead)
                            Button("Load latest workout") { showDiscard = true }.buttonStyle(NoopButtonStyle(.secondary))
                        }
                    }
                }
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
                        library: snapshot?.current.library ?? exerciseLibrary, revision: revision,
                        system: system, refresh: refresh, dirtyChanged: { id, dirty in
                            if dirty { dirtySetIDs.insert(id) } else { dirtySetIDs.remove(id) }
                        }, hasUnsavedEdits: !dirtySetIDs.isEmpty)
                        .id("\(exercise.id)-\(draftGeneration)")
                        .disabled(connectionChanged)
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
                if let revision { completion(revision: revision).disabled(!dirtySetIDs.isEmpty || connectionChanged) }
                if let snapshotReadAt {
                    Text("Life · updated \(snapshotReadAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .disabled(connectionChanged)
        .task(id: connectionIdentity) {
            if openedContext == nil { openedContext = connectionIdentity; editingSystem = UnitSystem(rawValue: units) ?? .metric }
            guard !connectionChanged else { refreshState.reset(); return }
            if snapshot == nil { snapshot = .init(session: session, revision: lifeRevision, readAt: readAt, library: exerciseLibrary) }
            if frontend.state.enabled { try? await frontend.checkCapabilities() }
            if refreshOnAppear { try? await refresh() }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; refreshState.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible && !connectionChanged { Task { try? await refresh() } }
        }
        .onChange(of: dirtySetIDs) { _, ids in
            snapshot?.reconsider(protectedSetIDs: ids)
            protectionChanged(!ids.isEmpty)
        }
        .confirmationDialog("Discard unsaved changes and load the latest workout?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) {
                dirtySetIDs = []; snapshot?.usePendingAfterDiscard(); draftGeneration += 1
            }
            Button("Keep editing", role: .cancel) { }
        }
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
    private var connectionIdentity: String { "\(session.mesocycleId)|\(session.id)|\(tracker.state.origin ?? "")|\(tracker.state.installationId?.uuidString ?? "")|\(tracker.state.enabled)" }
    private func refresh() async throws {
        guard !connectionChanged else { throw WorkoutSyncTransportError.configuration }
        let identity = connectionIdentity
        try await refreshState.refresh(identity: identity) {
            try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id)
            guard !Task.isCancelled, identity == connectionIdentity, let page = tracker.state.frontendPage else { throw CancellationError() }
            var value = snapshot ?? .init(session: session, revision: lifeRevision, readAt: readAt, library: exerciseLibrary)
            try value.receive(page, readAt: tracker.state.frontendReadAt ?? Date(), protectedSetIDs: dirtySetIDs)
            snapshot = value
        }
    }


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
