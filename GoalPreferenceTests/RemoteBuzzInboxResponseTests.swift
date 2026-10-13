import XCTest
import CryptoKit

final class RemoteBuzzInboxResponseTests: XCTestCase {
    private var enrollment: RemoteBuzzEnrollment {
        .init(version: 2, enrollmentId: "33333333-3333-4333-8333-333333333333", generation: 1,
            installationId: "22222222-2222-4222-8222-222222222222", topic: RemoteBuzzV2.topic, environment: "sandbox",
            secret: Data(repeating: 7, count: 32).base64EncodedString(), deviceBearer: String(repeating: "A", count: 43),
            endpoint: RemoteBuzzV2.endpoint, accessClientId: "synthetic", accessClientSecret: "synthetic")
    }
    private func reply(_ commands: [RemoteBuzzCommandV2], installation: String? = nil) -> RemoteBuzzInboxResponse {
        .init(version: 2, status: "accepted", enrollmentId: enrollment.enrollmentId, generation: 1,
            installationId: installation ?? enrollment.installationId, commands: commands, hasMore: false)
    }
    private func oracle(signature: String = "tY0GcsvylVf7QVpIw7dhLMezAc3FMgIlHMcrAw3PN2w=") -> RemoteBuzzCommandV2 {
        .init(version: 2, eventId: "44444444-4444-4444-8444-444444444444", installationId: enrollment.installationId,
            enrollmentId: enrollment.enrollmentId, generation: 1, topic: enrollment.topic,
            issuedAt: 1791500000, expiresAt: 1791500060, loops: 1, signature: signature)
    }
    func testIdentityAndEverySignatureRequiredBeforeBatchDispatch() {
        XCTAssertTrue(reply([oracle()]).valid(for: enrollment))
        XCTAssertTrue(reply([]).valid(for: enrollment))
        XCTAssertFalse(reply([oracle()], installation: UUID().uuidString.lowercased()).valid(for: enrollment))
        XCTAssertFalse(reply([oracle(), oracle(signature: Data(repeating: 0, count: 32).base64EncodedString())]).valid(for: enrollment))
        XCTAssertFalse(reply([oracle(), oracle()]).valid(for: enrollment))
    }
    func testOversizedOtherwiseAuthenticatedBatchIsRejected() {
        let commands = (0..<17).map { _ -> RemoteBuzzCommandV2 in
            let id = UUID().uuidString.lowercased(), e = enrollment
            let unsigned = RemoteBuzzCommandV2(version: 2, eventId: id, installationId: e.installationId,
                enrollmentId: e.enrollmentId, generation: 1, topic: e.topic,
                issuedAt: 1791500000, expiresAt: 1791500060, loops: 3, signature: "")
            let mac = HMAC<SHA256>.authenticationCode(for: unsigned.signingBytes, using: SymmetricKey(data: e.secretBytes!))
            return .init(version: 2, eventId: id, installationId: e.installationId, enrollmentId: e.enrollmentId,
                generation: 1, topic: e.topic, issuedAt: 1791500000, expiresAt: 1791500060, loops: 3,
                signature: Data(mac).base64EncodedString())
        }
        XCTAssertTrue(reply(Array(commands.prefix(16))).valid(for: enrollment))
        XCTAssertFalse(reply(commands).valid(for: enrollment))
    }
}
