import Foundation
import XCTest
import WhoopStore

@MainActor
final class LiftPhaseRecoveryTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "dhoop-phase-test-\(UUID().uuidString)")! }
    func testPausedRecoveryRetainsInputIdentityAndUnknownEnd() throws {
        let d = defaults()
        var engine = LiftSessionEngine(plan: [.init(exercise: "Press", targetSets: 2, restSec: 60)], startTs: 1_780_000_000)
        let slot = LiftSlot(exerciseIndex: 0, setIndex: 1)
        engine.start(slot, now: 1_780_000_010)
        let setID = UUID(), recordingID = UUID()
        let snapshot = LiftSessionPersistence.snapshot(engine: engine, programId: nil, programName: nil,
            pendingValues: [slot:.init(weightKg:42,reps:8,rpe:nil)], pendingWarmups: [],
            sourceDeviceId:"strap",recordingId:recordingID.uuidString,
            setIdentities:[.init(exerciseIndex:0,setIndex:1,id:setID.uuidString)])
        let decoded = try XCTUnwrap(LiftSessionPersistence.decode(LiftSessionPersistence.encode(snapshot)))
        var buzzes: [UInt8] = []
        let controller = LiftSessionController(buzz: { buzzes.append($0) }, setStrapHandler:{ _ in }, persistenceDefaults:d)
        controller.resume(from: decoded)
        XCTAssertTrue(controller.engine?.isPaused == true)
        XCTAssertEqual(controller.identity(for:slot),setID)
        XCTAssertEqual(controller.recordingId,recordingID)
        XCTAssertEqual(controller.pendingValues[slot]?.weightKg,42)
        controller.advance(fromStrap:true)
        XCTAssertTrue(controller.engine?.sets.isEmpty == true)
        XCTAssertTrue(buzzes.isEmpty)
        controller.togglePause()
        controller.advance()
        let phases = try XCTUnwrap(controller.activityIntervals(finishingAt:LiftSessionController.unixNow))
        XCTAssertNil(phases.first?.endedAt)
        XCTAssertEqual(phases.filter { $0.kind == .work }.map(\.sourceSetId), [setID.uuidString.lowercased(),setID.uuidString.lowercased()])
        controller.discard()
    }
    func testPausingRestCancelsItsPendingCue() async throws {
        let d = defaults()
        var buzzes: [UInt8] = []
        let controller = LiftSessionController(buzz: { buzzes.append($0) }, setStrapHandler:{ _ in }, persistenceDefaults:d)
        controller.start(plan:[.init(exercise:"Press",targetSets:2,restSec:2)],programId:nil,programName:nil)
        controller.advance(); controller.advance(); controller.togglePause()
        let remaining = controller.engine?.restRemaining(now:LiftSessionController.unixNow)
        try await Task.sleep(nanoseconds:2_200_000_000)
        XCTAssertEqual(controller.engine?.restRemaining(now:LiftSessionController.unixNow),remaining)
        XCTAssertTrue(buzzes.isEmpty)
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load(from:d))
        XCTAssertNotNil(snapshot.pauseState)
        controller.discard()
    }
}
