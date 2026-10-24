#if os(iOS)
import SwiftUI
import StrandDesign

struct DhoopTimerPanel: View {
    @ObservedObject var timer: DhoopTimerController
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var hours = 0
    @State private var minutes = 10
    @State private var seconds = 0
    @State private var backup = false
    @State private var details = false
    @ScaledMetric(relativeTo: .largeTitle) private var number = NoopMetrics.alarmTimeNumber
    private var duration: Int { hours * 3600 + minutes * 60 + seconds }
    var body: some View {
        VStack(spacing: NoopMetrics.space4) {
            if timer.session.inProgress {
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    let remaining = timer.session.remaining(at: clock.date)
                    if typeSize.isAccessibilitySize {
                        Text(time(remaining)).font(StrandFont.title2).monospacedDigit()
                        ProgressView(value: remaining / Double(timer.session.duration)).tint(StrandPalette.alarmAccent)
                    } else {
                        ZStack {
                            Circle().stroke(StrandPalette.hairline, lineWidth: NoopMetrics.sleepGoalStroke)
                            Circle().trim(from: 0, to: remaining / Double(timer.session.duration))
                                .stroke(StrandPalette.alarmAccent, style: StrokeStyle(lineWidth: NoopMetrics.sleepGoalStroke, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: NoopMetrics.space2) {
                                Text(timer.session.phase == .paused ? "Paused" : "WHOOP timer")
                                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                                Text(time(remaining)).font(StrandFont.number(number)).monospacedDigit()
                            }
                        }.frame(width: NoopMetrics.timerRingDiameter, height: NoopMetrics.timerRingDiameter)
                        .accessibilityElement(children: .ignore).accessibilityLabel("WHOOP timer")
                        .accessibilityValue(Text("\(Int(ceil(remaining))) seconds remaining"))
                    }
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: NoopMetrics.space3)) : AnyLayout(HStackLayout(spacing: NoopMetrics.space3))
                layout {
                    if timer.session.phase == .running { action("Pause", icon: "pause.fill", perform: timer.pause) }
                    else { action("Resume", icon: "play.fill", perform: timer.resume) }
                    action("Cancel", icon: "xmark", kind: .secondary, perform: timer.cancel)
                }
            } else {
                if timer.session.phase == .completed { Text("Timer finished").font(StrandFont.title2) }
                if typeSize.isAccessibilitySize {
                    Stepper("\(hours) hours", value: $hours, in: 0...23)
                    Stepper("\(minutes) minutes", value: $minutes, in: 0...59)
                    Stepper("\(seconds) seconds", value: $seconds, in: 0...59)
                } else {
                    HStack(spacing: 0) {
                        wheel("Hours", value: $hours, range: 0...23, suffix: String(localized: "h"))
                        wheel("Minutes", value: $minutes, range: 0...59, suffix: String(localized: "min"))
                        wheel("Seconds", value: $seconds, range: 0...59, suffix: String(localized: "sec"))
                    }.frame(height: NoopMetrics.timerPickerHeight)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NoopMetrics.space2) {
                        ForEach([1, 5, 15, 30], id: \.self) { value in
                            Button { hours = 0; minutes = value; seconds = 0 } label: { Text("\(value) min").fixedSize() }
                                .buttonStyle(NoopButtonStyle(.secondary))
                        }
                    }
                }
                action("Start timer", icon: "play.fill", perform: { timer.start(seconds: duration, backup: backup) }).disabled(duration == 0)
            }
            if let error = timer.error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
            NoopCard(padding: NoopMetrics.space3) {
                VStack(spacing: NoopMetrics.space2) {
                    HStack {
                        Text(LocalizedStringKey(timer.deliveryText)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        Spacer(minLength: NoopMetrics.space1)
                        Button { details = true } label: { Image(systemName: "info.circle") }
                            .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Timer delivery details")
                    }
                    if !timer.session.inProgress {
                        Toggle("iPhone backup", isOn: $backup).font(StrandFont.subhead).toggleStyle(NoopSwitchStyle())
                    }
                }
            }
        }
        .onAppear {
            hours = timer.session.duration / 3600; minutes = timer.session.duration / 60 % 60; seconds = timer.session.duration % 60
            backup = timer.session.phoneBackup
        }
        .sheet(isPresented: $details) {
            NavigationStack {
                ScreenScaffold(title: "Timer delivery") {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Keep Dhoop open for the WHOOP countdown buzz. The screen stays awake while this timer runs.").font(StrandFont.body)
                        Text("Locked or background delivery is best effort. A suspended or force-quit app cannot guarantee the buzz.").font(StrandFont.body)
                        Text("Wake alarms are never changed. Another workout or a wake alarm can take priority.").font(StrandFont.body)
                        Text("iPhone backup is an optional phone notification, not a WHOOP vibration. Focus or silent mode may mute it.").font(StrandFont.body)
                        if let cue = timer.cue { Text(verbatim: cue.detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                        if let status = timer.phoneStatus { Text(LocalizedStringKey(status)).font(StrandFont.caption) }
                        if let error = timer.error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                    }
                }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { details = false } } }
            }
        }
    }
    private func wheel(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        Picker(title, selection: value) {
            ForEach(Array(range), id: \.self) { number in
                let label = String(number) + " " + suffix
                Text(verbatim: label).tag(number)
            }
        }.pickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity).clipped().accessibilityLabel(title)
    }
    private func time(_ remaining: TimeInterval) -> String {
        let total = Int(ceil(remaining))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
    private struct ActionFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
    private func action(_ title: LocalizedStringKey, icon: String, kind: NoopButtonKind = .primary, perform: @escaping () -> Bool) -> some View {
        NoopAsyncButton(title, systemImage: icon, kind: kind, fullWidth: true) {
            guard perform() else { throw ActionFailure(message: timer.error ?? "Timer change was not applied.") }
        }
    }
}
#endif
