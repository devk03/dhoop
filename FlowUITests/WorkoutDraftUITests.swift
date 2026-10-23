import XCTest

final class WorkoutDraftUITests: XCTestCase {
    func testEarlierUncertainChangeDoesNotStrandNewWorkoutSave() throws {
        let app = proofApp(extra: ["--workout-ui-legacy-blocker"])
        app.launch(); try editFirstSet(app)
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved in Life"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Earlier change resolved: true"].exists)
        XCTAssertTrue(app.staticTexts["Demo posts: 1"].exists)
        capture(app, "legacy-change-recovered-before-whole-workout-save")
    }
    func testOfflineSaveRetriesSameOperationAfterRelaunch() throws {
        let app = proofApp(extra: ["--workout-ui-offline"])
        app.launch(); try editFirstSet(app)
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.buttons["Retry sync"].waitForExistence(timeout: 10), app.debugDescription)
        let original = app.staticTexts["workout-demo-operation-id"].label
        XCTAssertNotEqual(original, "none")
        app.terminate(); app.launchArguments.removeAll { $0 == "--workout-ui-offline" }; app.launch()
        XCTAssertTrue(app.buttons["Retry sync"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.staticTexts["workout-demo-operation-id"].label, original)
        app.buttons["Retry sync"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved in Life"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["workout-demo-operation-id"].label, original)
        XCTAssertTrue(app.staticTexts["Demo posts: 1"].exists)
        capture(app, "offline-save-recovered-with-original-operation")
    }
    func testRejectedSaveRetainsInlineValuesUntilReviewAndExplicitNewSave() throws {
        let app = proofApp(extra: ["--workout-ui-stale-once"])
        app.launch(); try editFirstSet(app)
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.buttons["Review rejected save"].waitForExistence(timeout: 15), app.debugDescription)
        let rejected = app.staticTexts["workout-demo-operation-id"].label
        XCTAssertEqual(app.textFields["Set 1 actual weight in lb"].value as? String, "135")
        XCTAssertEqual(app.textFields["Set 1 actual repetitions"].value as? String, "8")
        app.buttons["Review rejected save"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: app.buttons["Save workout"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["Demo posts: 1"].exists, "Review must not submit a replacement")
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved in Life"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertNotEqual(app.staticTexts["workout-demo-operation-id"].label, rejected)
        XCTAssertTrue(app.staticTexts["Demo posts: 2"].exists)
        capture(app, "stale-save-reviewed-before-explicit-replacement")
    }
    func testInlineEditsPersistBeforeOneWholeWorkoutSave() throws {
        let app = XCUIApplication(bundleIdentifier: "com.devkunjadia.zhoop.loshi.noop")
        app.launchArguments = ["--workout-draft-ui-proof", "--workout-ui-run=\(UUID().uuidString)", "--owner-data-review", "-theme.appearance", "dark"]
        app.launch()
        let load = app.textFields["Set 1 actual weight in lb"]
        XCTAssertTrue(load.waitForExistence(timeout: 20), app.debugDescription)
        load.tap(); load.typeText("135")
        let reps = app.textFields["Set 1 actual repetitions"]
        reps.tap(); reps.typeText("8")
        app.buttons["Complete set 1"].tap()
        XCTAssertTrue(app.buttons["Mark set 1 incomplete"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Demo posts: 0"].exists)
        capture(app, "workout-local-draft-before-sync")
        // Reopening preserves local input without any website command.
        app.terminate(); app.launch()
        XCTAssertTrue(load.waitForExistence(timeout: 20)); XCTAssertEqual(load.value as? String, "135")
        XCTAssertEqual(app.textFields["Set 1 actual repetitions"].value as? String, "8")
        XCTAssertTrue(app.buttons["Mark set 1 incomplete"].exists)
        XCTAssertTrue(app.staticTexts["Demo posts: 0"].exists)
        app.buttons["Save workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved in Life"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Demo posts: 1"].exists)
        XCTAssertEqual(load.value as? String, "135")
        capture(app, "workout-whole-save-acknowledged")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    private func proofApp(extra: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.devkunjadia.zhoop.loshi.noop")
        app.launchArguments = ["--workout-draft-ui-proof", "--workout-ui-run=\(UUID().uuidString)", "--owner-data-review", "-theme.appearance", "dark"] + extra
        return app
    }
    private func editFirstSet(_ app: XCUIApplication) throws {
        let load = app.textFields["Set 1 actual weight in lb"]
        XCTAssertTrue(load.waitForExistence(timeout: 20), app.debugDescription)
        load.tap(); load.typeText("135")
        let reps = app.textFields["Set 1 actual repetitions"]
        reps.tap(); reps.typeText("8")
        app.buttons["Complete set 1"].tap()
        XCTAssertTrue(app.buttons["Mark set 1 incomplete"].waitForExistence(timeout: 3))
    }
}
