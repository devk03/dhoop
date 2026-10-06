import XCTest

@MainActor
final class BuzzDeliveryCoordinatorTests: XCTestCase {
    private func make() -> BuzzDeliveryCoordinator {
        BuzzDeliveryCoordinator(file: FileManager.default.temporaryDirectory
            .appendingPathComponent("buzz-tests-\(UUID().uuidString)/ledger.json"))
    }
    private func connected(_ delivery: BuzzDeliveryCoordinator, connection: UUID = UUID()) {
        delivery.link = { .init(deviceId: "strap", connection: connection, ready: true) }
        delivery.gateEnabled = { _ in true }
    }
    func testDueCueIsPersistedBeforeSendAndDeduplicated() {
        let delivery = make(); connected(delivery)
        let now = Date()
        var writes = 0
        delivery.transmit = { cue in
            XCTAssertEqual(delivery.cues.first?.status, .requested)
            writes += 1
            return .init(sequence: 7, opcode: 19)
        }
        delivery.schedule(owner: "test", id: "same", deviceId: "strap", due: now, now: now)
        delivery.schedule(owner: "test", id: "same", deviceId: "strap", due: now, now: now)
        delivery.service(now: now.addingTimeInterval(1))
        XCTAssertEqual(writes, 1)
    }
    func testDisconnectCancelsFutureCueAndSequenceReuseCannotMisattributeAck() {
        let delivery = make(); let connection = UUID(); connected(delivery, connection: connection)
        let now = Date(); var writes = 0
        delivery.transmit = { _ in writes += 1; return .init(sequence: 7, opcode: 19) }
        delivery.schedule(owner: "test", id: "sent", deviceId: "strap", due: now, now: now)
        delivery.willUseSequence(7, connection: connection)
        delivery.acknowledge(sequence: 7, opcode: 19, result: "SUCCESS(1)", payload: [1,5], deviceId: "strap", connection: connection, now: now)
        XCTAssertEqual(delivery.cues.last?.status, .requested)
        delivery.schedule(owner: "test", id: "future", deviceId: "strap", due: now.addingTimeInterval(30), now: now)
        delivery.connectionLost()
        connected(delivery)
        delivery.service(now: now.addingTimeInterval(30))
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(delivery.cues.first { $0.id == "future" }?.status, .unavailable)
    }

    func testCancelledAndExpiredCuesNeverReplay() {
        let delivery = make(); connected(delivery)
        let now = Date(); var writes = 0
        delivery.transmit = { _ in writes += 1; return .init(sequence: 1, opcode: 19) }
        delivery.schedule(owner: "cancel", deviceId: "strap", due: now.addingTimeInterval(100), now: now)
        delivery.cancel(owner: "cancel")
        delivery.schedule(owner: "expired", deviceId: "strap", due: now.addingTimeInterval(-10), now: now)
        delivery.service(now: now.addingTimeInterval(200))
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(delivery.cues.contains { $0.status == .cancelled })
        XCTAssertTrue(delivery.cues.contains { $0.status == .missed })
    }
    func testDisconnectedCueDoesNotReplayAfterReconnectAndStaleSensorIsRejected() {
        let delivery = make(); let now = Date(); var writes = 0
        delivery.transmit = { _ in writes += 1; return .init(sequence: 1, opcode: 19) }
        delivery.schedule(owner: "offline", deviceId: "strap", due: now, now: now)
        connected(delivery)
        delivery.service(now: now.addingTimeInterval(1))
        delivery.schedule(owner: "zone", deviceId: "strap", due: now, sampleAt: now.addingTimeInterval(-3), now: now)
        XCTAssertEqual(writes, 0)
    }
    func testResponsesRequireConnectionSequenceAndSuccessDetailAndNeverConfirmVibration() {
        let delivery = make(); let connection = UUID(); connected(delivery, connection: connection)
        let now = Date()
        delivery.transmit = { _ in .init(sequence: 7, opcode: 19) }
        delivery.schedule(owner: "test", id: "cue", deviceId: "strap", due: now, now: now)
        delivery.acknowledge(sequence: 7, opcode: 19, result: "SUCCESS(1)", payload: [1,5], deviceId: "strap", connection: UUID(), now: now)
        XCTAssertEqual(delivery.cues.last?.status, .requested)
        delivery.acknowledge(sequence: 7, opcode: 19, result: "PENDING(2)", payload: [1,0], deviceId: "strap", connection: connection, now: now)
        XCTAssertEqual(delivery.cues.last?.status, .responseReceived)
        delivery.acknowledge(sequence: 7, opcode: 19, result: "SUCCESS(1)", payload: [1,5], deviceId: "strap", connection: connection, now: now)
        XCTAssertEqual(delivery.cues.last?.status, .acknowledged)
        delivery.confirm(id: "cue")
        XCTAssertEqual(delivery.cues.last?.status, .confirmed)
    }
    func testRejectionIsNotAcknowledgment() {
        for result in ["FAILURE(0)", "UNSUPPORTED(3)"] {
        let delivery = make(); let connection = UUID(); connected(delivery, connection: connection)
        let now = Date()
        delivery.transmit = { _ in .init(sequence: 8, opcode: 19) }
        delivery.schedule(owner: "test", id: "cue", deviceId: "strap", due: now, now: now)
        delivery.acknowledge(sequence: 8, opcode: 19, result: result, deviceId: "strap", connection: connection, now: now)
        delivery.confirm(id: "cue")
        XCTAssertEqual(delivery.cues.last?.status, .rejected)
        }
    }
    func testRelaunchNeedsOwnerRevalidationAndDoesNotRepeatSentCue() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("buzz-tests-\(UUID().uuidString)/ledger.json")
        let first = BuzzDeliveryCoordinator(file: file); connected(first)
        let now = Date(), due = now.addingTimeInterval(100)
        first.schedule(owner: "meditation", id: "future", deviceId: "strap", due: due, now: now)
        let restored = BuzzDeliveryCoordinator(file: file); connected(restored)
        var writes = 0; restored.transmit = { _ in writes += 1; return .init(sequence: 1, opcode: 19) }
        restored.service(now: due)
        XCTAssertEqual(writes, 0)
        restored.schedule(owner: "meditation", id: "future", deviceId: "strap", due: due, now: due)
        XCTAssertEqual(writes, 1)
        let again = BuzzDeliveryCoordinator(file: file); connected(again)
        again.transmit = { _ in XCTFail("Must not replay on launch"); return nil }
        again.service(now: due)
    }
    func testExclusiveOwnerAndCorruptStorageFailClosed() throws {
        let delivery = make(); connected(delivery)
        XCTAssertTrue(delivery.claim("run"))
        XCTAssertFalse(delivery.claim("meditation"))
        let now = Date()
        delivery.schedule(owner: "ambient", deviceId: "strap", due: now, now: now)
        XCTAssertEqual(delivery.cues.last?.status, .suppressed)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("buzz-corrupt-\(UUID().uuidString).json")
        try Data("bad".utf8).write(to: file)
        let broken = BuzzDeliveryCoordinator(file: file)
        XCTAssertFalse(broken.claim("run"))
        broken.connectionLost()
        broken.release("run")
        XCTAssertNotNil(broken.storageError)
        XCTAssertEqual(try Data(contentsOf: file), Data("bad".utf8))
    }
}
