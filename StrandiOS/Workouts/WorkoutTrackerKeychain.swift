#if os(iOS)
import Foundation
import Security

enum WorkoutTrackerKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dhoop") + ".workout-tracker",
         kSecAttrAccount as String: "dedicated-credential"]
    }
    static func read() throws -> WorkoutSyncConfiguration? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data else { throw WorkoutSyncTransportError.configuration }
        return try JSONDecoder().decode(WorkoutSyncConfiguration.self, from: bytes)
    }
    static func save(_ value: WorkoutSyncConfiguration) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, right in right } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw WorkoutSyncTransportError.configuration }
    }
}
#endif
