import SwiftUI
import StrandDesign

/// The host reads the app reference; the content subscribes only to this explicit running session.
struct RunningView: View {
    let controller: RunningSessionController
    @EnvironmentObject private var app: AppModel

    var body: some View {
        RunningContent(controller: controller, hiit: controller.hiit).equatable()
            .onAppear { controller.configure(app: app) }
            .task { if !controller.hasSession { await controller.refreshBaseline() } }
    }
}

private struct RunningContent: View, Equatable {
    @ObservedObject var controller: RunningSessionController
    @ObservedObject var hiit: HIITController
    @State private var workoutMode = "Zone run"
    @State private var section = "Train"
    @State private var historyRange: MetricRangeSelection = { var range = MetricRangeSelection(); range.preset = .month; return range }()
    @State private var capturedAt = Date()
    @State private var discardRunID: UUID?
    @StateObject private var history = CardioHistoryModel()
    @EnvironmentObject private var repo: Repository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.controller === rhs.controller }

    var body: some View {
        ScreenScaffold(title: nil, onRefresh: { capturedAt = Date(); await repo.refresh() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space3) {
                    if section != "Train" {
                        Button { section = "Train" } label: {
                            Image(systemName: "arrow.left").frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                        }.accessibilityLabel("Back to training")
                    }
                    Text(section == "Train" ? "Cardio" : section).font(StrandFont.title1)
                    Spacer(minLength: 0)
                    if section == "Train" {
                        Button("History") { section = "History" }.font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        Button("Review") { section = "Review" }.font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    }
                }
                if section == "History" {
                    CardioHistoryView(model: history, range: $historyRange, now: capturedAt, controller: controller)
                } else if section == "Review" {
                    CardioDetectionView(localSpans: history.localSpans, sessionActive: controller.hasSession || history.loading)
                } else {
                    if controller.session == nil && !hiit.hasSession {
                        NoopSegmentedControl("Workout type", options: ["Zone run", "HIIT", "Intervals"], selection: $workoutMode)
                    }
                    if hiit.hasSession || (controller.session == nil && workoutMode != "Zone run") {
                        HIITWorkoutView(controller: hiit, zones: controller.zones, canStart: controller.isConnected && controller.session == nil,
                            testBuzz: { controller.testBuzz() }, canTestBuzz: controller.strapAlertsReady && controller.workoutHapticsEnabled,
                            buzzFeedback: controller.buzzTestMessage)
                    } else {
                        if let run = controller.session { sessionCard(run) } else { setupCard }
                        if controller.session != nil { alertsCard }
                        if let message = controller.statusMessage, controller.session?.phase != .running {
                            Text(message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }

                }
            }
        }
        .onAppear { capturedAt = Date() }
        .confirmationDialog("Discard this workout?", isPresented: Binding(get: { discardRunID != nil }, set: { if !$0 { discardRunID = nil } }), titleVisibility: .visible, presenting: discardRunID) { id in
            Button("Discard workout", role: .destructive) { controller.discard(id: id) }
            Button("Keep workout", role: .cancel) { }
        } message: { _ in Text("The unfinished session will not be saved. Heart-rate history is kept.") }
        .onChange(of: section) { _, value in if value == "History" { capturedAt = Date() } }
        .onChange(of: controller.summaries.count) { _, _ in capturedAt = Date() }
        .onChange(of: hiit.historyRevision) { _, _ in capturedAt = Date() }
        .onChange(of: repo.refreshSeq) { _, _ in capturedAt = Date() }
        .onChange(of: workoutMode) { _, mode in
            if mode != "Zone run" { hiit.selectKind(mode == "Intervals" ? .intervals : .hiit) }
        }
        .task(id: "\(repo.refreshSeq)|\(repo.deviceId)|\(controller.summaries.count)|\(hiit.historyRevision)|\(historyRange.window(now: capturedAt).identity)") {
            await history.load(repo: repo, zones: controller.summaries, window: historyRange.window(now: capturedAt))
        }
    }

    private var setupCard: some View {
        NoopCard(padding: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack {
                    Text(controller.chosenTarget?.name ?? "Set your target").font(StrandFont.title2)
                    Spacer()
                    Label(controller.isConnected ? "Connected" : "Connect WHOOP", systemImage: "circle.fill")
                        .font(StrandFont.caption).foregroundStyle(controller.isConnected ? StrandPalette.statusPositive : StrandPalette.textSecondary)
                }
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("Target heart rate").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text(controller.chosenTarget?.rangeLabel ?? "Choose BPM below")
                        .font(StrandFont.title1).monospacedDigit().foregroundStyle(StrandPalette.textPrimary)
                    Text("Only time in this range counts toward your goal.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack {
                        Text("Time in zone").font(StrandFont.subhead)
                        Spacer()
                        Text("\(controller.targetMinutes) min").font(StrandFont.headline).monospacedDigit()
                    }
                    let presetLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: NoopMetrics.space2))
                        : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
                    presetLayout {
                        ForEach([20, 30, 45, 60], id: \.self) { minutes in
                            Button { controller.targetMinutes = minutes } label: {
                                Text("\(minutes)m").font(StrandFont.subhead).monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                                    .foregroundStyle(controller.targetMinutes == minutes ? NoopVisualStyle.selectedControlInk : StrandPalette.textSecondary)
                                    .background(controller.targetMinutes == minutes ? NoopVisualStyle.selectedControlFill : StrandPalette.surfaceInset,
                                                in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
                            }.buttonStyle(.plain).accessibilityLabel("\(minutes) minutes in zone")
                                .accessibilityAddTraits(controller.targetMinutes == minutes ? .isSelected : [])
                        }
                    }
                    DisclosureGroup("Custom duration") {
                        Stepper("\(controller.targetMinutes) minutes", value: $controller.targetMinutes, in: 1...180)
                            .font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                Toggle("WHOOP buzz alerts", isOn: $controller.alertsEnabled).font(StrandFont.subhead).tint(StrandPalette.accent)
                Text(alertReadiness).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Button { controller.start() } label: {
                    Label("Start \(controller.chosenTarget?.name ?? "run")", systemImage: "play.fill")
                        .font(StrandFont.headline).frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight)
                }.buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                    .disabled(!controller.canStart)
                if let reason = controller.startBlockedReason {
                    Text(reason).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                DisclosureGroup("Target settings & strap test", isExpanded: $showTargetSettings) {
                    targetSettings
                }.font(StrandFont.subhead)
            }
        }
        .onChange(of: controller.isLoadingBaseline) { _, loading in
            if !loading && controller.zones.isEmpty { showTargetSettings = true }
        }
        .onAppear { if !controller.isLoadingBaseline && controller.zones.isEmpty { showTargetSettings = true } }
    }

    @State private var showTargetSettings = false
    private var alertReadiness: String {
        if !controller.alertsEnabled { return "Buzz alerts are off." }
        if !controller.workoutHapticsEnabled { return "Workout haptics are off in Settings." }
        if !controller.strapAlertsReady { return "Connect and pair WHOOP to enable strap buzzes." }
        return "After you enter the target, a buzz cues sustained readings outside it."
    }

    private var targetSettings: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            if !controller.zones.isEmpty {
                Toggle("Manual BPM target", isOn: $controller.useManualTarget).font(StrandFont.subhead)
                if !controller.useManualTarget {
                    Picker("Zone", selection: $controller.selectedZone) {
                        ForEach(Array(controller.zones.enumerated()), id: \.offset) { index, zone in
                            Text("\(zone.name) · \(zone.rangeLabel)").tag(index + 1)
                        }
                    }.pickerStyle(.menu).frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
            }
            if controller.useManualTarget || controller.zones.isEmpty {
                Stepper("Minimum · \(controller.manualLowerBPM) bpm", value: $controller.manualLowerBPM, in: 30...max(30, controller.manualUpperBPM - 1))
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                Stepper("Maximum · \(controller.manualUpperBPM - 1) bpm",
                        value: Binding(get: { controller.manualUpperBPM - 1 }, set: { controller.manualUpperBPM = $0 + 1 }),
                        in: min(219, controller.manualLowerBPM)...219)
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
            if controller.useManualTarget || controller.selectedZone != 2, controller.zones.count >= 2 {
                Button("Use estimated Zone 2") { controller.useManualTarget = false; controller.selectedZone = 2 }
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
            Text(controller.baselineDescription).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Button("Test WHOOP buzz") { controller.testBuzz() }.buttonStyle(.bordered)
                .frame(minHeight: NoopMetrics.minimumTouchTarget)
                .disabled(!controller.strapAlertsReady || !controller.workoutHapticsEnabled)
            if let message = controller.buzzTestMessage { Text(message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
        }.font(StrandFont.subhead).padding(.top, NoopMetrics.space2)
    }

    private func sessionCard(_ run: RunningZoneSession) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack {
                    Text(run.target.name).font(StrandFont.title2)
                    Spacer()
                    Text(phaseLabel(run.phase)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Menu {
                        Button("Discard workout", role: .destructive) { discardRunID = run.id }
                    } label: {
                        Image(systemName: "ellipsis").frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                    }.accessibilityLabel("Workout actions")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(controller.currentBPM.map { "\($0)" } ?? "—").font(StrandFont.number(numberSize, weight: .semibold))
                    Text("bpm").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text(zoneStatus(run)).font(StrandFont.headline).foregroundStyle(zoneTint(run))
                }
                Text("Target · \(run.target.rangeLabel)").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Divider()
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("TIME IN ZONE").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                        Text(clock(run.inZoneSeconds)).font(StrandFont.number(numberSize, weight: .semibold))
                        Text("/ \(Int(run.goalSeconds / 60)) min").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }.accessibilityElement(children: .combine).accessibilityLabel("\(durationLabel(run.inZoneSeconds)) of \(Int(run.goalSeconds / 60)) minutes in zone")
                    ProgressView(value: run.inZoneSeconds, total: run.goalSeconds).tint(StrandPalette.accent)
                        .accessibilityLabel("In-zone goal progress")
                }
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space3))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space3))
                layout {
                    smallMetric("Elapsed", value: clock(controller.elapsedSeconds))
                    smallMetric("Average", value: run.averageBPM.map { "\(Int($0.rounded())) bpm" } ?? "—")
                    smallMetric("Peak", value: run.maximumBPM.map { "\($0) bpm" } ?? "—")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoopMetrics.space3) { sessionButtons(run) }
                    VStack(spacing: NoopMetrics.space3) { sessionButtons(run) }
                }
                DisclosureGroup("Session details") {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("\(run.readableSamples.formatted()) readable samples · \(durationLabel(run.observedSeconds)) of usable intervals")
                        Text(run.target.method)
                        Text("Warm-up, time outside your target and missing readings do not advance the in-zone goal.")
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }.font(StrandFont.subhead)
            }
        }
    }

    private func zoneStatus(_ run: RunningZoneSession) -> String {
        if run.phase == .completed { return "Goal reached" }
        if run.phase != .running { return phaseLabel(run.phase) }
        guard let bpm = controller.currentBPM else { return "Waiting for HR" }
        if run.target.contains(bpm) { return "In zone" }
        return bpm < run.target.lowerBPM ? "Below target" : "Above target"
    }
    private func zoneTint(_ run: RunningZoneSession) -> Color {
        guard run.phase == .running, let bpm = controller.currentBPM else { return StrandPalette.textSecondary }
        return run.target.contains(bpm) ? StrandPalette.statusPositive : StrandPalette.metricAmber
    }

    @ViewBuilder private func sessionButtons(_ run: RunningZoneSession) -> some View {
        if run.phase == .running {
            Button("Pause") { controller.pause() }
                .buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
        } else if run.phase == .paused {
            Button("Resume") { controller.resume() }
                .buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan)
                .frame(minHeight: NoopMetrics.minimumTouchTarget).disabled(!controller.isConnected)
        }
        Button(run.phase == .completed ? "Save run" : "Finish & save") { controller.endAndSave() }
            .buttonStyle(.borderedProminent).tint(StrandPalette.accent).frame(minHeight: NoopMetrics.minimumTouchTarget)
    }

    private var alertsCard: some View {
        NoopCard(padding: NoopMetrics.space3) {
            DisclosureGroup("WHOOP alerts") {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Toggle("Buzz outside target", isOn: $controller.alertsEnabled).tint(StrandPalette.accent)
                    Text(alertReadiness).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text("At least 3 seconds outside; 30 seconds between cues. Missing readings never buzz.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Button("Test WHOOP buzz") { controller.testBuzz() }.buttonStyle(.bordered)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget).disabled(!controller.strapAlertsReady || !controller.workoutHapticsEnabled)
                    if let message = controller.buzzTestMessage { Text(message).font(StrandFont.caption) }
                }.padding(.top, NoopMetrics.space2)
            }.font(StrandFont.subhead)
        }
    }

    private func smallMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(value).font(StrandFont.headline).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func phaseLabel(_ phase: RunningZoneSession.Phase) -> String {
        switch phase { case .running: "Running"; case .paused: "Paused"; case .completed: "Complete"; case .ended: "Ended" }
    }
    private func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    private func durationLabel(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return "\(value / 60) minutes, \(value % 60) seconds"
    }
}
