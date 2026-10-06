#if os(iOS)
import SwiftUI
import StrandDesign

struct MeditationCard: View {
    @EnvironmentObject private var meditation: MeditationController
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber

    var body: some View {
        StrandCard(padding: NoopMetrics.space4, cornerRadius: NoopMetrics.cardRadius) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "leaf").foregroundStyle(StrandPalette.metricPurple)
                    Text("Meditation").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: NoopMetrics.space2)
                    Text(phaseLabel).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if meditation.session.phase == .running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in countdown(at: context.date) }
                } else {
                    countdown(at: Date())
                }
                controls
                Text(alertMessage)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var phaseLabel: LocalizedStringKey {
        switch meditation.session.phase {
        case .idle, .cancelled: return "15 minutes"
        case .running: return "In progress"
        case .paused: return "Paused"
        case .completed: return "Complete"
        }
    }

    private func countdown(at now: Date) -> some View {
        let remaining = meditation.session.phase == .cancelled
            ? MeditationSession.duration : meditation.session.remaining(at: now)
        let seconds = Int(ceil(remaining))
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(StrandFont.number(numberSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityLabel("\(seconds / 60) minutes, \(seconds % 60) seconds remaining")
                Text(meditation.session.phase == .completed ? "Take a breath." : "A moment of quiet.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            if meditation.session.isInProgress {
                ProgressView(value: 1 - remaining / MeditationSession.duration)
                    .tint(StrandPalette.metricPurple)
                    .accessibilityLabel("Meditation progress")
            }
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: NoopMetrics.space3) {
            if meditation.session.phase == .running {
                action("Pause", icon: "pause.fill", perform: meditation.pause)
            } else if meditation.session.phase == .paused {
                action("Resume", icon: "play.fill", perform: meditation.resume)
            } else {
                action("Start 15 minutes", icon: "play.fill", perform: meditation.start)
            }
            if meditation.session.isInProgress {
                Button("Cancel", action: meditation.cancel)
                    .font(StrandFont.subhead)
                    .buttonStyle(.bordered)
                    .tint(StrandPalette.textSecondary)
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
        }
    }

    private func action(_ title: LocalizedStringKey, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Label(title, systemImage: icon).frame(maxWidth: .infinity) }
            .font(StrandFont.subhead)
            .buttonStyle(.borderedProminent)
            .tint(StrandPalette.metricPurple)
            .frame(minHeight: NoopMetrics.minimumTouchTarget)
    }

    private var alertMessage: String {
        if let alert = meditation.session.completionAlert {
            switch alert {
            case .buzzRequested:
                return String(localized: "Finished. One strap buzz was requested; delivery is not confirmed.")
            case .strapUnavailable:
                return String(localized: "Finished. The strap was not ready, so no buzz was requested.")
            case .missedWhileAway:
                return String(localized: "Finished while the app was away or delayed. No late strap buzz was requested.")
            }
        }
        if meditation.session.phase == .paused {
            return String(localized: "Timer paused. The completion notification has been cleared.")
        }
        let fallback: String
        switch meditation.notificationStatus {
        case .scheduled: fallback = String(localized: "An iPhone notification is scheduled as a fallback.")
        case .unavailable: fallback = String(localized: "iPhone notifications are off. Enable them in Settings for a fallback.")
        case .failed: fallback = String(localized: "The iPhone notification could not be scheduled.")
        case .checking: fallback = String(localized: "Checking iPhone notification availability.")
        case .none: fallback = String(localized: "An iPhone notification can provide a fallback when permitted.")
        }
        return String(localized: "One strap buzz at completion while the app is active and the strap is ready. Background strap buzz is not guaranteed.") + " " + fallback
    }
}
#endif
