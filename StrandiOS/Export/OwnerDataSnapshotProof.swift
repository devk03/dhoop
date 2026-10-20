#if os(iOS) && DEBUG
import Foundation
import GRDB
import WhoopStore

/// Explicit owner-requested local review slice; never copies credentials or preferences.
@MainActor
enum OwnerDataSnapshotProof {
    static func runIfRequested(model: AppModel) async {
        guard ProcessInfo.processInfo.arguments.contains("--owner-data-slice") else { return }
        let root = FileManager.default.temporaryDirectory
        var manifest: [String: Any] = ["schemaVersion": 1, "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "sourceWritesRequested": false, "keychainCopied": false, "preferencesCopied": false]
        do {
            guard let store = await model.repo.storeHandle() else { throw CocoaError(.fileReadUnknown) }
            let target = root.appendingPathComponent("owner-snapshot-" + UUID().uuidString.lowercased() + ".sqlite")
            let writer = store.registryWriter
            let result = try await Task.detached(priority: .utility) {
                try OwnerDataReviewSlice.create(from: writer, at: target)
            }.value
            manifest["rawSince"] = result.rawSince
            manifest["rawThrough"] = result.rawThrough
            manifest["subset"] = true
            manifest["recomputedMeasurements"] = false
            manifest["excludedTablesHaveNoRows"] = true
            manifest["filename"] = target.lastPathComponent
            manifest["counts"] = result.counts
            manifest["activeDeviceId"] = model.repo.deviceId
            manifest["status"] = "consistent_review_slice_ready"
        } catch { manifest["status"] = "snapshot_not_verified"; manifest["errorType"] = String(describing: type(of: error)) }
        if let bytes = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) {
            try? bytes.write(to: root.appendingPathComponent("owner-data-snapshot-proof.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
#endif
