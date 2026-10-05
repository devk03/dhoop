import SwiftUI
import Charts
import StrandDesign

struct HIITWorkoutView: View {
    @ObservedObject var controller: HIITController
    let zones: [RunningZoneTarget]
    let canStart: Bool
    let testBuzz: () -> Void
    @State private var selected: HIITSession?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = NoopMetrics.dashboardHeroNumber
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var grid: DashboardGridLayout { DashboardGridLayout(columns: typeSize.isAccessibilitySize ? 1 : 2) }

    var body: some View {
        if let run = controller.session { active(run) } else { setup }
        if let message = controller.message {
            Label(message, systemImage: "wave.3.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Keep your phone nearby and Dhoop open for reliable cues. HIIT pauses if iOS interrupts timing or WHOOP disconnects.")
            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        if !controller.saved.isEmpty { history }
    }
    private var setup: some View {
        Group {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                        Text("Custom intervals").font(StrandFont.headline)
                        Spacer(minLength: NoopMetrics.space1)
                        Text(clock(Double(controller.plan.totalSeconds))).font(StrandFont.headline).monospacedDigit()
                    }
                    Text("\(controller.plan.rounds) rounds · work and recovery").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            grid {
                durationTile("Work", value: $controller.plan.workSeconds, tint: StrandPalette.metricAmber)
                durationTile("Recovery", value: $controller.plan.restSeconds, tint: StrandPalette.metricCyan)
            }
            NoopCard {
                VStack(spacing: NoopMetrics.space3) {
                    Stepper("Warm-up · \(clock(Double(controller.plan.warmupSeconds)))", value: $controller.plan.warmupSeconds, in: 0...900, step: 30)
                    Divider()
                    Stepper("Cool-down · \(clock(Double(controller.plan.cooldownSeconds)))", value: $controller.plan.cooldownSeconds, in: 0...900, step: 30)
                    Divider()
                    Stepper("Rounds · \(controller.plan.rounds)", value: $controller.plan.rounds, in: 1...30)
                }.font(StrandFont.body).monospacedDigit()
            }
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Toggle("Vibration cues", isOn: $controller.cuesEnabled).font(StrandFont.headline).tint(StrandPalette.metricCyan)
                    Text("Short: work · Longer: recovery · Longest: finished").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text("Warm-up and cool-down use the recovery cue. Workout haptics must be on in Settings.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Button("Test WHOOP buzz", action: testBuzz).font(StrandFont.subhead).buttonStyle(.bordered)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
            }
            Button { controller.start(zones: zones, otherSessionActive: !canStart) } label: {
                Label("Start HIIT", systemImage: "play.fill").font(StrandFont.headline)
                    .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
            }.buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan).disabled(!canStart || !controller.plan.isValid)
            if !canStart { Text("Connect and pair your WHOOP to start.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            if !controller.plan.isValid { Text("Choose a workout of three hours or less.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
        }
    }
    private func durationTile(_ title: String, value: Binding<Int>, tint: Color) -> some View {
        NoopCard(tint: tint) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label(title, systemImage: title == "Work" ? "flame.fill" : "wind").font(StrandFont.headline).foregroundStyle(tint)
                Text(clock(Double(value.wrappedValue))).font(StrandFont.number(numberSize, weight: .bold)).monospacedDigit()
                HStack {
                    Button { value.wrappedValue = max(15, value.wrappedValue - 15) } label: {
                        Image(systemName: "minus").frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                    }.accessibilityLabel("Decrease \(title.lowercased()) by 15 seconds").disabled(value.wrappedValue <= 15)
                    Spacer(minLength: NoopMetrics.space1)
                    Button { value.wrappedValue = min(600, value.wrappedValue + 15) } label: {
                        Image(systemName: "plus").frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                    }.accessibilityLabel("Increase \(title.lowercased()) by 15 seconds").disabled(value.wrappedValue >= 600)
                }.buttonStyle(.bordered).tint(tint)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
    private func active(_ run: HIITSession) -> some View {
        let tint = run.interval?.kind == .work ? StrandPalette.metricAmber : StrandPalette.metricCyan
        return Group {
            NoopCard(tint: tint) {
                VStack(spacing: NoopMetrics.space3) {
                    Text(run.interval?.label ?? "Intervals complete").font(StrandFont.title2).foregroundStyle(tint)
                    Text(clock(Double(run.remaining))).font(StrandFont.number(timerSize, weight: .bold)).monospacedDigit()
                        .accessibilityLabel("\(run.remaining) seconds remaining in interval")
                    Text(run.state == .paused ? "Paused" : run.state == .completed ? "Workout finished" : nextLabel(run)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    ProgressView(value: run.elapsed, total: Double(run.plan.totalSeconds)).tint(tint)
                        .accessibilityLabel("HIIT workout progress")
                }.frame(maxWidth: .infinity)
            }
            grid {
                statTile("Heart rate", value: controller.currentBPM.map(String.init) ?? "—", detail: controller.currentBPM == nil ? "No fresh reading" : "bpm · WHOOP", symbol: "heart", tint: StrandPalette.metricRose)
                statTile("Elapsed", value: clock(run.elapsed), detail: "of \(clock(Double(run.plan.totalSeconds)))", symbol: "stopwatch", tint: StrandPalette.metricCyan)
            }
            if run.state == .running {
                Button { controller.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget) }
                    .buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan)
            } else if run.state == .paused {
                Button { controller.resume() } label: { Label("Resume HIIT", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget) }
                    .buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan).disabled(!canStart)
            }
            Button { controller.save() } label: { Label("End and save", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget) }
                .buttonStyle(.bordered)
        }
    }
    private func statTile(_ title: String, value: String, detail: String, symbol: String, tint: Color) -> some View {
        NoopCard(tint: tint) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label(title, systemImage: symbol).font(StrandFont.subhead).foregroundStyle(tint)
                Text(value).font(StrandFont.number(numberSize, weight: .bold)).monospacedDigit()
                Text(detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).accessibilityElement(children: .combine)
        }
    }
    private var history: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Recent HIIT workouts").font(StrandFont.headline)
                ForEach(controller.saved.prefix(20)) { run in
                    Button { selected = run } label: {
                        HStack(spacing: NoopMetrics.space2) {
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).font(StrandFont.subhead)
                                Text("\(run.plan.rounds) rounds planned · \(clock(run.elapsed)) · \(run.state == .completed ? "complete" : "ended early")")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            Spacer(minLength: NoopMetrics.space1)
                            Image(systemName: "chevron.right")
                        }.frame(minHeight: NoopMetrics.minimumTouchTarget)
                    }.buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selected) { HIITReviewView(run: $0) }
    }
    private func nextLabel(_ run: HIITSession) -> String {
        guard let current = run.interval, let next = run.plan.intervals.first(where: { $0.index == current.index + 1 }) else { return "Finish this interval" }
        return "Next · \(next.kind.label) for \(clock(Double(next.duration)))"
    }
    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

