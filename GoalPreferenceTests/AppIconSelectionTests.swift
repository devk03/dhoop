import XCTest
@testable import DhoopGoalTests

@MainActor
final class AppIconSelectionTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "icon-choice-\(UUID().uuidString)")! }

    func testFailureRetainsRequestedChoiceAndRetryPersistsConfirmedSystemState() async {
        let prefs = defaults()
        var name: String?, fails = true, calls = 0
        let operation = AppIconSelectionController(defaults: prefs, supports: { true }, read: { name }, apply: { target in
            calls += 1
            if fails { throw NSError(domain: "IconTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "System declined"]) }
            name = target
        })
        let failed = await operation.change(to: true)
        XCTAssertFalse(failed); XCTAssertEqual(operation.requested, true)
        XCTAssertNil(operation.confirmedName); XCTAssertFalse(prefs.bool(forKey: AppIconSelectionController.preferenceKey))
        XCTAssertEqual(operation.error, "System declined")
        fails = false
        let retried = await operation.retry()
        XCTAssertTrue(retried); XCTAssertNil(operation.requested)
        XCTAssertEqual(operation.confirmedName, "AppIcon-Navy")
        XCTAssertTrue(prefs.bool(forKey: AppIconSelectionController.preferenceKey)); XCTAssertEqual(calls, 2)
    }

    func testPendingChangeRejectsCompetingChoiceWithoutLosingItsTarget() async {
        var name: String?, calls = 0
        var finish: CheckedContinuation<Void, Never>?
        let operation = AppIconSelectionController(defaults: defaults(), supports: { true }, read: { name }, apply: { target in
            calls += 1
            await withCheckedContinuation { finish = $0 }
            name = target
        })
        let first = Task { await operation.change(to: true) }
        for _ in 0..<100 {
            if finish != nil { break }
            await Task.yield()
        }
        guard let finish else { XCTFail("The first native operation did not start"); return }
        let second = await operation.change(to: false)
        XCTAssertFalse(second); XCTAssertEqual(operation.requested, true)
        XCTAssertEqual(operation.state, .working); XCTAssertEqual(calls, 1)
        finish.resume()
        let succeeded = await first.value
        XCTAssertTrue(succeeded); XCTAssertEqual(operation.confirmedName, "AppIcon-Navy")
    }

    func testCompletionWithoutReadbackDoesNotClaimAppliedOrOverwriteActualChoice() async {
        let prefs = defaults()
        let operation = AppIconSelectionController(defaults: prefs, supports: { true }, read: { "AppIcon-Navy" }, apply: { _ in })
        let result = await operation.change(to: false)
        XCTAssertFalse(result); XCTAssertEqual(operation.requested, false)
        XCTAssertEqual(operation.confirmedName, "AppIcon-Navy")
        XCTAssertTrue(prefs.bool(forKey: AppIconSelectionController.preferenceKey))
        operation.keepCurrent()
        XCTAssertNil(operation.requested); XCTAssertEqual(operation.state, .idle)
        XCTAssertTrue(operation.selection)
    }

    func testAlreadyAppliedDoesNotCallSystemAndUnsupportedRetainsRequest() async {
        var calls = 0
        let operation = AppIconSelectionController(defaults: defaults(), supports: { true }, read: { nil }, apply: { _ in calls += 1 })
        let result = await operation.change(to: false)
        XCTAssertTrue(result); XCTAssertEqual(calls, 0); XCTAssertEqual(operation.state, .succeeded)
        let unsupported = AppIconSelectionController(defaults: defaults(), supports: { false }, read: { nil }, apply: { _ in calls += 1 })
        let failed = await unsupported.change(to: true)
        XCTAssertFalse(failed); XCTAssertEqual(unsupported.requested, true); XCTAssertEqual(calls, 0)
    }
}
