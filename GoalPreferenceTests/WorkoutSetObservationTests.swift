import XCTest
@testable import DhoopGoalTests

final class WorkoutSetObservationTests: XCTestCase {
    private func observation() -> WorkoutSetObservation {
        WorkoutSetObservation(sourceSetId: UUID(uuidString: "ABCDEFAB-1234-4234-8234-ABCDEFABCDEF")!, setType: .work, loadBasis: .total)
    }
    private func json(_ value: WorkoutSetObservation) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
    func testUnobservedFieldsAreOmittedAndExplicitClearIsNull() throws {
        var value = observation()
        let initial = try json(value)
        XCTAssertEqual(Set(initial.keys), ["sourceSetId", "setType", "loadBasis"])
        XCTAssertEqual(initial["sourceSetId"] as? String, "abcdefab-1234-4234-8234-abcdefabcdef")
        value.reps = .clear
        let cleared = try json(value)
        XCTAssertTrue(cleared["reps"] is NSNull)
        XCTAssertNil(cleared["loadKg"])
        XCTAssertNil(cleared["startedAt"], "An unmeasured time must not be synthesized")
    }
    func testKgPrecisionAndFractionalRpeArePreservedWithoutInventingRir() throws {
        var value = observation()
        let kg = 55 * 0.45359237
        value.loadKg = .value(kg)
        value.enteredLoad = .value(WorkoutEnteredLoad(value: "55", unit: .lb))
        value.rpe = .value(8.5)
        value.completed = true
        let encoded = try json(value)
        XCTAssertEqual(encoded["loadKg"] as? Double, kg)
        XCTAssertEqual(encoded["rpe"] as? Double, 8.5)
        XCTAssertNil(encoded["rir"])
        value.enteredLoad = .value(WorkoutEnteredLoad(value: "60", unit: .lb))
        XCTAssertThrowsError(try JSONEncoder().encode(value))
    }
    func testInvalidDurationsAndUnsupportedObservationsAreRejectedWithoutClamping() throws {
        var value = observation()
        value.startedAt = .value("2026-10-14T19:00:00Z")
        value.endedAt = .value("2026-10-14T19:00:20Z")
        value.measuredActiveSeconds = .value(21)
        XCTAssertThrowsError(try JSONEncoder().encode(value))
        value.measuredActiveSeconds = .value(20)
        value.reps = .value(101)
        XCTAssertThrowsError(try JSONEncoder().encode(value))
        XCTAssertEqual(value.reps, .value(101), "A sync bound never modifies the local observation")
    }
    func testEmptyHeartRateEvidenceRequiresExplicitUnavailableValues() throws {
        var value = observation()
        value.heartRateSummary = .value(WorkoutObservedHeartRate(sampleCount: 0, coverageFraction: nil, averageBpm: nil, maximumBpm: nil))
        let summary = try XCTUnwrap(try json(value)["heartRateSummary"] as? [String: Any])
        XCTAssertTrue(summary["averageBpm"] is NSNull)
        XCTAssertTrue(summary["maximumBpm"] is NSNull)
        XCTAssertTrue(summary["coverageFraction"] is NSNull)
        value.heartRateSummary = .value(WorkoutObservedHeartRate(sampleCount: 0, coverageFraction: nil, averageBpm: 100, maximumBpm: 110))
        XCTAssertThrowsError(try JSONEncoder().encode(value))
    }
    func testInterleavedSupersetOrderDoesNotInventTimingsOrUsePlannedOrder() throws {
        let group = try XCTUnwrap(UUID(uuidString: "ABCDEFAB-1234-4234-8234-ABCDEFABCDEF"))
        var value = observation()
        value.supersetGroupId = .value(group)
        value.roundIndex = .value(1)
        value.executionOrder = 3
        let encoded = try json(value)
        XCTAssertEqual(encoded["supersetGroupId"] as? String, "abcdefab-1234-4234-8234-abcdefabcdef")
        XCTAssertEqual(encoded["roundIndex"] as? Int, 1)
        XCTAssertEqual(encoded["executionOrder"] as? Int, 3)
        XCTAssertNil(encoded["startedAt"])
        XCTAssertNil(encoded["endedAt"])
    }
}
