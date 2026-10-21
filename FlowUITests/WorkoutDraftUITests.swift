import XCTest

final class WorkoutDraftUITests: XCTestCase {
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
}
