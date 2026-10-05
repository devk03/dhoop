import XCTest

final class DashboardSnapshotCadenceTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testSnapshotDoesNotRefreshAtPacketCadence() {
        let snapshot = date("2026-10-04T12:00:00Z")
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: snapshot, now: snapshot.addingTimeInterval(1)), 899)
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: snapshot, now: snapshot.addingTimeInterval(899)), 1)
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: snapshot, now: snapshot.addingTimeInterval(900)), 0)
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: snapshot, now: snapshot.addingTimeInterval(3600)), 0)
    }
    func testMidnightRefreshUsesLocalCalendarIncludingDST() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let before = date("2026-11-02T07:58:00Z") // 23:58 PST, after fall-back
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: before, now: before, calendar: c), 120)
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: before, now: before.addingTimeInterval(120), calendar: c), 0)
    }
    func testManualRefreshRestartsWaitAndClockRollbackCannotFreezeSnapshot() {
        let snapshot = date("2026-10-04T12:00:00Z")
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: snapshot.addingTimeInterval(600), now: snapshot.addingTimeInterval(900)), 600)
        XCTAssertEqual(DashboardSnapshotCadence.delay(after: snapshot, now: snapshot.addingTimeInterval(-60)), 0)
    }
}