private struct HIITReviewView: View {
    let run: HIITSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber
    private var total: HIITEffort { run.effort() }
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                Text("\(run.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(run.state == .completed ? "Completed" : "Ended early")")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                NoopCard(tint: StrandPalette.metricRose) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Recorded heart rate").font(StrandFont.headline)
                        if run.points.isEmpty { Text("No readable HR recorded").font(StrandFont.body) }
                        else { effortChart }
                    }
                }
                DashboardGridLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, squareMinimum: false) {
                    metric("Average HR", value: total.average.map { String(Int($0.rounded())) } ?? "—")
                    metric("Peak HR", value: total.peak.map(String.init) ?? "—")
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("Measurement coverage").font(StrandFont.headline)
                        Text("\(clock(total.observedSeconds)) of \(clock(run.elapsed)) measured · \(total.sampleCount) samples")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        ProgressView(value: min(total.observedSeconds, run.elapsed), total: max(1, run.elapsed)).tint(StrandPalette.metricCyan)
                    }
                }
                if !run.zones.isEmpty { zoneCard }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Intervals").font(StrandFont.headline)
                        ForEach(run.plan.intervals.filter { Double($0.start) < run.elapsed }) { phase in
                            let value = run.effort(interval: phase.index)
                            DisclosureGroup {
                                Text("\(clock(value.observedSeconds)) measured of \(clock(min(Double(phase.duration), run.elapsed - Double(phase.start)))) active")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Text("Average \(value.average.map { String(Int($0.rounded())) } ?? "—") bpm · Peak \(value.peak.map(String.init) ?? "—") bpm")
                                    .font(StrandFont.body)
                            } label: {
                                Text(phase.label).font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
                            }.tint(phase.kind == .work ? StrandPalette.metricAmber : StrandPalette.metricCyan)
                        }
                    }
                }
                Text("WHOOP heart-rate response, not a validated strain or calorie score. Missing HR remains unknown.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            .navigationTitle("HIIT effort").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(value).font(StrandFont.number(numberSize, weight: .bold)).monospacedDigit()
                Text("bpm").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
        }
    }
    private var zoneCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Time in heart-rate zones").font(StrandFont.headline)
                ForEach(Array(run.zones.enumerated()), id: \.offset) { i, zone in
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        HStack {
                            Text("\(zone.name) · \(zone.rangeLabel)")
                            Spacer(minLength: NoopMetrics.space1)
                            Text(clock(total.zoneSeconds[i])).monospacedDigit()
                        }.font(StrandFont.caption)
                        ProgressView(value: total.zoneSeconds[i], total: max(1, total.observedSeconds)).tint(StrandPalette.metricCyan)
                    }.accessibilityElement(children: .combine)
                }
                Text(run.zones.first?.method ?? "").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Boundary crossings and gaps are excluded from zone time.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private var effortChart: some View {
        let points = DashboardTraceSampling.reduce(run.points.map { TrendPoint(date: Date(timeIntervalSince1970: $0.elapsed), value: Double($0.bpm), segment: String($0.segment)) })
        let lower = Double((run.points.map(\.bpm).min() ?? 30) - 5)
        let upper = Double((run.points.map(\.bpm).max() ?? 220) + 5)
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Chart {
                ForEach(run.plan.intervals.filter { Double($0.start) < run.elapsed }) { phase in
                    RectangleMark(xStart: .value("Start", Double(phase.start)), xEnd: .value("End", min(Double(phase.end), run.elapsed)),
                                  yStart: .value("Minimum", lower), yEnd: .value("Maximum", upper))
                        .foregroundStyle((phase.kind == .work ? StrandPalette.metricAmber : StrandPalette.metricCyan).opacity(0.12))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Active seconds", point.date.timeIntervalSince1970), y: .value("BPM", point.value), series: .value("Observed segment", point.segment))
                        .interpolationMethod(.linear).foregroundStyle(StrandPalette.metricRose)
                    PointMark(x: .value("Active seconds", point.date.timeIntervalSince1970), y: .value("BPM", point.value))
                        .foregroundStyle(StrandPalette.metricRose).symbolSize(NoopMetrics.space1)
                }
            }
            .chartXScale(domain: 0...max(1, run.elapsed)).chartYScale(domain: lower...upper).chartLegend(.hidden)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel { if let seconds = value.as(Double.self) { Text(clock(seconds)).font(StrandFont.caption) } }
            } }
            .frame(height: NoopMetrics.chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("WHOOP heart-rate timeline by active workout time, \(run.points.count) readings. Missing samples remain gaps; pauses are excluded from the time axis.")
            HStack(spacing: NoopMetrics.space3) {
                Label("Work", systemImage: "square.fill").foregroundStyle(StrandPalette.metricAmber)
                Label("Recovery", systemImage: "square.fill").foregroundStyle(StrandPalette.metricCyan)
            }.font(StrandFont.caption)
        }
    }
    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
