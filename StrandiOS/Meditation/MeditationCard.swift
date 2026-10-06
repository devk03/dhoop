#if os(iOS)
import SwiftUI
import StrandDesign

struct MeditationCard: View {
    @EnvironmentObject private var meditation: MeditationController
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber

    var body: some View {
        StrandCard(padding: NoopMetrics.space4, cornerRadius: NoopMetrics.cardRadius) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space3) {
                    Image(systemName: "leaf").foregroundStyle(StrandPalette.metricPurple)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Meditation").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text("15 minutes · Quiet focus")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: NoopMetrics.space2)
                    if !meditation.session.isInProgress {
                        action("Start", icon: "play.fill", perform: meditation.start)
                    }
                }
                if meditation.session.phase == .running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in countdown(at: context.date) }
                } else if meditation.session.phase == .paused {
                    countdown(at: Date())
                }
                if meditation.session.isInProgress { controls }
                if let completionMessage {
                    Text(completionMessage).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if let error = meditation.storageError {
                    Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry storage", action: meditation.retryStorage)
                        .font(StrandFont.caption).frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                DisclosureGroup {
                    Text(alertDetails)
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text("Keep Dhoop open for the WHOOP buzz; iPhone notification when locked, if enabled.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                .tint(StrandPalette.metricPurple)
            }
        }
    }

    private func countdown(at now: Date) -> some View {
        let remaining = meditation.session.remaining(at: now)
        let seconds = Int(ceil(remaining))
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(StrandFont.number(numberSize, weight: .semibold))
                    .monospacedDigit().foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityLabel("\(seconds / 60) minutes, \(seconds % 60) seconds remaining")
                if meditation.session.phase == .paused {
                    Text("Paused").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            ProgressView(value: 1 - remaining / MeditationSession.duration)
                .tint(StrandPalette.metricPurple).accessibilityLabel("Meditation progress")
        }
    }

    private var controls: some View {
        HStack(spacing: NoopMetrics.space3) {
            if meditation.session.phase == .running {
                action("Pause", icon: "pause.fill", perform: meditation.pause)
            } else {
                action("Resume", icon: "play.fill", perform: meditation.resume)
            }
            Button("Cancel", action: meditation.cancel)
                .font(StrandFont.subhead).buttonStyle(.bordered).tint(StrandPalette.textSecondary)
                .frame(minHeight: NoopMetrics.minimumTouchTarget)
        }
    }

    private func action(_ title: LocalizedStringKey, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Label(title, systemImage: icon) }
            .font(StrandFont.subhead).buttonStyle(.borderedProminent).tint(StrandPalette.metricPurple)
            .frame(minHeight: NoopMetrics.minimumTouchTarget)
    }

    private var completionMessage: String? {
        switch meditation.session.completionAlert {
        case .buzzRequested:
            return String(localized: "Complete · WHOOP buzz requested. Delivery is not confirmed.")
        case .strapUnavailable:
            return String(localized: "Complete · WHOOP was not ready. No buzz requested.")
        case .missedWhileAway:
            return String(localized: "Complete · App was away or delayed. No late buzz requested.")
        case nil: return nil
        }
    }

    private var alertDetails: String {
        let fallback: String
        switch meditation.notificationStatus {
        case .scheduled: fallback = String(localized: "The iPhone notification is scheduled.")
        case .unavailable: fallback = String(localized: "iPhone notifications are off. Enable them in Settings for a fallback.")
        case .failed: fallback = String(localized: "The iPhone notification could not be scheduled.")
        case .checking: fallback = String(localized: "Checking iPhone notification availability.")
        case .none: fallback = String(localized: "The iPhone notification requires permission. Pausing or cancelling clears it.")
        }
        return String(localized: "The screen stays awake during an active session. A WHOOP buzz needs the connected, ready strap and the app in the foreground. Background strap buzz is not guaranteed; no strap alarm is scheduled.") + " " + fallback
    }
}
#endif
