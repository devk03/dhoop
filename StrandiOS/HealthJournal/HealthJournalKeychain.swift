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
        if ProcessInfo.processInfo.arguments.contains("--health-read-proof") { await readProof(); return }
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
    /// Two explicit GETs use only the installed Health credential. No record or credential is exported.
    private static func readProof() async {
        let prefix = "--health-read-run="
        let run = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
            .flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }?.uuidString ?? "manual"
        var result: [String: Any] = ["schemaVersion": 1, "runId": run, "writesAttempted": false,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "capturedAt": ISO8601DateFormatter().string(from: Date()), "status": "not_verified"]
        var stage = "credential"
        func milliseconds(_ start: ContinuousClock.Instant) -> Double {
            let parts = start.duration(to: .now).components
            return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        }
        do {
            guard let connection = try HealthJournalKeychain.read() else { throw HealthJournalFailure.configuration }
            let transport = HealthJournalTransport()
            stage = "capabilities"; var start = ContinuousClock.now
            let bytes = try await transport.send(.init(path: "capabilities"), connection: connection)
            let capabilities = try JSONDecoder().decode(HealthJournalCapabilities.self, from: bytes)
            guard capabilities.valid else { throw HealthJournalFailure.invalidResponse }
            result["capabilityReadMilliseconds"] = milliseconds(start)
            result["inlineTopicCreation"] = capabilities.inlineTopicCreation == true
            stage = "entries"; start = .now
            let page = try await transport.send(.init(path: "entries", query: [.init(name: "limit", value: "1")]), connection: connection)
            let document = try JSONDecoder().decode(HealthJournalDocument.self, from: page); try document.validate()
            result["entryReadMilliseconds"] = milliseconds(start); result["status"] = "authenticated_reads_verified"
        } catch {
            result["stage"] = stage; result["errorType"] = String(describing: type(of: error))
            if case HealthJournalFailure.http(let code) = error { result["httpStatus"] = code }
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys) {
            try? bytes.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("health-read-" + run + ".json"), options: [.atomic])
        }
    }

}
