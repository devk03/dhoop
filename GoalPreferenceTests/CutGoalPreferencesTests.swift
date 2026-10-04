import XCTest

final class CutGoalPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "DhoopGoalPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testExistingConfiguredPlanDoesNotOptUserIntoWeightLoss() {
        defaults.set(true, forKey: "cut.configured")
        defaults.set(75.0, forKey: "cut.goalKg")
        XCTAssertFalse(CutGoalPreferences(defaults: defaults).isEnabled)
        XCTAssertEqual(defaults.double(forKey: "cut.goalKg"), 75)
    }

    func testTogglePersistsAcrossInstancesWithoutDeletingHistory() {
        let history = Data("saved food and weigh-ins".utf8)
        defaults.set(history, forKey: "cut.food")
        defaults.set(history, forKey: "cut.weighIns")
        defaults.set(80.0, forKey: "cut.startKg")
        defaults.set(75.0, forKey: "cut.goalKg")
        let preferences = CutGoalPreferences(defaults: defaults)
        preferences.isEnabled = true
        XCTAssertTrue(CutGoalPreferences(defaults: defaults).isEnabled)
        preferences.isEnabled = false
        XCTAssertFalse(CutGoalPreferences(defaults: defaults).isEnabled)
        XCTAssertEqual(defaults.data(forKey: "cut.food"), history)
        XCTAssertEqual(defaults.data(forKey: "cut.weighIns"), history)
        XCTAssertEqual(defaults.double(forKey: "cut.startKg"), 80)
        XCTAssertEqual(defaults.double(forKey: "cut.goalKg"), 75)
    }

    func testDisabledTrackingDoesNotCalculateOrPublishWeightChanges() {
        let preferences = CutGoalPreferences(defaults: defaults)
        var weight = 80.0
        preferences.performTrackingUpdate { XCTFail("Disabled tracking must not calculate an estimate") }
        preferences.isEnabled = true
        preferences.performTrackingUpdate { weight = 79.5 }
        XCTAssertEqual(weight, 79.5)
        preferences.isEnabled = false
        // A refresh's completion arrives after tracking was disabled.
        preferences.performTrackingUpdate { weight = 78 }
        XCTAssertEqual(weight, 79.5)
    }
}
