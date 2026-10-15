import XCTest

final class WorkoutStrengthPageTests: XCTestCase {
    private func fixture(type: String = "four_lift_strength", status: String = "active", kind: String = "strength") throws -> WorkoutStrengthPage {
        let program: [String: Any] = ["id": 5, "name": "Fixture lifting", "startDate": "2026-10-14", "durationWeeks": 8,
            "status": status, "goals": [:], "config": ["programType": type], "createdAt": "", "updatedAt": ""]
        let row: [String: Any] = ["id": 10, "mesocycleId": 5, "weekNumber": 1, "sessionKey": "upper_a", "kind": kind,
            "title": "Upper A", "scheduledDate": "", "status": "planned", "completedAt": "", "exerciseCount": 6,
            "completedSetCount": 0, "totalSetCount": 18, "orderIndex": 0, "timing": "unscheduled"]
        let object: [String: Any] = ["schemaVersion": 1, "lifeRevision": 40, "view": "strength", "date": "2026-10-14",
            "program": program, "programs": [program], "nextUp": row, "scheduled": [], "unscheduled": [row],
            "counts": ["pending": 1, "scheduled": 0, "unscheduled": 1],
            "pagination": ["limit": 8, "scheduledHasMore": false, "unscheduledHasMore": false]]
        return try JSONDecoder().decode(WorkoutStrengthPage.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testOnlyActiveTypedLiftingProgramAndStrengthSessionsAreAccepted() throws {
        let page = try fixture(); XCTAssertNoThrow(try page.validate())
        XCTAssertEqual(page.nextUp?.scheduledDate, "")
        XCTAssertEqual(page.nextUp?.timing, "unscheduled")
        XCTAssertThrowsError(try fixture(type: "half_marathon_strength").validate())
        XCTAssertThrowsError(try fixture(status: "completed").validate())
        XCTAssertThrowsError(try fixture(kind: "run").validate())
    }
}
