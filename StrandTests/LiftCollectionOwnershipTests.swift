import XCTest
@testable import Strand

@MainActor
final class LiftCollectionOwnershipTests: XCTestCase {
    override func tearDown() {
        LiftSessionPersistence.clear()
        super.tearDown()
    }

    private var plan: [LiftPlanItem] {
        [LiftPlanItem(exercise: "Bench press", targetSets: 3, restSec: 60)]
    }

    func testStartingAndReopeningCannotDuplicateTheCollectionClaim() {
        var claims: [Bool] = []
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in },
            setCollectionActive: { claims.append($0); return true })
        XCTAssertTrue(controller.start(plan: plan, programId: nil, programName: "Upper A"))
        let start = controller.engine?.startTs
        XCTAssertFalse(controller.start(plan: plan, programId: nil, programName: "Upper B"))
        XCTAssertTrue(controller.claimCollection())
        controller.isPresented = false
        controller.isPresented = true
        XCTAssertEqual(claims, [true])
        XCTAssertEqual(controller.engine?.startTs, start)
        controller.discard()
        controller.discard()
        XCTAssertEqual(claims, [true, false])
    }

    func testRejectedOwnerDoesNotCreateOrReleaseAnotherSessionsStream() {
        var claims: [Bool] = []
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in },
            setCollectionActive: { claims.append($0); return false })
        XCTAssertFalse(controller.start(plan: plan, programId: nil, programName: nil))
        XCTAssertNil(controller.engine)
        XCTAssertNotNil(controller.collectionMessage)
        controller.discard()
        XCTAssertEqual(claims, [true])
    }

    func testRestoredSessionAcquiresOnceAndSavedSessionReleasesOnce() throws {
        let original = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        original.start(plan: plan, programId: "routine", programName: "Upper A")
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load())
        var claims: [Bool] = []
        let restored = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in },
            setCollectionActive: { claims.append($0); return true })
        restored.resume(from: snapshot)
        restored.resume(from: snapshot)
        XCTAssertEqual(restored.engine?.startTs, snapshot.startSec)
        XCTAssertEqual(claims, [true])
        restored.finishedSaving()
        restored.finishedSaving()
        XCTAssertEqual(claims, [true, false])
    }

    func testCaptureSourceSurvivesRelaunchAndRejectsAnotherStrapsGesture() throws {
        var activeDevice = "strap-a"
        let original = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in },
            currentDeviceId: { activeDevice })
        original.start(plan: plan, programId: nil, programName: nil)
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load())
        XCTAssertEqual(snapshot.sourceDeviceId, "strap-a")
        activeDevice = "strap-b"
        let restored = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in },
            currentDeviceId: { activeDevice })
        restored.resume(from: snapshot)
        let stage = restored.engine?.stage
        restored.advance(fromStrap: true)
        XCTAssertEqual(restored.sourceDeviceId, "strap-a")
        XCTAssertEqual(restored.engine?.stage, stage)
        restored.discard()
    }

    func testPendingSaveCannotBeChangedByHardwareGestureOrRepeatedSubmission() {
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        controller.start(plan: plan, programId: nil, programName: nil)
        controller.advance()
        let stage = controller.engine?.stage
        XCTAssertTrue(controller.beginSaving())
        XCTAssertFalse(controller.beginSaving())
        controller.advance(fromStrap: true)
        controller.updateSet(LiftSlot(exerciseIndex: 0, setIndex: 1), weightKg: 99, reps: 20, rpe: 10, isWarmup: false)
        XCTAssertEqual(controller.engine?.stage, stage)
        XCTAssertTrue(controller.pendingValues.isEmpty)
        controller.endSaving()
        controller.advance()
        XCTAssertEqual(controller.engine?.sets.count, 1)
        controller.discard()
    }
}
