import XCTest
import Foundation
import CryptoKit

final class RemoteBuzzStateTests: XCTestCase {
    private let now = 1791500000
    private var enrollment: RemoteBuzzEnrollment {
        RemoteBuzzEnrollment(version: 2, enrollmentId: "33333333-3333-4333-8333-333333333333", generation: 1,
            installationId: "22222222-2222-4222-8222-222222222222", topic: RemoteBuzzV2.topic, environment: "sandbox",
            secret: Data(repeating: 7, count: 32).base64EncodedString(), deviceBearer: String(repeating: "A", count: 43),
            endpoint: RemoteBuzzV2.endpoint, accessClientId: "synthetic", accessClientSecret: "synthetic")
    }
    private func command(at date: Int, id: String = UUID().uuidString.lowercased()) -> RemoteBuzzCommandV2 {
        let e = enrollment
        let unsigned = RemoteBuzzCommandV2(version: 2, eventId: id, installationId: e.installationId,
            enrollmentId: e.enrollmentId, generation: e.generation, topic: e.topic,
            issuedAt: date, expiresAt: date + 60, loops: 1, signature: "")
        let mac = HMAC<SHA256>.authenticationCode(for: unsigned.signingBytes, using: SymmetricKey(data: e.secretBytes!))
        return RemoteBuzzCommandV2(version: 2, eventId: id, installationId: e.installationId,
            enrollmentId: e.enrollmentId, generation: e.generation, topic: e.topic,
            issuedAt: date, expiresAt: date + 60, loops: 1, signature: Data(mac).base64EncodedString())
    }
    func testRelaunchDedupAndNoReconnectReplay() throws {
        var state = RemoteBuzzState(); state.enabled = true
        let cue = command(at: now)
        XCTAssertTrue(try state.consume(cue, enrollment: enrollment, now: now, connected: true, exerciseOwnsBuzz: false))
        state = try JSONDecoder().decode(RemoteBuzzState.self, from: JSONEncoder().encode(state))
        XCTAssertFalse(try state.consume(cue, enrollment: enrollment, now: now + 1, connected: true, exerciseOwnsBuzz: false))
        let disconnected = command(at: now + 31)
        XCTAssertFalse(try state.consume(disconnected, enrollment: enrollment, now: now + 31, connected: false, exerciseOwnsBuzz: false))
        XCTAssertFalse(try state.consume(disconnected, enrollment: enrollment, now: now + 32, connected: true, exerciseOwnsBuzz: false))
        XCTAssertEqual(state.events.map(\.outcome), ["received", "disconnected"])
        XCTAssertEqual(state.receipts.count, 2)
    }
    func testDefaultOffExpiryOwnershipCooldownAndHourLimit() throws {
        var state = RemoteBuzzState()
        XCTAssertFalse(try state.consume(command(at: now), enrollment: enrollment, now: now, connected: true, exerciseOwnsBuzz: false))
        state.enabled = true
        XCTAssertFalse(try state.consume(command(at: now), enrollment: enrollment, now: now + 60, connected: true, exerciseOwnsBuzz: false))
        XCTAssertFalse(try state.consume(command(at: now + 60), enrollment: enrollment, now: now + 60, connected: true, exerciseOwnsBuzz: true))
        XCTAssertTrue(try state.consume(command(at: now + 60), enrollment: enrollment, now: now + 60, connected: true, exerciseOwnsBuzz: false))
        XCTAssertFalse(try state.consume(command(at: now + 89), enrollment: enrollment, now: now + 89, connected: true, exerciseOwnsBuzz: false))
        for delta in [90, 120] {
            XCTAssertTrue(try state.consume(command(at: now + delta), enrollment: enrollment, now: now + delta, connected: true, exerciseOwnsBuzz: false))
        }
        XCTAssertFalse(try state.consume(command(at: now + 150), enrollment: enrollment, now: now + 150, connected: true, exerciseOwnsBuzz: false))
        XCTAssertTrue(try state.consume(command(at: now + 3660), enrollment: enrollment, now: now + 3660, connected: true, exerciseOwnsBuzz: false))
    }
    func testReceiptEvidenceIsIndependentAndRetriesBounded() throws {
        var state = RemoteBuzzState(); state.enabled = true
        let cue = command(at: now)
        _ = try state.consume(cue, enrollment: enrollment, now: now, connected: true, exerciseOwnsBuzz: false)
        try state.appendReceipt(eventId: cue.eventId, enrollment: enrollment, stage: "strap_response", outcome: "response_received", now: now + 1)
        XCTAssertEqual(state.receipts.map(\.receipt.stage), ["phone_received", "strap_response"])
        XCTAssertFalse(state.receipts.contains { $0.receipt.stage == "wearer_confirmed" })
        XCTAssertThrowsError(try state.appendReceipt(eventId: cue.eventId, enrollment: enrollment, stage: "strap_response", outcome: "felt", now: now + 1))
        var pending = state.receipts[0]
        XCTAssertTrue(pending.mayAttempt(now: now))
        pending.attempts = 10
        XCTAssertFalse(pending.mayAttempt(now: now))
        pending.attempts = 1; pending.lastAttemptAt = now
        XCTAssertFalse(pending.mayAttempt(now: now + 29))
        XCTAssertTrue(pending.mayAttempt(now: now + 30))
        XCTAssertFalse(pending.mayAttempt(now: now + 3600))
    }
}
