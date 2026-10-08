import Foundation
import CryptoKit

/// Fixed, short-lived, one-pulse command. Remote data cannot choose BLE commands or alarm slots.
struct RemoteBuzzCommand: Codable, Equatable {
    let version: Int
    let eventId: String
    let installationId: String
    let topic: String
    let issuedAt: Int
    let expiresAt: Int
    let loops: Int
    let signature: String

    var signingBytes: Data {
        Data("dhoop-buzz:v1|\(eventId)|\(installationId)|\(topic)|\(issuedAt)|\(expiresAt)|\(loops)".utf8)
    }
    func validate(secret: Data, installation: String, topic expectedTopic: String, now: Date) -> Bool {
        let seconds = now.timeIntervalSince1970
        guard version == 1, loops == 1, secret.count == 32,
              UUID(uuidString: eventId)?.uuidString.lowercased() == eventId,
              UUID(uuidString: installationId)?.uuidString.lowercased() == installationId,
              installationId == installation, topic == expectedTopic,
              issuedAt >= 0, expiresAt > issuedAt, expiresAt - issuedAt <= 60,
              Double(issuedAt) <= seconds + 5, Double(expiresAt) > seconds,
              let mac = Data(base64Encoded: signature), mac.count == 32 else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: signingBytes,
            using: SymmetricKey(data: secret))
    }
}

struct RemoteBuzzTestSetup: Codable {
    let installationId: String
    let secret: String
    let expiresAt: Date
    var secretBytes: Data? { Data(base64Encoded: secret).flatMap { $0.count == 32 ? $0 : nil } }
    func valid(now: Date) -> Bool {
        UUID(uuidString: installationId)?.uuidString.lowercased() == installationId && secretBytes != nil
            && expiresAt > now && expiresAt.timeIntervalSince(now) <= 7200
    }
}
