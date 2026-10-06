import XCTest
import WhoopStore
@testable import Strand

@MainActor
final class FitnessInputPersistenceTests: XCTestCase {
    private func row(_ day: String, rhr: Int?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: nil,
                    recovery: nil, strain: nil, exerciseCount: nil)
    }

    func testPersistedComputedNightsUnlockEstimateAcrossReaddedStrap() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.upsertDailyMetrics([row("2026-10-01", rhr: 58), row("2026-10-02", rhr: 60)], deviceId: "my-whoop-noop")
        _ = try await store.upsertDailyMetrics([row("2026-10-03", rhr: 62), row("2026-10-04", rhr: 60)], deviceId: "new-strap-noop")
        let repo = Repository(deviceId: "new-strap"); repo.setStoreForTesting(store)
        let importedOnly = await repo.dailyMetrics(fromDay: "2026-10-01", toDay: "2026-10-04")
        XCTAssertTrue(importedOnly.isEmpty)
        let days = try await repo.fitnessDailyMetrics(fromDay: "2026-10-01", toDay: "2026-10-04")
        XCTAssertEqual(days.count, 4)
        let result = IntelligenceEngine.fitnessAgeRows(gateDays: days, age: 30, sex: "male", waistCm: 0,
            heightCm: 0, weightKg: 0, computedId: "new-strap-noop", satKey: "2026-10-03")
        XCTAssertEqual(result.first { $0.key == "vo2max_est" }?.value ?? 0, 47.685, accuracy: 0.001)
        XCTAssertEqual(IntelligenceEngine.vo2MaxProvenance(points: result, waistCm: 0).first?.sourceId, "uth")
    }

    func testMergedInputPrecedenceAndDateBoundaries() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.upsertDailyMetrics([row("2026-10-01", rhr: 58), row("2026-10-02", rhr: nil)], deviceId: "my-whoop")
        _ = try await store.upsertDailyMetrics([row("2026-09-30", rhr: 55), row("2026-10-01", rhr: 90), row("2026-10-02", rhr: 62), row("2026-10-03", rhr: 63)], deviceId: "my-whoop-noop")
        let repo = Repository(deviceId: "my-whoop"); repo.setStoreForTesting(store)
        let days = try await repo.fitnessDailyMetrics(fromDay: "2026-10-01", toDay: "2026-10-02")
        XCTAssertEqual(days.map(\.day), ["2026-10-01", "2026-10-02"])
        XCTAssertEqual(days.compactMap(\.restingHr), [58, 62])
    }

    func testReadinessDoesNotUseOldHistoryOrClaimReadyWithoutProfile() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.upsertDailyMetrics((1...7).map { row("2025-10-0\($0)", rhr: 58) } + [row("2026-10-05", rhr: 60)], deviceId: "my-whoop-noop")
        let repo = Repository(deviceId: "my-whoop"); repo.setStoreForTesting(store)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z"))
        let days = try await repo.recentFitnessDailyMetrics(now: now)
        XCTAssertEqual(days.map(\.day), ["2026-10-05"])
        let inputs = FitnessInputStatus(days: days, age: 30, sex: "male")
        XCTAssertEqual(inputs.missingDays, 3)
        XCTAssertFalse(inputs.canEstimate)
        XCTAssertFalse(FitnessInputStatus(days: Array(repeating: row("2026-10-05", rhr: 60), count: 4), age: 0, sex: "").canEstimate)
    }
    func testReadFailureIsNotReportedAsZeroCoverage() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop"); repo.setStoreForTesting(store)
        try store.registryWriter.close()
        do {
            _ = try await repo.recentFitnessDailyMetrics()
            XCTFail("A closed database must report unavailable input, not an empty history")
        } catch { }
    }

}
