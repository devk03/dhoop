import XCTest
import GRDB
@testable import WhoopStore

final class LiftRecordingDetailTests: XCTestCase {
    private func session(_ id: String, start: Int) -> LiftSessionRow {
        .init(id: id, deviceId: "strap", startTs: start, endTs: start + 100, sport: "Strength Training",
              programId: nil, programName: "Upper", sessionRpe: 7, note: "Original note")
    }
    private func set(_ id: String, session: LiftSessionRow, weight: Double = 60) -> LiftSetRow {
        .init(id: id, deviceId: session.deviceId, sessionId: session.id, ord: 0, exercise: "Bench",
              primaryMuscle: .chest, secondaryMuscles: [], setIndex: 1, weightKg: weight, reps: 8,
              rpe: nil, isWarmup: false, startTs: session.startTs + 10, endTs: session.startTs + 30,
              restSec: nil, note: nil)
    }
    private func workout(_ session: LiftSessionRow) -> WorkoutRow {
        .init(startTs: session.startTs, endTs: session.endTs!, sport: session.sport, source: "manual",
              durationS: 100, energyKcal: 40, avgHr: 90, maxHr: 120, strain: 2, distanceM: nil,
              zonesJSON: "{}", notes: "Measured workout", steps: 12)
    }

    func testDetailUsesCurrentWholeSessionAndExactPairedWorkoutAndPriorSets() async throws {
        let store = try await WhoopStore.inMemory()
        let prior = session("prior", start: 1000), current = session("current", start: 2000)
        try await store.saveLiftRecording(session: prior, sets: [set("prior-set", session: prior)], workout: workout(prior))
        try await store.saveLiftRecording(session: current, sets: [set("current-set", session: current, weight: 65)], workout: workout(current))
        var corrected = current
        corrected.sessionRpe = nil; corrected.note = "Corrected note"; corrected.programName = "Renamed snapshot"
        _ = try await store.upsertLiftSessions([corrected])
        let result = try await store.liftRecordingDetail(deviceId: "strap", sessionId: "current")
        let detail = try XCTUnwrap(result)
        XCTAssertEqual(detail.session, corrected)
        XCTAssertEqual(detail.sets.map(\.id), ["current-set"])
        XCTAssertEqual(detail.workout, workout(current))
        XCTAssertEqual(detail.previousSets["Bench"]?.map(\.id), ["prior-set"])
        XCTAssertEqual(detail.previousSets["Bench"]?.first?.weightKg, 60)
    }

    func testMissingSessionIsDistinctFromValidEmptyDetail() async throws {
        let store = try await WhoopStore.inMemory(), current = session("empty", start: 1000)
        _ = try await store.upsertLiftSessions([current])
        let empty = try await store.liftRecordingDetail(deviceId: "strap", sessionId: "empty")
        XCTAssertEqual(empty?.session, current); XCTAssertEqual(empty?.sets, [])
        XCTAssertNil(empty?.workout); XCTAssertEqual(empty?.previousSets, [:])
        let wrongSource = try await store.liftRecordingDetail(deviceId: "other", sessionId: "empty")
        let absent = try await store.liftRecordingDetail(deviceId: "strap", sessionId: "missing")
        XCTAssertNil(wrongSource); XCTAssertNil(absent)
    }

    func testFailedWorkoutQueryThrowsInsteadOfReturningEmptyOrPartialDetail() async throws {
        let store = try await WhoopStore.inMemory(), current = session("current", start: 1000)
        try await store.saveLiftRecording(session: current, sets: [set("set", session: current)], workout: workout(current))
        // A temporary shadow makes this query fail; the real table/data/schema remain untouched.
        try await store.registryWriter.write { db in try db.execute(sql: "CREATE TEMP TABLE workout (unreadable TEXT)") }
        do {
            _ = try await store.liftRecordingDetail(deviceId: "strap", sessionId: "current")
            XCTFail("A read failure cannot become a missing paired workout")
        } catch is DatabaseError { }
        let retained = try await store.liftSets(sessionId: "current")
        XCTAssertEqual(retained.map(\.id), ["set"])
    }

    func testForeignSetCannotBeDisplayedAsThisSessionsWork() async throws {
        let store = try await WhoopStore.inMemory(), current = session("current", start: 1000)
        try await store.saveLiftRecording(session: current, sets: [set("set", session: current)], workout: workout(current))
        try await store.registryWriter.write { db in try db.execute(sql: "UPDATE liftSet SET deviceId = 'foreign' WHERE id = 'set'") }
        do {
            _ = try await store.liftRecordingDetail(deviceId: "strap", sessionId: "current")
            XCTFail("Foreign set attribution must fail")
        } catch LiftRecordingError.inconsistentRecording { }
    }
}
