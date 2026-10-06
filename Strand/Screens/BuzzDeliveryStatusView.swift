import SwiftUI
import StrandDesign

/// One readout for scheduled app cues, command responses, and explicit wearer confirmation.
struct BuzzDeliveryStatusView: View {
    let ble: BLEManager
    @ObservedObject var delivery: BuzzDeliveryCoordinator
    init(ble: BLEManager) { self.ble = ble; self.delivery = ble.buzzDelivery }

    private var latest: BuzzDeliveryCoordinator.Cue? {
        delivery.cues.filter { $0.requestedAt != nil }.max { ($0.requestedAt ?? .distantPast) < ($1.requestedAt ?? .distantPast) }
    }
    var body: some View {
        NoopCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Label("Background delivery · Best effort", systemImage: "clock")
                    Label("Wake alarms unchanged", systemImage: "checkmark.shield")
                    Text("Scheduled in Dhoop is not armed on WHOOP. Workout and meditation cues do not change wake alarms.")
                    Text("Locked or background: best-effort delivery during Bluetooth execution. Suspension can delay or miss timed cues. Force-quitting stops app-driven cues. Disconnection drops due cues; they are not replayed later.")
                    Text("Zone alerts require fresh heart-rate readings. Phone notifications, where enabled, are a separate fallback—not WHOOP vibration.")
                    if let owner = delivery.exclusiveOwner { Text("Cue session: \(owner)") }
                    let scheduled = delivery.cues.filter { $0.status == .scheduled }.sorted { $0.due < $1.due }
                    if let next = scheduled.first {
                        Text("Next cue in Dhoop: \(next.due.formatted(date: .abbreviated, time: .standard)) · \(scheduled.count) pending")
                    } else { Text("No timed WHOOP cue pending in Dhoop") }
                    if let last = delivery.cues.last {
                        Text("Latest event · \(last.owner): \(last.detail)")
                    }
                    if let latest, let time = latest.requestedAt {
                        Text("Last command request: \(time.formatted(date: .abbreviated, time: .standard)) · \(latest.detail)")
                        if [.requested, .responseReceived, .acknowledged].contains(latest.status) {
                            Button("I felt this buzz") { delivery.confirm(id: latest.id) }
                                .buttonStyle(NoopButtonStyle(.primary)).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        }
                    }
                    if let error = delivery.storageError {
                        Text(error).foregroundStyle(StrandPalette.statusWarning)
                        Button("Retry buzz storage") { delivery.retryStorage() }
                    }
                    Button("Test WHOOP buzz now") { ble.buzzStrapOnce() }
                        .buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    Button("Read WHOOP 5 alarm slots") { ble.readWhoop5AlarmSlots() }
                        .buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    Text("Read-only diagnostic. Six slots are documented, but safe restoration and physical timed execution remain unverified. A zero response does not prove a slot is free.")
                    ForEach(Array(delivery.alarmReadback.enumerated()), id: \.offset) { _, value in
                        Text(value).textSelection(.enabled)
                    }
                }
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Label("WHOOP alert delivery", systemImage: "wave.3.right")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(delivery.storageError == nil ? "Background · Best effort" : "Alerts unavailable · Storage error")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
}
