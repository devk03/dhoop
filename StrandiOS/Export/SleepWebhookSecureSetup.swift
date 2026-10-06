import Foundation
import CryptoKit

struct SleepWebhookCredentials: Codable {
    let endpoint: String
    let bearer: String
    let clientId: String
    let clientSecret: String

    var isValid: Bool {
        let destinations = ["https://track.kunjadia.dev/api/webhooks/sleep", "https://tracker.kunjadia.dev/api/webhooks/sleep"]
        return destinations.contains(endpoint) && bearer.count >= 32 && bearer.count <= 1024
            && !clientId.isEmpty && clientId.count <= 1024 && !clientSecret.isEmpty && clientSecret.count <= 2048
            && [bearer, clientId, clientSecret].allSatisfy { text in
                text.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 }
            }
    }
}

/// The setup file crossing the device boundary contains ciphertext only. Its receiver key is
/// generated on the phone and held in ThisDeviceOnly Keychain; no private key leaves the phone.
enum SleepWebhookSecureSetup {
    struct Invitation: Codable, Equatable {
        let version: Int
        let setupId: String
        let installationId: String
        let publicKey: Data
        let expiresAt: Date
    }
    struct Envelope: Codable {
        let invitation: Invitation
        let ephemeralPublicKey: Data
        let sealed: Data
    }
    static let context = Data("Dhoop sleep webhook setup v1".utf8)

    static func seal(_ credentials: SleepWebhookCredentials, invitation: Invitation, now: Date = Date()) throws -> Envelope {
        guard credentials.isValid, invitation.version == 1, invitation.expiresAt > now else { throw SleepWebhookFailure.expiredSetup }
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: invitation.publicKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: peer)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(invitation.setupId.utf8), sharedInfo: context, outputByteCount: 32)
        let aad = Data((invitation.setupId + "|" + invitation.installationId).utf8)
        let box = try AES.GCM.seal(JSONEncoder().encode(credentials), using: key, authenticating: aad)
        guard let combined = box.combined else { throw SleepWebhookFailure.credentials }
        return Envelope(invitation: invitation, ephemeralPublicKey: ephemeral.publicKey.x963Representation, sealed: combined)
    }
    static func open(_ envelope: Envelope, invitation: Invitation, privateKey: P256.KeyAgreement.PrivateKey, now: Date = Date()) throws -> SleepWebhookCredentials {
        guard invitation.version == 1, invitation.expiresAt > now,
              envelope.invitation == invitation,
              invitation.publicKey == privateKey.publicKey.x963Representation else { throw SleepWebhookFailure.expiredSetup }
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: envelope.ephemeralPublicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(invitation.setupId.utf8), sharedInfo: context, outputByteCount: 32)
        let aad = Data((invitation.setupId + "|" + invitation.installationId).utf8)
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key, authenticating: aad)
        let credentials = try JSONDecoder().decode(SleepWebhookCredentials.self, from: clear)
        guard credentials.isValid else { throw SleepWebhookFailure.credentials }
        return credentials
    }
}
