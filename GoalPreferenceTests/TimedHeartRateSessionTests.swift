import XCTest

@MainActor
final class TimedHeartRateSessionTests: XCTestCase {
    func testOpeningWithoutPressingDoesNotRequestOrReleaseAStream() {
        let session = TimedHeartRateSession()
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.remainingSeconds(atUptime: 100), 0)
        session.stop()
        XCTAssertNil(session.deviceId)
    }

    func testExpiresAtSixtySecondsAndReleasesExactlyOneInterest() {
        let session = TimedHeartRateSession()
        var requests = 0, releases = 0
        session.start(deviceId: "strap-a", atUptime: 100, request: { requests += 1 }, release: { releases += 1 })
        XCTAssertEqual(session.remainingSeconds(atUptime: 100), 60)
        session.expireIfNeeded(atUptime: 159.99)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.remainingSeconds(atUptime: 159.99), 1)
        session.expireIfNeeded(atUptime: 160)
        session.expireIfNeeded(atUptime: 161)
        session.stop()
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(releases, 1)
    }

    func testRepeatedStartDoesNotExtendTheDeadlineOrLeakAnInterest() {
        let session = TimedHeartRateSession()
        var requests = 0, releases = 0
        session.start(deviceId: "strap-a", atUptime: 100, request: { requests += 1 }, release: { releases += 1 })
        XCTAssertFalse(session.start(deviceId: "strap-a", atUptime: 140, request: { requests += 1 }, release: { releases += 1 }))
        XCTAssertEqual(session.remainingSeconds(atUptime: 140), 20)
        session.stop()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(releases, 1)
    }

    func testEarlyStopReleasesOnlyThisOwnerAndAllowsAnotherSession() {
        let session = TimedHeartRateSession()
        var owners = 1 // A workout already wants the feed.
        session.start(deviceId: "strap-a", atUptime: 100, request: { owners += 1 }, release: { owners -= 1 })
        session.stop(); session.stop()
        XCTAssertEqual(owners, 1)
        XCTAssertTrue(session.start(deviceId: "strap-b", atUptime: 150, request: { owners += 1 }, release: { owners -= 1 }))
        XCTAssertEqual(session.deviceId, "strap-b")
        session.stop()
        XCTAssertEqual(owners, 1)
    }

    func testOldCancelledTimerCannotEndANewSession() {
        let session = TimedHeartRateSession()
        var releases = 0
        session.start(deviceId: "strap-a", atUptime: 100, request: {}, release: { releases += 1 })
        let oldId = session.sessionId!
        session.stop()
        session.start(deviceId: "strap-a", atUptime: 150, request: {}, release: { releases += 1 })
        session.expireIfNeeded(sessionId: oldId, atUptime: 500)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(releases, 1)
        session.expireIfNeeded(sessionId: session.sessionId, atUptime: 210)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(releases, 2)
    }

    func testDelayedTickExpiresWithoutAddingAnotherSixtySeconds() {
        let session = TimedHeartRateSession()
        var releases = 0
        session.start(deviceId: "strap-a", atUptime: 100, request: {}, release: { releases += 1 })
        session.expireIfNeeded(atUptime: 500)
        XCTAssertEqual(releases, 1)
        XCTAssertFalse(session.isActive)
    }

    func testReconnectCannotRearmAnExpiredSession() {
        let session = TimedHeartRateSession()
        var rearms = 0, releases = 0
        session.start(deviceId: "strap-a", atUptime: 100, request: {}, release: { releases += 1 })
        session.rearmIfValid(deviceId: "strap-a", connected: true, isWhoop: true, atUptime: 130, rearm: { rearms += 1 })
        session.rearmIfValid(deviceId: "strap-a", connected: true, isWhoop: true, atUptime: 160, rearm: { rearms += 1 })
        XCTAssertEqual(rearms, 1)
        XCTAssertEqual(releases, 1)
    }

    func testDisconnectOrSourceChangeReleasesInterestWithoutRearming() {
        for (device, connected, whoop) in [("strap-b", true, true), ("strap-a", false, true), ("strap-a", true, false)] {
            let session = TimedHeartRateSession()
            var rearms = 0, releases = 0
            session.start(deviceId: "strap-a", atUptime: 100, request: {}, release: { releases += 1 })
            session.rearmIfValid(deviceId: device, connected: connected, isWhoop: whoop, atUptime: 120, rearm: { rearms += 1 })
            XCTAssertEqual(rearms, 0)
            XCTAssertEqual(releases, 1)
            XCTAssertFalse(session.isActive)
        }
    }
}
