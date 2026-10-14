import XCTest
import WhoopStore
@testable import DhoopGoalTests

@MainActor
final class WorkoutTrackerClientTests: XCTestCase {
    private struct Fixture {
        let file: WorkoutTrackerFileStore
        let config: WorkoutSyncConfiguration
        let binding: WorkoutTrackerCaptureBinding
        let record: LiftSessionRow
        let sets: [LiftSetRow]
        let db: WhoopStore
    }
    private func fixture() async throws -> Fixture {
        let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), credential: String(repeating: "a", count: 64))
        let target = WorkoutTrackerManifest.PlannedSet(lifeSetId: 1, setNumber: 1, setType: "work", plannedLoad: 60, plannedReps: 8,
            loadOverride: false, repsOverride: false, actualLoad: nil, actualReps: nil, rir: nil, completed: false)
        let occurrence = WorkoutTrackerManifest.Occurrence(sessionExerciseId: 2, programSlotId: 3, slotKey: "push", exerciseKey: "bench", originalExerciseKey: "bench", name: "Bench", order: 0,
            measurementKind: "mass_reps", loadMode: .barbell, loadBasis: "total", unit: "kg", targetRir: 2, restTargetSeconds: nil, sets: [target])
        let manifest = WorkoutTrackerManifest(schemaVersion: 1, cycleId: 4, sessionId: 5, sessionKey: "upper_a", title: "Upper A", scheduledDate: nil, status: "planned", manifestRevision: "hash", lifeRevision: 0, exerciseOccurrences: [occurrence], sourceWorkoutId: nil)
        let binding = try WorkoutTrackerCaptureBinding(manifest: manifest, connection: .init(origin: config.origin, installationId: config.installationId))
        let record = LiftSessionRow(id: binding.sourceWorkoutId.uuidString.lowercased(), deviceId: "strap", startTs: 1000, endTs: 1600, sport: "Strength Training", programId: nil, programName: "Upper A", sessionRpe: 7.5, note: nil)
        let set = LiftSetRow(id: binding.occurrences[0].sets[0].sourceSetId.uuidString.lowercased(), deviceId: "strap", sessionId: record.id, ord: 0, exercise: "Bench", primaryMuscle: nil, setIndex: 1, weightKg: 60, reps: 8, rpe: 7, isWarmup: false, startTs: nil, endTs: nil, restSec: nil, note: "Controlled movement")
        let file = WorkoutTrackerFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var state = WorkoutTrackerState(); state.enabled = true; state.origin = config.origin; state.installationId = config.installationId
        try file.save(state)
        let db = try await WhoopStore.inMemory()
        return Fixture(file: file, config: config, binding: binding, record: record, sets: [set], db: db)
    }
    private func receipt(_ body: Data, fixture: Fixture, reconciliation: String = "done") throws -> Data {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "eventId": payload["eventId"]!, "sourceWorkoutId": fixture.record.id,
            "acceptedSourceRevision": payload["sourceRevision"]!, "outcome": "applied", "lifeRevision": 1, "receiptLifeRevision": 1,
            "preservedFields": [], "reconciliation": ["state": reconciliation], "mappings": ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 5],
                "sets": [fixture.sets[0].id: 1], "setTargets": [fixture.sets[0].id: ["kind": "workout_set", "lifeSetId": 1, "sessionExerciseId": 2]]]])
    }
    private func ready(_ client: WorkoutTrackerClient, fixture: Fixture) async throws {
        let event = try await client.prepare(record: fixture.record, sets: fixture.sets, binding: fixture.binding, store: fixture.db)
        try await fixture.db.saveLiftRecording(session: fixture.record, sets: fixture.sets, workout: WorkoutRow(startTs: 1000, endTs: 1600, sport: "Strength Training", source: "manual", durationS: 600,
            energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil))
        try await client.confirmPersistence(event, store: fixture.db)
    }

    func testConcurrentPreparationHasOneImmutableIntentAndNeedsNoCredentialRead() async throws {
        let f = try await fixture()
        let client = WorkoutTrackerClient(store: f.file, readCredential: { throw WorkoutSyncTransportError.configuration })
        let successes = await withTaskGroup(of: UUID?.self, returning: [UUID].self) { group in
            for _ in 0..<20 {
                group.addTask { @MainActor in try? await client.prepare(record: f.record, sets: f.sets, binding: f.binding, store: f.db) }
            }
            var ids: [UUID] = []; for await id in group { if let id { ids.append(id) } }; return ids
        }
        XCTAssertFalse(successes.isEmpty)
        XCTAssertEqual(Set(successes).count, 1)
        XCTAssertEqual(client.state.deliveries.count, 1)
        XCTAssertEqual(client.state.deliveries[0].revision, 1)
        XCTAssertNotNil(client.state.deliveries[0].bytes, "Local save does not depend on a readable credential")
    }
    func testLegacyExerciseIdsKeepStableSourceKeysAcrossRelaunchAndRemainDeviceScoped() async throws {
        let f = try await fixture()
        let client = WorkoutTrackerClient(store: f.file, readCredential: { nil })
        let id = try client.sourceExerciseIdentity(nativeId: "legacy-exercise", deviceID: "strap")
        XCTAssertEqual(try client.sourceExerciseIdentity(nativeId: "legacy-exercise", deviceID: "strap"), id)
        let restored = WorkoutTrackerClient(store: f.file, readCredential: { nil })
        XCTAssertEqual(try restored.sourceExerciseIdentity(nativeId: "legacy-exercise", deviceID: "strap"), id)
        XCTAssertNotEqual(try restored.sourceExerciseIdentity(nativeId: "legacy-exercise", deviceID: "other"), id)
        let embedded = try restored.sourceExerciseIdentity(nativeId: "c", deviceID: "a\u{0}b")
        XCTAssertNotEqual(try restored.sourceExerciseIdentity(nativeId: "b\u{0}c", deviceID: "a"), embedded, "An embedded delimiter cannot conflate two source exercises")
        let nativeUUID = UUID()
        XCTAssertEqual(try restored.sourceExerciseIdentity(nativeId: nativeUUID.uuidString, deviceID: "strap"), nativeUUID)
    }

    func testTimeoutRelaunchRetriesExactEventAndPendingReconciliationDoesNotReplaceCapture() async throws {
        let f = try await fixture()
        var sent: [Data] = []
        let first = WorkoutTrackerClient(store: f.file, send: { _, body, _ in sent.append(try XCTUnwrap(body)); throw URLError(.timedOut) }, readCredential: { f.config })
        try await ready(first, fixture: f)
        do { try await first.synchronize(store: f.db); XCTFail("An unknown receipt cannot be reported as accepted") }
        catch is URLError {}
        XCTAssertEqual(first.state.deliveries[0].status, .failed)
        var replies = 0
        let restored = WorkoutTrackerClient(store: f.file, send: { _, body, _ in
            let body = try XCTUnwrap(body); sent.append(body); replies += 1
            return try self.receipt(body, fixture: f, reconciliation: replies == 1 ? "pending" : "done")
        }, readCredential: { f.config })
        try await restored.synchronize(store: f.db)
        XCTAssertEqual(restored.state.deliveries[0].status, .accepted)
        XCTAssertTrue(restored.state.deliveries[0].needsReconciliation)
        try await restored.synchronize(store: f.db)
        XCTAssertFalse(restored.state.deliveries[0].needsReconciliation)
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(Set(sent).count, 1, "Timeout and derived retries must preserve bytes and source/delivery IDs")
        XCTAssertEqual(restored.state.deliveries.count, 1)
    }

    func testHistoryMutationWaitsForInFlightReceiptAndOffKeepsUncertainIntent() async throws {
        let f = try await fixture(), received = expectation(description: "Upload entered")
        var release: CheckedContinuation<Data, Error>?, body: Data?
        let client = WorkoutTrackerClient(store: f.file, send: { _, bytes, _ in
            body = bytes; received.fulfill()
            return try await withCheckedThrowingContinuation { release = $0 }
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let sending = Task { try await client.synchronize(store: f.db) }
        await fulfillment(of: [received], timeout: 2)
        do {
            _ = try await client.prepareHistoryChange(record: f.record, sets: f.sets, store: f.db, deleting: true)
            XCTFail("An in-flight delivery must not race its deletion")
        } catch WorkoutTrackerContractError.deliveryInProgress {}
        try client.setEnabled(false)
        release?.resume(returning: try receipt(try XCTUnwrap(body), fixture: f))
        try await sending.value
        XCTAssertFalse(client.state.enabled)
        XCTAssertEqual(client.state.deliveries.count, 1)
        XCTAssertEqual(client.state.deliveries[0].status, .ready, "Switching off cannot falsely claim the late receipt or discard its original event")
    }

    func testHTTPConflictKeepsLocalCaptureAndFailsTheSyncAction() async throws {
        let f = try await fixture()
        let client = WorkoutTrackerClient(store: f.file, send: { _, _, _ in throw WorkoutSyncTransportError.http(409) }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let original = client.state.deliveries[0].bytes
        do { try await client.synchronize(store: f.db); XCTFail("The button must not report success for a conflict") }
        catch WorkoutSyncTransportError.http(let status) { XCTAssertEqual(status, 409) }
        XCTAssertEqual(client.state.deliveries[0].status, .review)
        XCTAssertEqual(client.state.deliveries[0].bytes, original)
        let rows = try await f.db.liftSets(sessionId: f.record.id)
        XCTAssertEqual(rows, f.sets)
    }

    func testCaptureComparisonRejectsMixedRevisionsAndCannotSendObservations() async throws {
        let f = try await fixture()
        var reads = 0
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
            XCTAssertNil(body)
            guard case .captures(let id, _, _) = endpoint else { XCTFail("Comparison must be read-only"); throw WorkoutSyncTransportError.invalidResponse }
            XCTAssertEqual(id, f.binding.sourceWorkoutId)
            reads += 1
            let setID = reads == 1 ? f.sets[0].id : UUID().uuidString.lowercased()
            let next: Any = reads == 1 ? 1 : NSNull()
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sourceWorkoutId": f.record.id,
                "sourceRevision": reads, "lifeRevision": 2, "binding": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "tombstone": false,
                "session": ["timeZone": "Europe/London"], "ownership": [:], "projectionPolicy": "apply", "projectionState": "current", "nextCursor": next,
                "sets": [["sourceSetId": setID, "sourceOccurrenceId": f.binding.occurrences[0].sourceOccurrenceId.uuidString.lowercased(), "exerciseKey": "bench", "setType": "work",
                    "raw": ["sourceSetId": setID, "loadKg": 60, "reps": 8], "projection": ["actual_load": 132.2773573109265, "actual_reps": 8, "completed": 1]]]])
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let before = client.state.deliveries
        do { _ = try await client.captureSnapshot(deliveryId: before[0].id); XCTFail("Mixed snapshots cannot become a trustworthy comparison") }
        catch WorkoutTrackerContractError.invalidSnapshot {}
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(client.state.deliveries, before)
    }

    func testSelectedRecoveryRefusesStaleLocalValuesBeforeSending() async throws {
        let f = try await fixture()
        var sends = 0
        let client = WorkoutTrackerClient(store: f.file, send: { _, _, _ in sends += 1; throw URLError(.badServerResponse) }, readCredential: { f.config })
        try await ready(client, fixture: f)
        var changed = f.sets[0]; changed.reps = 10
        try await f.db.upsertLiftSets([changed])
        do { try await client.synchronize(store: f.db, deliveryId: client.state.deliveries[0].id); XCTFail("Stale local observations cannot be replayed") }
        catch WorkoutTrackerContractError.invalidSnapshot {}
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(client.state.deliveries[0].status, .review)
        let stored = try await f.db.liftSets(sessionId: f.record.id)
        XCTAssertEqual(stored[0].reps, 10)
    }

    func testKeepLocallyStopsAutomaticDeliveryAcrossRelaunchWithoutRemovingIntent() async throws {
        let f = try await fixture()
        var sends = 0
        let sender: (WorkoutSyncEndpoint, Data?, WorkoutSyncConfiguration) async throws -> Data = { _, body, _ in
            sends += 1; return try self.receipt(try XCTUnwrap(body), fixture: f)
        }
        let client = WorkoutTrackerClient(store: f.file, send: sender, readCredential: { f.config })
        try await ready(client, fixture: f)
        let original = client.state.deliveries[0]
        try client.keepLocally(deliveryId: original.id)
        let restored = WorkoutTrackerClient(store: f.file, send: sender, readCredential: { f.config })
        try await restored.synchronize(store: f.db)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(restored.state.deliveries[0].bytes, original.bytes)
        XCTAssertEqual(restored.state.deliveries[0].paused, true)
        try await restored.synchronize(store: f.db, deliveryId: original.id)
        XCTAssertEqual(sends, 1, "Only an explicit selected recovery can send the retained original event")
        XCTAssertEqual(restored.state.deliveries[0].status, .accepted)
        XCTAssertEqual(restored.state.deliveries[0].paused, true)
    }
}
