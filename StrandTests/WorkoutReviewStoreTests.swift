import XCTest
@testable import Strand

final class WorkoutReviewStoreTests: XCTestCase {
    func testReviewSurvivesReloadBoundaryShiftAndScanExpiryWithoutCrossingDevices() throws {
        let suite = "WorkoutReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkoutReviewStore(defaults: defaults)
        var original = WorkoutReview(deviceID: "strap-a", startSec: 1000, endSec: 1900,
            avgBpm: 130, peakBpm: 150, durationMin: 15)
        try store.capture(original)
        original.decision = .notWorkout
        try store.save(original)
        try store.capture(WorkoutReview(deviceID: "strap-a", startSec: 1010, endSec: 1910,
            avgBpm: 132, peakBpm: 151, durationMin: 15))
        let reloaded = WorkoutReviewStore(defaults: defaults)
        XCTAssertEqual(try reloaded.reviews(deviceID: "strap-a"), [original],
            "An old rejected snapshot must survive reload and shifted redetection")
        XCTAssertEqual(try reloaded.reviews(deviceID: "strap-b"), [])
        original.decision = .workout
        original.linkedWorkout = .init(owner: "strap-a-noop", startSec: 1000, endSec: 1900,
                                      sport: "Workout", source: "strap-a-noop")
        try reloaded.save(original)
        XCTAssertEqual(try store.reviews(deviceID: "strap-a"), [original])
    }

    func testSeparateSuggestionsRetainEveryPendingDecision() throws {
        let suite = "WorkoutReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkoutReviewStore(defaults: defaults)
        let older = WorkoutReview(deviceID: "strap", startSec: 1000, endSec: 1900,
                                  avgBpm: 130, peakBpm: 150, durationMin: 15)
        let newer = WorkoutReview(deviceID: "strap", startSec: 3000, endSec: 3900,
                                  avgBpm: 140, peakBpm: 160, durationMin: 15)
        try store.capture(older)
        try store.capture(newer)
        XCTAssertEqual(try store.reviews(deviceID: "strap"), [newer, older])
    }

    func testPendingSnapshotExtendsWithoutLosingIdentityOrBeingTruncatedByRollingScan() throws {
        let suite = "WorkoutReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkoutReviewStore(defaults: defaults)
        let initial = WorkoutReview(deviceID: "strap", startSec: 1000, endSec: 1900,
                                    avgBpm: 130, peakBpm: 150, durationMin: 15)
        try store.capture(initial)
        try store.capture(WorkoutReview(deviceID: "strap", startSec: 1000, endSec: 2800,
            avgBpm: 135, peakBpm: 155, durationMin: 30))
        let extended = try XCTUnwrap(store.reviews(deviceID: "strap").first)
        XCTAssertEqual(extended.id, initial.id)
        XCTAssertEqual(extended.endSec, 2800)
        XCTAssertEqual(extended.durationMin, 30)
        try store.capture(WorkoutReview(deviceID: "strap", startSec: 1900, endSec: 2800,
            avgBpm: 140, peakBpm: 155, durationMin: 15))
        XCTAssertEqual(try store.reviews(deviceID: "strap"), [extended])
    }

    func testRefreshCaptureIsSingleFlightCadencedAndIndependentForEachDevice() {
        var cadence = WorkoutReviewCaptureCadence()
        let now = Date(timeIntervalSince1970: 10000)
        XCTAssertTrue(cadence.begin(deviceID: "a", now: now))
        XCTAssertFalse(cadence.begin(deviceID: "b", now: now), "Two scans must not overlap")
        cadence.finish()
        XCTAssertFalse(cadence.begin(deviceID: "a", now: now.addingTimeInterval(899)))
        XCTAssertTrue(cadence.begin(deviceID: "b", now: now))
        cadence.finish()
        XCTAssertTrue(cadence.begin(deviceID: "a", now: now.addingTimeInterval(900)))
    }

    func testCorruptHistoryIsReportedAndNotOverwritten() throws {
        let suite = "WorkoutReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("unreadable history".utf8)
        defaults.set(corrupt, forKey: WorkoutReviewStore.key)
        let store = WorkoutReviewStore(defaults: defaults)
        XCTAssertThrowsError(try store.capture(WorkoutReview(deviceID: "strap", startSec: 1000,
            endSec: 1900, avgBpm: 130, peakBpm: 150, durationMin: 15)))
        XCTAssertEqual(defaults.data(forKey: WorkoutReviewStore.key), corrupt)
    }
}
