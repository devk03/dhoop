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
    @StateObject private var history = CardioHistoryModel()
    @EnvironmentObject private var repo: Repository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.controller === rhs.controller }

    var body: some View {
        ScreenScaffold(title: nil, onRefresh: { capturedAt = Date(); await repo.refresh() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Cardio").font(StrandFont.title1)
                Picker("Cardio section", selection: $section) {
                    Text("Train").tag("Train")
                    Text("History").tag("History")
                }.pickerStyle(.segmented).frame(minHeight: NoopMetrics.minimumTouchTarget)
                if section == "History" {
                    CardioHistoryView(model: history, range: $historyRange, now: capturedAt)
                } else {
                    if controller.session == nil && !hiit.hasSession {
                        Picker("Workout type", selection: $workoutMode) {
                            Text("Zone run").tag("Zone run")
                            Text("HIIT").tag("HIIT")
                            Text("Intervals").tag("Intervals")
                        }.pickerStyle(.segmented).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    }
                    if hiit.hasSession || (controller.session == nil && workoutMode != "Zone run") {
                        HIITWorkoutView(controller: hiit, zones: controller.zones, canStart: controller.isConnected && controller.session == nil,
                            testBuzz: { controller.testBuzz() }, canTestBuzz: controller.strapAlertsReady && controller.workoutHapticsEnabled,
                            buzzFeedback: controller.buzzTestMessage)
                    } else {
                        if let run = controller.session { sessionCard(run) } else { setupCard }
                        alertsCard
                        if let message = controller.statusMessage {
                            Text(message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    CardioDetectionView(localSpans: history.localSpans, sessionActive: controller.hasSession || history.loading)
                    Button { section = "History" } label: {
                        Label("View all cardio history", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                    }.buttonStyle(.bordered).font(StrandFont.subhead)
                }
            }
        }
        .onAppear { capturedAt = Date() }
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
        NoopCard(tint: StrandPalette.metricCyan) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Label(controller.chosenTarget?.name ?? "Zone run", systemImage: "figure.run")
                    .font(StrandFont.title2).foregroundStyle(StrandPalette.metricCyan)
                if !controller.zones.isEmpty {
                    Toggle("Choose a manual BPM target", isOn: $controller.useManualTarget).font(StrandFont.body)
                    if !controller.useManualTarget {
                        Picker("Target zone", selection: $controller.selectedZone) {
                            ForEach(Array(controller.zones.enumerated()), id: \.offset) { index, zone in
                                Text("\(zone.name) · \(zone.rangeLabel)").tag(index + 1)
                            }
                        }
                        .pickerStyle(.menu).font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    }
                }
                if controller.useManualTarget || controller.zones.isEmpty {
                    Text("Manual BPM target").font(StrandFont.headline)
                    Stepper("Lower bound: \(controller.manualLowerBPM) bpm", value: $controller.manualLowerBPM,
                            in: 30...max(30, controller.manualUpperBPM - 1))
                        .font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    Stepper("Upper bound: \(controller.manualUpperBPM) bpm", value: $controller.manualUpperBPM,
                            in: min(220, controller.manualLowerBPM + 1)...220)
                        .font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                if let target = controller.chosenTarget {
                    Text(target.rangeLabel).font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                        .accessibilityLabel("Target range \(target.rangeLabel)")
                }
                if !controller.useManualTarget && controller.selectedZone != 2 && controller.zones.count >= 2 {
                    Button("Use Zone 2 for a steady run") { controller.selectedZone = 2 }.font(StrandFont.subhead)
                }
                DisclosureGroup("Zone method") {
                    Text(controller.baselineDescription).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(StrandFont.subhead)
                Stepper("Goal: \(controller.targetMinutes) minutes in-zone", value: $controller.targetMinutes, in: 1...180)
                    .font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                Button { controller.start() } label: {
                    Label("Start zone run", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                }
                .buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan)
                .disabled(!controller.isConnected || controller.chosenTarget == nil)
                if !controller.isConnected {
                    Text("Connect and pair your WHOOP to start.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                Text("The goal counts measured time inside the target. Elapsed time is shown separately. Zone 2 is an HR target, not a prescribed running speed.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sessionCard(_ run: RunningZoneSession) -> some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Label(run.target.name, systemImage: "figure.run").font(StrandFont.title2)
                    Spacer(minLength: NoopMetrics.space1)
                    Text(phaseLabel(run.phase)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                Text(run.target.rangeLabel).font(StrandFont.headline).foregroundStyle(StrandPalette.metricCyan)
                Text(clock(run.inZoneSeconds)).font(StrandFont.number(numberSize, weight: .bold))
                    .accessibilityLabel("Observed time in target zone")
                    .accessibilityValue(durationLabel(run.inZoneSeconds))
                Text("of \(Int(run.goalSeconds / 60)) minutes in-zone").font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                ProgressView(value: run.inZoneSeconds, total: run.goalSeconds).tint(StrandPalette.metricCyan)
                    .accessibilityLabel("In-zone goal progress")
                    .accessibilityValue("\(Int(run.inZoneSeconds / run.goalSeconds * 100)) percent")
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space4))
                    : AnyLayout(DashboardPairLayout(spacing: NoopMetrics.space4))
                layout {
                    smallMetric("Current HR", value: controller.currentBPM.map { "\($0) bpm" } ?? "Unavailable")
                    smallMetric("Observed average", value: run.averageBPM.map { "\(Int($0.rounded())) bpm" } ?? "—")
                }
                layout {
                    smallMetric("Observed maximum", value: run.maximumBPM.map { "\($0) bpm" } ?? "—")
                    smallMetric("Elapsed run", value: clock(controller.elapsedSeconds))
                }
                Text(run.target.method).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(run.readableSamples.formatted()) readable samples · \(durationLabel(run.observedSeconds)) of usable intervals")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoopMetrics.space3) { sessionButtons(run) }
                    VStack(spacing: NoopMetrics.space3) { sessionButtons(run) }
                }
                if run.phase == .completed {
                    Text("Goal reached. This run’s live-feed request ended automatically.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.statusPositive)
                }
            }
        }
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
        Button("End and save") { controller.endAndSave() }
            .buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
    }

    private var alertsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Toggle("WHOOP zone alerts", isOn: $controller.alertsEnabled).font(StrandFont.headline)
                    .accessibilityHint("Buzzes the WHOOP after sustained fresh readings below or above your target zone")
                Text("After entering your target, a short strap buzz cues sustained readings below or above it. At least 3 seconds outside; at least 30 seconds between cues. Missing readings never buzz.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Test WHOOP buzz") { controller.testBuzz() }
                    .buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    .disabled(!controller.strapAlertsReady || !controller.workoutHapticsEnabled)
                if controller.isConnected && !controller.strapAlertsReady {
                    Text("WHOOP alerts need a confirmed encrypted connection. HR timing can still work without it.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !controller.workoutHapticsEnabled {
                    Text("Workout haptics are off in Settings. Zone alerts respect that preference.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
