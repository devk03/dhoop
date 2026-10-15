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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingShare = false
    @State private var showingSchedule = false
    private var system: UnitSystem { UnitSystem(rawValue: units) ?? .metric }

    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(current.title), subtitle: LocalizedStringKey(current.scheduledDate.isEmpty ? "Unscheduled" : current.scheduledDate)) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Label(current.status.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "link")
                            .font(StrandFont.headline)
                        if !current.notes.isEmpty { Text(current.notes).font(StrandFont.body) }
                        if !current.readiness.isEmpty { Text("Readiness: \(current.readiness)").font(StrandFont.subhead) }
                        if !current.rating.isEmpty { Text("Rating: \(current.rating)").font(StrandFont.subhead) }
                        if let revision {
                            NavigationLink("Edit workout log") { WorkoutTrackerSessionEditor(session: current, revision: revision) }
                                .buttonStyle(NoopButtonStyle(.secondary))
                        }
                    }
                }
                ForEach(current.exercises) { exercise in
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text(exercise.name).font(StrandFont.headline)
                            Text(WorkoutTrackerLoadMode(rawValue: exercise.loadMode)?.explanation ?? exercise.loadMode)
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            if !exercise.notes.isEmpty { Text(exercise.notes).font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true) }
                            if !exercise.originalExerciseName.isEmpty && exercise.originalExerciseName != exercise.name {
                                Text("Replaces \(exercise.originalExerciseName)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            ForEach(exercise.sets) { row in
                                setRow(row, mode: exercise.loadMode)
                                if let revision {
                                    NavigationLink("Log set \(row.setNumber)") {
                                        WorkoutTrackerSetEditor(session: current, exercise: exercise, row: row, revision: revision, system: system)
                                    }.buttonStyle(NoopButtonStyle(.secondary))
                                }
                            }
                            if let revision {
                                NavigationLink("Adjust or replace exercise") {
                                    WorkoutTrackerExerciseEditor(session: current, exercise: exercise,
                                        library: tracker.state.frontendPage?.dashboard.exerciseLibrary ?? [], revision: revision)
                                }.buttonStyle(NoopButtonStyle(.secondary))
                            }
                        }
                    }
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
                if let revision, frontend.state.capabilities?.frontendStart == true { lifecycle(revision: revision) }
                if let snapshotReadAt {
                    Text("Life · updated \(snapshotReadAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
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

    private func lifecycle(revision: Int) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Workout status in Life").font(StrandFont.headline)
            Text("These actions update the shared tracker. They do not start or stop a separate WHOOP recording.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            if ["planned", "in_progress"].contains(current.status) {
                WorkoutFrontendSubmitSection(title: "Start in Life", action: "start_session", revision: revision, lifecycle: true, command: {
                    ["action": .string("start_session"), "mesocycleId": .number(Double(current.mesocycleId)), "sessionId": .number(Double(current.id))]
                }, refresh: refresh).id("start-\(revision)")
            }
            ForEach(current.status == "skipped" ? ["planned"] : current.status == "completed" ? ["planned"] : ["completed", "skipped"], id: \.self) { status in
                WorkoutFrontendSubmitSection(title: status == "planned" ? "Reopen in Life" : status == "completed" ? "Complete in Life" : "Skip in Life",
                    action: "update_session", revision: revision, lifecycle: true, command: {
                        ["action": .string("update_session"), "mesocycleId": .number(Double(current.mesocycleId)),
                         "sessionId": .number(Double(current.id)), "status": .string(status)]
                    }, refresh: refresh).id("\(status)-\(revision)")
            }
        }
    }
    private func refresh() async throws { try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id) }

    private func setRow(_ row: WorkoutTrackerDashboard.SetLog, mode: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space3))
        return layout {
            Label("Set \(row.setNumber) · \(row.setType)", systemImage: row.completed ? "checkmark.circle.fill" : "circle")
                .font(StrandFont.caption).foregroundStyle(row.completed ? StrandPalette.metricCyan : StrandPalette.textSecondary)
                .accessibilityValue(row.completed ? "Completed in Life" : "Not completed in Life")
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Prescribed").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(mode == "duration" ? "Timed exercise" : "\(load(row.plannedLoad, mode: mode)) × \(row.plannedReps)").font(StrandFont.bodyNumber)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Actual saved in Life").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if mode == "duration" {
                    Text(row.completed ? "Completed" : "Not logged").font(StrandFont.subhead)
                } else if row.actualLoad != nil || row.actualReps != nil {
                    Text("\(row.actualLoad.map { load($0, mode: mode) } ?? "—") × \(row.actualReps.map(String.init) ?? "—")").font(StrandFont.bodyNumber)
                    if let rir = row.rir { Text("\(rir.formatted()) RIR").font(StrandFont.caption) }
                } else { Text("Not logged").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, NoopMetrics.space2)
    }
    private func load(_ pounds: Double, mode: String) -> String {
        if mode == "bodyweight" { return "Bodyweight" }
        if mode == "duration" { return "Time-based" }
        return UnitFormatter.massFromKilograms(pounds / UnitFormatter.poundsPerKilogram, system: system)
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
