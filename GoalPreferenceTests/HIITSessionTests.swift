import XCTest

final class HIITSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    private let zone = RunningZoneTarget(name: "Target", lowerBPM: 120, upperBPM: 151, method: "Manual")
    private func make() -> HIITSession {
        HIITSession(deviceId: "strap", plan: HIITPlan(rounds: 2, workSeconds: 30, restSeconds: 15, warmupSeconds: 0, cooldownSeconds: 30), zones: [zone], startedAt: start)!
    }
    private func observe(_ run: inout HIITSession, _ elapsed: Double, _ bpm: Int, device: String = "strap", age: Double = 0) {
        _ = run.advance(to: elapsed)
        run.observe(RunningHeartRateSample(deviceId: device, bpm: bpm, receivedAt: 1000 + elapsed), elapsed: elapsed, now: 1000 + elapsed + age)
    }
    func testScheduleHasNoFinalRecoveryAndExactBoundaries() {
        var run = make()
        XCTAssertEqual(run.plan.intervals.map(\.kind), [.work, .recovery, .work, .cooldown])
        XCTAssertEqual(run.plan.totalSeconds, 105)
        XCTAssertEqual(run.interval?.label, "Work · round 1")
        XCTAssertTrue(run.advance(to: 30)); XCTAssertEqual(run.interval?.kind, .recovery)
        XCTAssertTrue(run.advance(to: 45)); XCTAssertEqual(run.interval?.label, "Work · round 2")
        XCTAssertTrue(run.advance(to: 75)); XCTAssertEqual(run.interval?.kind, .cooldown)
        XCTAssertTrue(run.advance(to: 105)); XCTAssertEqual(run.state, .completed)
        XCTAssertNil(run.effort().average)
    }
    func testDelayedTickResolvesOneCurrentTransition() {
        var run = make()
        XCTAssertTrue(run.advance(to: 80))
        XCTAssertEqual(run.interval?.kind, .cooldown)
        XCTAssertEqual(run.remaining, 25)
        XCTAssertFalse(run.advance(to: 80))
        XCTAssertFalse(run.advance(to: 79))
    }
    func testPausingDoesNotCountTimeOrConnectHeartRateAcrossPause() {
        var run = make()
        observe(&run, 1, 120); observe(&run, 2, 140)
        run.pause(); XCTAssertFalse(run.advance(to: 70)); XCTAssertEqual(run.elapsed, 2)
        run.resume(); observe(&run, 3, 130); observe(&run, 4, 130)
        XCTAssertEqual(run.effort().observedSeconds, 2)
        XCTAssertEqual(run.effort().average!, 130, accuracy: 0.001)
        XCTAssertNotEqual(run.points[1].segment, run.points[2].segment)
    }
    func testStaleWrongDeviceDuplicateAndMissingReadingsCannotInventEffort() {
        var run = make()
        observe(&run, 1, 120); observe(&run, 2, 140)
        observe(&run, 2, 180)
        observe(&run, 3, 200, device: "other")
        observe(&run, 4, 200, age: 3)
        observe(&run, 10, 130); observe(&run, 11, 130)
        XCTAssertEqual(run.points.count, 4)
        XCTAssertEqual(run.effort().observedSeconds, 2)
        XCTAssertEqual(run.effort().peak, 140)
        XCTAssertEqual(run.effort().zoneSeconds, [2])
        XCTAssertNotEqual(run.points[1].segment, run.points[2].segment)
    }
    func testReceiptAttributedToActualIntervalInsteadOfCurrentTick() {
        var run = make()
        run.advance(to: 30.5)
        XCTAssertTrue(run.observe(.init(deviceId: "strap", bpm: 150, receivedAt: 1029.5), elapsed: 29.5, now: 1030.5))
        XCTAssertEqual(run.points.first?.interval, 0)
        observe(&run, 30.5, 130)
        XCTAssertEqual(run.points.last?.interval, 1)
        XCTAssertEqual(run.effort(interval: 0).observedSeconds, 0)
        XCTAssertEqual(run.effort(interval: 1).observedSeconds, 0)
        XCTAssertEqual(run.effort().observedSeconds, 1)
    }
    func testZoneCrossingsRemainUnallocatedAndWeightedAverageUsesTime() {
        var run = make()
        observe(&run, 0, 100); observe(&run, 1, 140); observe(&run, 3, 150)
        XCTAssertEqual(run.effort().average!, (120 + 290) / 3, accuracy: 0.001)
        XCTAssertEqual(run.effort().zoneSeconds, [2])
    }
    func testRoundTripPreservesFullTraceBeyondLiveBuffer() throws {
        var run = HIITSession(deviceId: "strap", plan: HIITPlan(rounds: 2, workSeconds: 600, restSeconds: 60, warmupSeconds: 0, cooldownSeconds: 0), zones: [zone], startedAt: start)!
        for second in 0...700 { observe(&run, Double(second), 130) }
        run.pause()
        let restored = try JSONDecoder().decode(HIITSession.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(restored, run); XCTAssertEqual(restored.points.count, 701)
        XCTAssertEqual(restored.effort().observedSeconds, 700)
    }
    func testCompletionRetainsFreshReceiptsBeforeFinalBoundaryOnly() {
        var run = make()
        observe(&run, 103.5, 130)
        run.advance(to: 105.5)
        XCTAssertTrue(run.observe(.init(deviceId: "strap", bpm: 140, receivedAt: 1104.5), elapsed: 104.5, now: 1105.5))
        XCTAssertFalse(run.observe(.init(deviceId: "strap", bpm: 150, receivedAt: 1105), elapsed: 105, now: 1105.5))
        XCTAssertEqual(run.state, .completed)
        XCTAssertEqual(run.effort().observedSeconds, 1)
    }
    func testInvalidPlansRejectedAndEarlyEndRetainsRecordedData() {
        XCTAssertNil(HIITSession(deviceId: "strap", plan: HIITPlan(rounds: 0), zones: []))
        var run = make(); observe(&run, 1, 130); run.finish(at: start.addingTimeInterval(2))
        XCTAssertEqual(run.state, .ended); XCTAssertEqual(run.points.count, 1)
        XCTAssertFalse(run.advance(to: 105))
    }
}
