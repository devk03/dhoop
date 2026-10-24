import Foundation
import Security

enum CalendarReaderKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dhoop") + ".calendar-reader",
         kSecAttrAccount as String: "dedicated-credential"]
    }
    static func read() throws -> CalendarReaderConfiguration? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw CalendarReaderFailure.configuration }
        let result = try JSONDecoder().decode(CalendarReaderConfiguration.self, from: data)
        guard result.valid else { throw CalendarReaderFailure.configuration }; return result
    }
    static func save(_ configuration: CalendarReaderConfiguration) throws {
        guard configuration.valid else { throw CalendarReaderFailure.configuration }
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(configuration),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, right in right } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw CalendarReaderFailure.configuration }
    }
}
