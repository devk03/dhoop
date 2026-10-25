import XCTest

final class ProteinLogStoreTests: XCTestCase {
    @MainActor
    func testLegacyEntriesRetainUnknownTimeAndNewEntriesPersistLoggingTime() throws {
        let suite = "ProteinLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = "[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"day\":\"2026-10-04\",\"name\":\"Lunch\",\"grams\":25}]"
        defaults.set(Data(legacy.utf8), forKey: ProteinLogStore.entriesKey)
        let store = ProteinLogStore(defaults: defaults)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.entries.first?.loggedAt)
        let at = Date(timeIntervalSince1970: 1_791_200_000)
        try store.add(grams: 15, name: "Snack", day: "2026-10-04", now: at)
        let reopened = ProteinLogStore(defaults: defaults)
        XCTAssertNil(reopened.entries.first?.loggedAt)
        XCTAssertEqual(reopened.entries.last?.loggedAt, at)
        XCTAssertEqual(reopened.total(day: "2026-10-04"), 40)
    }

    @MainActor
    func testProteinPersistsWithoutCreatingCalorieDaysOrChangingWeightGoals() throws {
        let suite = "ProteinLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let savedFood = Data("existing calorie history".utf8)
        defaults.set(savedFood, forKey: "cut.food")
        defaults.set(75.0, forKey: "cut.goalKg")
        defaults.set(false, forKey: CutGoalPreferences.enabledKey)
        let store = ProteinLogStore(defaults: defaults)
        XCTAssertNil(store.targetGrams, "Protein targets must not come from a weight goal")
        try store.add(grams: 25, name: "Lunch", day: "2026-10-04")
        try store.add(grams: 15, name: "Snack", day: "2026-10-04")
        try store.add(grams: 30, name: "Yesterday", day: "2026-10-03")
        let reopened = ProteinLogStore(defaults: defaults)
        XCTAssertEqual(reopened.total(day: "2026-10-04", foodProtein: 10), 50)
        XCTAssertEqual(reopened.total(day: "2026-10-05"), 0)
        XCTAssertEqual(defaults.data(forKey: "cut.food"), savedFood)
        XCTAssertEqual(defaults.double(forKey: "cut.goalKg"), 75)
        XCTAssertFalse(CutGoalPreferences(defaults: defaults).isEnabled)
    }

    @MainActor
    func testIndependentTargetAndRemovalSurviveRestart() throws {
        let suite = "ProteinLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProteinLogStore(defaults: defaults)
        try store.setTarget(120)
        try store.add(grams: 25, name: "Meal", day: "2026-10-04")
        XCTAssertEqual(ProteinLogStore(defaults: defaults).targetGrams, 120)
        try store.remove(store.entries[0].id)
        try store.setTarget(nil)
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
            XCTAssertThrowsError(try store.add(grams: grams, name: "Invalid", day: "2026-10-04"))
        }
        XCTAssertTrue(store.entries.isEmpty)
    }
    @MainActor
    func testUnreadableHistoryIsPreservedAndWritesRequireAValidRead() throws {
        let suite = "ProteinLogTests.corrupt." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("broken protein history".utf8)
        defaults.set(corrupt, forKey: ProteinLogStore.entriesKey)
        let store = ProteinLogStore(defaults: defaults)
        XCTAssertTrue(store.storageUnavailable)
        XCTAssertNotNil(store.storageError)
        XCTAssertThrowsError(try store.add(grams: 25, name: "Lunch", day: "2026-10-14"))
        XCTAssertThrowsError(try store.remove(UUID()))
        XCTAssertEqual(defaults.data(forKey: ProteinLogStore.entriesKey), corrupt)
        // A user-owned restoration can be read without erasing or rewriting the source bytes.
        let restored = Data("[]".utf8); defaults.set(restored, forKey: ProteinLogStore.entriesKey)
        try store.reload()
        XCTAssertFalse(store.storageUnavailable)
        XCTAssertEqual(defaults.data(forKey: ProteinLogStore.entriesKey), restored)
        try store.add(grams: 25, name: "Lunch", day: "2026-10-14")
        XCTAssertEqual(store.total(day: "2026-10-14"), 25)
    }
    @MainActor
    func testEncodingFailureKeepsTheLastSavedEntriesAndTarget() throws {
        let suite = "ProteinLogTests.encoding." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProteinLogStore(defaults: defaults)
        try store.add(grams: 20, name: "Breakfast", day: "2026-10-14")
        try store.setTarget(120)
        let original = defaults.data(forKey: ProteinLogStore.entriesKey)
        XCTAssertThrowsError(try store.add(grams: 25, name: "Keep this input", day: "2026-10-14", now: Date(timeIntervalSince1970: .infinity)))
        XCTAssertEqual(defaults.data(forKey: ProteinLogStore.entriesKey), original)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertThrowsError(try store.setTarget(.nan))
        XCTAssertEqual(store.targetGrams, 120)
        XCTAssertEqual(defaults.double(forKey: ProteinLogStore.targetKey), 120)
    }
    @MainActor
    func testTwoStoreInstancesCannotOverwriteEachOthersNewerEntries() throws {
        let suite = "ProteinLogTests.concurrent." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ProteinLogStore(defaults: defaults), second = ProteinLogStore(defaults: defaults)
        try first.add(grams: 25, name: "Lunch", day: "2026-10-14")
        try second.add(grams: 15, name: "Snack", day: "2026-10-14")
        XCTAssertEqual(second.total(day: "2026-10-14"), 40)
        XCTAssertEqual(ProteinLogStore(defaults: defaults).entries.map(\.name), ["Lunch", "Snack"])
        try first.remove(first.entries[0].id)
        XCTAssertEqual(ProteinLogStore(defaults: defaults).total(day: "2026-10-14"), 15)
    }
    @MainActor
    func testOptionalCaloriesPreserveLegacyIDsUnknownsAndZeroWithoutCreatingCutDays() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FoodLogTests." + UUID().uuidString))
        let legacy = Data(#"[{"id":"00000000-0000-4000-8000-000000000001","day":"2026-10-24","name":"Old meal","grams":25}]"#.utf8)
        defaults.set(legacy, forKey: ProteinLogStore.entriesKey)
        let store = ProteinLogStore(defaults: defaults), id = try XCTUnwrap(store.entries.first?.id)
        XCTAssertNil(store.entries.first?.calories)
        try store.add(grams: 0, name: "Water", day: "2026-10-24", calories: 0)
        try store.add(grams: 0, name: "Fruit", day: "2026-10-24", calories: 90)
        let reopened = ProteinLogStore(defaults: defaults)
        XCTAssertEqual(reopened.entries.first?.id, id); XCTAssertNil(reopened.entries.first?.calories)
        XCTAssertEqual(reopened.entries.map(\.calories), [nil, 0, 90]); XCTAssertEqual(reopened.total(day: "2026-10-24"), 25)
        XCTAssertNil(defaults.object(forKey: "cut.food")); XCTAssertNil(defaults.object(forKey: "cut.goalKg"))
        for calories in [-1, Double.infinity, Double.nan, 20001] {
            XCTAssertThrowsError(try store.add(grams: 0, name: "Invalid", day: "2026-10-24", calories: calories))
        }
        XCTAssertEqual(ProteinLogStore(defaults: defaults).entries.count, 3)
    }
}
