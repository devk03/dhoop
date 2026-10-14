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
        var manifest = WorkoutTrackerManifest(schemaVersion: 1, cycleId: 4, sessionId: 5, sessionKey: "upper_a", title: "Upper A", scheduledDate: nil, status: "planned", manifestRevision: "hash", lifeRevision: 0, exerciseOccurrences: [occurrence], sourceWorkoutId: nil)
        manifest.ownership = [:]
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

    func testCachedStartNeedsNoCredentialOrNetworkAndDoesNotInventLegacyFetchAge() async throws {
        let f = try await fixture()
        var state = try f.file.load(); state.enabled = false
        state.manifests["5"] = f.binding.manifest
        state.capturedAt = Date(timeIntervalSince1970: 1700000000)
        try f.file.save(state)
        var sends = 0, credentialReads = 0
        let client = WorkoutTrackerClient(store: f.file, send: { _, _, _ in sends += 1; return Data() }, readCredential: { credentialReads += 1; return nil })
        let binding = try client.cachedCaptureBinding(sessionId: 5)
        XCTAssertEqual(binding.manifest, f.binding.manifest)
        XCTAssertEqual(binding.connection?.origin, f.config.origin)
        XCTAssertEqual(binding.connection?.installationId, f.config.installationId)
        XCTAssertEqual(binding.planAtStart?.provenance, .cached)
        XCTAssertNil(binding.planAtStart?.fetchedAt, "An index read time is not a plan fetch time")
        XCTAssertEqual(sends, 0); XCTAssertEqual(credentialReads, 0)
        XCTAssertFalse(client.state.enabled)
        let restored = try JSONDecoder().decode(WorkoutTrackerCaptureBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(restored, binding)
    }

    func testKnownInconsistentPlanCannotUseOldCacheAndFreshReadClearsTheBlock() async throws {
        let f = try await fixture()
        var state = try f.file.load(); state.manifests["5"] = f.binding.manifest
        try f.file.save(state)
        let blocked = WorkoutTrackerClient(store: f.file, send: { _, _, _ in throw WorkoutSyncTransportError.rejected(.prescriptionInconsistent) }, readCredential: { f.config })
        do { _ = try await blocked.manifest(sessionId: 5); XCTFail("A reported inconsistency must fail the live read") }
        catch WorkoutSyncTransportError.rejected(let reason) { XCTAssertEqual(reason, .prescriptionInconsistent) }
        XCTAssertThrowsError(try blocked.cachedCaptureBinding(sessionId: 5))
        let restored = WorkoutTrackerClient(store: f.file, send: { _, _, _ in try JSONEncoder().encode(f.binding.manifest) }, readCredential: { f.config })
        XCTAssertEqual(restored.state.cachedPlanBlocks["5"], .inconsistent)
        let fresh = try await restored.manifest(sessionId: 5)
        XCTAssertNil(restored.state.cachedPlanBlocks["5"])
        let binding = try restored.captureBinding(manifest: fresh)
        XCTAssertEqual(binding.planAtStart?.provenance, .live)
        XCTAssertEqual(binding.planAtStart?.fetchedAt, restored.state.manifestReadAt["5"])
        XCTAssertNotNil(binding.planAtStart?.fetchedAt)
        let cached = try restored.cachedCaptureBinding(sessionId: 5)
        XCTAssertEqual(cached.planAtStart?.fetchedAt, binding.planAtStart?.fetchedAt)
        XCTAssertEqual(cached.planAtStart?.provenance, .cached)
    }

    func testTransientNetworkFailureDoesNotInvalidateTheFrozenCachedPlan() async throws {
        let f = try await fixture()
        var state = try f.file.load(); state.manifests["5"] = f.binding.manifest
        let date = Date(timeIntervalSince1970: 1700000000); state.manifestReadAt["5"] = date
        try f.file.save(state)
        let client = WorkoutTrackerClient(store: f.file, send: { _, _, _ in throw URLError(.timedOut) }, readCredential: { f.config })
        do { _ = try await client.manifest(sessionId: 5); XCTFail("The timeout is still a failed read") }
        catch is URLError {}
        let cached = try client.cachedCaptureBinding(sessionId: 5)
        XCTAssertEqual(cached.manifest, f.binding.manifest)
        XCTAssertEqual(cached.planAtStart?.fetchedAt, date)
        XCTAssertNil(client.state.cachedPlanBlocks["5"])
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
    func testKnownConflictSurvivesRelaunchAndOriginalRecoveryClearsItOnlyAfterReceipt() async throws {
        let f = try await fixture()
        let failing = WorkoutTrackerClient(store: f.file, send: { _, _, _ in throw WorkoutSyncTransportError.rejected(.lifeRevisionConflict) }, readCredential: { f.config })
        try await ready(failing, fixture: f)
        let original = try XCTUnwrap(failing.state.deliveries.first)
        do { try await failing.synchronize(store: f.db); XCTFail("A conflict must fail the action") }
        catch WorkoutSyncTransportError.rejected(let reason) { XCTAssertEqual(reason, .lifeRevisionConflict) }
        let restored = WorkoutTrackerClient(store: f.file, send: { _, body, _ in
            XCTAssertEqual(body, original.bytes)
            return try self.receipt(try XCTUnwrap(body), fixture: f)
        }, readCredential: { f.config })
        XCTAssertEqual(restored.state.deliveries.first?.rejection, .lifeRevisionConflict)
        XCTAssertEqual(restored.state.deliveries.first?.status, .review)
        try await restored.synchronize(store: f.db, deliveryId: original.id)
        XCTAssertNil(restored.state.deliveries.first?.rejection)
        XCTAssertEqual(restored.state.deliveries.first?.status, .accepted)
        XCTAssertEqual(restored.state.deliveries.first?.bytes, original.bytes)
    }

    func testReviewComparisonBracketsAbsentCaptureWithoutReplacingOrSendingTheIntent() async throws {
        let f = try await fixture()
        var reads = 0
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
            XCTAssertNil(body, "Comparison may not send observations")
            reads += 1
            switch endpoint {
            case .manifest(5): return try JSONEncoder().encode(f.binding.manifest)
            case .captures(let source, cursor: 0, limit: 50):
                XCTAssertEqual(source, f.binding.sourceWorkoutId)
                throw WorkoutSyncTransportError.captureNotFound
            default: XCTFail("Unexpected write or read"); throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let before = client.state
        let comparison = try await client.reviewComparison(deliveryId: client.state.deliveries[0].id)
        XCTAssertNil(comparison.capture)
        XCTAssertEqual(comparison.manifest, f.binding.manifest)
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(client.state, before, "A missing capture cannot authorize replacing an uncertain event")
    }

    func testReviewComparisonRejectsChangingManifestAndGenericMissingRoute() async throws {
        for generic404 in [false, true] {
            let f = try await fixture()
            var manifestReads = 0
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
                XCTAssertNil(body)
                switch endpoint {
                case .manifest:
                    manifestReads += 1
                    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.binding.manifest)) as? [String: Any])
                    object["lifeRevision"] = manifestReads
                    return try JSONSerialization.data(withJSONObject: object)
                case .captures:
                    if generic404 { throw WorkoutSyncTransportError.http(404) }
                    throw WorkoutSyncTransportError.captureNotFound
                default: XCTFail("Comparison cannot send"); throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            try await ready(client, fixture: f)
            let before = client.state
            do {
                _ = try await client.reviewComparison(deliveryId: client.state.deliveries[0].id)
                XCTFail("Inconsistent or unverified absence must fail closed")
            } catch WorkoutTrackerContractError.invalidSnapshot { XCTAssertFalse(generic404) }
            catch WorkoutSyncTransportError.http(let code) { XCTAssertTrue(generic404); XCTAssertEqual(code, 404) }
            XCTAssertEqual(client.state, before)
            XCTAssertFalse(client.busy)
        }
    }

    func testReviewComparisonRequiresCaptureAndManifestAtTheSameRevision() async throws {
        for captureRevision in [0, 1] {
            let f = try await fixture()
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
                XCTAssertNil(body)
                switch endpoint {
                case .manifest: return try JSONEncoder().encode(f.binding.manifest)
                case .captures:
                    return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sourceWorkoutId": f.record.id,
                        "sourceRevision": 1, "lifeRevision": captureRevision,
                        "binding": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "tombstone": false,
                        "session": ["timeZone": "Europe/London"], "ownership": [:],
                        "projectionPolicy": "apply", "projectionState": "current", "sets": [], "nextCursor": NSNull()])
                default: XCTFail("Comparison cannot write"); throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            try await ready(client, fixture: f)
            let before = client.state
            do {
                let comparison = try await client.reviewComparison(deliveryId: client.state.deliveries[0].id)
                XCTAssertEqual(captureRevision, 0)
                XCTAssertEqual(comparison.capture?.sourceWorkoutId, f.binding.sourceWorkoutId)
            } catch WorkoutTrackerContractError.invalidSnapshot { XCTAssertEqual(captureRevision, 1) }
            XCTAssertEqual(client.state, before)
        }
    }

    func testReviewedGlobalConflictPreparesANewPausedEventAndPreservesOriginalObservations() async throws {
        let f = try await fixture()
        var submitted: [Data] = []
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
            switch endpoint {
            case .observations:
                let body = try XCTUnwrap(body); submitted.append(body)
                if submitted.count == 1 { throw WorkoutSyncTransportError.rejected(.lifeRevisionConflict) }
                return try self.receipt(body, fixture: f)
            case .manifest:
                XCTAssertNil(body)
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.binding.manifest)) as? [String: Any])
                object["lifeRevision"] = 1
                return try JSONSerialization.data(withJSONObject: object)
            case .captures: XCTAssertNil(body); throw WorkoutSyncTransportError.captureNotFound
            default: XCTFail("Unexpected request"); throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let original = client.state.deliveries[0]
        do { try await client.synchronize(store: f.db); XCTFail("First attempt must report its conflict") }
        catch WorkoutSyncTransportError.rejected {}
        let review = try await client.reviewRecovery(deliveryId: original.id)
        let replacementId = try await client.prepareReviewedRecovery(reviewId: review.id, store: f.db)
        let replacement = try XCTUnwrap(client.state.deliveries.first { $0.id == replacementId })
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.sourceWorkoutId, original.sourceWorkoutId)
        XCTAssertEqual(replacement.revision, original.revision)
        XCTAssertEqual(replacement.binding, original.binding)
        XCTAssertEqual(replacement.sets, original.sets)
        XCTAssertEqual(replacement.paused, true)
        XCTAssertEqual(replacement.recoveryOf, original.id)
        XCTAssertEqual(try client.delivery(original.id)?.bytes, original.bytes)
        XCTAssertEqual(submitted.count, 1, "Review and preparation must not send observations")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(original.bytes)) as? [String: Any])
        var new = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(replacement.bytes)) as? [String: Any])
        XCTAssertEqual(new["baseLifeRevision"] as? Int, 1)
        for key in ["eventId", "baseLifeRevision"] { old[key] = nil; new[key] = nil }
        XCTAssertEqual(old as NSDictionary, new as NSDictionary)
        let restored = WorkoutTrackerClient(store: f.file, send: { _, body, _ in
            submitted.append(try XCTUnwrap(body)); return try self.receipt(try XCTUnwrap(body), fixture: f)
        }, readCredential: { f.config })
        try await restored.synchronize(store: f.db)
        XCTAssertEqual(submitted.count, 1, "The replacement stays paused after relaunch")
        try await restored.synchronize(store: f.db, deliveryId: replacementId)
        XCTAssertEqual(submitted.last, replacement.bytes)
        XCTAssertEqual(try restored.delivery(replacementId)?.status, .accepted)
    }

    func testChangedPrescriptionRebaseKeepsPerformedValuesAndOriginalStartProvenance() async throws {
        let base = try await fixture()
        var binding = base.binding
        binding.planAtStart = .init(manifest: binding.manifest, provenance: .cached, fetchedAt: Date(timeIntervalSince1970: 1700000000))
        let f = Fixture(file: base.file, config: base.config, binding: binding, record: base.record, sets: base.sets, db: base.db)
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, _, _ in
            switch endpoint {
            case .observations: throw WorkoutSyncTransportError.rejected(.manifestConflict)
            case .captures: throw WorkoutSyncTransportError.captureNotFound
            case .manifest:
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.binding.manifest)) as? [String: Any])
                object["lifeRevision"] = 2; object["manifestRevision"] = "new-prescription"
                var occurrences = try XCTUnwrap(object["exerciseOccurrences"] as? [[String: Any]])
                var targets = try XCTUnwrap(occurrences[0]["sets"] as? [[String: Any]])
                targets[0]["plannedLoad"] = 45; occurrences[0]["sets"] = targets; object["exerciseOccurrences"] = occurrences
                return try JSONSerialization.data(withJSONObject: object)
            default: throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let original = client.state.deliveries[0]
        do { try await client.synchronize(store: f.db); XCTFail("Conflict must be explicit") }
        catch WorkoutSyncTransportError.rejected {}
        let review = try await client.reviewRecovery(deliveryId: original.id)
        XCTAssertTrue(review.prescriptionChanged)
        let id = try await client.prepareReviewedRecovery(reviewId: review.id, store: f.db)
        let replacement = try XCTUnwrap(try client.delivery(id))
        XCTAssertEqual(replacement.revision, original.revision + 1)
        XCTAssertEqual(replacement.binding.planAtStart, binding.planAtStart)
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(original.bytes)) as? [String: Any])
        let new = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(replacement.bytes)) as? [String: Any])
        XCTAssertEqual(new["manifestRevision"] as? String, "new-prescription")
        XCTAssertEqual(new["exerciseOccurrences"] as? NSArray, old["exerciseOccurrences"] as? NSArray)
        XCTAssertEqual(new["planAtStart"] as? NSDictionary, old["planAtStart"] as? NSDictionary)
        XCTAssertEqual(replacement.sets[0].weightKg, 60, "Current targets never replace performed load")
        XCTAssertEqual(replacement.reviewedManifest?.manifestRevision, "new-prescription")
        var laterConflict = replacement; laterConflict.status = .review; laterConflict.rejection = .lifeRevisionConflict
        let laterReview = WorkoutTrackerRecoveryReview(id: UUID(), original: laterConflict, comparison: review.comparison)
        XCTAssertFalse(laterReview.prescriptionChanged, "Compare against the queued write plan, not the immutable original start plan")
        XCTAssertEqual(try laterReview.replacement().revision, replacement.revision)
        let restored = WorkoutTrackerClient(store: f.file, send: { _, body, _ in try self.receipt(try XCTUnwrap(body), fixture: f) }, readCredential: { f.config })
        try await restored.synchronize(store: f.db, deliveryId: id)
        var corrected = f.sets; corrected[0].reps = 10
        let correctedId = try await restored.prepareHistoryChange(record: f.record, sets: corrected, store: f.db)
        let correction = try XCTUnwrap(try restored.delivery(XCTUnwrap(correctedId)))
        XCTAssertEqual(correction.writeManifestRevision, "new-prescription")
        XCTAssertEqual(correction.reviewedManifest?.manifestRevision, "new-prescription")
        XCTAssertEqual(correction.binding.planAtStart, binding.planAtStart)
    }

    func testReviewCannotRebaseUnknownReceiptOrChangedLocalRecording() async throws {
        for timeout in [true, false] {
            let f = try await fixture()
            var reads = 0
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, _, _ in
                switch endpoint {
                case .observations:
                    if timeout { throw URLError(.timedOut) }
                    throw WorkoutSyncTransportError.rejected(.lifeRevisionConflict)
                case .manifest: reads += 1; return try JSONEncoder().encode(f.binding.manifest)
                case .captures: reads += 1; throw WorkoutSyncTransportError.captureNotFound
                default: throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            try await ready(client, fixture: f)
            do { try await client.synchronize(store: f.db); XCTFail("Submission must fail") } catch {}
            let original = client.state.deliveries[0]
            if timeout {
                do { _ = try await client.reviewRecovery(deliveryId: original.id); XCTFail("Unknown outcomes must recover the original event") }
                catch WorkoutTrackerContractError.invalidSnapshot {}
                XCTAssertEqual(reads, 0)
            } else {
                let review = try await client.reviewRecovery(deliveryId: original.id)
                var changed = f.sets[0]; changed.reps = 12
                try await f.db.upsertLiftSets([changed])
                do { _ = try await client.prepareReviewedRecovery(reviewId: review.id, store: f.db); XCTFail("A stale local snapshot cannot be prepared") }
                catch WorkoutTrackerContractError.sessionChanged {}
            }
            XCTAssertEqual(client.state.deliveries.count, 1)
            XCTAssertEqual(client.state.deliveries[0].bytes, original.bytes)
        }
    }

    func testReviewedRecoveryRejectsChangedIdentitiesTombstonesAndEqualOrNewerServerSource() async throws {
        for scenario in ["set", "exercise", "loadMode", "tombstone", "equal", "newer"] {
            let f = try await fixture()
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, _, _ in
                switch endpoint {
                case .observations: throw WorkoutSyncTransportError.rejected(.lifeRevisionConflict)
                case .manifest:
                    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.binding.manifest)) as? [String: Any])
                    var occurrences = try XCTUnwrap(object["exerciseOccurrences"] as? [[String: Any]])
                    if scenario == "set" {
                        var sets = try XCTUnwrap(occurrences[0]["sets"] as? [[String: Any]])
                        sets[0]["lifeSetId"] = 999; occurrences[0]["sets"] = sets
                    }
                    if scenario == "exercise" { occurrences[0]["exerciseKey"] = "different-exercise" }
                    if scenario == "loadMode" { occurrences[0]["loadMode"] = "machine" }
                    object["exerciseOccurrences"] = occurrences
                    return try JSONSerialization.data(withJSONObject: object)
                case .captures:
                    if ["set", "exercise", "loadMode"].contains(scenario) { throw WorkoutSyncTransportError.captureNotFound }
                    return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sourceWorkoutId": f.record.id,
                        "sourceRevision": scenario == "newer" ? 2 : 1, "lifeRevision": 0,
                        "binding": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "tombstone": scenario == "tombstone",
                        "session": ["timeZone": "Europe/London"], "ownership": [:], "projectionPolicy": "apply",
                        "projectionState": "current", "sets": [], "nextCursor": NSNull()])
                default: throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            try await ready(client, fixture: f)
            do { try await client.synchronize(store: f.db); XCTFail("Original rejection must remain explicit") }
            catch WorkoutSyncTransportError.rejected {}
            let original = client.state.deliveries[0]
            do { _ = try await client.reviewRecovery(deliveryId: original.id); XCTFail("Unsafe \(scenario) must not produce an applicable review") }
            catch WorkoutTrackerContractError.invalidSnapshot {}
            XCTAssertEqual(client.state.deliveries, [original])
        }
    }

    func testPreparedReviewRejectsAChangedTrackerSnapshotAndRepeatedPreparation() async throws {
        let f = try await fixture()
        var manifestReads = 0, changed = false
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, _, _ in
            switch endpoint {
            case .observations: throw WorkoutSyncTransportError.rejected(.lifeRevisionConflict)
            case .captures: throw WorkoutSyncTransportError.captureNotFound
            case .manifest:
                manifestReads += 1
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.binding.manifest)) as? [String: Any])
                object["lifeRevision"] = changed ? 2 : 1
                return try JSONSerialization.data(withJSONObject: object)
            default: throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        do { try await client.synchronize(store: f.db) } catch WorkoutSyncTransportError.rejected {}
        let original = client.state.deliveries[0]
        let review = try await client.reviewRecovery(deliveryId: original.id)
        changed = true
        do { _ = try await client.prepareReviewedRecovery(reviewId: review.id, store: f.db); XCTFail("Old review must not be applied to new tracker data") }
        catch WorkoutTrackerContractError.sessionChanged {}
        XCTAssertEqual(client.state.deliveries.count, 1)
        changed = false
        let refreshed = try await client.reviewRecovery(deliveryId: original.id)
        _ = try await client.prepareReviewedRecovery(reviewId: refreshed.id, store: f.db)
        do { _ = try await client.prepareReviewedRecovery(reviewId: refreshed.id, store: f.db); XCTFail("Preparation cannot submit twice") }
        catch WorkoutTrackerContractError.sessionChanged {}
        XCTAssertEqual(client.state.deliveries.count, 2)
        XCTAssertEqual(manifestReads, 8)
    }

    func testExistingCaptureRebaseUsesVerifiedOriginalOccurrenceAndRejectsItsTombstone() async throws {
        for failure in ["none", "deleted", "ownership"] {
            let occurrenceDeleted = failure == "deleted"
            let f = try await fixture()
            var posts = 0
            let sourceOccurrence = f.binding.occurrences[0].sourceOccurrenceId.uuidString.lowercased()
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
                switch endpoint {
                case .observations:
                    posts += 1
                    if posts == 1 { return try self.receipt(try XCTUnwrap(body), fixture: f) }
                    throw WorkoutSyncTransportError.rejected(.lifeRevisionConflict)
                case .manifest:
                    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.binding.manifest)) as? [String: Any])
                    object["lifeRevision"] = 2; object["sourceWorkoutId"] = f.record.id
                    object["ownership"] = ["set:1:actualLoad": ["origin": "manual"]]
                    return try JSONSerialization.data(withJSONObject: object)
                case .captures:
                    return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sourceWorkoutId": f.record.id,
                        "sourceRevision": 1, "lifeRevision": 2, "binding": ["kind": "programmed", "cycleId": 4, "sessionId": 5],
                        "tombstone": false, "session": ["timeZone": "Europe/London"], "ownership": failure == "ownership" ? [:] : ["set:1:actualLoad": ["origin": "manual"]],
                        "projectionPolicy": "apply", "projectionState": "current", "nextCursor": NSNull(),
                        "occurrences": [sourceOccurrence: ["kind": "prescribed", "sessionExerciseId": 2, "programSlotId": 3,
                            "slotKey": "push", "exerciseKey": "bench", "loadMode": "barbell", "raw": ["deleted": occurrenceDeleted]]],
                        "sets": [["sourceSetId": f.sets[0].id, "sourceOccurrenceId": sourceOccurrence, "sessionExerciseId": 2,
                            "lifeSetId": 1, "exerciseKey": "bench", "setType": "work", "raw": ["loadKg": 60, "loadBasis": "total", "reps": 8]]]])
                default: throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            try await ready(client, fixture: f)
            try await client.synchronize(store: f.db)
            var changed = f.sets; changed[0].reps = 10
            let prepared = try await client.prepareHistoryChange(record: f.record, sets: changed, store: f.db)
            let event = try XCTUnwrap(prepared)
            try await f.db.upsertLiftSets(changed)
            try await client.confirmPersistence(event, store: f.db)
            do { try await client.synchronize(store: f.db); XCTFail("Correction should encounter the test conflict") }
            catch WorkoutSyncTransportError.rejected {}
            do {
                let review = try await client.reviewRecovery(deliveryId: event)
                XCTAssertEqual(failure, "none")
                XCTAssertEqual(review.comparison.manifest.ownership?["set:1:actualLoad"]?.origin, "manual")
                let replacementId = try await client.prepareReviewedRecovery(reviewId: review.id, store: f.db)
                XCTAssertEqual(try client.delivery(replacementId)?.sets[0].reps, 10)
                XCTAssertEqual(try client.delivery(replacementId)?.revision, 2)
            } catch WorkoutTrackerContractError.invalidSnapshot { XCTAssertNotEqual(failure, "none") }
            XCTAssertEqual(posts, 2, "Neither review nor preparation may apply manual website values")
        }
    }
    private func historyCapture(_ f: Fixture, sourceRevision: Int = 1) throws -> [String: Any] {
        let occurrence = f.binding.occurrences[0].sourceOccurrenceId.uuidString.lowercased()
        return ["schemaVersion": 1, "sourceWorkoutId": f.record.id, "sourceRevision": sourceRevision, "lifeRevision": 2,
            "binding": ["kind": "programmed", "cycleId": 4, "sessionId": 5], "tombstone": false,
            "session": ["timeZone": f.binding.timeZone, "notes": "Website source note"],
            "planAtStart": NSNull(), "ownership": ["set:1:actualLoad": ["origin": "manual"]],
            "projectionPolicy": "apply", "projectionState": "retired", "nextCursor": NSNull(),
            "occurrences": [occurrence: ["kind": "prescribed", "sessionExerciseId": 2, "programSlotId": 3,
                "slotKey": "push", "exerciseKey": "bench", "loadMode": "barbell", "raw": [:]]],
            "sets": [["sourceSetId": f.sets[0].id, "sourceOccurrenceId": occurrence, "sessionExerciseId": 2,
                "lifeSetId": 1, "exerciseKey": "bench", "setType": "work", "raw": ["loadKg": 60, "loadBasis": "total", "reps": 8],
                "projection": ["actual_load": 150, "actual_reps": 9]]]]
    }
    private func localHistoryCorrection(_ client: WorkoutTrackerClient, fixture f: Fixture) async throws -> UUID {
        try await ready(client, fixture: f)
        try await client.synchronize(store: f.db)
        var changed = f.sets; changed[0].reps = 10; changed[0].note = "Corrected note"
        let prepared = try await client.prepareHistoryChange(record: f.record, sets: changed, store: f.db)
        let event = try XCTUnwrap(prepared)
        try await f.db.upsertLiftSets(changed)
        try await client.confirmPersistence(event, store: f.db)
        return event
    }

    func testExplicitHistoryOnlyCorrectionUsesAcceptedRetiredCaptureAndSendsOnlyAfterPreparation() async throws {
        let f = try await fixture()
        var posts = [Data](), captureReads = 0
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
            switch endpoint {
            case .observations:
                let body = try XCTUnwrap(body); posts.append(body)
                XCTAssertEqual(try f.file.load().deliveries.last?.submissionAttempted, true, "Submission must be durable before transport starts")
                var ack = try XCTUnwrap(JSONSerialization.jsonObject(with: self.receipt(body, fixture: f)) as? [String: Any])
                if posts.count > 1 {
                    ack["outcome"] = "captured_only"; ack["projectionPolicy"] = "capture_only"; ack["projectionState"] = "retired"
                    ack["lifeRevision"] = 3; ack["receiptLifeRevision"] = 3; ack["reconciliation"] = ["state": "not_requested"]
                }
                return try JSONSerialization.data(withJSONObject: ack)
            case .captures: captureReads += 1; return try JSONSerialization.data(withJSONObject: self.historyCapture(f))
            default: XCTFail("Retired history review must not depend on a current manifest"); throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        let originalId = try await localHistoryCorrection(client, fixture: f)
        let original = try XCTUnwrap(client.delivery(originalId)), originalBytes = try XCTUnwrap(original.bytes)
        let review = try await client.reviewHistoryOnly(deliveryId: originalId)
        XCTAssertEqual(review.capture.projectionState, "retired")
        let replacementId = try await client.prepareHistoryOnly(reviewId: review.id, store: f.db)
        XCTAssertEqual(posts.count, 1, "Review/preparation may only read; the first POST was the original accepted workout")
        XCTAssertEqual(captureReads, 4)
        let replacement = try XCTUnwrap(client.delivery(replacementId))
        XCTAssertTrue(replacement.isHistoryOnly); XCTAssertTrue(replacement.paused == true)
        XCTAssertEqual(replacement.revision, 3); XCTAssertEqual(replacement.sourceWorkoutId, original.sourceWorkoutId)
        XCTAssertEqual(try client.delivery(originalId)?.bytes, originalBytes)
        var before = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
        var after = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(replacement.bytes)) as? [String: Any])
        for key in ["eventId", "sourceRevision", "baseLifeRevision", "projectionPolicy"] { before.removeValue(forKey: key); after.removeValue(forKey: key) }
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: after), "All measured values, binding IDs and start provenance must be retained")
        do { _ = try await client.prepareHistoryOnly(reviewId: review.id, store: f.db); XCTFail("No duplicate preparation") }
        catch WorkoutTrackerContractError.sessionChanged {}
        do { try await client.synchronize(store: f.db, deliveryId: originalId); XCTFail("Superseded apply cannot be sent") }
        catch WorkoutTrackerContractError.deliverySuperseded {}
        try await client.synchronize(store: f.db)
        XCTAssertEqual(posts.count, 1, "Automatic sync must not send a paused history-only choice")
        try await client.synchronize(store: f.db, deliveryId: replacementId)
        let accepted = try XCTUnwrap(client.delivery(replacementId))
        XCTAssertEqual(posts.count, 2); XCTAssertEqual(accepted.status, .accepted)
        XCTAssertTrue(accepted.canArchive); XCTAssertFalse(accepted.needsReconciliation)
        XCTAssertTrue(accepted.message.contains("history only"))
        let restored = WorkoutTrackerClient(store: f.file, readCredential: { f.config })
        XCTAssertEqual(try restored.delivery(replacementId)?.bytes, replacement.bytes)
        XCTAssertEqual(try restored.delivery(replacementId)?.submissionAttempted, true)
        XCTAssertEqual(try restored.delivery(replacementId)?.status, .accepted)
    }

    func testNeverSubmittedCorrectionKeptLocallyCanStillBeExplicitlyReviewed() async throws {
        let f = try await fixture()
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
            switch endpoint {
            case .observations: return try self.receipt(try XCTUnwrap(body), fixture: f)
            case .captures: return try JSONSerialization.data(withJSONObject: self.historyCapture(f))
            default: throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        let event = try await localHistoryCorrection(client, fixture: f)
        try client.keepLocally(deliveryId: event)
        let review = try await client.reviewHistoryOnly(deliveryId: event)
        let prepared = try await client.prepareHistoryOnly(reviewId: review.id, store: f.db)
        XCTAssertTrue(try XCTUnwrap(client.delivery(prepared)).isHistoryOnly)
        XCTAssertTrue(client.state.locallyKeptSources.contains(f.binding.sourceWorkoutId))
    }

    func testRetiredCanonicalReceiptStillProvesAcceptedSourceHistory() async throws {
        let f = try await fixture()
        let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
            switch endpoint {
            case .observations:
                var ack = try XCTUnwrap(JSONSerialization.jsonObject(with: self.receipt(try XCTUnwrap(body), fixture: f)) as? [String: Any])
                ack["projectionState"] = "retired"; ack["currentProjectionState"] = "retired"
                return try JSONSerialization.data(withJSONObject: ack)
            case .captures: return try JSONSerialization.data(withJSONObject: self.historyCapture(f))
            default: throw WorkoutSyncTransportError.invalidResponse
            }
        }, readCredential: { f.config })
        try await ready(client, fixture: f)
        let event = client.state.deliveries[0].id
        try await client.synchronize(store: f.db)
        XCTAssertEqual(try client.delivery(event)?.status, .review, "Retired canonical targets must not imply canonical application")
        XCTAssertTrue(try XCTUnwrap(client.delivery(event)).hasVerifiedSourceReceipt)
        let review = try await client.reviewHistoryOnly(deliveryId: event)
        let replacement = try await client.prepareHistoryOnly(reviewId: review.id, store: f.db)
        XCTAssertTrue(try XCTUnwrap(client.delivery(replacement)).isHistoryOnly)
    }

    func testHistoryOnlyReviewRejectsUncertainSubmissionsAndChangedAcceptedIdentityOrProvenance() async throws {
        for scenario in ["unknown", "legacy", "newer", "tombstone", "identity", "provenance", "missing", "removedSet"] {
            let f = try await fixture()
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
                switch endpoint {
                case .observations: return try self.receipt(try XCTUnwrap(body), fixture: f)
                case .captures:
                    if scenario == "missing" { throw WorkoutSyncTransportError.captureNotFound }
                    var object = try self.historyCapture(f, sourceRevision: scenario == "newer" ? 3 : 1)
                    if scenario == "tombstone" { object["tombstone"] = true }
                    if scenario == "identity" {
                        var sets = try XCTUnwrap(object["sets"] as? [[String: Any]])
                        sets[0]["lifeSetId"] = 99; object["sets"] = sets
                    }
                    if scenario == "provenance" { object["planAtStart"] = ["manifestRevision": NSNull(), "provenance": "live", "fetchedAt": NSNull()] }
                    if scenario == "removedSet" { object["sets"] = [] }
                    return try JSONSerialization.data(withJSONObject: object)
                default: throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            let event = try await localHistoryCorrection(client, fixture: f)
            if ["unknown", "legacy"].contains(scenario) {
                var state = try f.file.load()
                state.deliveries[state.deliveries.count - 1].submissionAttempted = scenario == "unknown" ? true : nil
                try f.file.save(state)
            }
            let candidate = ["unknown", "legacy"].contains(scenario)
                ? WorkoutTrackerClient(store: f.file, send: { _, _, _ in try JSONSerialization.data(withJSONObject: self.historyCapture(f)) }, readCredential: { f.config }) : client
            do { _ = try await candidate.reviewHistoryOnly(deliveryId: event); XCTFail("Must hold \(scenario) for review") }
            catch {}
            XCTAssertEqual(candidate.state.deliveries.count, 2)
        }
    }

    func testBackupCannotTurnAnOldUnacceptedSnapshotIntoProofOfNoSubmission() async throws {
        for archived in [false, true] {
            let f = try await fixture(), client = WorkoutTrackerClient(store: f.file, readCredential: { nil })
            try await ready(client, fixture: f)
            var state = client.state
            let original = state.deliveries[0]
            XCTAssertEqual(original.submissionAttempted, false)
            var originalArchiveId: UUID?
            if archived {
                let fileId = UUID(); originalArchiveId = fileId
                try FileManager.default.createDirectory(at: f.file.archiveDirectory, withIntermediateDirectories: true)
                try JSONEncoder().encode(original).write(to: f.file.archiveURL(fileId))
                state.deliveries = []
                state.archives[original.id.uuidString.lowercased()] = WorkoutTrackerArchiveReference(delivery: original, fileId: fileId)
            }
            let package = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dhoopworkouts")
            try f.file.prepareBackup(state: state, destination: package)
            let target = WorkoutTrackerFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
            let merged = try target.mergedBackup(from: package, current: WorkoutTrackerState())
            let imported: WorkoutTrackerDelivery
            if archived {
                let reference = try XCTUnwrap(merged.archives[original.id.uuidString.lowercased()])
                imported = try target.archived(reference)
                XCTAssertTrue(FileManager.default.fileExists(atPath: target.archiveURL(try XCTUnwrap(originalArchiveId)).path), "Original provenance snapshot is retained")
            } else { imported = try XCTUnwrap(merged.deliveries.first) }
            XCTAssertNil(imported.submissionAttempted, "An old backup cannot prove the original phone never sent this intent later")
            XCTAssertEqual(imported.bytes, original.bytes); XCTAssertEqual(imported.id, original.id)
            XCTAssertFalse(merged.enabled)
        }
    }

    func testHistoryOnlyPreparationRechecksUnrenderedEvidenceAndCurrentLocalStorage() async throws {
        for scenario in ["rawEvidence", "localStorage"] {
            let f = try await fixture()
            var changed = false
            let client = WorkoutTrackerClient(store: f.file, send: { endpoint, body, _ in
                switch endpoint {
                case .observations: return try self.receipt(try XCTUnwrap(body), fixture: f)
                case .captures:
                    var object = try self.historyCapture(f)
                    object["collectionSessionId"] = changed && scenario == "rawEvidence" ? "00000000-0000-4000-8000-000000000099" : NSNull()
                    return try JSONSerialization.data(withJSONObject: object)
                default: throw WorkoutSyncTransportError.invalidResponse
                }
            }, readCredential: { f.config })
            let event = try await localHistoryCorrection(client, fixture: f)
            let review = try await client.reviewHistoryOnly(deliveryId: event)
            changed = true
            if scenario == "localStorage" {
                var sets = f.sets; sets[0].reps = 11
                try await f.db.upsertLiftSets(sets)
            }
            do { _ = try await client.prepareHistoryOnly(reviewId: review.id, store: f.db); XCTFail("A changed review cannot prepare") }
            catch WorkoutTrackerContractError.sessionChanged {}
            XCTAssertEqual(client.state.deliveries.count, 2)
        }
    }

    func testUnsupportedNoteIsSavedLocallyWithItsActualValidationReasonAndCannotUpload() async throws {
        let f = try await fixture()
        var rows = f.sets; rows[0].note = String(repeating: "x", count: 2001)
        var sends = 0
        let client = WorkoutTrackerClient(store: f.file, send: { _, _, _ in sends += 1; return Data() }, readCredential: { f.config })
        let event = try await client.prepare(record: f.record, sets: rows, binding: f.binding, store: f.db)
        XCTAssertNil(client.state.deliveries.first?.bytes)
        XCTAssertTrue(client.state.deliveries.first?.message.contains("set notes") == true)
        try await f.db.saveLiftRecording(session: f.record, sets: rows, workout: WorkoutRow(startTs: 1000, endTs: 1600, sport: "Strength Training", source: "manual", durationS: 600,
            energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil))
        try await client.confirmPersistence(event, store: f.db)
        XCTAssertEqual(client.state.deliveries.first?.status, .review)
        XCTAssertTrue(client.state.deliveries.first?.message.contains("set notes") == true)
        do { try await client.synchronize(store: f.db, deliveryId: event); XCTFail("An invalid payload cannot be sent or reported as a success") }
        catch WorkoutTrackerContractError.invalidSnapshot {}
        XCTAssertEqual(sends, 0)
        let saved = try await f.db.liftSets(sessionId: f.record.id)
        XCTAssertEqual(saved.first?.note, rows[0].note, "Failed preparation must not truncate or discard entered notes")
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

    func testArchiveKeepsOriginalBytesAndCorrectionsContinueFromAcceptedRevision() async throws {
        let f = try await fixture()
        var state = try f.file.load()
        for revision in 1...90 {
            let event = UUID()
            let body = try WorkoutCapturePayload.make(record: f.record, sets: f.sets, binding: f.binding, installationId: f.config.installationId,
                revision: revision, eventId: event).bytes()
            state.deliveries.append(WorkoutTrackerDelivery(id: event, sourceWorkoutId: f.binding.sourceWorkoutId, installationId: f.config.installationId,
                origin: f.config.origin, revision: revision, bytes: body, record: f.record, sets: f.sets, binding: f.binding,
                status: .accepted, acknowledgement: try receipt(body, fixture: f), localPersistenceConfirmed: true))
        }
        let oldest = try XCTUnwrap(state.deliveries.first)
        let compacted = try f.file.compact(state, protecting: [])
        XCTAssertEqual(compacted.deliveries.count, 80)
        XCTAssertEqual(compacted.archives.count, 10)
        try f.file.save(compacted)
        let reference = try XCTUnwrap(compacted.archives[oldest.id.uuidString.lowercased()])
        XCTAssertEqual(try f.file.archived(reference), oldest)
        var changedSummary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as? [String: Any])
        changedSummary["status"] = "failed"
        let conflictingSummary = try JSONDecoder().decode(WorkoutTrackerArchiveReference.self, from: JSONSerialization.data(withJSONObject: changedSummary))
        XCTAssertThrowsError(try f.file.archived(conflictingSummary), "The list summary and full receipt must resolve from the same facts")
        let package = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dhoopworkouts", isDirectory: true)
        try f.file.prepareBackup(state: compacted, destination: package)
        let restoredFile = WorkoutTrackerFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let merged = try restoredFile.mergedBackup(from: package, current: WorkoutTrackerState())
        try restoredFile.save(merged)
        let restoredReference = try XCTUnwrap(merged.archives[oldest.id.uuidString.lowercased()])
        XCTAssertEqual(try restoredFile.archived(restoredReference).bytes, oldest.bytes)
        XCTAssertFalse(merged.enabled)
        var sends: [Data] = []
        let client = WorkoutTrackerClient(store: f.file, send: { _, body, _ in
            let body = try XCTUnwrap(body); sends.append(body); return try self.receipt(body, fixture: f)
        }, readCredential: { f.config })
        // Restore the matching local recording so the archived event can be explicitly recovered.
        try await f.db.saveLiftRecording(session: f.record, sets: f.sets, workout: WorkoutRow(startTs: 1000, endTs: 1600, sport: "Strength Training", source: "manual", durationS: 600,
            energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil))
        XCTAssertEqual(try client.delivery(oldest.id)?.bytes, oldest.bytes)
        try await client.synchronize(store: f.db, deliveryId: oldest.id)
        XCTAssertEqual(sends, [try XCTUnwrap(oldest.bytes)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.file.archiveURL(reference.fileId).path), "Recovery never removes the original snapshot")
        let correction = try await client.prepareHistoryChange(record: f.record, sets: f.sets, store: f.db)
        XCTAssertNotNil(correction)
        XCTAssertEqual(client.state.deliveries.last?.revision, 91)
    }

    func testPendingAndUnverifiedIntentsCannotBeArchivedAndFailuresKeepStateFile() async throws {
        let f = try await fixture()
        var state = try f.file.load()
        for revision in 1...81 {
            let event = UUID()
            let body = try WorkoutCapturePayload.make(record: f.record, sets: f.sets, binding: f.binding, installationId: f.config.installationId,
                revision: revision, eventId: event).bytes()
            state.deliveries.append(WorkoutTrackerDelivery(id: event, sourceWorkoutId: f.binding.sourceWorkoutId, installationId: f.config.installationId,
                origin: f.config.origin, revision: revision, bytes: body, record: f.record, sets: f.sets, binding: f.binding,
                status: .accepted, acknowledgement: try receipt(body, fixture: f, reconciliation: "pending")))
        }
        let kept = try f.file.compact(state, protecting: [])
        XCTAssertEqual(kept.deliveries.count, 81)
        XCTAssertTrue(kept.archives.isEmpty)
        try f.file.save(state)
        let before = try Data(contentsOf: f.file.url)
        var completed = state
        let item = completed.deliveries[0]
        completed.deliveries[0].acknowledgement = try receipt(try XCTUnwrap(item.bytes), fixture: f)
        var unverified = completed
        var invalidReceipt = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(completed.deliveries[0].acknowledgement)) as? [String: Any])
        invalidReceipt["mappings"] = ["session": ["kind": "programmed", "cycleId": 4, "sessionId": 999], "sets": [:]]
        unverified.deliveries[0].acknowledgement = try JSONSerialization.data(withJSONObject: invalidReceipt)
        XCTAssertTrue(try f.file.compact(unverified, protecting: []).archives.isEmpty, "Matching event/revision alone does not verify target mappings")
        // A file at the archive-directory path makes archive creation fail without deleting anything.
        try Data("preserve-this-file".utf8).write(to: f.file.archiveDirectory)
        XCTAssertThrowsError(try f.file.compact(completed, protecting: []))
        XCTAssertEqual(try Data(contentsOf: f.file.url), before)
        XCTAssertEqual(try Data(contentsOf: f.file.archiveDirectory), Data("preserve-this-file".utf8))
    }

    func testMetadataBackupRestoresOfflineWithOriginalIdsAndNoCredentialsOrSQLiteWrites() async throws {
        let f = try await fixture()
        var state = try f.file.load(); state.manifests["5"] = f.binding.manifest
        let fetched = Date(timeIntervalSince1970: 1700000000); state.manifestReadAt["5"] = fetched
        state.cachedPlanBlocks["5"] = .inconsistent; try f.file.save(state)
        let source = WorkoutTrackerClient(store: f.file, readCredential: { f.config })
        try await ready(source, fixture: f)
        let original = source.state.deliveries[0]
        try source.keepLocally(deliveryId: original.id)
        let package = try await source.prepareMetadataBackup()
        let bytes = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(f.config.credential))
        let backup = try JSONDecoder().decode(WorkoutTrackerBackupManifest.self, from: bytes)
        XCTAssertFalse(backup.state.enabled)
        let targetFile = WorkoutTrackerFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let restored = WorkoutTrackerClient(store: targetFile, readCredential: { nil })
        try await restored.restoreMetadataBackup(from: package)
        XCTAssertFalse(restored.state.enabled)
        XCTAssertEqual(restored.state.deliveries[0].id, original.id)
        XCTAssertEqual(restored.state.deliveries[0].bytes, original.bytes)
        XCTAssertEqual(restored.state.deliveries[0].binding, original.binding)
        XCTAssertTrue(restored.state.locallyKeptSources.contains(original.sourceWorkoutId))
        XCTAssertEqual(restored.state.manifestReadAt["5"], fetched)
        XCTAssertEqual(restored.state.cachedPlanBlocks["5"], .inconsistent)
        XCTAssertThrowsError(try restored.cachedCaptureBinding(sessionId: 5), "Restoration cannot bypass a known invalid prescription")
        let db = try await WhoopStore.inMemory()
        let rows = try await db.liftSessions(deviceId: "strap", fromTs: 0, toTs: 2000)
        XCTAssertTrue(rows.isEmpty, "Metadata restoration is not a database restore")
    }

    func testBackupConflictDoesNotReplaceLocalStateAndMissingArchivedFilesAreRejected() async throws {
        let f = try await fixture(), source = WorkoutTrackerClient(store: f.file, readCredential: { nil })
        try await ready(source, fixture: f)
        let original = source.state.deliveries[0], package = try await source.prepareMetadataBackup()
        var backup = try JSONDecoder().decode(WorkoutTrackerBackupManifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        var changed = original.record; changed.note = "Conflicting copy"
        backup.state.deliveries[0] = WorkoutTrackerDelivery(id: original.id, sourceWorkoutId: original.sourceWorkoutId,
            installationId: original.installationId, origin: original.origin, revision: original.revision, bytes: original.bytes,
            record: changed, sets: original.sets, binding: original.binding)
        try JSONEncoder().encode(backup).write(to: package.appendingPathComponent("manifest.json"))
        let before = try Data(contentsOf: f.file.url)
        do { try await source.restoreMetadataBackup(from: package); XCTFail("Conflicting events cannot replace current data") }
        catch WorkoutTrackerContractError.backupConflict {}
        XCTAssertEqual(try Data(contentsOf: f.file.url), before)
        XCTAssertEqual(source.state.deliveries[0], original)
        let missing = UUID()
        backup.state = source.state
        backup.state.archives[original.id.uuidString.lowercased()] = WorkoutTrackerArchiveReference(delivery: original, fileId: missing)
        backup = WorkoutTrackerBackupManifest(createdAt: Date(), state: backup.state, archiveFiles: [missing])
        try JSONEncoder().encode(backup).write(to: package.appendingPathComponent("manifest.json"))
        do { try await source.restoreMetadataBackup(from: package); XCTFail("Missing archive files cannot produce a successful restore") }
        catch {}
        XCTAssertEqual(try Data(contentsOf: f.file.url), before)
    }
}
