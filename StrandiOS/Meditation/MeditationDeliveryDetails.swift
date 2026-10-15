#if os(iOS)
import SwiftUI
import StrandDesign

struct MeditationDeliveryDetails: View {
    @EnvironmentObject private var meditation: MeditationController
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text(alertDetails).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep your phone nearby. Locked-screen cues are best-effort through Bluetooth; no workout alarm is armed on WHOOP. Missed transitions or disconnection pause the workout. Reopen Dhoop after force-quitting.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("No buzzes outside the range. Goal completion cues repeat every ten seconds for up to three minutes or until stopped. No wake alarms are changed.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
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
        return String(localized: "The screen stays awake while Dhoop is foregrounded. The completion cue is scheduled in Dhoop, not on the strap. Background Bluetooth events may allow delivery while locked; suspension, disconnection, or force-quit can prevent it. No late cue is replayed. Wake alarms remain unchanged.") + " " + fallback
    }
}
#endif
