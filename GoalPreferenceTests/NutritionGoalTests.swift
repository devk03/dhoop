import Foundation
import XCTest

@MainActor
final class NutritionGoalTests: XCTestCase {
    private let installation = "00000000-0000-4000-8000-000000000001"
    private let id = "00000000-0000-4000-8000-000000000002"
    private func connection() -> NutritionGoalConnection {
        .init(credentials: .init(endpoint: "https://track.kunjadia.dev/api/webhooks/sleep", bearer: String(repeating: "s", count: 43),
            clientId: "synthetic", clientSecret: "synthetic-secret", proteinBearer: String(repeating: "p", count: 43)), installationId: installation)
    }
    private func goal(from: String = "2026-10-24", through: String = "2026-11-07") -> CalorieGoalPeriod {
        .init(id: id, startDate: from, endDate: through, minCalories: 2000, maxCalories: 2400)
    }
    private func document(version: Int = 0, periods: [CalorieGoalPeriod] = []) -> NutritionGoalDocument {
        .init(schemaVersion: 1, kind: "nutrition_goals", installationId: installation, version: version, periods: periods)
    }
    func testGoalDatesAreInclusiveNonoverlappingAndNeverInventDefaultTargets() throws {
        let goal = goal(); XCTAssertTrue(goal.contains("2026-10-24")); XCTAssertTrue(goal.contains("2026-11-07"))
        XCTAssertFalse(goal.contains("2026-10-23")); XCTAssertFalse(goal.contains("2026-11-08"))
        XCTAssertNil(CalorieGoalPeriod.date("2026-02-30"))
        let overlap = CalorieGoalPeriod(id: UUID().uuidString, startDate: "2026-11-07", endDate: "2026-11-08", minCalories: 2000, maxCalories: 2000)
        XCTAssertThrowsError(try document(periods: [goal, overlap]).validate(installation: installation))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NutritionGoals.empty." + UUID().uuidString))
        let client = NutritionGoalClient(defaults: defaults, connection: connection, send: { _, _ in XCTFail(); return Data() })
        XCTAssertTrue(client.periods.isEmpty); XCTAssertNil(client.goal(for: "2026-10-24")); XCTAssertFalse(client.enabled)
    }
    func testCalorieUnknownZeroAndPartialCoverageRemainDistinct() {
        XCTAssertNil(NutritionCalorieSummary(estimates: [nil, nil]).calories)
        let zero = NutritionCalorieSummary(estimates: [nil, 0]); XCTAssertEqual(zero.calories, 0)
        XCTAssertEqual(zero.entryCount, 2); XCTAssertEqual(zero.estimatedEntryCount, 1)
        XCTAssertEqual(NutritionCalorieSummary(estimates: [250, nil, 100]).calories, 350)
    }
    func testPastedThousandsDoNotBecomeFractionalCalories() {
        XCTAssertEqual(NutritionInputNumber.parse("2,000", locale: Locale(identifier: "en_US")), 2000)
        XCTAssertEqual(NutritionInputNumber.parse("1,500.5", locale: Locale(identifier: "en_US")), 1500.5)
        XCTAssertEqual(NutritionInputNumber.parse("1.500,5", locale: Locale(identifier: "de_DE")), 1500.5)
        XCTAssertEqual(NutritionInputNumber.parse("1,5", locale: Locale(identifier: "fr_FR")), 1.5)
        for value in ["1,50", "NaN", "-20", "100kcal", "2,000oops", "1e3"] {
            XCTAssertNil(NutritionInputNumber.parse(value, locale: Locale(identifier: "en_US")))
        }
    }
    func testGoalWriteHasOnlyTheNarrowActionFieldsAndStrictBounds() throws {
        let write = NutritionGoalWrite(installationId: installation, expectedVersion: 2, action: "upsert", goal: goal(), id: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(write)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["schemaVersion", "kind", "installationId", "expectedVersion", "action", "goal"])
        let malformed = NutritionGoalWrite(installationId: installation, expectedVersion: 2, action: "remove", goal: goal(), id: id)
        XCTAssertThrowsError(try JSONEncoder().encode(malformed))
        XCTAssertFalse(CalorieGoalPeriod(id: id, startDate: "2026-10-24", endDate: "2026-10-24", minCalories: 0, maxCalories: 0).valid)
        XCTAssertThrowsError(try document(version: 2147483648).validate(installation: installation))
    }
    func testReadBackedSaveRejectsConflictAndRequiresExplicitRefreshBeforeRetry() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NutritionGoals.conflict." + UUID().uuidString))
        var writes = 0, reads = 0, accepted = false
        let client = NutritionGoalClient(defaults: defaults, connection: connection) { write, _ in
            if write != nil { writes += 1; if !accepted { throw NutritionGoalFailure.changed } }
            else { reads += 1 }
            return try JSONEncoder().encode(self.document(version: accepted ? 2 : 1, periods: accepted ? [self.goal()] : []))
        }
        let activated = await client.refresh(activate: true); XCTAssertTrue(activated); XCTAssertEqual(reads, 1)
        do { try await client.save(goal()); XCTFail() } catch { }
        XCTAssertEqual(writes, 1); XCTAssertTrue(client.requiresRefresh); XCTAssertTrue(client.periods.isEmpty)
        do { try await client.save(goal()); XCTFail() } catch { }
        XCTAssertEqual(writes, 1, "No automatic POST retry or stale-version write")
        accepted = true; let refreshed = await client.refresh(); XCTAssertTrue(refreshed)
        try await client.save(goal()); XCTAssertEqual(writes, 2); XCTAssertEqual(client.goal(for: "2026-10-24"), goal())
    }
    func testWrongInstallationReadCannotReplaceCacheAndConnectionChangeHidesOldGoals() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NutritionGoals.identity." + UUID().uuidString))
        var active = connection(), wrong = false
        let client = NutritionGoalClient(defaults: defaults, connection: { active }) { _, _ in
            if wrong { return try JSONEncoder().encode(NutritionGoalDocument(schemaVersion: 1, kind: "nutrition_goals", installationId: UUID().uuidString, version: 2, periods: [])) }
            return try JSONEncoder().encode(self.document(version: 1, periods: [self.goal()]))
        }
        let first = await client.refresh(activate: true); XCTAssertTrue(first)
        let original = defaults.data(forKey: NutritionGoalClient.cacheKey); wrong = true
        let second = await client.refresh(); XCTAssertFalse(second); XCTAssertEqual(defaults.data(forKey: NutritionGoalClient.cacheKey), original)
        XCTAssertEqual(client.periods.count, 1)
        active = .init(credentials: active.credentials, installationId: UUID().uuidString)
        client.connectionDidChange(); XCTAssertTrue(client.periods.isEmpty); XCTAssertEqual(defaults.data(forKey: NutritionGoalClient.cacheKey), original)
    }
    func testNewGoalCannotBeReportedSavedWithoutAConfirmedVersionChange() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NutritionGoals.version." + UUID().uuidString))
        let client = NutritionGoalClient(defaults: defaults, connection: connection) { write, _ in
            try JSONEncoder().encode(self.document(version: 1, periods: write == nil ? [] : [self.goal()]))
        }
        _ = await client.refresh(activate: true)
        do { try await client.save(goal()); XCTFail("A new goal requires a newer server version") } catch { }
        XCTAssertTrue(client.periods.isEmpty); XCTAssertTrue(client.requiresRefresh)
    }
}
