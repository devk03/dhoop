import XCTest

final class RemoteBuzzInboxPolicyTests: XCTestCase {
    func testQuietChecksBackOffAndActivityResetsDelay() {
        let start = Date(timeIntervalSince1970: 1791500000)
        var policy = RemoteBuzzInboxPolicy()
        XCTAssertTrue(policy.begin(.foreground, now: start))
        policy.finish(success: true, commandCount: 0)
        XCTAssertFalse(policy.begin(.bluetooth, now: start.addingTimeInterval(29)))
        XCTAssertTrue(policy.begin(.bluetooth, now: start.addingTimeInterval(30)))
        policy.finish(success: true, commandCount: 0)
        XCTAssertFalse(policy.begin(.bluetooth, now: start.addingTimeInterval(89)))
        XCTAssertTrue(policy.begin(.bluetooth, now: start.addingTimeInterval(90)))
        policy.finish(success: true, commandCount: 1)
        XCTAssertEqual(policy.delay, 15)
    }
    func testFailuresBackOffButReconnectAllowsOneFreshAttempt() {
        let start = Date(timeIntervalSince1970: 1791500000)
        var policy = RemoteBuzzInboxPolicy()
        XCTAssertTrue(policy.begin(.manual, now: start))
        for _ in 0..<10 { policy.finish(success: false, commandCount: 0) }
        XCTAssertEqual(policy.delay, 300)
        XCTAssertFalse(policy.begin(.reconnect, now: start.addingTimeInterval(4)))
        XCTAssertTrue(policy.begin(.reconnect, now: start.addingTimeInterval(5)))
        XCTAssertFalse(policy.begin(.bluetooth, now: start.addingTimeInterval(299)))
        policy.finish(success: true, commandCount: 1)
        XCTAssertEqual(policy.delay, 15)
    }
}
