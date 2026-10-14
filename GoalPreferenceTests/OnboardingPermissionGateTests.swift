import XCTest
@testable import DhoopGoalTests

final class OnboardingPermissionGateTests: XCTestCase {
    func testRepeatedTapsAndCallbacksAdvanceOnePageOnly() throws {
        var gate = OnboardingPermissionGate(), page = 9
        let request = try XCTUnwrap(gate.begin(page: page))
        XCTAssertNil(gate.begin(page: page))
        if gate.consume(request, page: page) { page += 1 }
        if gate.consume(request, page: page) { page += 1 }
        XCTAssertEqual(page, 10)
        XCTAssertFalse(gate.isPending)
    }

    func testChangedPageRejectsCompletionAndReleasesItsOwnGate() throws {
        var gate = OnboardingPermissionGate()
        let request = try XCTUnwrap(gate.begin(page: 9))
        XCTAssertFalse(gate.consume(request, page: 10))
        XCTAssertFalse(gate.isPending)
        XCTAssertNotNil(gate.begin(page: 10))
    }

    func testStaleCallbackCannotConsumeANewerPermissionRequest() throws {
        var gate = OnboardingPermissionGate()
        let old = try XCTUnwrap(gate.begin(page: 9))
        gate.invalidate()
        let current = try XCTUnwrap(gate.begin(page: 9))
        XCTAssertNotEqual(old, current)
        XCTAssertFalse(gate.consume(old, page: 9))
        XCTAssertTrue(gate.isPending)
        XCTAssertTrue(gate.consume(current, page: 9))
        XCTAssertFalse(gate.consume(current, page: 9))
    }
}
