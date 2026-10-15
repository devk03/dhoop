import XCTest
import WhoopStore
#if !DHOOP_HOSTLESS_TESTS
@testable import Strand
#endif

@MainActor
final class LiftPreviousPerformanceTests: XCTestCase {
    private func row(_ device: String, weight: Double = 60) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: device, sessionId: "earlier", ord: 0, exercise: "Bench",
                   primaryMuscle: nil, setIndex: 1, weightKg: weight, reps: 8, rpe: nil, isWarmup: false,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }
    func testLookupUsesCapturedStrapAndReadFailureDoesNotClearKnownOrTypedValues() async throws {
        var active = "original"
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in }, currentDeviceId: { active })
        defer { controller.discard() }
        XCTAssertTrue(controller.start(plan: [LiftPlanItem(exercise: "Bench", targetSets: 1)], programId: nil, programName: nil))
        active = "different"
        try await controller.readPreviousPerformance { device, exercise, _ in
            XCTAssertEqual(device, "original"); XCTAssertEqual(exercise, "Bench")
            return [self.row(device)]
        }
        let slot = LiftSlot(exerciseIndex: 0, setIndex: 1)
        XCTAssertEqual(controller.values(of: slot).weightKg, 60)
        controller.updateSet(slot, weightKg: nil, reps: 12, rpe: nil, isWarmup: false)
        XCTAssertEqual(controller.enteredValues(for: slot).reps, 12)
        do { try await controller.readPreviousPerformance { _, _, _ in throw NSError(domain: "read", code: 1) }; XCTFail("Read failure must remain visible") }
        catch {}
        XCTAssertEqual(controller.values(of: slot).weightKg, 60)
        XCTAssertEqual(controller.enteredValues(for: slot).reps, 12)
        XCTAssertNotNil(controller.previousPerformanceError)
        XCTAssertFalse(controller.readingPreviousPerformance)
    }
    func testForeignRowsAreRejectedAndSupersededReadCannotOverwriteNewerCarry() async throws {
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in }, currentDeviceId: { "strap" })
        defer { controller.discard() }
        XCTAssertTrue(controller.start(plan: [LiftPlanItem(exercise: "Bench", targetSets: 1)], programId: nil, programName: nil))
        do { try await controller.readPreviousPerformance { _, _, _ in [self.row("other")] }; XCTFail("Foreign measurements cannot become previous performance") }
        catch WorkoutTrackerContractError.invalidSnapshot {}
        let entered = expectation(description: "Earlier read waiting")
        var release: CheckedContinuation<[LiftSetRow], Never>?
        let older = Task { @MainActor in
            do {
                try await controller.readPreviousPerformance { _, _, _ in
                    entered.fulfill(); return await withCheckedContinuation { release = $0 }
                }
                XCTFail("Older read must not replace a newer result")
            } catch WorkoutTrackerContractError.sessionChanged {}
        }
        await fulfillment(of: [entered], timeout: 2)
        try await controller.readPreviousPerformance { _, _, _ in [self.row("strap", weight: 70)] }
        release?.resume(returning: [row("strap", weight: 50)])
        try await older.value
        XCTAssertEqual(controller.values(of: LiftSlot(exerciseIndex: 0, setIndex: 1)).weightKg, 70)
        XCTAssertNil(controller.previousPerformanceError)
    }
}
