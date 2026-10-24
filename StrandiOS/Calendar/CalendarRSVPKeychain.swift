import Foundation
import Security

/// Independent from reader/workout/buzz credentials; widgets never access this service.
enum CalendarRSVPKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.devkunjadia.zhoop.loshi.noop") + ".calendar-rsvp",
         kSecAttrAccount as String: "dedicated-credential"]
    }
    static func read() throws -> CalendarRSVPConfiguration? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let code = SecItemCopyMatching(q as CFDictionary, &item)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = item as? Data else { throw CalendarRSVPFailure.configuration }
        let value = try JSONDecoder().decode(CalendarRSVPConfiguration.self, from: data)
        guard value.valid else { throw CalendarRSVPFailure.configuration }; return value
    }
    static func save(_ value: CalendarRSVPConfiguration) throws {
        guard value.valid else { throw CalendarRSVPFailure.configuration }; let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CalendarRSVPFailure.configuration }
        } else if status != errSecSuccess { throw CalendarRSVPFailure.configuration }
    }
}
