import SwiftUI
import StrandDesign

struct CardioHistoryView: View {
    @ObservedObject var model: CardioHistoryModel
    @Binding var range: MetricRangeSelection
    let now: Date
    let controller: RunningSessionController
    @State private var kind: CardioHistoryKind?
    @State private var search = ""
    @State private var visibleCount = 40
    @State private var selected: CardioHistoryGroup?
    @State private var exportURL: URL?
    @State private var preparingExport = false
    @State private var exportGeneration = 0
    @State private var exportError: String?
    @State private var pendingDelete: CardioHistoryItem?
    @State private var deleting = false
    @State private var deletionError: String?
    @EnvironmentObject private var repo: Repository
    @Environment(\.dynamicTypeSize) private var typeSize
    private var filtered: [CardioHistoryGroup] { CardioHistoryProjection.filtered(model.groups, window: range.window(now: now), kind: kind, search: search) }
    private var months: [String] { Array(Set(filtered.prefix(visibleCount).map { monthKey($0.primary.start) })).sorted(by: >) }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            MetricRangeControl(selection: $range, now: now)
            Picker("Workout type", selection: $kind) {
                Text("All types").tag(nil as CardioHistoryKind?)
                ForEach(CardioHistoryKind.allCases) { Text($0.title).tag(Optional($0)) }
            }.pickerStyle(.menu).font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
            TextField("Search workouts or sources", text: $search).font(StrandFont.body).textFieldStyle(.roundedBorder)
                .frame(minHeight: NoopMetrics.minimumTouchTarget).accessibilityLabel("Search cardio history")
            DashboardGridLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, squareMinimum: false) {
                summary("Saved sessions", "\(filtered.count)", "figure.run")
                summary("Recorded duration", duration(filtered.reduce(0) { $0 + max(0, $1.primary.duration) }), "clock")
            }
            if model.loading { ProgressView("Reading workout history…") }
            if let error = model.error { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
            if filtered.isEmpty && !model.loading { Text("No workouts in this range. Choose All history or different dates.").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary) }
            ForEach(months, id: \.self) { month in
                Text(monthTitle(month)).font(StrandFont.headline).foregroundStyle(StrandPalette.textSecondary)
                NoopCard {
                    VStack(spacing: NoopMetrics.space3) {
                        let rows = filtered.prefix(visibleCount).filter { monthKey($0.primary.start) == month }
                        ForEach(rows) { group in
                            if group.id != rows.first?.id { Divider() }
                            HStack(spacing: NoopMetrics.space2) {
                                Button { selected = group } label: { row(group) }.buttonStyle(.plain)
                                let deletable = group.recordings.filter { canDelete($0) }
                                if !deletable.isEmpty {
                                    Menu {
                                        ForEach(deletable) { item in
                                            Button(role: .destructive) { pendingDelete = item } label: {
                                                Label(deletable.count == 1 ? "Delete recording" : "Delete \(item.title) · \(item.source)", systemImage: "trash")
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").font(StrandFont.headline)
                                            .frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                                    }.accessibilityLabel("Actions for \(group.primary.title)").disabled(deleting)
                                }
                            }
                        }
                    }
                }
            }
            if filtered.count > visibleCount {
                Button("Load older sessions · \(filtered.count - visibleCount) more") { visibleCount += 40 }
                    .font(StrandFont.subhead).frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget).buttonStyle(.bordered)
            }
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("Keep a copy of Cardio history").font(StrandFont.headline)
                    Text("The general app backup excludes local zone runs and interval sessions. Export those records separately. This JSON copy has no in-app restore yet.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Save or share Cardio export", systemImage: "square.and.arrow.up") }
                            .font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        Button("Prepare a fresh copy") { prepareExport() }.font(StrandFont.caption)
                    } else {
                        Button { prepareExport() } label: { Label(preparingExport ? "Preparing…" : "Export local Cardio data", systemImage: "square.and.arrow.up") }
                            .font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget).disabled(preparingExport)
                    }
                    if let exportError { Text(exportError).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                }
            }
            Text("Dates use the workout's start time. Linked recordings stay available; unknown activity types retain their recorded labels.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .onChange(of: range) { _, _ in visibleCount = 40 }
        .onChange(of: kind) { _, _ in visibleCount = 40 }
        .onChange(of: search) { _, _ in visibleCount = 40 }
        .sheet(item: $selected) { group in
            CardioHistoryDetail(group: group, payloads: model.payloads, canDelete: canDelete, delete: deleteRecording)
        }
        .confirmationDialog("Delete this recording?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Delete recording", role: .destructive) { Task {
                do { try await deleteRecording(item) }
                catch { deletionError = "Could not delete recording: \(error.localizedDescription). Refresh history and try again." }
            } }
            Button("Cancel", role: .cancel) { }
        } message: { item in
            Text("\(item.title) · \(item.start.formatted(date: .abbreviated, time: .shortened)) · \(item.source). This removes this recording from Dhoop. Heart-rate history and linked recordings are kept.")
        }
        .alert("Recording was not deleted", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: { Text(deletionError ?? "") }
    }
    private func canDelete(_ item: CardioHistoryItem) -> Bool {
        switch model.payloads[item.id] {
        case .zone, .intervals: return true
        case .recorded(let row): return WorkoutSource.classify(row.source) == .manual || WorkoutSource.classify(row.source) == .detected
        case nil: return false
        }
    }
    @MainActor private func deleteRecording(_ item: CardioHistoryItem) async throws {
        guard !deleting, let payload = model.payloads[item.id], canDelete(item) else { throw CocoaError(.fileReadNoSuchFile) }
        deleting = true
        defer { deleting = false }
        exportGeneration += 1
        preparingExport = false; exportURL = nil; exportError = nil
        model.invalidatePendingLoad()
        switch payload {
        case .zone(let run): try controller.deleteSummary(id: run.id)
        case .intervals(let url, let id): try controller.hiit.deleteWorkout(at: url, id: id)
        case .recorded(let row): try await repo.deleteCardioWorkout(row)
        }
        exportURL = nil
        await model.load(repo: repo, zones: controller.summaries, window: range.window(now: now))
    }
    private func prepareExport() {
        guard !preparingExport, !deleting else { return }
        exportGeneration += 1
        let generation = exportGeneration
        preparingExport = true; exportError = nil; exportURL = nil
        Task {
            defer { if generation == exportGeneration { preparingExport = false } }
            do {
                let url = try await CardioLocalExport.writeCopy()
                guard generation == exportGeneration else { return }
                exportURL = url
            } catch {
                guard generation == exportGeneration else { return }
                exportError = "Export failed: \(error.localizedDescription). Original records remain on this phone."
            }
        }
    }
    private func row(_ group: CardioHistoryGroup) -> some View {
        let item = group.primary
        return HStack(alignment: .center, spacing: NoopMetrics.space3) {
            Image(systemName: item.kind == .zone ? "figure.run" : item.kind == .hiit ? "bolt.fill" : item.kind == .intervals ? "timer" : "figure.mixed.cardio")
                .font(StrandFont.title2).foregroundStyle(item.kind == .hiit ? StrandPalette.metricPurple : StrandPalette.metricCyan)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(StrandFont.headline)
                    Spacer(minLength: NoopMetrics.space1)
                    Text(duration(item.duration)).font(StrandFont.subhead).monospacedDigit()
                }
                Text(item.start.formatted(date: .abbreviated, time: .shortened)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("\(item.averageHR.map { "Avg \(Int($0.rounded())) bpm · " } ?? "")\(item.source)")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if group.recordings.count > 1 { Text("\(group.recordings.count) linked recordings").font(StrandFont.caption).foregroundStyle(StrandPalette.metricCyan) }
            }
            Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }.frame(minHeight: NoopMetrics.minimumTouchTarget).accessibilityElement(children: .combine)
    }
    private func summary(_ title: String, _ value: String, _ icon: String) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label(title, systemImage: icon).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(value).font(StrandFont.title2).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds)) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m \(max(0, Int(seconds)) % 60)s"
    }
    private func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }
    private func monthTitle(_ key: String) -> String { HeartDashboardProjection.date(key + "-01")?.formatted(.dateTime.month(.wide).year()) ?? key }
}

