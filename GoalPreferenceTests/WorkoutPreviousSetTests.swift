import Foundation
import XCTest

@MainActor
final class WorkoutPreviousSetTests: XCTestCase {
    private let row = WorkoutTrackerDashboard.SetLog(id: 302, setNumber: 2, setType: "work", plannedLoad: 200,
        plannedReps: 10, actualLoad: nil, actualReps: nil, rir: nil, completed: false)
    private func exercise(_ mode: String = "barbell") -> WorkoutTrackerDashboard.Exercise {
        .init(id: 30, exerciseKey: "bench", name: "Bench press", orderIndex: 1, loadMode: mode, progressionType: "double",
            plannedSets: 3, plannedReps: 10, plannedLoad: 200, targetRir: 2, notes: "", slotKey: "press", movementPattern: "push",
            originalExerciseKey: "bench", originalExerciseName: "Bench press", isPriming: false, sets: [row])
    }
    private func session(_ mode: String = "barbell") -> WorkoutTrackerDashboard.Session {
        .init(id: 10, mesocycleId: 1, weekNumber: 3, sessionKey: "upper_a", kind: "strength", title: "Upper A", scheduledDate: "2026-10-15",
            orderIndex: 1, status: "planned", readiness: "", rating: "", notes: "", metrics: [:], sheetItemId: "", linkedSessionId: nil,
            completedAt: "", exercises: [exercise(mode)], finisher: nil)
    }
    private func response(_ mode: String = "barbell", change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        let basis = mode == "dumbbell_each" ? "per_hand" : mode == "bodyweight_added" ? "added" : ["bodyweight", "duration"].contains(mode) ? "none" : "total"
        let mass = basis != "none"
        var value: [String: Any] = ["schemaVersion": 1, "lifeRevision": 42, "view": "previous_set", "comparison": "previous_program_week",
            "current": ["mesocycleId": 1, "sessionId": 10, "weekNumber": 3, "sessionKey": "upper_a", "sessionExerciseId": 30,
                "setId": 302, "slotKey": "press", "exerciseKey": "bench", "loadMode": mode, "setType": "work", "setNumber": 2],
            "previousWeekNumber": 2, "availability": "available", "unavailableReason": NSNull(),
            "previous": ["mesocycleId": 1, "sessionId": 9, "title": "Upper A", "weekNumber": 2, "scheduledDate": "2026-10-08",
                "completedAt": "2026-10-09T01:42:00Z", "sessionExerciseId": 29, "setId": 292, "slotKey": "press", "exerciseKey": "bench",
                "loadMode": mode, "setType": "work", "setNumber": 2, "actualLoad": mass ? 135 as Any : NSNull(), "actualReps": 8,
                "loadUnit": mass ? "lb" as Any : NSNull(), "loadBasis": basis,
                "measurementKind": mass ? "mass_reps" : mode == "duration" ? "duration" : "bodyweight_reps"]]
        change(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func decode(_ data: Data) throws -> WorkoutPreviousSetPage { try JSONDecoder().decode(WorkoutPreviousSetPage.self, from: data) }

    func testRecordedActualsAndMeasurementBasisArePreservedAndConvertedOnce() throws {
        for mode in ["barbell", "machine", "dumbbell_each", "bodyweight_added", "bodyweight", "duration"] {
            let page = try decode(response(mode))
            try page.validate(session: session(mode), exercise: exercise(mode), set: row)
            let imperial = page.report(exerciseName: "Bench press", system: .imperial)
            let metric = page.report(exerciseName: "Bench press", system: .metric)
            if mode == "duration" { XCTAssertEqual(imperial.result, "8 seconds") }
            else if mode == "bodyweight" { XCTAssertEqual(imperial.result, "8 reps") }
            else {
                XCTAssertEqual(imperial.result, "135 lb × 8 reps")
                XCTAssertEqual(metric.result, "61.24 kg × 8 reps")
            }
            XCTAssertEqual(imperial.dateLabel, "Scheduled 2026-10-08")
            XCTAssertEqual(imperial.workoutTitle, "Upper A")
            if mode == "dumbbell_each" { XCTAssertEqual(imperial.loadDetail, "Weight per hand") }
            if mode == "bodyweight_added" { XCTAssertEqual(imperial.loadDetail, "Added weight · body weight excluded") }
        }
    }
    func testWrongWeekSubstitutedExerciseAndDifferentSetCannotBeShownAsLastWeek() throws {
        for (key, value) in [("weekNumber", 1 as Any), ("exerciseKey", "squat"), ("loadMode", "dumbbell_each"),
                             ("setType", "warmup"), ("setNumber", 1), ("mesocycleId", 2), ("slotKey", "other"), ("actualLoad", -1)] {
            let page = try decode(response { object in
                var previous = object["previous"] as! [String: Any]; previous[key] = value; object["previous"] = previous
            })
            XCTAssertThrowsError(try page.validate(session: session(), exercise: exercise(), set: row), key)
        }
        let changedCurrent = try decode(response { object in
            var current = object["current"] as! [String: Any]; current["setId"] = 303; object["current"] = current
        })
        XCTAssertThrowsError(try changedCurrent.validate(session: session(), exercise: exercise(), set: row))
    }
    func testPriorRIRIsOptionalStoredEvidenceAndNeverDefaultsToZeroOrTarget() throws {
        let old = try decode(response())
        XCTAssertNil(old.previous?.rir); XCTAssertNil(old.report(exerciseName: "Bench", system: .imperial).rirLabel)
        for rir in [0.0, 2.0, 2.5, 5.0] {
            let page = try decode(response { object in
                var previous = object["previous"] as! [String: Any]; previous["rir"] = rir; object["previous"] = previous
            })
            try page.validate(session: session(), exercise: exercise(), set: row)
            XCTAssertEqual(page.previous?.rir, rir)
            XCTAssertEqual(page.report(exerciseName: "Bench", system: .imperial).rirLabel,
                "RIR \(rir.formatted(.number.precision(.fractionLength(0...1))))")
        }
        for rir in [-1.0, 6.0] {
            let page = try decode(response { object in
                var previous = object["previous"] as! [String: Any]; previous["rir"] = rir; object["previous"] = previous
            })
            XCTAssertThrowsError(try page.validate(session: session(), exercise: exercise(), set: row))
        }
    }
    func testMissingActualsAndUnknownReasonsDoNotTurnTargetsIntoResults() throws {
        for reason in ["actuals_missing", "exercise_changed", "new_server_reason"] {
            let page = try decode(response { $0["availability"] = "unavailable"; $0["previous"] = NSNull(); $0["unavailableReason"] = reason })
            try page.validate(session: session(), exercise: exercise(), set: row)
            let report = page.report(exerciseName: "Bench press", system: .imperial)
            XCTAssertNil(report.result); XCTAssertNotNil(report.unavailable)
            XCTAssertNil(report.dateLabel)
        }
        let absentActuals = try response { object in
            var previous = object["previous"] as! [String: Any]; previous["actualLoad"] = NSNull(); object["previous"] = previous
        }
        XCTAssertThrowsError(try decode(absentActuals).validate(session: session(), exercise: exercise(), set: row))
    }

    func testPopupReadIsOneBoundedGetAndDoesNotReplaceCurrentCacheOrPersistedState() async throws {
        let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), credential: String(repeating: "a", count: 64))
        let file = WorkoutTrackerFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var state = WorkoutTrackerState(); state.enabled = true; state.origin = config.origin; state.installationId = config.installationId
        try file.save(state)
        let bytes = try response()
        var calls = 0
        let client = WorkoutTrackerClient(store: file, send: { endpoint, body, _ in
            calls += 1; XCTAssertNil(body); XCTAssertEqual(endpoint.method, "GET")
            let url = try endpoint.url(origin: config.origin)
            let values = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(values, ["view": "previous_set", "mesocycleId": "1", "sessionId": "10", "setId": "302"])
            return bytes
        }, readCredential: { config }, saveCredential: { _ in XCTFail("Read must not write credentials") })
        let before = client.state
        let result = try await client.readPreviousSet(session: session(), exercise: exercise(), set: row, minimumRevision: 42)
        XCTAssertEqual(result.previous?.actualLoad, 135); XCTAssertEqual(calls, 1)
        XCTAssertEqual(client.state, before); XCTAssertEqual(try file.load(), before)
        do {
            _ = try await client.readPreviousSet(session: session(), exercise: exercise(), set: row, minimumRevision: 43)
            XCTFail("Older server snapshot must not be presented")
        } catch { }
        try client.setEnabled(false)
        let priorCalls = calls
        do {
            _ = try await client.readPreviousSet(session: session(), exercise: exercise(), set: row, minimumRevision: 42)
            XCTFail("Disabled connection must not send a read")
        } catch { }
        XCTAssertEqual(calls, priorCalls)
        XCTAssertThrowsError(try WorkoutSyncEndpoint.previousSet(mesocycleId: 1, sessionId: 10, setId: 0).url(origin: config.origin))
    }

    func testReplyArrivingAfterConnectionIsDisabledCannotPopulatePopup() async throws {
        let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), credential: String(repeating: "a", count: 64))
        let file = WorkoutTrackerFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var state = WorkoutTrackerState(); state.enabled = true; state.origin = config.origin; state.installationId = config.installationId
        try file.save(state)
        let bytes = try response()
        var duringRead: () throws -> Void = { }
        let client = WorkoutTrackerClient(store: file, send: { _, _, _ in try duringRead(); return bytes }, readCredential: { config })
        duringRead = { try client.setEnabled(false) }
        do {
            _ = try await client.readPreviousSet(session: session(), exercise: exercise(), set: row, minimumRevision: 42)
            XCTFail("A superseded connection must not populate a popup")
        } catch { }
        XCTAssertFalse(client.state.enabled)
    }
}
