import XCTest

final class MeditationSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testStartIsExplicitAndRepeatedStartCannotExtendDeadline() {
        var session = MeditationSession()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.completeIfDue(at: start, foreground: true, strapReady: true))
        XCTAssertTrue(session.start(at: start, deviceId: "strap-a"))
        XCTAssertFalse(session.start(at: start.addingTimeInterval(200), deviceId: "strap-b"))
        XCTAssertEqual(session.deadline, Date(timeIntervalSince1970: 1_900))
        XCTAssertEqual(session.deviceId, "strap-a")
    }

    func testPauseAndResumePreserveUnspentTimeAndInvalidateOldNotification() {
        var session = MeditationSession()
        session.start(at: start, deviceId: "strap-a")
        let originalNotification = session.notificationId
        XCTAssertTrue(session.pause(at: start.addingTimeInterval(120)))
        XCTAssertNil(session.notificationId)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(5_000)), 780)
        XCTAssertNil(session.completeIfDue(at: start.addingTimeInterval(5_000), foreground: true, strapReady: true))
        XCTAssertTrue(session.resume(at: start.addingTimeInterval(5_000)))
        XCTAssertEqual(session.deadline, Date(timeIntervalSince1970: 6_780))
        XCTAssertNotEqual(session.notificationId, originalNotification)
        XCTAssertFalse(session.resume(at: start.addingTimeInterval(6_000)))
    }

    func testCancelRunningOrPausedNeverCompletesAndAllowsFreshSession() {
        for paused in [false, true] {
            var session = MeditationSession()
            session.start(at: start, deviceId: "strap-a")
            let oldID = session.id
            if paused { session.pause(at: start.addingTimeInterval(60)) }
            XCTAssertTrue(session.cancel())
            XCTAssertFalse(session.cancel())
            XCTAssertNil(session.notificationId)
            XCTAssertNil(session.completeIfDue(at: start.addingTimeInterval(1_000), foreground: true, strapReady: true))
            XCTAssertTrue(session.start(at: start.addingTimeInterval(2_000), deviceId: "strap-b"))
            XCTAssertNotEqual(session.id, oldID)
            XCTAssertEqual(session.remaining(at: start.addingTimeInterval(2_000)), 900)
        }
    }

    func testCompletionIsClaimedExactlyOnceIncludingAfterPersistence() throws {
        var session = MeditationSession()
        session.start(at: start, deviceId: "strap-a")
        XCTAssertNil(session.completeIfDue(at: start.addingTimeInterval(899), foreground: true, strapReady: true))
        XCTAssertEqual(session.completeIfDue(at: start.addingTimeInterval(900), foreground: true, strapReady: true), .buzzRequested)
        XCTAssertEqual(session.completedAt, Date(timeIntervalSince1970: 1_900))
        XCTAssertNil(session.completeIfDue(at: start.addingTimeInterval(901), foreground: true, strapReady: true))
        var restored = try JSONDecoder().decode(MeditationSession.self, from: JSONEncoder().encode(session))
        XCTAssertNil(restored.completeIfDue(at: start.addingTimeInterval(902), foreground: true, strapReady: true))
        XCTAssertEqual(restored.completionAlert, .buzzRequested)
    }

    func testRelaunchKeepsOriginalWallClockDeadlineAndSuppressesLateBuzz() throws {
        var session = MeditationSession()
        session.start(at: start, deviceId: "strap-a")
        var restored = try JSONDecoder().decode(MeditationSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(600)), 300)
        XCTAssertEqual(restored.completeIfDue(at: start.addingTimeInterval(1_200), foreground: true, strapReady: true), .missedWhileAway)
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(1_200)), 0)
        XCTAssertFalse(restored.resume(at: start.addingTimeInterval(1_200)))
    }

    func testBackgroundDisconnectedAndGraceBoundaryHaveHonestDispositions() {
        let cases: [(TimeInterval, Bool, Bool, MeditationSession.CompletionAlert)] = [
            (900, false, true, .missedWhileAway),
            (900, true, false, .strapUnavailable),
            (910, true, true, .buzzRequested),
            (910.01, true, true, .missedWhileAway)
        ]
        for (elapsed, foreground, ready, expected) in cases {
            var session = MeditationSession()
            session.start(at: start, deviceId: "strap-a")
            XCTAssertEqual(session.completeIfDue(at: start.addingTimeInterval(elapsed), foreground: foreground, strapReady: ready), expected)
            XCTAssertNil(session.completeIfDue(at: start.addingTimeInterval(elapsed + 1), foreground: true, strapReady: true))
        }
    }

    func testPauseAtDeadlineCannotReviveExpiredTimer() {
        var session = MeditationSession()
        session.start(at: start, deviceId: "strap-a")
        XCTAssertFalse(session.pause(at: start.addingTimeInterval(900)))
        XCTAssertEqual(session.completeIfDue(at: start.addingTimeInterval(900), foreground: true, strapReady: true), .buzzRequested)
    }
    func testAtomicFileRestoresCompletionWithoutAnotherDisposition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MeditationSessionFileStore(fileURL: directory.appendingPathComponent("session.json"))
        XCTAssertEqual(try store.load().phase, .idle)
        var session = MeditationSession()
        session.start(at: start, deviceId: "strap-a")
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        XCTAssertEqual(session.completeIfDue(at: start.addingTimeInterval(900), foreground: true, strapReady: true), .buzzRequested)
        try store.save(session)
        var restored = try store.load()
        XCTAssertEqual(restored.completionAlert, .buzzRequested)
        XCTAssertNil(restored.completeIfDue(at: start.addingTimeInterval(901), foreground: true, strapReady: true))
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testFailedFileWriteAndCorruptReadAreReportedWithoutReplacingBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockingFile = directory.appendingPathComponent("blocker")
        let original = Data("preserve existing bytes".utf8)
        try original.write(to: blockingFile)
        let blockedStore = MeditationSessionFileStore(fileURL: blockingFile.appendingPathComponent("session.json"))
        XCTAssertThrowsError(try blockedStore.save(MeditationSession()))
        XCTAssertEqual(try Data(contentsOf: blockingFile), original)
        let corruptStore = MeditationSessionFileStore(fileURL: blockingFile)
        XCTAssertThrowsError(try corruptStore.load())
        XCTAssertEqual(try Data(contentsOf: blockingFile), original)
    }

}
