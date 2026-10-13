import XCTest
import Foundation

final class RemoteBuzzEnrollmentTests: XCTestCase {
    // Synthetic fixed-key Swift oracle, independently decrypted with Node crypto.
    private let fixture = #"{"invitation":{"environment":"sandbox","expiresAt":1791500600,"installationId":"22222222-2222-4222-8222-222222222222","publicKey":"BGsX0fLhLEJH+Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT+NC4v4af5uO5+tKfA+eFivOM1drMV7Oy7ZAaDe/UfU=","setupId":"11111111-1111-4111-8111-111111111111","topic":"com.devkunjadia.zhoop.loshi.noop","version":2},"sealed":"AwMDAwMDAwMDAwMD1XYIHzA0i3H+XbeqZDrmSNtOgi+JDdphKzmUBaUV2I6mneQ9IQ8U8w6/CsPfsNjhAFHOmvMBkXchuSPeu6AvsWterjuGO7NgtPNbMUWpbcLi1aj9HLldFhJY0MQKe5x7LWn0CZXNX9MFecE+SPnfWoed6M9zhyfhFqoA7qa95buivZtXsC7/7le/95g99kOqpD/qLlYTWINuDSDdD6aR8fOTn+FtrkZ5YgC5qIKLDNCaGe7V25KGIptS/2X6gVuWTZ3T9UrDzEPXQKXFJ7qRcatOPNa8vQzfyh0s7xAkC1LK5lvgE4xshCNARuZ5mgdLQlUP+GoT+FLDOnM0A/jr7sknMZD1x5tPcXUnHx/jBHe2byPlsYiqUTVqeuXgeSmvyqycU5iECHQ8cx03BZIZ6NHdYoalX8s/Mhbr3EQ70Y1yhJwcvol6JQRHpJemuygu3C0S0mJ8AUdizUcfB21ROuK612zordTwfYRXP/F0ihbb/kDfZxk/bnm7yWRq87N6LlOIHDkAytOHVRkKsaGn27P3pyKOczsO0Z5xg7iZJtzSBrkV7fi1DwY2GXJsl+9twrLg/S8mP/XjAGIpcrHJ6oVz1i6+ofPKVuixf9ZcZ7ol5DHMPDa1Kvn6CIY=","serverPublicKey":"BHzyexiNA09+ilI4AwS1GsPAiWnid/IbNaYLSPxHZpl4B3dVENuO0EApPZrGn3Qw27p9reY86YIpngS3nSJ4c9E="}"#
    private let now = Date(timeIntervalSince1970: 1791500000)
    private func envelope() throws -> RemoteBuzzEnvelope {
        try JSONDecoder().decode(RemoteBuzzEnvelope.self, from: Data(fixture.utf8))
    }
    private func pairing(_ envelope: RemoteBuzzEnvelope) -> RemoteBuzzPairing {
        var raw = Data(repeating: 0, count: 32); raw[31] = 1
        return RemoteBuzzPairing(invitation: envelope.invitation, privateKey: raw)
    }
    func testCrossRuntimeEnvelopeAndIdentityBinding() throws {
        let box = try envelope()
        let enrollment = try box.open(pairing: pairing(box), now: now)
        XCTAssertEqual(enrollment.enrollmentId, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(enrollment.secretBytes, Data(repeating: 7, count: 32))
        XCTAssertEqual(enrollment.endpoint, RemoteBuzzV2.endpoint)
        let i = box.invitation
        let changed = RemoteBuzzInvitation(version: 2, setupId: i.setupId,
            installationId: "99999999-9999-4999-8999-999999999999", publicKey: i.publicKey,
            expiresAt: i.expiresAt, topic: i.topic, environment: i.environment)
        let changedBox = RemoteBuzzEnvelope(invitation: changed, serverPublicKey: box.serverPublicKey, sealed: box.sealed)
        XCTAssertThrowsError(try changedBox.open(pairing: RemoteBuzzPairing(invitation: changed, privateKey: pairing(box).privateKey), now: now))
        XCTAssertThrowsError(try box.open(pairing: pairing(box), now: Date(timeIntervalSince1970: 1791500600)))
        var wrongKey = Data(repeating: 0, count: 32); wrongKey[31] = 3
        XCTAssertThrowsError(try box.open(pairing: RemoteBuzzPairing(invitation: i, privateKey: wrongKey), now: now))
    }
    func testCiphertextTamperingCannotPair() throws {
        let box = try envelope()
        var data = try XCTUnwrap(Data(base64Encoded: box.sealed)); data[15] ^= 1
        let changed = RemoteBuzzEnvelope(invitation: box.invitation, serverPublicKey: box.serverPublicKey, sealed: data.base64EncodedString())
        XCTAssertThrowsError(try changed.open(pairing: pairing(box), now: now))
    }
    func testNodeHMACOracleExpiryAndGeneration() throws {
        let box = try envelope(), enrollment = try box.open(pairing: pairing(box), now: now)
        func command(generation: Int = 1, loops: Int = 1,
                     signature: String = "tY0GcsvylVf7QVpIw7dhLMezAc3FMgIlHMcrAw3PN2w=") -> RemoteBuzzCommandV2 {
            RemoteBuzzCommandV2(version: 2, eventId: "44444444-4444-4444-8444-444444444444",
                installationId: enrollment.installationId, enrollmentId: enrollment.enrollmentId,
                generation: generation, topic: enrollment.topic, issuedAt: 1791500000, expiresAt: 1791500060,
                loops: loops, signature: signature)
        }
        XCTAssertTrue(command().authenticated(by: enrollment))
        XCTAssertTrue(command().fresh(now: now))
        XCTAssertFalse(command().fresh(now: Date(timeIntervalSince1970: 1791500060)))
        XCTAssertFalse(command().fresh(now: Date(timeIntervalSince1970: 1791499994)))
        XCTAssertFalse(command(generation: 2).authenticated(by: enrollment))
        XCTAssertFalse(command(loops: 2).authenticated(by: enrollment))
        // Independent Node HMAC oracle: loop count is signed, not an unsigned delivery hint.
        XCTAssertTrue(command(loops: 3, signature: "V/rkKcjpo16m5gc/y5MYJFfWM54ny9MqGjghlajjmSw=")
            .authenticated(by: enrollment))
        XCTAssertFalse(command(loops: 3).authenticated(by: enrollment))
    }
}
