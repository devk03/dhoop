import XCTest

final class ProteinLogStoreTests: XCTestCase {
    @MainActor
    func testProteinPersistsWithoutCreatingCalorieDaysOrChangingWeightGoals() {
        let suite = "ProteinLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let savedFood = Data("existing calorie history".utf8)
        defaults.set(savedFood, forKey: "cut.food")
        defaults.set(75.0, forKey: "cut.goalKg")
        defaults.set(false, forKey: CutGoalPreferences.enabledKey)
        let store = ProteinLogStore(defaults: defaults)
        XCTAssertNil(store.targetGrams, "Protein targets must not come from a weight goal")
        store.add(grams: 25, name: "Lunch", day: "2026-10-04")
        store.add(grams: 15, name: "Snack", day: "2026-10-04")
        store.add(grams: 30, name: "Yesterday", day: "2026-10-03")
        let reopened = ProteinLogStore(defaults: defaults)
        XCTAssertEqual(reopened.total(day: "2026-10-04", foodProtein: 10), 50)
        XCTAssertEqual(reopened.total(day: "2026-10-05"), 0)
        XCTAssertEqual(defaults.data(forKey: "cut.food"), savedFood)
        XCTAssertEqual(defaults.double(forKey: "cut.goalKg"), 75)
        XCTAssertFalse(CutGoalPreferences(defaults: defaults).isEnabled)
    }

    @MainActor
    func testIndependentTargetAndRemovalSurviveRestart() {
        let suite = "ProteinLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProteinLogStore(defaults: defaults)
        store.targetGrams = 120
        store.add(grams: 25, name: "Meal", day: "2026-10-04")
        XCTAssertEqual(ProteinLogStore(defaults: defaults).targetGrams, 120)
        store.remove(store.entries[0].id)
        store.targetGrams = nil
        let reopened = ProteinLogStore(defaults: defaults)
        XCTAssertNil(reopened.targetGrams)
        XCTAssertEqual(reopened.total(day: "2026-10-04"), 0)
    }

    @MainActor
    func testInvalidProteinCannotPolluteTotals() {
        let suite = "ProteinLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProteinLogStore(defaults: defaults)
        for grams in [0, -1, Double.nan, Double.infinity] {
            store.add(grams: grams, name: "Invalid", day: "2026-10-04")
        }
        XCTAssertTrue(store.entries.isEmpty)
    }
}
