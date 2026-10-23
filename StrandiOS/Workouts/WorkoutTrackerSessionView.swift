#if os(iOS)
import SwiftUI
import StrandDesign

/// Life owns the workout; this screen edits a durable, scoped pending version until Save/Finish.
struct WorkoutTrackerSessionView: View {
    let session: WorkoutTrackerDashboard.Session
    let lifeRevision: Int?
    let readAt: Date?
    var refreshOnAppear = true
    var protectionChanged: (Bool) -> Void = { _ in }
    var exerciseLibrary: [WorkoutTrackerDashboard.LibraryItem] = []
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @ObservedObject private var frontend = WorkoutFrontendClient.shared
    @StateObject private var drafts: WorkoutSessionDraftController
    @StateObject private var refreshState = WorkoutRefreshController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var showingShare = false
    @State private var showingSchedule = false
    @State private var showingConflict = false
    @State private var openedContext: String?
    private var current: WorkoutTrackerDashboard.Session { drafts.state.baseline }
    private var system: UnitSystem { drafts.state.massScale == 1 ? .imperial : .metric }
    private var connectionIdentity: String { "\(tracker.state.origin ?? "")|\(tracker.state.installationId?.uuidString ?? "")|\(tracker.state.enabled)" }
    private var connectionChanged: Bool { openedContext.map { $0 != connectionIdentity } ?? false }
    private var sameConnection: Bool {
        !connectionChanged && tracker.state.origin == drafts.state.origin && tracker.state.installationId == drafts.state.installationId &&
        frontend.state.origin == drafts.state.origin && frontend.state.installationId == drafts.state.installationId
    }
    init(session: WorkoutTrackerDashboard.Session, lifeRevision: Int?, readAt: Date?, refreshOnAppear: Bool = true,
         protectionChanged: @escaping (Bool) -> Void = { _ in }, exerciseLibrary: [WorkoutTrackerDashboard.LibraryItem] = []) {
        self.session = session; self.lifeRevision = lifeRevision; self.readAt = readAt; self.refreshOnAppear = refreshOnAppear
        self.protectionChanged = protectionChanged; self.exerciseLibrary = exerciseLibrary
        let tracker = WorkoutTrackerClient.shared
        let unit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        _drafts = StateObject(wrappedValue: WorkoutSessionDraftController.open(session: session, revision: lifeRevision ?? 0,
            origin: tracker.state.origin ?? "", installationId: tracker.state.installationId ?? UUID(),
            massScale: unit == .imperial ? 1 : UnitFormatter.poundsPerKilogram))
    }
    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(current.title), subtitle: LocalizedStringKey(current.scheduledDate.isEmpty ? "Unscheduled" : current.scheduledDate), onRefresh: { try? await refresh() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                WorkoutRefreshFeedback(state: refreshState, retry: refresh)
                if connectionChanged {
                    Text("The connection changed. Your workout draft is retained on this phone. Close and reopen the workout.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning)
                }
                if drafts.state.remote != nil && drafts.state.pending == nil {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Life has newer workout values. Your local edits are retained.").font(StrandFont.subhead)
                            Button("Review changes") { showingConflict = true }.buttonStyle(NoopButtonStyle(.secondary))
                        }
                    }
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        HStack(spacing: NoopMetrics.space2) {
                            Label(current.status.replacingOccurrences(of: "_", with: " ").capitalized,
                                systemImage: current.status == "completed" ? "checkmark.circle.fill" : "calendar").font(StrandFont.subhead)
                            Spacer(minLength: NoopMetrics.space2)
                            NavigationLink { WorkoutTrackerSessionEditor(session: current, revision: drafts.state.revision) } label: {
                                Image(systemName: "square.and.pencil")
                            }.buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Edit workout notes and metrics").disabled(drafts.state.isProtected)
                        }
                        if !current.notes.isEmpty { Text(current.notes).font(StrandFont.body) }
                        if !current.readiness.isEmpty { Text("Readiness: \(current.readiness)").font(StrandFont.subhead) }
                        if !current.rating.isEmpty { Text("Rating: \(current.rating)").font(StrandFont.subhead) }
                        if current.status == "completed" {
                            Text("Edit weight, reps or RIR below. Saving keeps this workout completed.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                ForEach(current.exercises) { exercise in
                    WorkoutInlineExerciseCard(session: current, exercise: exercise,
                        library: tracker.state.frontendPage?.dashboard.exerciseLibrary ?? exerciseLibrary,
                        revision: drafts.state.revision, system: system, refresh: refresh, drafts: drafts,
                        editingEnabled: sameConnection, hasUnsavedEdits: drafts.state.isProtected)
                }
                if current.status == "planned", current.scheduledDate.isEmpty, frontend.state.capabilities?.sessionDateScheduling == true {
                    Button { showingSchedule = true } label: { Label("Schedule workout", systemImage: "calendar.badge.plus") }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true)).disabled(drafts.state.isProtected || !sameConnection)
                }
                if current.status == "completed" {
                    Button { showingShare = true } label: { Label("Share workout", systemImage: "square.and.arrow.up") }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                    WorkoutFrontendSubmitSection(title: "Reopen workout", action: "update_session", revision: drafts.state.revision, command: {
                        ["action": .string("update_session"), "mesocycleId": .number(Double(current.mesocycleId)),
                         "sessionId": .number(Double(current.id)), "status": .string("planned")]
                    }, refresh: refresh).disabled(drafts.state.isProtected || !sameConnection)
                }
                Text("Edits stay on your phone until you save the workout.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            WorkoutSessionDraftActions(drafts: drafts, frontend: frontend, enabled: sameConnection, refresh: WorkoutSessionDraftController.reader(for: drafts.state))
        }
        .task(id: connectionIdentity) {
            if openedContext == nil { openedContext = connectionIdentity }
            guard !connectionChanged else { refreshState.reset(); return }
            drafts.setRefresh(WorkoutSessionDraftController.reader(for: drafts.state))
            if frontend.state.enabled { try? await frontend.checkCapabilities() }
            if refreshOnAppear { try? await refresh() }
            drafts.resume()
        }
        .onAppear { visible = true; protectionChanged(drafts.state.isProtected); if sameConnection { drafts.resume() } }
        .onDisappear { visible = false; refreshState.cancel(); protectionChanged(false) }
        .onChange(of: drafts.state.isProtected) { _, protected in protectionChanged(protected) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible && sameConnection {
                Task { try? await refresh(); drafts.resume() }
            }
        }
        .onChange(of: frontend.busy) { _, busy in if !busy && visible && sameConnection { drafts.resume() } }
        .onChange(of: frontend.state.operations) { _, _ in if visible && sameConnection { drafts.resume() } }
        .sheet(isPresented: $showingConflict) { WorkoutDraftConflictView(drafts: drafts) }
        .sheet(isPresented: $showingSchedule) {
            WorkoutDateScheduleSheet(row: .init(id: current.id, mesocycleId: current.mesocycleId,
                weekNumber: current.weekNumber, sessionKey: current.sessionKey, kind: current.kind, title: current.title,
                scheduledDate: current.scheduledDate, status: current.status, completedAt: current.completedAt,
                exerciseCount: current.exercises.count, completedSetCount: current.exercises.reduce(0) { $0 + $1.sets.filter(\.completed).count },
                totalSetCount: current.exercises.reduce(0) { $0 + $1.sets.count }), revision: drafts.state.revision, refresh: refresh)
        }
        .sheet(isPresented: $showingShare) { WorkoutShareSheet(title: current.title, content: shareCard) }
    }
    private func refresh() async throws {
        guard sameConnection else { throw WorkoutSyncTransportError.configuration }
        try await refreshState.refresh(identity: connectionIdentity) { try drafts.receive(await readForSave()) }
    }
    private func readForSave() async throws -> WorkoutSessionDraft.Remote {
        guard sameConnection else { throw WorkoutSyncTransportError.configuration }
        let identity = connectionIdentity
        try await tracker.refreshDashboard(mesocycleId: current.mesocycleId, sessionId: current.id)
        guard !Task.isCancelled, identity == connectionIdentity,
              let page = tracker.state.frontendPage,
              let session = page.dashboard.sessions.first(where: { $0.id == current.id && $0.mesocycleId == current.mesocycleId }) else { throw WorkoutTrackerContractError.invalidSnapshot }
        return .init(session: session, revision: page.lifeRevision)
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
