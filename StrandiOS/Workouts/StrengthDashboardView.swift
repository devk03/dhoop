import SwiftUI
import StrandDesign

@MainActor
struct StrengthDashboardView: View {
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @ObservedObject private var frontend = WorkoutFrontendClient.shared
    @EnvironmentObject private var recording: LiftSessionController
    @ObservedObject private var refreshState = WorkoutTrackerClient.shared.strengthRefresh
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    private var page: WorkoutStrengthPage? { tracker.strengthPage }
    private var busy: Bool { refreshState.busy }
    @State private var selected: WorkoutHistoryPage.Session?
    @State private var scheduling: WorkoutHistoryPage.Session?
    private var connectionIdentity: String { "\(tracker.state.origin ?? "")|\(tracker.state.installationId?.uuidString ?? "")|\(tracker.state.enabled)" }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(spacing: NoopMetrics.space2) {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("Next workout").font(StrandFont.title2)
                    if let program = page?.program { Text(program.name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                }
                Spacer(minLength: NoopMetrics.space2)
                NoopAsyncButton("Refresh", systemImage: "arrow.clockwise", kind: .secondary) { try await load() }.disabled(busy || !tracker.state.enabled)
                Menu {
                    NavigationLink("Lifting history") { ScreenScaffold(title: "Lifting history") { WorkoutHistoryView(strengthOnly: true) } }
                    if let program = page?.program { NavigationLink("Program settings") { StrengthProgramSettings(program: program) } }
                    NavigationLink("Workout connection") { WorkoutTrackerSettingsView() }
                    NavigationLink("Saved WHOOP recordings") { LiftLogView(recordingsOnly: true) }
                } label: { Image(systemName: "ellipsis") }.buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Strength options")
            }
            if recording.isActive {
                Button { recording.isPresented = true } label: { Label("Resume WHOOP recording", systemImage: "play.fill") }
                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
            }
            WorkoutRefreshFeedback(state: refreshState, retry: load)
            if !tracker.state.enabled {
                NavigationLink("Connect Life workouts") { WorkoutTrackerSettingsView() }.buttonStyle(NoopButtonStyle(.secondary))
            }
            if let page {
                if let next = page.nextUp { nextCard(next) }
                else {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Label(page.program == nil ? "No active lifting program" : "You're up to date", systemImage: "dumbbell")
                                .font(StrandFont.headline)
                            Text(page.program == nil ? "Choose or create a lifting program in Life." : "There are no pending lifting workouts in this program.")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                let upcoming = page.scheduled.filter { $0.id != page.nextUp?.id }
                if !upcoming.isEmpty {
                    Text("Upcoming").font(StrandFont.headline)
                    ForEach(upcoming) { row in sessionRow(row) }
                }
                let unscheduled = page.unscheduled.filter { $0.id != page.nextUp?.id }
                if !unscheduled.isEmpty {
                    Text("Not scheduled").font(StrandFont.headline)
                    ForEach(unscheduled) { row in sessionRow(row) }
                }
                if page.pagination.scheduledHasMore || page.pagination.unscheduledHasMore {
                    NavigationLink("All planned lifting workouts") { PlannedLiftingWorkoutsView(programID: page.program?.id) }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                }
            }
            if frontend.unresolved != nil {
                NavigationLink("A workout change needs attention") { WorkoutFrontendSettingsView() }.buttonStyle(NoopButtonStyle(.secondary))
            }
        }
        .task(id: connectionIdentity) { if tracker.state.enabled { try? await load() } }
        .onAppear { visible = true; if tracker.state.enabled { Task { try? await load() } } }
        .onDisappear { visible = false; refreshState.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible && tracker.state.enabled { Task { try? await load() } }
        }
        .sheet(item: $selected, onDismiss: { Task { try? await load() } }) { row in WorkoutHistorySessionSheet(row: row) }
        .sheet(item: $scheduling) { row in
            if let page { WorkoutDateScheduleSheet(row: row, revision: page.lifeRevision, refresh: load) }
        }
    }
    private func nextCard(_ row: WorkoutHistoryPage.Session) -> some View { workoutCard(row, prominent: true) }
    private func sessionRow(_ row: WorkoutHistoryPage.Session) -> some View { workoutCard(row, prominent: false) }
    private func workoutCard(_ row: WorkoutHistoryPage.Session, prominent: Bool) -> some View {
        StrengthWorkoutCard(title: row.title, scheduledLabel: scheduleLabel(row),
            summary: "\(row.exerciseCount) exercises · \(row.totalSetCount) sets", prominent: prominent,
            openTitle: row.status == "in_progress" ? "Resume workout log" : "View workout",
            open: { selected = row }, schedule: canSchedule(row) ? { scheduling = row } : nil)
    }
    private func scheduleLabel(_ row: WorkoutHistoryPage.Session) -> String {
        if row.status == "in_progress" { return "In progress" }
        guard !row.scheduledDate.isEmpty else { return "Not scheduled" }
        let date = HeartDashboardProjection.date(row.scheduledDate)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? row.scheduledDate
        return row.timing == "overdue" ? "Overdue · \(date)" : row.timing == "today" ? "Today · \(date)" : date
    }
    private func canSchedule(_ row: WorkoutHistoryPage.Session) -> Bool {
        row.status == "planned" && row.scheduledDate.isEmpty && frontend.state.capabilities?.sessionDateScheduling == true && frontend.supports("update_session")
    }
    private func load() async throws {
        try await tracker.refreshStrength()
        if frontend.state.enabled && !frontend.busy { try? await frontend.checkCapabilities() }
    }
}

struct WorkoutDateScheduleSheet: View {
    let row: WorkoutHistoryPage.Session
    let revision: Int
    let refresh: () async throws -> Void
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    private var day: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "America/Los_Angeles"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: LocalizedStringKey("Schedule \(row.title)")) {
                Text("Choose a date in your Life tracker.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                DatePicker("Workout date", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                    .environment(\.timeZone, TimeZone(identifier: "America/Los_Angeles")!)
                WorkoutFrontendSubmitSection(title: "Save in Life", action: "update_session", revision: revision, command: {
                    guard row.status == "planned", row.scheduledDate.isEmpty else { throw WorkoutTrackerContractError.invalidSnapshot }
                    return ["action": .string("update_session"), "mesocycleId": .number(Double(row.mesocycleId)), "sessionId": .number(Double(row.id)), "date": .string(day)]
                }, refresh: { try await refresh(); dismiss() })
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PlannedLiftingWorkoutsView: View {
    let programID: Int?
    var body: some View {
        ScreenScaffold(title: "Planned workouts") {
            if let programID { WorkoutHistoryView(strengthOnly: true, plannedProgramID: programID) }
            else { Text("No active lifting program").font(StrandFont.subhead) }
        }
    }
}

private struct StrengthProgramSettings: View {
    let program: WorkoutTrackerDashboard.Cycle
    @State private var page: WorkoutTrackerDashboard?
    @State private var error: String?
    var body: some View {
        Group {
            if let page { WorkoutTrackerProgramEditor(page: page, liftingOnly: true) }
            else if let error { Text(error).font(StrandFont.subhead).padding(NoopMetrics.space4) }
            else { ProgressView("Reading program settings…") }
        }.task(id: program.id) {
            do {
                let client = WorkoutTrackerClient.shared
                try await client.refreshDashboard(mesocycleId: program.id)
                guard let next = client.state.frontendPage,
                      next.dashboard.activeMesocycle?.config["programType"] == .string("four_lift_strength")
                else { throw WorkoutTrackerContractError.invalidSnapshot }
                page = next
            } catch { self.error = error.localizedDescription }
        }
    }
}
