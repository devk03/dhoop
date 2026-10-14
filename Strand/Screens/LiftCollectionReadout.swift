import SwiftUI
import StrandDesign
import WhoopStore

/// Isolated receipt and storage evidence; a heartbeat does not redraw the set-entry form.
struct LiftCollectionReadout: View {
    let fromTs: Int
    let deviceId: String?
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @State private var snapshot: WhoopCollectionSnapshot?
    @State private var error: String?

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let status = live.heartRateEvidence.status(connected: live.connected, isWhoop: live.activeIsWhoop,
                        heartRate: live.heartRate, at: context.date.timeIntervalSince1970,
                        silenceSeconds: LiveState.heartRateSilenceSeconds, expectedDeviceId: deviceId ?? repo.deviceId,
                        connectionDeviceId: live.connectedWhoopDeviceId)
                    Label(deviceId == nil ? "Capture source unverified" : status.isReceiving ? "WHOOP · Receiving HR" : status.connected ? "WHOOP · Waiting for HR" : "WHOOP · Disconnected",
                          systemImage: "waveform.path.ecg")
                        .font(StrandFont.subhead)
                        .foregroundStyle(status.isReceiving ? StrandPalette.statusPositive : StrandPalette.textSecondary)
                }
                if let snapshot, snapshot.deviceId == deviceId {
                    Text("\(snapshot.heartRate.count.formatted()) measured HR readings saved since workout start")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text("Checked through \(Date(timeIntervalSince1970: Double(snapshot.toTs)).formatted(date: .omitted, time: .standard))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                if let error { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical) }
                NoopAsyncButton("Check saved readings", systemImage: "arrow.clockwise", kind: .tertiary) { try await refresh() }
                    .disabled(deviceId == nil)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: "\(fromTs)|\(deviceId ?? "unknown")|\(repo.refreshSeq)") { try? await refresh() }
    }

    @MainActor private func refresh() async throws {
        guard let deviceID = deviceId else { return }
        let through = Int(Date().timeIntervalSince1970)
        do {
            guard let store = await repo.storeHandle() else { throw LiftCollectionError.storageUnavailable }
            let result = try await store.collectionSnapshot(deviceId: deviceID, from: fromTs, to: through)
            guard !Task.isCancelled else { return }
            snapshot = result; error = nil
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
}

private enum LiftCollectionError: LocalizedError {
    case storageUnavailable
    var errorDescription: String? { "Saved-reading check is unavailable. Connection alone does not prove persistence." }
}
