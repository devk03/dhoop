import XCTest
import WhoopStore
import WhoopProtocol
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

    func testTimedSetEvidenceUsesOriginalStrapAndHalfOpenActualWindow() async throws {
        let binding = try binding(), id = binding.sourceWorkoutId.uuidString.lowercased()
        let setID = try XCTUnwrap(binding.occurrences.first?.sets.first?.sourceSetId)
        let record = LiftSessionRow(id: id, deviceId: "original", startTs: 1000, endTs: 1600, sport: "Strength Training", programId: nil, programName: nil, sessionRpe: nil, note: nil)
        let timed = LiftSetRow(id: setID.uuidString.lowercased(), deviceId: "original", sessionId: id, ord: 0, exercise: "Bench", primaryMuscle: nil, setIndex: 1,
            weightKg: 60, reps: 8, rpe: nil, isWarmup: false, startTs: 1010, endTs: 1040, restSec: nil, note: nil)
        let store = try await WhoopStore.inMemory()
        _ = try await store.insert(Streams(hr: [HRSample(ts: 1010, bpm: 60), HRSample(ts: 1039, bpm: 120), HRSample(ts: 1040, bpm: 150)]), deviceId: "original")
        _ = try await store.insert(Streams(hr: [HRSample(ts: 1020, bpm: 200)]), deviceId: "other")
        let evidence = try await WorkoutCapturePayload.measuredEvidence(record: record, sets: [timed], store: store)
        XCTAssertEqual(evidence[setID], WorkoutObservedHeartRate(sampleCount: 2, coverageFraction: nil, averageBpm: 90, maximumBpm: 120))
        let bytes = try WorkoutCapturePayload.make(record: record, sets: [timed], binding: binding, installationId: UUID(), revision: 1, heartRateEvidence: evidence).bytes()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let occurrences = try XCTUnwrap(object["exerciseOccurrences"] as? [[String: Any]])
        let sets = try XCTUnwrap(occurrences[0]["sets"] as? [[String: Any]])
        let summary = try XCTUnwrap(sets[0]["heartRateSummary"] as? [String: Any])
        XCTAssertEqual(summary["sampleCount"] as? Int, 2)
        XCTAssertTrue(summary["coverageFraction"] is NSNull, "Sample count does not establish continuous sensor coverage")
        var untimed = timed; untimed.startTs = nil; untimed.endTs = nil
        let noTiming = try await WorkoutCapturePayload.measuredEvidence(record: record, sets: [untimed], store: store)
        XCTAssertTrue(noTiming.isEmpty)
        var outside = timed; outside.endTs = 1601
        let invalidWindow = try await WorkoutCapturePayload.measuredEvidence(record: record, sets: [outside], store: store)
        XCTAssertTrue(invalidWindow.isEmpty)
        var missing = timed; missing.startTs = 1200; missing.endTs = 1220
        let empty = try await WorkoutCapturePayload.measuredEvidence(record: record, sets: [missing], store: store)
        XCTAssertEqual(empty[setID], WorkoutObservedHeartRate(sampleCount: 0, coverageFraction: nil, averageBpm: nil, maximumBpm: nil))
    }

    func testReceiptRequiresExactProgramAndSetMappingsAndRetainsPendingReconciliation() throws {
        let binding = try binding(), event = UUID(), setID = try XCTUnwrap(binding.occurrences.first?.sets.first?.sourceSetId).uuidString.lowercased()
        let record = LiftSessionRow(id: binding.sourceWorkoutId.uuidString.lowercased(), deviceId: "strap", startTs: 1000, endTs: 1600, sport: "Strength Training", programId: nil, programName: nil, sessionRpe: nil, note: nil)
        let set = LiftSetRow(id: setID, deviceId: "strap", sessionId: record.id, ord: 0, exercise: "Bench", primaryMuscle: nil, setIndex: 1, weightKg: nil, reps: 8, rpe: nil, isWarmup: false, startTs: nil, endTs: nil, restSec: nil, note: nil)
        var object: [String: Any] = ["schemaVersion": 1, "eventId": event.uuidString.lowercased(), "sourceWorkoutId": record.id, "acceptedSourceRevision": 1,
            "outcome": "applied", "lifeRevision": 12, "receiptLifeRevision": 11, "preservedFields": [],
            "mappings": ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "sets": [setID: 1]], "reconciliation": ["state": "pending"]]
        func decode() throws -> WorkoutCaptureAcknowledgement { try JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: JSONSerialization.data(withJSONObject: object)) }
        let receipt = try decode()
        try receipt.validate(eventId: event, sourceWorkoutId: binding.sourceWorkoutId, revision: 1)
        try receipt.validate(binding: binding, sets: [set])
        XCTAssertTrue(receipt.reconciliation.pending)
        XCTAssertFalse(receipt.needsSourceReview(revision: 1, deleting: false))
        object["currentSourceRevision"] = 2
        XCTAssertTrue(try decode().needsSourceReview(revision: 1, deleting: false), "A recovered old receipt is not evidence that its values are still current")
        object["currentSourceRevision"] = 1
        object["currentTombstone"] = true
        XCTAssertTrue(try decode().needsSourceReview(revision: 1, deleting: false))
        XCTAssertFalse(try decode().needsSourceReview(revision: 1, deleting: true))
        object["currentTombstone"] = false
        object["mappings"] = ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "sets": [setID: 99]]
        XCTAssertThrowsError(try decode().validate(binding: binding, sets: [set]), "A response for another set is not a delivery receipt")
        object["mappings"] = ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 99], "sets": [setID: 1]]
        XCTAssertThrowsError(try decode().validate(binding: binding, sets: [set]))
    }

    func testAdditionalSetRemainsCaptureOnlyAndCannotBeAcknowledgedAsAPrescribedSet() throws {
        var binding = try binding()
        let extraID = UUID(), event = UUID()
        try binding.bindAdditionalSet(exerciseIndex: 0, slotIndex: 2, sourceSetId: extraID)
        XCTAssertNil(binding.occurrences[0].sets[1].lifeSetId)
        let restored = try JSONDecoder().decode(WorkoutTrackerCaptureBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(restored.occurrences[0].sets[1].sourceSetId, extraID)
        let record = LiftSessionRow(id: binding.sourceWorkoutId.uuidString.lowercased(), deviceId: "strap", startTs: 1000, endTs: 1600, sport: "Strength Training", programId: nil, programName: nil, sessionRpe: nil, note: nil)
        let extra = LiftSetRow(id: extraID.uuidString.lowercased(), deviceId: "strap", sessionId: record.id, ord: 0, exercise: "Bench", primaryMuscle: nil, setIndex: 2, weightKg: 60, reps: 9, rpe: 7.5, isWarmup: false, startTs: nil, endTs: nil, restSec: nil, note: nil)
        let bytes = try WorkoutCapturePayload.make(record: record, sets: [extra], binding: binding, installationId: UUID(), revision: 1).bytes()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let occurrences = try XCTUnwrap(object["exerciseOccurrences"] as? [[String: Any]])
        let sets = try XCTUnwrap(occurrences[0]["sets"] as? [[String: Any]])
        XCTAssertTrue(sets[0]["lifeSetId"] is NSNull)
        XCTAssertEqual(sets[0]["reps"] as? Int, 9)
        var ack: [String: Any] = ["schemaVersion": 1, "eventId": event.uuidString, "sourceWorkoutId": record.id, "acceptedSourceRevision": 1,
            "outcome": "applied", "lifeRevision": 1, "receiptLifeRevision": 1, "preservedFields": [], "reconciliation": ["state": "done"],
            "mappings": ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "sets": [:],
                "setTargets": [extra.id: ["kind": "capture_set", "sourceWorkoutId": record.id, "sourceSetId": extra.id]]]]
        func decode() throws -> WorkoutCaptureAcknowledgement { try JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: JSONSerialization.data(withJSONObject: ack)) }
        try decode().validate(binding: binding, sets: [extra])
        ack["mappings"] = ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "sets": [extra.id: 99],
            "setTargets": [extra.id: ["kind": "workout_set", "lifeSetId": 99, "sessionExerciseId": 2]]]
        XCTAssertThrowsError(try decode().validate(binding: binding, sets: [extra]))
    }

    func testTombstoneIntentRequiresCompletedLocalDeletionAndNeverDeletesSensorHistory() async throws {
        let binding = try binding(), event = UUID(), install = UUID()
        let record = LiftSessionRow(id: binding.sourceWorkoutId.uuidString.lowercased(), deviceId: "strap", startTs: 1000, endTs: 1600, sport: "Strength Training", programId: nil, programName: nil, sessionRpe: nil, note: nil)
        let set = LiftSetRow(id: binding.occurrences[0].sets[0].sourceSetId.uuidString.lowercased(), deviceId: "strap", sessionId: record.id, ord: 0, exercise: "Bench", primaryMuscle: nil, setIndex: 1, weightKg: 60, reps: 8, rpe: nil, isWarmup: false, startTs: 1010, endTs: 1040, restSec: nil, note: nil)
        let bytes = try WorkoutCapturePayload.make(record: record, sets: [set], binding: binding, installationId: install, revision: 2, eventId: event, baseLifeRevision: 12, deleting: true).bytes()
        let delivery = WorkoutTrackerDelivery(id: event, sourceWorkoutId: binding.sourceWorkoutId, installationId: install,
            origin: "https://track.kunjadia.dev", revision: 2, bytes: bytes, record: record, sets: [set], binding: binding, operation: .delete)
        try delivery.validateBody()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["operation"] as? String, "delete")
        XCTAssertEqual(object["baseLifeRevision"] as? Int, 12)
        XCTAssertEqual((object["exerciseOccurrences"] as? [Any])?.count, 0)
        let store = try await WhoopStore.inMemory()
        try await store.saveLiftRecording(session: record, sets: [set], workout: WorkoutRow(startTs: 1000, endTs: 1600, sport: "Strength Training", source: "manual", durationS: 600, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil))
        _ = try await store.insert(Streams(hr: [HRSample(ts: 1020, bpm: 90)]), deviceId: "strap")
        let before = try await delivery.matches(store: store)
        XCTAssertFalse(before)
        _ = try await store.deleteLiftRecording(record)
        let after = try await delivery.matches(store: store)
        XCTAssertTrue(after)
        let measured = try await store.measuredHeartRateStats(deviceId: "strap", from: 1000, toExclusive: 1600)
        XCTAssertEqual(measured.n, 1)
        let restored = try JSONDecoder().decode(WorkoutTrackerDelivery.self, from: JSONEncoder().encode(delivery))
        XCTAssertEqual(restored.bytes, bytes, "Relaunch must preserve the immutable tombstone event")
        XCTAssertEqual(restored.operation, .delete)
    }
}
