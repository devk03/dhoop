#if canImport(Security)
import Foundation
import Security

enum WorkoutTrackerKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dhoop") + ".workout-tracker",
         kSecAttrAccount as String: "dedicated-credential"]
    }
    private static var frontendQuery: [String: Any] {
        var value = query
        value[kSecAttrService as String] = (Bundle.main.bundleIdentifier ?? "dhoop") + ".workout-frontend"
        return value
    }
    static func read() throws -> WorkoutSyncConfiguration? { try read(query: query) }
    static func readFrontend() throws -> WorkoutSyncConfiguration? { try read(query: frontendQuery) }
    private static func read(query: [String:Any]) throws -> WorkoutSyncConfiguration? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data else { throw WorkoutSyncTransportError.configuration }
        return try JSONDecoder().decode(WorkoutSyncConfiguration.self, from: bytes)
    }
    static func save(_ value: WorkoutSyncConfiguration) throws { try save(value, query: query) }
    static func saveFrontend(_ value: WorkoutSyncConfiguration) throws { try save(value, query: frontendQuery) }
    private static func save(_ value: WorkoutSyncConfiguration, query: [String:Any]) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, right in right } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw WorkoutSyncTransportError.configuration }
    }
}
#endif
