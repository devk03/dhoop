import XCTest
@testable import StrandDesign

final class NoopActionControllerTests: XCTestCase {
    @MainActor
    func testSecondTapCannotSubmitWhileFirstActionIsPending() async {
        let controller = NoopActionController()
        let started = expectation(description: "Operation started")
        var continuation: CheckedContinuation<Void, Never>?
        var executions = 0
        let first = Task { @MainActor in
            await controller.run {
                executions += 1
                started.fulfill()
                await withCheckedContinuation { continuation = $0 }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(controller.state, .working)
        controller.reset()
        await controller.run { executions += 1 }
        XCTAssertEqual(executions, 1)
        XCTAssertEqual(controller.state, .working)
        continuation?.resume()
        await first.value
        XCTAssertEqual(controller.state, .succeeded)
    }

    @MainActor
    func testFailureRetainsMessageAndAnExplicitRetryCanSucceed() async {
        struct Failure: LocalizedError { var errorDescription: String? { "Storage unavailable" } }
        let controller = NoopActionController()
        await controller.run { throw Failure() }
        XCTAssertEqual(controller.state, .failed("Storage unavailable"))
        await controller.run { }
        XCTAssertEqual(controller.state, .succeeded)
    }

    @MainActor
    func testCancellationDoesNotClaimSuccessOrFailure() async {
        let controller = NoopActionController()
        await controller.run { throw CancellationError() }
        XCTAssertEqual(controller.state, .idle)
    }
}
