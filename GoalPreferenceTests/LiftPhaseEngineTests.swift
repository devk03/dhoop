import XCTest
import WhoopStore

final class LiftPhaseEngineTests: XCTestCase {
    private let slot = LiftSlot(exerciseIndex: 0, setIndex: 1)
    private func engine() -> LiftSessionEngine {
        LiftSessionEngine(plan: [.init(exercise: "Press", targetSets: 2, restSec: 60)], startTs: 100)
    }
    func testPauseSplitsWorkWithoutDuplicatingTheSet() {
        var state = engine()
        state.start(slot, now: 110)
        state.pause(now: 120)
        state.advance(now: 150)
        XCTAssertTrue(state.sets.isEmpty)
        state.resume(now: 160)
        state.advance(now: 180)
        XCTAssertEqual(state.sets.count, 1)
        XCTAssertEqual(state.sets.first?.startTs, 110)
        XCTAssertEqual(state.sets.first?.endTs, 180)
        XCTAssertEqual(state.activityPhases?.map(\.kind), [.work, .pause, .work, .rest])
        let work = state.activityPhases!.filter { $0.kind == .work }
        XCTAssertEqual(work.map { ($0.endedAt ?? 0) - $0.startedAt }, [10, 20])
        XCTAssertEqual(Set(state.activityPhases!.map(\.id)).count, 4)
        XCTAssertEqual(work.map(\.slot), [slot, slot])
    }
    func testRestFreezesAndExcludesPausedSeconds() {
        var state = engine()
        state.start(slot, now: 110)
        state.advance(now: 120)
        state.pause(now: 140)
        XCTAssertEqual(state.restRemaining(now: 1000), 40)
        XCTAssertNil(state.activityPhases?.last?.slot, "Rest pause is session-wide, outside the prior set envelope")
        state.resume(now: 200)
        XCTAssertEqual(state.restRemaining(now: 200), 40)
        state.advance(now: 215)
        XCTAssertEqual(state.sets.first?.restSec, 35)
    }
    func testRecoveryDoesNotCloseAnUnknownInterval() {
        var state = engine()
        state.start(slot, now: 110)
        let priorID = state.activityPhases!.first!.id
        state.markRecovered(now: 200)
        XCTAssertTrue(state.isPaused)
        state.resume(now: 210)
        state.advance(now: 230)
        XCTAssertEqual(state.activityPhases?.first?.id, priorID)
        XCTAssertNil(state.activityPhases?.first?.endedAt)
        XCTAssertEqual(state.activityPhases?.filter { $0.kind == .work && $0.endedAt != nil }.count, 1)
        XCTAssertEqual(state.sets.first?.startTs, 110)
    }
    func testFinishWhilePausedClosesOnlyTheObservedPause() {
        var state = engine()
        state.start(slot, now: 110)
        state.advance(now: 120)
        state.pause(now: 130)
        state.finish(now: 200)
        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.sets.first?.restSec, 10)
        XCTAssertEqual(state.activityPhases?.last?.endedAt, 200)
    }
    func testClockRegressionDoesNotCreateNegativeWork() {
        var state = engine()
        state.start(slot, now: 110)
        let before = state
        state.advance(now: 109)
        XCTAssertEqual(state, before)
    }
}
