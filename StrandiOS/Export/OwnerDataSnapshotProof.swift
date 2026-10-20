#if os(iOS) && DEBUG
import Foundation
import GRDB
import WhoopStore

/// Explicit owner-requested, local-only SQLite online backup; never copies credentials or preferences.
@MainActor
enum OwnerDataSnapshotProof {
    static func runIfRequested(model: AppModel) async {
        guard ProcessInfo.processInfo.arguments.contains("--owner-data-snapshot") else { return }
        let root = FileManager.default.temporaryDirectory
        var manifest: [String: Any] = ["schemaVersion": 1, "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "sourceWritesRequested": false, "keychainCopied": false, "preferencesCopied": false]
        do {
            guard let store = await model.repo.storeHandle() else { throw CocoaError(.fileReadUnknown) }
            let target = root.appendingPathComponent("owner-snapshot-" + UUID().uuidString.lowercased() + ".sqlite")
            let writer = store.registryWriter
            let counts = try await Task.detached(priority: .utility) { () throws -> [String: Int] in
                // Exclusive creation reserves a new destination. Existing databases cannot be replaced.
                try Data().write(to: target, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                let destination = try DatabaseQueue(path: target.path)
                // SQLite's backup API reads a coherent committed snapshot, including committed WAL pages.
                // No checkpoint, source write, migration, trim or raw live-file copy is involved.
                try writer.backup(to: destination)
                return try destination.read { db in
                    guard try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok" else { throw CocoaError(.fileReadCorruptFile) }
                    let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
                    var result: [String: Int] = [:]
                    for name in names where name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
                        result[name] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(name)\"") ?? 0
                    }
                    return result
                }
            }.value
            manifest["filename"] = target.lastPathComponent
            manifest["counts"] = counts
            manifest["activeDeviceId"] = model.repo.deviceId
            manifest["status"] = "consistent_snapshot_ready"
        } catch { manifest["status"] = "snapshot_not_verified"; manifest["errorType"] = String(describing: type(of: error)) }
        if let bytes = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) {
            try? bytes.write(to: root.appendingPathComponent("owner-data-snapshot-proof.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
#endif
