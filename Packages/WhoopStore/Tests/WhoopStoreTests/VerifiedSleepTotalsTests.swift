import XCTest
@testable import WhoopStore

final class VerifiedSleepTotalsTests: XCTestCase {
    func testProviderTransitionsAndImportedPrecedence() async throws {
        let store = try await WhoopStore.inMemory()
        let day = "2026-10-05"
        func persist(_ minutes: Double, owner: String) async throws {
            let daily = DailyMetric(day: day, totalSleepMin: minutes, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)
            try await store.persistComputedScores(dailyMetrics: [daily], metricPoints: [.init(day: day, key: "sleep_total_min", value: minutes)],
                provenance: [.init(day: day, key: "sleep_performance", sourceId: owner)], deviceId: "strap-noop", from: day, to: day)
        }
        try await persist(480, owner: "apple-health")
        var rows = try await store.verifiedWhoopSleepTotals(rawSourceIds: ["strap"], from: day, to: day)
        XCTAssertTrue(rows.isEmpty, "Apple-derived computed sleep is not WHOOP sleep")
        try await persist(515.5, owner: "strap")
        rows = try await store.verifiedWhoopSleepTotals(rawSourceIds: ["strap"], from: day, to: day)
        XCTAssertEqual(rows.first?.minutes, 515.5); XCTAssertEqual(rows.first?.estimated, true)
        try await persist(420, owner: "apple-health")
        rows = try await store.verifiedWhoopSleepTotals(rawSourceIds: ["strap"], from: day, to: day)
        XCTAssertTrue(rows.isEmpty)
        try await store.upsertMetricSeries([.init(day: day, key: "sleep_total_min", value: 499)], deviceId: "strap")
        try await persist(520, owner: "strap")
        rows = try await store.verifiedWhoopSleepTotals(rawSourceIds: ["strap"], from: day, to: day)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.minutes, 499); XCTAssertEqual(rows.first?.estimated, false)
    }
}
