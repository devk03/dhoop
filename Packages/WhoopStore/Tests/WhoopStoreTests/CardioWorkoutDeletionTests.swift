import XCTest
import GRDB
@testable import WhoopStore

final class CardioWorkoutDeletionTests: XCTestCase {
    private func row(source: String = "manual", end: Int = 1900) -> WorkoutRow {
        WorkoutRow(startTs: 1000, endTs: end, sport: "Running", source: source,
            durationS: 900, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
            distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }

    func testExactDeletionPreservesImportsChangedEndTimeAndSensorRows() async throws {
        let store = try await WhoopStore.inMemory()
        let target = row()
        try await store.upsertWorkouts([target], deviceId: "a")
        try await store.upsertWorkouts([target], deviceId: "b")
        try await store.upsertWorkouts([row(source: "whoop")], deviceId: "import")
        try await store.upsertWorkouts([row(end: 2000)], deviceId: "edited")
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId,ts,bpm) VALUES ('a',1000,130)")
        }
        let count = try await store.deleteWorkoutRecording(target, deviceIds: ["a", "b", "import", "edited", "a"])
        XCTAssertEqual(count, 2)
        let imported = try await store.workouts(deviceId: "import", from: 0, to: 3000, limit: 100)
        let edited = try await store.workouts(deviceId: "edited", from: 0, to: 3000, limit: 100)
        XCTAssertEqual(imported, [row(source: "whoop")])
        XCTAssertEqual(edited, [row(end: 2000)])
        let hrCount = try await store.registryWriter.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM hrSample") }
        XCTAssertEqual(hrCount, 1)
    }

    func testFailureOnSecondNamespaceRollsBackFirstDeletion() async throws {
        let store = try await WhoopStore.inMemory(), target = row()
        try await store.upsertWorkouts([target], deviceId: "a")
        try await store.upsertWorkouts([target], deviceId: "b")
        try await store.registryWriter.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_b BEFORE DELETE ON workout WHEN OLD.deviceId = 'b' BEGIN SELECT RAISE(ABORT, 'rejected'); END")
        }
        do {
            _ = try await store.deleteWorkoutRecording(target, deviceIds: ["a", "b"])
            XCTFail("A rejected deletion must reach the caller")
        } catch { }
        let a = try await store.workouts(deviceId: "a", from: 0, to: 3000, limit: 100)
        let b = try await store.workouts(deviceId: "b", from: 0, to: 3000, limit: 100)
        XCTAssertEqual(a, [target]); XCTAssertEqual(b, [target])
    }
}
