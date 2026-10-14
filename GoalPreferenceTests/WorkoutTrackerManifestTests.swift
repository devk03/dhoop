import XCTest
@testable import DhoopGoalTests

final class WorkoutTrackerManifestTests: XCTestCase {
    private func manifest() throws -> WorkoutTrackerManifest {
        let json = #"""
        {"schemaVersion":1,"cycleId":5,"sessionId":282,"sessionKey":"upper_b","title":"Upper B","scheduledDate":null,"status":"planned","manifestRevision":"exact-hash","lifeRevision":12,"sourceWorkoutId":null,"exerciseOccurrences":[{"sessionExerciseId":891,"programSlotId":61,"slotKey":"vertical_push","exerciseKey":"db_shoulder_press","originalExerciseKey":"db_shoulder_press","name":"Dumbbell press","order":0,"measurementKind":"mass_reps","loadMode":"dumbbell_each","loadBasis":"per_hand","unit":"lb","targetRir":2,"restTargetSeconds":null,"sets":[{"lifeSetId":7886,"setNumber":1,"setType":"work","plannedLoad":55,"plannedReps":8,"loadOverride":false,"repsOverride":false,"actualLoad":null,"actualReps":null,"rir":null,"completed":false}]}]}
        """#
        return try JSONDecoder().decode(WorkoutTrackerManifest.self, from: Data(json.utf8))
    }
    func testCaptureRetainsExactIdsAndPerHandLoadWithoutInferringRpeOrRest() throws {
        let value = try manifest()
        let connection = WorkoutTrackerCaptureBinding.Connection(origin: "https://track.kunjadia.dev", installationId: UUID())
        let binding = try WorkoutTrackerCaptureBinding(manifest: value, timeZone: "Europe/London", connection: connection)
        XCTAssertEqual(binding.manifest.sessionId, 282)
        XCTAssertEqual(binding.occurrences.first?.sessionExerciseId, 891)
        XCTAssertEqual(binding.occurrences.first?.sets.first?.lifeSetId, 7886)
        XCTAssertEqual(try value.exerciseOccurrences[0].kilograms(for: value.exerciseOccurrences[0].sets[0]), 55 * 0.45359237)
        XCTAssertEqual(value.exerciseOccurrences[0].loadBasis, "per_hand")
        XCTAssertNil(value.exerciseOccurrences[0].restTargetSeconds)
        let reloaded = try JSONDecoder().decode(WorkoutTrackerCaptureBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(reloaded, binding)
        XCTAssertEqual(reloaded.connection, connection, "Capture destination survives settings changes and app relaunch")
    }
    func testWrongLoadBasisAndDuplicateLifeIdsCannotStartCapture() throws {
        let value = try manifest()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        var occurrences = try XCTUnwrap(json["exerciseOccurrences"] as? [[String: Any]])
        occurrences[0]["loadBasis"] = "total"
        json["exerciseOccurrences"] = occurrences
        let wrong = try JSONDecoder().decode(WorkoutTrackerManifest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try wrong.validate())
        json["exerciseOccurrences"] = [try XCTUnwrap((JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])?["exerciseOccurrences"] as? [[String: Any]])[0],
                                      try XCTUnwrap((JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])?["exerciseOccurrences"] as? [[String: Any]])[0]]
        let duplicate = try JSONDecoder().decode(WorkoutTrackerManifest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try duplicate.validate())
    }
    func testExistingObservationsRequireReviewRatherThanAnotherCapture() throws {
        let value = try manifest()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        json["sourceWorkoutId"] = UUID().uuidString.lowercased()
        let recorded = try JSONDecoder().decode(WorkoutTrackerManifest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try WorkoutTrackerCaptureBinding(manifest: recorded))
    }
}
