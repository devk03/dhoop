import Foundation
import Combine
import WhoopStore

struct CollectionProof: Codable {
    let capturedAt: TimeInterval
    let checkedAt: TimeInterval?
    let deviceId: String
    let deviceName: String
    let connected: Bool
    let receivingHR: Bool
    let livePackets: Int
    let lastLiveHRAt: TimeInterval?
    let liveDeviceId: String?
    let fromTs: Int?
    let toTs: Int?
    let storedHR: Int?
    let latestStoredHR: Int?
    let scorableRR: Int?
    let latestScorableRR: Int?
    let historyReady: Bool
    let lastSuccessfulSync: TimeInterval?
    let error: String?
    let unattributedSyncError: String?
}

@MainActor
final class WhoopCollectionModel: ObservableObject {
    @Published private(set) var snapshot: WhoopCollectionSnapshot?
    @Published private(set) var identity: PairedDevice?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var addedHR: Int?
    private var generation = 0
    private var selectedDeviceId: String?

    func deviceName(for id: String) -> String {
        guard let identity, identity.id == id else { return "Device identity unverified" }
        return identity.nickname?.isEmpty == false ? identity.nickname! : identity.model
    }

    func refresh(repo: Repository, live: LiveState, now: Date = Date()) async {
        generation += 1
        let generation = generation
        let id = repo.deviceId
        selectedDeviceId = id
        if snapshot?.deviceId != id { snapshot = nil; identity = nil; checkedAt = nil; addedHR = nil; error = nil }
        let from = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        guard let store = await repo.storeHandle() else {
            guard generation == self.generation, id == repo.deviceId else { return }
            error = "Local storage is unavailable"
            saveDiagnosticProof(live: live)
            return
        }
        do {
            let result = try await store.collectionSnapshot(deviceId: id, from: from, to: Int(now.timeIntervalSince1970))
            let device = try? DeviceRegistryStore(dbQueue: store.registryWriter).all().first { $0.id == id }
            guard generation == self.generation, id == repo.deviceId, !Task.isCancelled,
                  from == Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) else { return }
            addedHR = snapshot.flatMap { $0.deviceId == id && $0.fromTs == result.fromTs ? result.heartRate.count - $0.heartRate.count : nil }
            snapshot = result; identity = device; checkedAt = now; error = nil
            saveDiagnosticProof(live: live)

        } catch {
            guard generation == self.generation, id == repo.deviceId else { return }
            self.error = "Storage check failed: \(error.localizedDescription)"
            addedHR = nil
            saveDiagnosticProof(live: live)
        }
    }

    func proof(live: LiveState, now: Date, deviceId: String? = nil) -> CollectionProof {
        let id = deviceId ?? selectedDeviceId ?? "Unknown"
        let stored = snapshot.flatMap { $0.deviceId == id ? $0 : nil }
        let status = live.heartRateEvidence.status(connected: live.connected, isWhoop: live.activeIsWhoop,
            heartRate: live.heartRate, at: now.timeIntervalSince1970, silenceSeconds: LiveState.heartRateSilenceSeconds, expectedDeviceId: id, connectionDeviceId: live.connectedWhoopDeviceId)
        return CollectionProof(capturedAt: now.timeIntervalSince1970, checkedAt: stored != nil ? checkedAt?.timeIntervalSince1970 : nil,
            deviceId: id, deviceName: deviceName(for: id),
            connected: status.connected, receivingHR: status.isReceiving, livePackets: status.packets,
            lastLiveHRAt: status.sampleAge != nil ? live.heartRateEvidence.lastReceivedAt : nil,
            liveDeviceId: live.heartRateEvidence.sourceDeviceId, fromTs: stored?.fromTs, toTs: stored?.toTs,
            storedHR: stored?.heartRate.count, latestStoredHR: stored?.heartRate.latestTs,
            scorableRR: stored?.scorableRR.count, latestScorableRR: stored?.scorableRR.latestTs,
            historyReady: live.historyIsReady(for: id), lastSuccessfulSync: live.successfulSyncAt(for: id),
            error: error, unattributedSyncError: live.lastSyncError)
    }

    private func saveDiagnosticProof(live: LiveState) {
        // Explicit local support capture shares the same resolution as Data collection's export.
        guard ProcessInfo.processInfo.arguments.contains("--collection-proof") else { return }
        let current = proof(live: live, now: Date())
        if let data = try? JSONEncoder().encode(current) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("collection-proof-latest.json"), options: .atomic)
        }
    }

    func proofText(live: LiveState, now: Date, deviceId: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(proof(live: live, now: now, deviceId: deviceId)), let text = String(data: data, encoding: .utf8) else { return "Collection evidence unavailable" }
        return "Dhoop collection evidence\n\(text)\nReceipt and storage evidence do not establish physiological accuracy."
    }
}
