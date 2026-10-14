#if os(iOS)
import SwiftUI
import StrandDesign

struct RemoteBuzzTestView: View {
    @ObservedObject private var receiver = RemoteBuzzReceiver.shared
    var body: some View {
        NoopCard {
            DisclosureGroup("Remote push buzz test") {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text(receiver.status).font(StrandFont.subhead)
                    Text(receiver.registrationStatus)
                    if let until = receiver.enabledUntil { Text("Test expires \(until.formatted(date: .abbreviated, time: .shortened))") }
                    if let receipt = receiver.receipt { Text(receipt).textSelection(.enabled) }
                    Text("Import the prepared test setup, then call the authenticated API while the phone is locked. Apple may delay or discard background pushes. Force-quitting prevents normal background delivery.")
                    Button("Import setup and enable Apple push test") { receiver.importAndEnable() }
                        .buttonStyle(NoopButtonStyle(.secondary)).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    Button("Disable remote buzz test") { receiver.disable() }
                        .buttonStyle(NoopButtonStyle(.secondary)).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    Text("This test accepts one short WHOOP cue from your configured Life sender. It expires within two hours. No polling, wake-alarm changes, or phone-notification fallback.")
                }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.font(StrandFont.subhead)
        }
    }
}
#endif
