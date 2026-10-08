import XCTest
import CryptoKit

final class RemoteBuzzContractTests: XCTestCase {
    private let secret = Data(repeating: 7, count: 32)
    private let installation = "00000000-0000-0000-0000-000000000001"
    private let event = "00000000-0000-0000-0000-000000000002"
    private let topic = "com.devkunjadia.zhoop.loshi.noop"
    private let now = Date(timeIntervalSince1970: 1_791_500_000)
    private func command(loops: Int = 1, age: Int = 0, lifespan: Int = 60, signature: String? = nil) -> RemoteBuzzCommand {
        let issued = Int(now.timeIntervalSince1970) - age
        let unsigned = RemoteBuzzCommand(version: 1, eventId: event, installationId: installation, topic: topic,
            issuedAt: issued, expiresAt: issued + lifespan, loops: loops, signature: "")
        let mac = Data(HMAC<SHA256>.authenticationCode(for: unsigned.signingBytes, using: SymmetricKey(data: secret)))
        return RemoteBuzzCommand(version: 1, eventId: event, installationId: installation, topic: topic,
            issuedAt: issued, expiresAt: issued + lifespan, loops: loops, signature: signature ?? mac.base64EncodedString())
    }
    func testValidCommandAndFixedCanonicalWireFormat() {
        let value = command()
        XCTAssertEqual(String(data: value.signingBytes, encoding: .utf8),
            "dhoop-buzz:v1|00000000-0000-0000-0000-000000000002|00000000-0000-0000-0000-000000000001|com.devkunjadia.zhoop.loshi.noop|1791500000|1791500060|1")
        XCTAssertTrue(value.validate(secret: secret, installation: installation, topic: topic, now: now))
    }
    func testExpiredFutureWrongSignatureIdentityAndUnsupportedPatternsFailClosed() {
        for value in [command(age: 60), command(age: -6), command(lifespan: 61), command(loops: 2), command(signature: Data(repeating: 0, count: 32).base64EncodedString())] {
            XCTAssertFalse(value.validate(secret: secret, installation: installation, topic: topic, now: now))
        }
        XCTAssertFalse(command().validate(secret: secret, installation: event, topic: topic, now: now))
        XCTAssertFalse(command().validate(secret: secret, installation: installation, topic: "other", now: now))
    }
    func testSetupNeverEnablesBeyondTwoHours() {
        XCTAssertTrue(RemoteBuzzTestSetup(installationId: installation, secret: secret.base64EncodedString(), expiresAt: now.addingTimeInterval(7200)).valid(now: now))
        XCTAssertFalse(RemoteBuzzTestSetup(installationId: installation, secret: secret.base64EncodedString(), expiresAt: now.addingTimeInterval(7201)).valid(now: now))
        XCTAssertFalse(RemoteBuzzTestSetup(installationId: installation, secret: secret.base64EncodedString(), expiresAt: now).valid(now: now))
    }
}
