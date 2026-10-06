#if os(iOS)
import Foundation
import Security

enum SleepWebhookKeychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dhoop") + ".sleep-webhook",
         kSecAttrAccount as String: account]
    }
    static func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data else { throw SleepWebhookFailure.credentials }
        return bytes
    }
    static func save(_ bytes: Data, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: bytes,
            kSecAttrAccessible as String: account == "setup" ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(account).merging(attributes) { _, right in right } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SleepWebhookFailure.credentials }
    }
}
#endif
