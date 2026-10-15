import XCTest
import WhoopStore

final class LiftSupersetTests: XCTestCase {
    func testAlternatesRoundThenRestsAndRetainsObservedMetadata() {
        var engine = LiftSessionEngine(plan: [
            .init(exercise:"Press",targetSets:2,restSec:60,supersetGroupId:"g"),
            .init(exercise:"Row",targetSets:2,restSec:60,supersetGroupId:"g")],startTs:100)
        engine.advance(now:110)
        engine.advance(now:120)
        XCTAssertEqual(engine.stage,.working(.init(exerciseIndex:1,setIndex:1)))
        engine.advance(now:130)
        XCTAssertEqual(engine.stage,.resting(.init(exerciseIndex:1,setIndex:1),endsAt:190))
        engine.advance(now:190)
        engine.advance(now:200)
        engine.advance(now:210)
        XCTAssertEqual(engine.sets.map(\.exerciseIndex),[0,1,0,1])
        XCTAssertEqual(engine.sets.map(\.roundIndex),[0,0,1,1])
        XCTAssertEqual(engine.sets.map(\.supersetGroupId),["g","g","g","g"])
        _ = engine.setSupersetGroup(nil,forExercise:0)
        XCTAssertEqual(engine.sets.first?.supersetGroupId,"g")
    }
    func testUnequalSetsAndReplacementDoNotLoseEarlierWork() {
        var engine = LiftSessionEngine(plan:[.init(exercise:"Press",targetSets:1,supersetGroupId:"g"),
            .init(exercise:"Row",targetSets:2,supersetGroupId:"g")],startTs:100)
        engine.advance(now:110);engine.advance(now:120);engine.advance(now:130)
        let replacement = engine.replaceExercise(1,with:.init(exercise:"Cable row"))
        XCTAssertEqual(replacement,2)
        XCTAssertEqual(engine.plan[2].supersetGroupId,"g")
        engine.advance(now:140)
        XCTAssertEqual(engine.currentSlot?.exerciseIndex,2)
        XCTAssertEqual(engine.sets.map(\.exerciseIndex),[0,1])
    }
    func testRoundAndGroupingSurvivePersistenceAndPause() throws {
        var engine = LiftSessionEngine(plan:[.init(exercise:"Press",targetSets:2,supersetGroupId:"g"),
            .init(exercise:"Row",targetSets:2,supersetGroupId:"g")],startTs:1_780_000_000)
        engine.advance(now:1_780_000_010);engine.advance(now:1_780_000_020)
        engine.pause(now:1_780_000_030)
        let snapshot = LiftSessionPersistence.snapshot(engine:engine,programId:nil,programName:nil,pendingValues:[:],pendingWarmups:[])
        let decoded = try XCTUnwrap(LiftSessionPersistence.decode(LiftSessionPersistence.encode(snapshot)))
        let restored = LiftSessionPersistence.engine(from:decoded)
        XCTAssertEqual(restored.plan,engine.plan)
        XCTAssertEqual(restored.sets,engine.sets)
        XCTAssertEqual(restored.activityPhases,engine.activityPhases)
        XCTAssertEqual(restored.pauseState,engine.pauseState)
    }

    func testLinkIsOneUndoAndWarmupDoesNotClaimAWorkRound() {
        var engine = LiftSessionEngine(plan:[.init(exercise:"Press",targetSets:2),.init(exercise:"Row",targetSets:2)],startTs:100)
        XCTAssertTrue(engine.groupWithPreviousExercise(1,newGroupID:"g"))
        engine.undo()
        XCTAssertEqual(engine.plan.map(\.supersetGroupId),[nil,nil])
        _ = engine.groupWithPreviousExercise(1,newGroupID:"g")
        engine.advance(now:110);engine.advance(now:120,isWarmup:true)
        XCTAssertNil(engine.sets.first?.supersetGroupId)
        XCTAssertNil(engine.sets.first?.roundIndex)
        if case .resting = engine.stage {} else { XCTFail("Warmup should retain its rest") }
    }
}
