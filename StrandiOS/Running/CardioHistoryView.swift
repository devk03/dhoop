import SwiftUI
import StrandDesign

struct CardioHistoryView: View {
    @ObservedObject var model: CardioHistoryModel
    @Binding var range: MetricRangeSelection
    let now: Date
    @State private var kind: CardioHistoryKind?
    @State private var search = ""
    @State private var visibleCount = 40
    @State private var selected: CardioHistoryGroup?
    @State private var exportURL: URL?
    @State private var preparingExport = false
    @State private var exportError: String?
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
                            Button { selected = group } label: { row(group) }.buttonStyle(.plain)
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
        .sheet(item: $selected) { CardioHistoryDetail(group: $0, payloads: model.payloads) }
    }
    private func prepareExport() {
        guard !preparingExport else { return }
        preparingExport = true; exportError = nil; exportURL = nil
        Task {
            do { exportURL = try await CardioLocalExport.writeCopy() }
            catch { exportError = "Export failed: \(error.localizedDescription). Original records remain on this phone." }
            preparingExport = false
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
    @State private var selectedID: String?
    var body: some View {
        Group {
            switch payloads[selectedID ?? group.primary.id] {
            case .zone(let run): ZoneRunReviewView(run: run)
            case .intervals(let url): CardioIntervalFileView(url: url)
            case .recorded(let row): NavigationStack { WorkoutDetailView(row: row) }
            case nil: Text("This recording could not be opened.").font(StrandFont.body)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if group.recordings.count > 1 {
                Menu("Linked recordings") {
                    ForEach(group.recordings) { row in Button("\(row.title) · \(row.source)") { selectedID = row.id } }
                }.font(StrandFont.subhead).frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                    .background(StrandPalette.surfaceBase)
            }
        }
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