private struct CardioHistoryDetail: View {
    let group: CardioHistoryGroup
    let payloads: [String: CardioHistoryPayload]
    let canDelete: (CardioHistoryItem) -> Bool
    let delete: (CardioHistoryItem) async throws -> Void
    @State private var selectedID: String?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deletionError: String?
    @Environment(\.dismiss) private var dismiss
    private var item: CardioHistoryItem { group.recordings.first { $0.id == selectedID } ?? group.primary }
    var body: some View {
        Group {
            switch payloads[selectedID ?? group.primary.id] {
            case .zone(let run): ZoneRunReviewView(run: run)
            case .intervals(let url, _): CardioIntervalFileView(url: url)
            case .recorded(let row): NavigationStack { WorkoutDetailView(row: row) }
            case nil: Text("This recording could not be opened.").font(StrandFont.body)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: NoopMetrics.space2) {
                if group.recordings.count > 1 {
                    Menu("Linked recordings") {
                        ForEach(group.recordings) { row in Button("\(row.title) · \(row.source)") { selectedID = row.id } }
                    }.font(StrandFont.subhead).frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget).disabled(deleting)
                }
                if canDelete(item) {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label(deleting ? "Deleting…" : "Delete recording", systemImage: "trash")
                            .font(StrandFont.subhead).frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                    }.buttonStyle(.bordered).tint(StrandPalette.statusCritical).disabled(deleting)
                } else {
                    Text("Imported recordings are read-only. Manage the original in its source app.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }.padding(NoopMetrics.space3).background(StrandPalette.surfaceBase)
        }
        .interactiveDismissDisabled(deleting)
        .confirmationDialog("Delete this recording?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete recording", role: .destructive) {
                let target = item
                deleting = true
                Task {
                    do { try await delete(target); dismiss() }
                    catch { deletionError = "Could not delete recording: \(error.localizedDescription). Refresh history and try again." }
                    deleting = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(item.title) · \(item.start.formatted(date: .abbreviated, time: .shortened)) · \(item.source). Heart-rate history and linked recordings are kept.")
        }
        .alert("Recording was not deleted", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: { Text(deletionError ?? "") }
    }
}
private struct CardioIntervalFileView: View {
    let url: URL
    @State private var run: HIITSession?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let run { HIITReviewView(run: run) }
            else if failed { VStack { Text("This saved workout could not be read."); Button("Done") { dismiss() } }.font(StrandFont.body) }
            else { ProgressView("Reading interval data…") }
        }.task(id: url) {
            let result = await Task.detached(priority: .userInitiated) { () -> HIITSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(HIITSession.self, from: data)
            }.value
            guard !Task.isCancelled else { return }
            run = result; failed = result == nil
        }
    }
}
private struct ZoneRunReviewView: View {
    let run: RunningSessionSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NoopCard(tint: StrandPalette.metricCyan) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("\(clock(run.inZoneSeconds)) in zone").font(StrandFont.title1).monospacedDigit()
                        Text("of \(clock(run.goalSeconds)) goal · \(run.goalMet ? "Reached" : "Not reached")").font(StrandFont.subhead)
                        ProgressView(value: min(run.inZoneSeconds, run.goalSeconds), total: run.goalSeconds).tint(StrandPalette.metricCyan)
                        Text(run.target.rangeLabel).font(StrandFont.headline)
                    }
                }
                DashboardGridLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, squareMinimum: false) {
                    metric("Average HR", run.averageBPM.map { "\(Int($0.rounded())) bpm" } ?? "—")
                    metric("Peak HR", run.maximumBPM.map { "\($0) bpm" } ?? "—")
                    metric("Active elapsed", clock(run.elapsedSeconds))
                    metric("Measured intervals", clock(run.observedSeconds))
                }
                NoopCard {
                    DisclosureGroup("Source and zone method") {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("WHOOP · \(run.readableSamples) readable samples")
                            Text(run.target.method)
                            Text("Device: \(run.deviceId)")
                            Text("This saved zone session contains summary values. No raw session HR trace was saved.")
                        }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }.font(StrandFont.subhead)
                }
            }
            .navigationTitle("\(run.target.name) run").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        NoopCard { VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(value).font(StrandFont.title2).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(max(0, seconds)) / 60, Int(max(0, seconds)) % 60) }
}
