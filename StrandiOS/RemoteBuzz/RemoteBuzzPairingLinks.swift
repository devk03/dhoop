import Foundation

enum RemoteBuzzPairingLinks {
    static let importedNotification = Notification.Name("dhoop.remoteBuzzPairingImported")
    static func invitationURL(_ invitation: RemoteBuzzInvitation, now: Date) throws -> URL {
        guard invitation.valid(now: now) else { throw RemoteBuzzEnrollmentError.invalid }
        let bytes = try JSONEncoder().encode(invitation)
        guard bytes.count <= 2048 else { throw RemoteBuzzEnrollmentError.invalid }
        var url = URLComponents(string: "https://track.kunjadia.dev/settings")!
        url.fragment = "dhoopBuzzInvitation=" + encode(bytes)
        guard let result = url.url else { throw RemoteBuzzEnrollmentError.invalid }
        return result
    }
    static func envelope(from url: URL) throws -> Data {
        guard url.absoluteString.utf8.count <= 16_384,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "dhoop", parts.host == "remote-buzz", parts.path == "/pair",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "envelope",
              let value = items[0].value, let bytes = decode(value), bytes.count <= 8192,
              let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(body.keys) == ["invitation", "serverPublicKey", "sealed"]
        else { throw RemoteBuzzEnrollmentError.invalid }
        return bytes
    }
    static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func decode(_ value: String) -> Data? {
        guard value.utf8.count <= 10_923, value.unicodeScalars.allSatisfy({
            (65...90).contains($0.value) || (97...122).contains($0.value)
                || (48...57).contains($0.value) || $0.value == 45 || $0.value == 95
        }) else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), encode(bytes) == value else { return nil }
        return bytes
    }
}
