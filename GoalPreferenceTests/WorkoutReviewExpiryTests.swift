import XCTest

final class WorkoutReviewExpiryTests: XCTestCase {
    func testExpiryBoundarySuppressesRedetectionAndPreservesDecisionsAndOtherDevices() throws {
        let suite = "ExpiryTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkoutReviewStore(defaults: defaults)
        let pending = WorkoutReview(deviceID: "a", startSec: 100, endSec: 1000, avgBpm: 130, peakBpm: 160, durationMin: 15)
        var confirmed = WorkoutReview(deviceID: "a", startSec: 2000, endSec: 3000, avgBpm: 140, peakBpm: 160, durationMin: 15)
        confirmed.decision = .workout
        var rejected = WorkoutReview(deviceID: "a", startSec: 4000, endSec: 5000, avgBpm: 140, peakBpm: 160, durationMin: 15)
        rejected.decision = .notWorkout
        let other = WorkoutReview(deviceID: "b", startSec: 100, endSec: 1000, avgBpm: 130, peakBpm: 160, durationMin: 15)
        for row in [pending, confirmed, rejected, other] { try store.save(row) }
        XCTAssertEqual(try store.expirePending(deviceID: "a", now: 173799), 0)
        XCTAssertEqual(try store.expirePending(deviceID: "a", now: 173800), 1)
        XCTAssertEqual(try store.expirePending(deviceID: "a", now: 300000), 0)
        try store.capture(WorkoutReview(deviceID: "a", startSec: 90, endSec: 1100, avgBpm: 135, peakBpm: 170, durationMin: 17))
        let rows = try store.all()
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.first { $0.id == pending.id }?.expiredAt, 173800)
        XCTAssertEqual(rows.first { $0.id == pending.id }?.endSec, 1000)
        XCTAssertEqual(rows.first { $0.id == confirmed.id }, confirmed)
        XCTAssertEqual(rows.first { $0.id == rejected.id }, rejected)
        XCTAssertNil(rows.first { $0.id == other.id }?.expiredAt)
    }
    func testSleepStageMissingZeroAndInvalidFractionsRemainDistinct() {
        XCTAssertNil(SleepComparisonProjection.stageFraction(nil, total: 400))
        XCTAssertEqual(SleepComparisonProjection.stageFraction(0, total: 400), 0)
        XCTAssertEqual(SleepComparisonProjection.stageFraction(100, total: 400), 0.25)
        XCTAssertNil(SleepComparisonProjection.stageFraction(410, total: 400))
        XCTAssertNil(SleepComparisonProjection.stageFraction(.nan, total: 400))
    }
}
