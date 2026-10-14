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

    func testRepeatedActualExercisesKeepDistinctIdsAndNeverChangePrescriptions() throws {
        let original = try manifest(), exercise = UUID()
        var binding = try WorkoutTrackerCaptureBinding(manifest: original)
        try binding.bindAdditionalExercise(planIndex: 1, exerciseId: exercise, name: "Dumbbell press", loadMode: .dumbbellEach)
        try binding.bindAdditionalExercise(planIndex: 2, exerciseId: exercise, name: "Dumbbell press", loadMode: .dumbbellEach)
        let extras = try XCTUnwrap(binding.additionalOccurrences)
        XCTAssertEqual(binding.manifest, original)
        XCTAssertEqual(extras.map(\.exerciseKey), Array(repeating: "custom:" + exercise.uuidString.lowercased(), count: 2))
        XCTAssertNotEqual(extras[0].sourceOccurrenceId, extras[1].sourceOccurrenceId)
        XCTAssertNotEqual(extras[0].sets[0].sourceSetId, extras[1].sets[0].sourceSetId)
        XCTAssertTrue(extras.flatMap(\.sets).allSatisfy { $0.lifeSetId == nil })
        let id = UUID()
        try binding.bindAdditionalSet(exerciseIndex: 2, slotIndex: 2, sourceSetId: id)
        XCTAssertEqual(binding.identity(exerciseIndex: 2, slotIndex: 2)?.sourceSetId, id)
        let restored = try JSONDecoder().decode(WorkoutTrackerCaptureBinding.self, from: JSONEncoder().encode(binding))
        try restored.validate()
        XCTAssertEqual(restored, binding)
        let beforeFailure = binding
        XCTAssertThrowsError(try binding.bindAdditionalSet(exerciseIndex: 2, slotIndex: 3, sourceSetId: id))
        XCTAssertEqual(binding, beforeFailure, "Rejected duplicate IDs cannot corrupt the durable binding")
    }
    func testReplacementPreservesOriginalBindingAndRejectsUnknownOrSelfLineage() throws {
        let original = try manifest()
        var binding = try WorkoutTrackerCaptureBinding(manifest: original)
        let prior = binding.occurrences
        try binding.bindReplacementExercise(planIndex: 1, replacing: 0, exerciseId: UUID(), name: "Machine press", loadMode: .machine)
        XCTAssertEqual(binding.occurrences, prior)
        XCTAssertEqual(binding.manifest, original)
        let replacement = try XCTUnwrap(binding.additionalOccurrences?.first)
        XCTAssertEqual(replacement.replacesSourceOccurrenceId, prior[0].sourceOccurrenceId)
        XCTAssertNil(replacement.sets[0].lifeSetId)
        XCTAssertNotEqual(replacement.sets[0].sourceSetId, prior[0].sets[0].sourceSetId)
        let restored = try JSONDecoder().decode(WorkoutTrackerCaptureBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(restored, binding)
        for invalid in [UUID(), replacement.sourceOccurrenceId] {
            var wrong = binding; wrong.additionalOccurrences?[0].replacesSourceOccurrenceId = invalid
            XCTAssertThrowsError(try wrong.validate())
        }
    }
}
