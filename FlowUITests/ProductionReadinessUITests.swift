import XCTest

/// Read-only navigation checks. The isolated simulator has no Life credentials or automatic export.
final class ProductionReadinessUITests: XCTestCase {
    func testPrimaryScreensAndConnectionDisclosures() throws {
        let app = XCUIApplication(bundleIdentifier: "com.devkunjadia.zhoop.loshi.noop")
        app.launchArguments = ["-noop.onboarded", "YES", "-noop.acceptedTermsVersion", "2.0",
            "-noop.lastSeenChangelogVersion", "11.8.0", "-theme.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Sleep"].waitForExistence(timeout: 30), app.debugDescription)
        capture(app, "today-read-only")
        app.swipeUp()
        capture(app, "today-after-scroll")
        let protein = app.buttons["Expand protein history"]
        XCTAssertTrue(protein.waitForExistence(timeout: 5), app.debugDescription)
        protein.tap()
        XCTAssertTrue(app.textFields["Protein in grams"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Add protein"].exists)
        capture(app, "protein-inline-entry-read-only")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Sleep"].tap()
        XCTAssertTrue(app.buttons["Share sleep"].waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "sleep-read-only")
        app.swipeUp()
        capture(app, "sleep-after-scroll")
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.staticTexts["Next workout"].waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "exercises-read-only")
        app.swipeUp()
        app.swipeDown()
        app.tabBars.buttons["Today"].tap()
        app.swipeDown()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        // The toolbar gear remains behind the menu; select the observed menu collection row.
        let menuSettings = app.collectionViews.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "gearshape", "Settings")).firstMatch
        XCTAssertTrue(menuSettings.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(menuSettings.isHittable, app.debugDescription)
        menuSettings.tap()
        let life = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Life sync")).firstMatch
        for _ in 0..<8 {
            if life.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(life.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(life.isHittable, app.debugDescription)
        life.tap()
        let disclosure = app.buttons["Connection settings"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "life-sync-collapsed")
        disclosure.tap()
        XCTAssertTrue(app.buttons["Enter or replace credentials"].waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "life-sync-connection-expanded")
        disclosure.tap()
        XCTAssertFalse(app.secureTextFields["Sleep access token"].isHittable)
        let sync = app.buttons["Sync now"].firstMatch
        XCTAssertTrue(sync.exists)
        XCTAssertFalse(sync.isEnabled, "This isolated simulator must not submit data with absent credentials")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let accessibility = XCTAttachment(string: app.debugDescription)
        accessibility.name = name + "-accessibility"; accessibility.lifetime = .keepAlways; add(accessibility)
    }
}
