import XCTest
import GRDB
@testable import WhoopStore

final class LiftRecordingStoreTests: XCTestCase {
    private func session(_ id: String = "session", start: Int = 1000) -> LiftSessionRow {
        LiftSessionRow(id: id, deviceId: "strap", startTs: start, endTs: start + 600,
            sport: "Strength Training", programId: nil, programName: "Upper A", sessionRpe: 7, note: nil)
    }
    private func set(_ id: String = "set", sessionID: String = "session", reps: Int = 8) -> LiftSetRow {
        LiftSetRow(id: id, deviceId: "strap", sessionId: sessionID, ord: 0,
            exercise: "Bench press", primaryMuscle: .chest, secondaryMuscles: [], setIndex: 1,
            weightKg: 60, reps: reps, rpe: 7, isWarmup: false, startTs: 1010, endTs: 1040,
            restSec: 60, note: nil)
    }
    private func workout(start: Int = 1000) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 600, sport: "Strength Training", source: "manual",
            durationS: 600, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
            distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }

    func testRejectedWorkoutWriteRollsBackSessionAndSets() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_workout BEFORE INSERT ON workout BEGIN SELECT RAISE(ABORT, 'storage failure'); END")
        }
        do {
            try await store.saveLiftRecording(session: session(), sets: [set()], workout: workout())
            XCTFail("A storage failure must reach the UI")
        } catch { }
        let sessions = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 3000)
        let sets = try await store.liftSets(sessionId: "session")
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertTrue(sets.isEmpty)
    }

    func testRetryRetainsCanonicalSessionAndSetIDsWithoutOrphans() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveLiftRecording(session: session(), sets: [set()], workout: workout())
        try await store.saveLiftRecording(session: session("retry"),
            sets: [set("retry-set", sessionID: "retry", reps: 9)], workout: workout())
        let sessions = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 3000)
        let sets = try await store.liftSets(sessionId: "session")
        let orphan = try await store.liftSets(sessionId: "retry")
        let workouts = try await store.workouts(deviceId: "strap", from: 0, to: 3000, limit: 10)
        XCTAssertEqual(sessions.map(\.id), ["session"])
        XCTAssertEqual(sets.map(\.id), ["set"])
        XCTAssertEqual(sets.first?.reps, 9)
        XCTAssertTrue(orphan.isEmpty)
        XCTAssertEqual(workouts.count, 1)
    }

    func testDeletionFailurePreservesTheWholeRecordingAndSamples() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveLiftRecording(session: session(), sets: [set()], workout: workout())
        try await store.saveLiftRecording(session: session("other", start: 2000),
            sets: [set("other-set", sessionID: "other")], workout: workout(start: 2000))
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId,ts,bpm) VALUES ('strap',1010,120)")
            try db.execute(sql: "CREATE TRIGGER reject_delete BEFORE DELETE ON workout WHEN OLD.startTs = 1000 BEGIN SELECT RAISE(ABORT, 'delete failure'); END")
        }
        do {
            _ = try await store.deleteLiftRecording(session())
            XCTFail("Deletion must fail visibly")
        } catch { }
        let sessions = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 3000)
        let sets = try await store.liftSets(sessionId: "session")
        let hr = try await store.hrSamples(deviceId: "strap", from: 0, to: 3000, limit: 10)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(hr.count, 1)
    }

    func testDeletingOneRecordingPreservesOtherSessionsAndSensorData() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveLiftRecording(session: session(), sets: [set()], workout: workout())
        try await store.saveLiftRecording(session: session("other", start: 2000),
            sets: [set("other-set", sessionID: "other")], workout: workout(start: 2000))
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId,ts,bpm) VALUES ('strap',1010,120)")
        }
        let deleted = try await store.deleteLiftRecording(session())
        let sessions = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 3000)
        let sets = try await store.liftSets(sessionId: "other")
        let workouts = try await store.workouts(deviceId: "strap", from: 0, to: 3000, limit: 10)
        let hr = try await store.hrSamples(deviceId: "strap", from: 0, to: 3000, limit: 10)
        XCTAssertTrue(deleted)
        XCTAssertEqual(sessions.map(\.id), ["other"])
        XCTAssertEqual(sets.map(\.id), ["other-set"])
        XCTAssertEqual(workouts.map(\.startTs), [2000])
        XCTAssertEqual(hr.count, 1)
    }

    func testFailedCorrectionRollsBackUpdatedValues() async throws {
        let store = try await WhoopStore.inMemory()
        var second = set("second")
        second.ord = 1; second.setIndex = 2
        try await store.saveLiftRecording(session: session(), sets: [set(), second], workout: workout())
        try await store.registryWriter.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_set_delete BEFORE DELETE ON liftSet WHEN OLD.id = 'second' BEGIN SELECT RAISE(ABORT, 'delete failure'); END")
        }
        do {
            try await store.editLiftRecording(session: session(), upserts: [set(reps: 12)], deletedSetIDs: ["second"])
            XCTFail("A correction must not partially succeed")
        } catch { }
        let rows = try await store.liftSets(sessionId: "session")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.reps, 8)
        XCTAssertEqual(rows.first?.startTs, 1010)
        XCTAssertEqual(rows.first?.endTs, 1040)
    }

    func testRejectedRoutineLinesDoNotLeavePartialRoutineMetadata() async throws {
        let store = try await WhoopStore.inMemory()
        let program = LiftProgramRow(id: "routine", deviceId: "strap", name: "Upper A", note: nil,
            createdAt: 1000, updatedAt: 1000, archived: false)
        let item = LiftProgramItemRow(id: "line", deviceId: "strap", programId: "routine", ord: 0,
            exercise: "Bench press", targetSets: 3, targetRepsLow: 8, targetRepsHigh: nil,
            targetRpe: nil, targetWeightKg: 60, restSec: 60, note: nil)
        do {
            try await store.saveLiftProgram(program, items: [item, item])
            XCTFail("Duplicate item IDs must fail without saving half a routine")
        } catch { }
        let programs = try await store.liftPrograms(deviceId: "strap")
        let items = try await store.liftProgramItems(programId: "routine")
        XCTAssertTrue(programs.isEmpty)
        XCTAssertTrue(items.isEmpty)
    }
}
