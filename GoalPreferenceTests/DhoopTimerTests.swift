import Foundation
import XCTest

@MainActor
final class DhoopTimerTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("countdown-test-" + UUID().uuidString) }
    private func ready(_ buzz: BuzzDeliveryCoordinator) {
        let connection = UUID(); buzz.link = { .init(deviceId: "test-strap", connection: connection, ready: true) }
    }
    func testCountdownPauseResumeRetainsRemainingAndChangesCueIdentity() {
        let now = Date(timeIntervalSince1970: 1000); var session = DhoopTimerSession()
        XCTAssertFalse(session.start(seconds: 0, deviceID: "strap", backup: false, now: now))
        XCTAssertTrue(session.start(seconds: 60, deviceID: "strap", backup: false, now: now)); let old = session.cueID
        XCTAssertTrue(session.pause(now: now.addingTimeInterval(17))); XCTAssertEqual(session.remaining, 43)
        XCTAssertEqual(session.remaining(at: now.addingTimeInterval(100)), 43)
        XCTAssertTrue(session.resume(now: now.addingTimeInterval(100))); XCTAssertNotEqual(old, session.cueID)
        XCTAssertEqual(session.deadline, now.addingTimeInterval(143)); XCTAssertTrue(session.valid)
    }
    func testCompletionRequestsOnlyOneSharedBuzzAndReleasesOwner() {
        let folder = root(); var now = Date(); let buzz = BuzzDeliveryCoordinator(file: folder.appendingPathComponent("buzz.json")); ready(buzz)
        var requests = 0; buzz.transmit = { _ in requests += 1; return .init(sequence: 1, opcode: 19) }
        let timer = DhoopTimerController(file: .init(url: folder.appendingPathComponent("timer.json")), clock: { now })
        timer.attach(coordinator: buzz, foreground: true, keepAwake: { _ in })
        XCTAssertTrue(timer.start(seconds: 30, backup: false)); now = now.addingTimeInterval(30)
        timer.reconcile(); timer.reconcile(); XCTAssertEqual(requests, 1); XCTAssertEqual(timer.session.phase, .completed)
        XCTAssertNil(buzz.exclusiveOwner); XCTAssertEqual(timer.cue?.status, .requested)
    }
    func testCancelAndPauseDoNotLeaveScheduledBuzzes() {
        let folder = root(); var now = Date(); let buzz = BuzzDeliveryCoordinator(file: folder.appendingPathComponent("buzz.json")); ready(buzz)
        var requests = 0; buzz.transmit = { _ in requests += 1; return nil }
        let timer = DhoopTimerController(file: .init(url: folder.appendingPathComponent("timer.json")), clock: { now })
        timer.attach(coordinator: buzz, foreground: true, keepAwake: { _ in })
        XCTAssertTrue(timer.start(seconds: 30, backup: false)); let old = timer.session.cueID
        XCTAssertFalse(timer.resume()); XCTAssertEqual(buzz.cues.first { $0.id == old }?.status, .scheduled)
        now = now.addingTimeInterval(8); XCTAssertTrue(timer.pause()); XCTAssertNil(buzz.exclusiveOwner)
        XCTAssertTrue(timer.resume()); XCTAssertNotEqual(timer.session.cueID, old)
        XCTAssertTrue(timer.cancel()); now = now.addingTimeInterval(50); timer.reconcile()
        XCTAssertEqual(requests, 0); XCTAssertTrue(buzz.cues.allSatisfy { $0.status == .cancelled })
    }
    func testOtherExerciseAndWakeWindowTakePriority() {
        let folder = root(); var now = Date(); let buzz = BuzzDeliveryCoordinator(file: folder.appendingPathComponent("buzz.json")); ready(buzz)
        let timer = DhoopTimerController(file: .init(url: folder.appendingPathComponent("timer.json")), clock: { now })
        timer.attach(coordinator: buzz, foreground: false, keepAwake: { _ in })
        XCTAssertTrue(buzz.claim("workout")); XCTAssertFalse(timer.start(seconds: 10, backup: false)); XCTAssertEqual(timer.session.phase, .idle)
        buzz.release("workout"); XCTAssertTrue(timer.start(seconds: 10, backup: false))
        buzz.motorBlocked = { _ in true }; now = now.addingTimeInterval(10); timer.reconcile()
        XCTAssertEqual(timer.cue?.status, .suppressed); XCTAssertEqual(timer.session.phase, .completed)
    }
    func testDisconnectDoesNotReplayCueAfterReconnect() {
        let folder = root(); var now = Date(); let buzz = BuzzDeliveryCoordinator(file: folder.appendingPathComponent("buzz.json")); ready(buzz)
        var requests = 0; buzz.transmit = { _ in requests += 1; return nil }
        let timer = DhoopTimerController(file: .init(url: folder.appendingPathComponent("timer.json")), clock: { now })
        timer.attach(coordinator: buzz, foreground: true, keepAwake: { _ in })
        XCTAssertTrue(timer.start(seconds: 30, backup: false)); buzz.connectionLost(); ready(buzz)
        now = now.addingTimeInterval(40); timer.setForeground(true); XCTAssertEqual(requests, 0)
        XCTAssertEqual(timer.cue?.status, .unavailable)
    }
    func testExpiredRelaunchDoesNotRearmOrReplayMissedTimer() {
        let folder = root(); var now = Date(); let file = DhoopTimerFile(url: folder.appendingPathComponent("timer.json"))
        let buzzFile = folder.appendingPathComponent("buzz.json"); let buzz = BuzzDeliveryCoordinator(file: buzzFile); ready(buzz)
        let first = DhoopTimerController(file: file, clock: { now }); first.attach(coordinator: buzz, foreground: true, keepAwake: { _ in })
        XCTAssertTrue(first.start(seconds: 15, backup: false)); now = now.addingTimeInterval(100)
        let restoredBuzz = BuzzDeliveryCoordinator(file: buzzFile); ready(restoredBuzz); var requests = 0
        restoredBuzz.transmit = { _ in requests += 1; return nil }
        let restored = DhoopTimerController(file: file, clock: { now }); restored.attach(coordinator: restoredBuzz, foreground: true, keepAwake: { _ in })
        XCTAssertEqual(restored.session.phase, .completed); XCTAssertEqual(requests, 0)
    }
    func testCorruptTimerFileIsPreservedAndCannotSchedule() throws {
        let folder = root(); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("timer.json"), original = Data("invalid timer".utf8); try original.write(to: file)
        let buzz = BuzzDeliveryCoordinator(file: folder.appendingPathComponent("buzz.json")); ready(buzz)
        let timer = DhoopTimerController(file: .init(url: file)); timer.attach(coordinator: buzz, foreground: true, keepAwake: { _ in })
        XCTAssertFalse(timer.start(seconds: 5, backup: false)); XCTAssertEqual(try Data(contentsOf: file), original); XCTAssertTrue(buzz.cues.isEmpty)
    }
    func testScreenAwakeHoldEndsOnPauseBackgroundAndCompletion() {
        let folder = root(); var now = Date(); let buzz = BuzzDeliveryCoordinator(file: folder.appendingPathComponent("buzz.json")); ready(buzz)
        var held = false; let timer = DhoopTimerController(file: .init(url: folder.appendingPathComponent("timer.json")), clock: { now })
        timer.attach(coordinator: buzz, foreground: true, keepAwake: { held = $0 })
        XCTAssertTrue(timer.start(seconds: 10, backup: false)); XCTAssertTrue(held)
        timer.setForeground(false); XCTAssertFalse(held); timer.setForeground(true); XCTAssertTrue(held)
        XCTAssertTrue(timer.pause()); XCTAssertFalse(held); XCTAssertTrue(timer.resume()); XCTAssertTrue(held)
        now = now.addingTimeInterval(11); timer.reconcile(); XCTAssertFalse(held)
    }
}
