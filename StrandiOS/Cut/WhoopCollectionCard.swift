import SwiftUI
import StrandDesign
import WhoopStore

/// Live receipt and durable storage are separate observations; a radio connection proves neither.
struct WhoopCollectionCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @State private var snapshot: WhoopCollectionSnapshot?
    @State private var previous: WhoopCollectionSnapshot?
    @State private var checkedAt: Date?
    @State private var readFailed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fresh = live.connected && live.activeIsWhoop && (live.heartRate ?? 0) > 0 && live.heartRateEvidence.isFresh(
                at: context.date.timeIntervalSince1970, silenceSeconds: LiveState.heartRateSilenceSeconds)
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack {
                        Label("WHOOP data", systemImage: "waveform.path.ecg").font(StrandFont.headline)
                        Spacer()
                        Text(fresh ? "Receiving HR" : live.connected ? "Connected" : "Disconnected")
                            .font(StrandFont.caption).foregroundStyle(fresh ? StrandPalette.statusPositive : StrandPalette.textSecondary)
                    }
                    if live.activeIsWhoop {
                        row("History access", live.historyReady ? "Ready" : "Not ready")
                        row("Last history sync", live.lastSyncedAt.map(time) ?? "None yet")
                        if let battery = live.batteryPct {
                            row("Last strap battery", "\(Int(battery.rounded()))%")
                        }
                        row("Last readable HR", live.heartRateEvidence.lastReceivedAt.map { time($0) } ?? "None this connection")
                        row("Readable HR packets", "\(live.heartRateEvidence.packets) this connection")
                    } else {
                        Text("The active live source is not WHOOP.").font(StrandFont.caption)
                    }
                    if let snapshot, snapshot.deviceId == repo.deviceId {
                        row("Stored source", snapshot.deviceId)
                        row("Stored HR · today", stored(snapshot.heartRate))
                        row("Stored R-R · today", stored(snapshot.rr))
                        row("Optical HR estimates", stored(snapshot.opticalEstimates))
                        row("Step records · today", stored(snapshot.steps))
                        if let previous, previous.deviceId == snapshot.deviceId, previous.fromTs == snapshot.fromTs {
                            let added = snapshot.heartRate.count - previous.heartRate.count
                            Text(added > 0 ? "\(added) new stored HR samples since the previous check."
                                 : "No new stored HR samples since the previous check.")
                                .font(StrandFont.caption).foregroundStyle(added > 0 ? StrandPalette.statusPositive : StrandPalette.textTertiary)
                        }
                        if let checkedAt { row("Store checked", time(checkedAt.timeIntervalSince1970)) }
                    } else {
                        Text(readFailed ? "Storage could not be checked. Try again after connecting." : "Checking local storage…")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text("Fresh packets prove receipt; increasing stored counts prove persistence. HRV, strain and VO₂ max need their own inputs and may be estimates.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    HStack {
                        Button("Check storage") { Task { await load() } }
                        Spacer()
                        Button("Devices") { router.requestedDestination = .devices }
                    }
                    .font(StrandFont.subhead).tint(StrandPalette.accent)
                }
                .foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .task(id: repo.deviceId) {
            snapshot = nil; previous = nil
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(StrandFont.captionNumber)
    }

    private func time(_ ts: TimeInterval) -> String {
        Date(timeIntervalSince1970: ts).formatted(.dateTime.hour().minute().second())
    }

    private func stored(_ stream: CollectionStreamSnapshot) -> String {
        "\(stream.count.formatted())" + (stream.latestTs.map { " · latest \(time(TimeInterval($0)))" } ?? " · no samples")
    }

    @State private var loadGeneration = 0
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let id = repo.deviceId
        let now = Int(Date().timeIntervalSince1970)
        // A local calendar day keeps count comparisons stable, then resets honestly at midnight.
        let from = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        guard let store = await repo.storeHandle() else { readFailed = true; snapshot = nil; return }
        do {
            let next = try await store.collectionSnapshot(deviceId: id, from: from, to: now)
            guard generation == loadGeneration, id == repo.deviceId, !Task.isCancelled else { return }
            previous = snapshot
            snapshot = next
            checkedAt = Date()
            readFailed = false
        } catch {
            guard generation == loadGeneration else { return }
            readFailed = true
            snapshot = nil
            previous = nil
        }
    }
}
