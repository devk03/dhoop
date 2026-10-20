#if os(iOS)
import SwiftUI
import StrandDesign

struct LifeSyncStatusView: View {
    let status: LifeSyncStatus
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                if status.phase == .checking { ProgressView().controlSize(.small) }
                else { Image(systemName: icon).foregroundStyle(status.phase == .failed ? StrandPalette.statusWarning : StrandPalette.textSecondary) }
                title.font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let detail = status.detail {
                Text(detail).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let day = status.pendingDay {
                Text("Saved on this phone · \(day)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if let day = status.receiptDay, let received = status.receivedAt {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text(status.protein ? "Logged date \(day)" : "Wake date \(day)")
                    Text("Received \(received.formatted(date: .abbreviated, time: .shortened))")
                    switch status.outcome {
                    case "manual_preserved": Text("Life kept your manual value.")
                    case "cleared": Text("Life cleared the previous automatic value.")
                    case "stale": Text("Life already has a newer revision.")
                    case "duplicate": Text("Life already received this summary.")
                    default: EmptyView()
                    }
                }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }.accessibilityElement(children: .combine)
    }
    private var icon: String {
        switch status.phase {
        case .off: return "pause.circle"
        case .checking: return "arrow.triangle.2.circlepath"
        case .queued: return "tray.full"
        case .failed: return "exclamationmark.circle"
        case .processing: return "hourglass"
        case .idle: return "tray"
        case .receipt: return "checkmark.circle"
        }
    }
    @ViewBuilder private var title: some View {
        switch status.phase {
        case .off: Text("Off")
        case .checking: Text("Checking summaries…")
        case .queued: Text("Queued on this phone")
        case .failed: Text("Needs attention")
        case .processing: Text("Waiting for sleep processing")
        case .idle: Text("No new summaries ready")
        case .receipt: Text("Last received summary")
        }
    }
}
#endif
