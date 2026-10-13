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
    func testDefaultOffExpiryAndExerciseOwnership() throws {
        var state = RemoteBuzzState()
        XCTAssertFalse(try state.consume(command(at: now), enrollment: enrollment, now: now, connected: true, exerciseOwnsBuzz: false))
        state.enabled = true
        XCTAssertFalse(try state.consume(command(at: now), enrollment: enrollment, now: now + 60, connected: true, exerciseOwnsBuzz: false))
        XCTAssertFalse(try state.consume(command(at: now + 60), enrollment: enrollment, now: now + 60, connected: true, exerciseOwnsBuzz: true))
        XCTAssertTrue(try state.consume(command(at: now + 60), enrollment: enrollment, now: now + 60, connected: true, exerciseOwnsBuzz: false))
    }
    func testDistinctPrivateCommandsHaveNoHourlyQuotaOrCooldown() throws {
        var state = RemoteBuzzState(); state.enabled = true
        for _ in 0..<12 {
            XCTAssertTrue(try state.consume(command(at: now), enrollment: enrollment,
                now: now, connected: true, exerciseOwnsBuzz: false))
        }
        state = try JSONDecoder().decode(RemoteBuzzState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(try state.consume(command(at: now + 1), enrollment: enrollment,
            now: now + 1, connected: true, exerciseOwnsBuzz: false))
        XCTAssertEqual(state.events.count, 13)
        XCTAssertEqual(state.receipts.count, 13)
        XCTAssertTrue(state.valid())
    }

    func testCorruptCountersAndReceiptOwnershipFailClosed() throws {
        var state = RemoteBuzzState(); state.enabled = true
        let cue = command(at: now)
        _ = try state.consume(cue, enrollment: enrollment, now: now, connected: true, exerciseOwnsBuzz: false)
        XCTAssertTrue(state.valid())
        state.receiptSequence = 0
        XCTAssertFalse(state.valid())
        state.receiptSequence = 1
        state.receipts[0].attempts = -1
        XCTAssertFalse(state.valid())
        state.receipts[0].attempts = 1
        state.events = []
        XCTAssertFalse(state.valid())
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
    func testFirstDeliveryPathSurvivesCrossTransportDuplicateAndRelaunch() throws {
        for source in ["inbox", "apns"] {
            var state = RemoteBuzzState(); state.enabled = true
            let cue = command(at: now)
            XCTAssertTrue(try state.consume(cue, enrollment: enrollment, now: now, connected: true,
                exerciseOwnsBuzz: false, transport: source, appState: "background"))
            state = try JSONDecoder().decode(RemoteBuzzState.self, from: JSONEncoder().encode(state))
            XCTAssertFalse(try state.consume(cue, enrollment: enrollment, now: now + 1, connected: true,
                exerciseOwnsBuzz: false, transport: source == "apns" ? "inbox" : "apns", appState: "foreground"))
            XCTAssertEqual(state.receipts.count, 1)
            XCTAssertEqual(state.receipts[0].receipt.transport, source)
            XCTAssertEqual(state.receipts[0].receipt.appState, "background")
            XCTAssertTrue(state.valid())
        }
    }
    func testLegacyReceiptDecodesAndAttributionCannotClaimAnUnsupportedStage() throws {
        var state = RemoteBuzzState(); state.enabled = true
        let cue = command(at: now)
        _ = try state.consume(cue, enrollment: enrollment, now: now, connected: true, exerciseOwnsBuzz: false)
        let restored = try JSONDecoder().decode(RemoteBuzzState.self, from: JSONEncoder().encode(state))
        XCTAssertNil(restored.receipts[0].receipt.transport)
        XCTAssertTrue(restored.valid())
        XCTAssertThrowsError(try state.appendReceipt(eventId: cue.eventId, enrollment: enrollment,
            stage: "strap_response", outcome: "acknowledged", now: now + 1, transport: "inbox"))
    }
    func testPushBeforeBluetoothRestorationLeavesFreshInboxRequestRecoverable() throws {
        var state = RemoteBuzzState(); state.enabled = true
        let cue = command(at: now)
        XCTAssertFalse(try state.consume(cue, enrollment: enrollment, now: now, connected: false,
            exerciseOwnsBuzz: false, transport: "apns", appState: "background", deferDisconnected: true))
        XCTAssertTrue(state.events.isEmpty); XCTAssertTrue(state.receipts.isEmpty)
        state = try JSONDecoder().decode(RemoteBuzzState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(try state.consume(cue, enrollment: enrollment, now: now + 20, connected: true,
            exerciseOwnsBuzz: false, transport: "inbox", appState: "background", deferDisconnected: true))
        XCTAssertEqual(state.receipts.first?.receipt.transport, "inbox")
        XCTAssertFalse(try state.consume(cue, enrollment: enrollment, now: now + 21, connected: true,
            exerciseOwnsBuzz: false, transport: "apns", deferDisconnected: true))
    }
    func testDeferralNeverReplaysExpiredDisabledOrWorkoutSuppressedRequests() throws {
        for scenario in ["expired", "disabled", "suppressed"] {
            var state = RemoteBuzzState(); state.enabled = scenario != "disabled"
            let cue = command(at: now)
            XCTAssertFalse(try state.consume(cue, enrollment: enrollment,
                now: scenario == "expired" ? now + 60 : now, connected: false,
                exerciseOwnsBuzz: scenario == "suppressed", transport: "apns", deferDisconnected: true))
            XCTAssertEqual(state.events.first?.outcome, scenario)
            state.enabled = true
            XCTAssertFalse(try state.consume(cue, enrollment: enrollment, now: now + 61,
                connected: true, exerciseOwnsBuzz: false, transport: "inbox", deferDisconnected: true))
        }
    }
}
