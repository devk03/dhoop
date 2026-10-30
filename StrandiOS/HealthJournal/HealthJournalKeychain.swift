import Foundation
import Security

enum HealthJournalKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dhoop") + ".health-journal",
         kSecAttrAccount as String: "dedicated-credential"]
    }
    static func read() throws -> HealthJournalConnection? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw HealthJournalFailure.configuration }
        let result = try JSONDecoder().decode(HealthJournalConnection.self, from: data)
        guard result.valid else { throw HealthJournalFailure.configuration }; return result
    }
    static func save(_ connection: HealthJournalConnection) throws {
        guard connection.valid else { throw HealthJournalFailure.configuration }
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(connection),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw HealthJournalFailure.configuration }
    }
}

@MainActor
enum HealthJournalProvisioner {
    static func consume(_ url: URL, client: HealthJournalClient) async throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 8192 else { throw HealthJournalFailure.configuration }
        let connection = try JSONDecoder().decode(HealthJournalConnection.self, from: data)
        try await client.install(connection)
        try Data("{\"schemaVersion\":1,\"consumed\":true}".utf8).write(to: url, options: [.atomic])
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--configure-health") else { return }
        let folder = FileManager.default.temporaryDirectory
        var status = "setup_not_verified"
        do { try await consume(folder.appendingPathComponent("dhoop-health-provisioning.json"), client: .shared); status = "authenticated_reads_verified" } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "status": status, "writesAttempted": false,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let bytes = try? JSONSerialization.data(withJSONObject: report) {
            try? bytes.write(to: folder.appendingPathComponent("dhoop-health-connection-result.json"), options: .atomic)
        }
    }
}
