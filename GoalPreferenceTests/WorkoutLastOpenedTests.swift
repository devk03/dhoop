import Foundation
import XCTest

final class WorkoutLastOpenedTests: XCTestCase {
    func testReturningUsesTheExactOriginalWorkoutAndHistoricalProgram() throws {
        let installation = UUID()
        let record = WorkoutLastOpened(origin: "https://track.kunjadia.dev", installationId: installation, mesocycleId: 2, sessionId: 284)
        let value = try XCTUnwrap(record.storageValue)
        let restored = try XCTUnwrap(WorkoutLastOpened.resolve(value, origin: record.origin, installationId: installation, enabled: true))
        XCTAssertEqual(restored.mesocycleId, 2)
        XCTAssertEqual(restored.sessionId, 284)
        XCTAssertEqual(restored, record)
    }
    func testForeignDisabledOrUnreadableBookmarkCannotOpenAWorkout() throws {
        let installation = UUID()
        let record = WorkoutLastOpened(origin: "https://track.kunjadia.dev", installationId: installation, mesocycleId: 2, sessionId: 284)
        let value = try XCTUnwrap(record.storageValue)
        XCTAssertNil(WorkoutLastOpened.resolve(value, origin: record.origin, installationId: UUID(), enabled: true))
        XCTAssertNil(WorkoutLastOpened.resolve(value, origin: "https://tracker.kunjadia.dev", installationId: installation, enabled: true))
        XCTAssertNil(WorkoutLastOpened.resolve(value, origin: record.origin, installationId: installation, enabled: false))
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
        invalid["sessionId"] = -1
        let invalidId = String(decoding: try JSONSerialization.data(withJSONObject: invalid), as: UTF8.self)
        for damaged in ["", "{", String(repeating: "x", count: 2049), invalidId] {
            XCTAssertNil(WorkoutLastOpened.resolve(damaged, origin: record.origin, installationId: installation, enabled: true))
        }
        XCTAssertNil(WorkoutLastOpened(origin: record.origin, installationId: installation, mesocycleId: 0, sessionId: 284).storageValue)
    }
}
