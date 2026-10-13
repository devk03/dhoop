import Foundation
import CryptoKit

enum RemoteBuzzV2 {
    static let topic = "com.devkunjadia.zhoop.loshi.noop"
    static let endpoint = "https://track.kunjadia.dev/api/dhoop/buzz/device"
    static let context = "dhoop-buzz-enrollment:v2"
    static func uuid(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString.lowercased() == value
    }
    static func canonicalBase64(_ value: String, count: Int) -> Data? {
        guard let bytes = Data(base64Encoded: value), bytes.count == count,
              bytes.base64EncodedString() == value else { return nil }
        return bytes
    }
    static func bearer(_ value: String) -> Bool {
        guard value.count == 43 else { return false }
        let encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "="
        guard let bytes = Data(base64Encoded: encoded), bytes.count == 32 else { return false }
        return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
    }
}

struct RemoteBuzzInvitation: Codable, Equatable {
    let version: Int
    let setupId: String
    let installationId: String
    let publicKey: String
    let expiresAt: Int
    let topic: String
    let environment: String

    var associatedData: Data {
        Data("\(RemoteBuzzV2.context)|\(setupId)|\(installationId)|\(topic)|\(environment)|\(expiresAt)".utf8)
    }
    func valid(now: Date) -> Bool {
        let seconds = now.timeIntervalSince1970
        return version == 2 && RemoteBuzzV2.uuid(setupId) && RemoteBuzzV2.uuid(installationId)
            && topic == RemoteBuzzV2.topic && ["sandbox", "production"].contains(environment)
            && Double(expiresAt) > seconds && Double(expiresAt) <= seconds + 600
            && RemoteBuzzV2.canonicalBase64(publicKey, count: 65).flatMap {
                try? P256.KeyAgreement.PublicKey(x963Representation: $0)
            } != nil
    }
}

struct RemoteBuzzPairing: Codable {
    let invitation: RemoteBuzzInvitation
    let privateKey: Data

    static func create(installationId: String, environment: String, now: Date) throws -> Self {
        let key = P256.KeyAgreement.PrivateKey()
        let invitation = RemoteBuzzInvitation(version: 2, setupId: UUID().uuidString.lowercased(),
            installationId: installationId, publicKey: key.publicKey.x963Representation.base64EncodedString(),
            expiresAt: Int(now.timeIntervalSince1970) + 600, topic: RemoteBuzzV2.topic, environment: environment)
        guard invitation.valid(now: now) else { throw RemoteBuzzEnrollmentError.invalid }
        return Self(invitation: invitation, privateKey: key.rawRepresentation)
    }
}

struct RemoteBuzzEnrollment: Codable, Equatable {
    let version: Int
    let enrollmentId: String
    let generation: Int
    let installationId: String
    let topic: String
    let environment: String
    let secret: String
    let deviceBearer: String
    let endpoint: String
    let accessClientId: String
    let accessClientSecret: String

    var secretBytes: Data? { RemoteBuzzV2.canonicalBase64(secret, count: 32) }
    func valid(for invitation: RemoteBuzzInvitation) -> Bool {
        version == 2 && RemoteBuzzV2.uuid(enrollmentId) && generation == 1
            && installationId == invitation.installationId && topic == invitation.topic
            && environment == invitation.environment && secretBytes != nil
            && RemoteBuzzV2.bearer(deviceBearer) && endpoint == RemoteBuzzV2.endpoint
            && !accessClientId.isEmpty && !accessClientSecret.isEmpty
            && accessClientId.count <= 256 && accessClientSecret.count <= 256
            && [accessClientId, accessClientSecret].allSatisfy { text in
                text.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 }
            }
    }
}

struct RemoteBuzzEnvelope: Codable {
    let invitation: RemoteBuzzInvitation
    let serverPublicKey: String
    let sealed: String

    func open(pairing: RemoteBuzzPairing, now: Date) throws -> RemoteBuzzEnrollment {
        guard invitation == pairing.invitation, invitation.valid(now: now),
              let serverBytes = RemoteBuzzV2.canonicalBase64(serverPublicKey, count: 65),
              let sealedBytes = Data(base64Encoded: sealed), sealedBytes.count <= 8192,
              sealedBytes.base64EncodedString() == sealed else { throw RemoteBuzzEnrollmentError.invalid }
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: pairing.privateKey)
        guard privateKey.publicKey.x963Representation.base64EncodedString() == invitation.publicKey
        else { throw RemoteBuzzEnrollmentError.invalid }
        let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverBytes)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(invitation.setupId.utf8),
            sharedInfo: Data(RemoteBuzzV2.context.utf8), outputByteCount: 32)
        let box = try AES.GCM.SealedBox(combined: sealedBytes)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: invitation.associatedData)
        let enrollment = try JSONDecoder().decode(RemoteBuzzEnrollment.self, from: plaintext)
        guard enrollment.valid(for: invitation) else { throw RemoteBuzzEnrollmentError.invalid }
        return enrollment
    }
}

enum RemoteBuzzEnrollmentError: LocalizedError {
    case invalid
    var errorDescription: String? { "Pairing is invalid, expired, or belongs to a different installation." }
}

struct RemoteBuzzCommandV2: Codable, Equatable {
    let version: Int
    let eventId: String
    let installationId: String
    let enrollmentId: String
    let generation: Int
    let topic: String
    let issuedAt: Int
    let expiresAt: Int
    let loops: Int
    let signature: String

    var signingBytes: Data {
        Data("dhoop-buzz:v2|\(eventId)|\(installationId)|\(enrollmentId)|\(generation)|\(topic)|\(issuedAt)|\(expiresAt)|\(loops)".utf8)
    }
    func authenticated(by enrollment: RemoteBuzzEnrollment) -> Bool {
        // Keep previously signed single-buzz events valid during the three-buzz rollout.
        guard version == 2, [1, 3].contains(loops), RemoteBuzzV2.uuid(eventId),
              installationId == enrollment.installationId, enrollmentId == enrollment.enrollmentId,
              generation == enrollment.generation, topic == enrollment.topic,
              issuedAt >= 0, expiresAt > issuedAt, expiresAt - issuedAt == 60,
              let secret = enrollment.secretBytes,
              let signatureBytes = RemoteBuzzV2.canonicalBase64(signature, count: 32) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(signatureBytes, authenticating: signingBytes,
            using: SymmetricKey(data: secret))
    }
    func fresh(now: Date) -> Bool {
        Double(issuedAt) <= now.timeIntervalSince1970 + 5 && Double(expiresAt) > now.timeIntervalSince1970
    }
}
