import XCTest
import WhoopStore
@testable import DhoopGoalTests

final class WorkoutTrackerDeliveryTests: XCTestCase {
    private func binding() throws -> WorkoutTrackerCaptureBinding {
        let set = WorkoutTrackerManifest.PlannedSet(lifeSetId: 1, setNumber: 1, setType: "work", plannedLoad: 60, plannedReps: 8,
            loadOverride: false, repsOverride: false, actualLoad: nil, actualReps: nil, rir: nil, completed: false)
        let occurrence = WorkoutTrackerManifest.Occurrence(sessionExerciseId: 2, programSlotId: 3, slotKey: "push", exerciseKey: "bench", originalExerciseKey: "bench",
            name: "Bench", order: 0, measurementKind: "mass_reps", loadMode: .barbell, loadBasis: "total", unit: "kg", targetRir: 2, restTargetSeconds: nil, sets: [set])
        let manifest = WorkoutTrackerManifest(schemaVersion: 1, cycleId: 4, sessionId: 5, sessionKey: "upper_a", title: "Upper A",
            scheduledDate: nil, status: "planned", manifestRevision: "hash", lifeRevision: 0, exerciseOccurrences: [occurrence], sourceWorkoutId: nil)
        return try WorkoutTrackerCaptureBinding(manifest: manifest)
    }
    func testPreparedIntentRequiresExactLocalSessionAndSetPersistence() async throws {
        let binding = try binding(), id = binding.sourceWorkoutId.uuidString.lowercased()
        let setID = try XCTUnwrap(binding.occurrences.first?.sets.first?.sourceSetId).uuidString.lowercased()
        let record = LiftSessionRow(id: id, deviceId: "strap", startTs: 1000, endTs: 1600, sport: "Strength Training", programId: nil, programName: "Upper A", sessionRpe: nil, note: nil)
        let set = LiftSetRow(id: setID, deviceId: "strap", sessionId: id, ord: 0, exercise: "Bench", primaryMuscle: nil, setIndex: 1,
            weightKg: 60, reps: 8, rpe: nil, isWarmup: false, startTs: 1010, endTs: 1040, restSec: nil, note: nil)
        let install = UUID(), event = UUID()
        let bytes = try WorkoutCapturePayload.make(record: record, sets: [set], binding: binding, installationId: install, revision: 1, eventId: event).bytes()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertTrue(session["rpe"] is NSNull, "Session RPE remains independent and can explicitly be cleared")
        let delivery = WorkoutTrackerDelivery(id: event, sourceWorkoutId: binding.sourceWorkoutId, installationId: install,
            origin: "https://track.kunjadia.dev", revision: 1, bytes: bytes, record: record, sets: [set], binding: binding)
        let store = try await WhoopStore.inMemory()
        let empty = try await delivery.matches(store: store)
        XCTAssertFalse(empty)
        try await store.upsertLiftSessions([record])
        let partial = try await delivery.matches(store: store)
        XCTAssertFalse(partial)
        try await store.upsertLiftSets([set])
        let missingWorkout = try await delivery.matches(store: store)
        XCTAssertFalse(missingWorkout)
        try await store.upsertWorkouts([WorkoutRow(startTs: 1000, endTs: 1600, sport: "Strength Training", source: "manual", durationS: 600,
            energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)], deviceId: "strap")
        let complete = try await delivery.matches(store: store)
        XCTAssertTrue(complete)
        var changed = set; changed.reps = 10
        try await store.upsertLiftSets([changed])
        let stale = try await delivery.matches(store: store)
        XCTAssertFalse(stale, "A stale intent cannot overwrite a newer local correction")
        try delivery.validateBody()
    }
    func testLegacyReadCacheDecodesWithAnEmptyQueueAndCorruptionIsPreserved() throws {
        let old = Data(#"{"version":1,"enabled":false,"manifests":{},"message":"off"}"#.utf8)
        let state = try JSONDecoder().decode(WorkoutTrackerState.self, from: old)
        XCTAssertTrue(state.deliveries.isEmpty)
        try state.validate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("invalid-state".utf8); try corrupt.write(to: url)
        XCTAssertThrowsError(try WorkoutTrackerFileStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}
