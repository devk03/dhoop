import XCTest
import WhoopProtocol
import WhoopStore
import GRDB
import StrandAnalytics
@testable import Strand

@MainActor
final class WorkoutReviewTests: XCTestCase {
    private func withPreferences(_ body: () async throws -> Void) async throws {
        let keys = [WorkoutReviewStore.key, "workouts.autoDetectDismissed",
                    WorkoutSource.dismissedDefaultsKey, PuffinExperiment.autoDetectWorkoutsKey]
        let defaults = UserDefaults.standard
        let prior = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in prior {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        try await body()
    }

    func testRejectAcceptRejectAcceptIsDurableAndNeverDuplicatesOrDeletesManualRows() async throws {
        try await withPreferences {
            let device = "review-strap"
            let store = try await WhoopStore.inMemory()
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store)
            let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            try WorkoutReviewStore().capture(review)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            var rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            XCTAssertEqual(rows.count, 1)
            let manual = WorkoutRow(startTs: 1000, endTs: 1900, sport: "Running", source: "manual",
                durationS: 900, energyKcal: nil, avgHr: 132, maxHr: nil, strain: nil,
                distanceM: nil, zonesJSON: nil, notes: "Keep me", steps: nil)
            try await store.upsertWorkouts([manual], deviceId: device)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
            rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            let remaining = try await store.workouts(deviceId: device, from: 0, to: 4000, limit: -1)
            XCTAssertTrue(rows.isEmpty)
            XCTAssertEqual(remaining, [manual])
            let reloaded = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(reloaded.first?.decision, .notWorkout)
            XCTAssertNil(reloaded.first?.linkedWorkout)
            do {
                try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
                XCTFail("Reaccepting a suggestion must not duplicate an overlapping manual session")
            } catch WorkoutReviewError.alreadySaved { }
            catch { XCTFail("Expected overlap protection, got \(error)") }
            // Remove the test's manual overlap explicitly; acceptance can now re-create one linked row.
            try await store.deleteWorkoutRecording(manual, deviceIds: [device])
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            XCTAssertEqual(rows.count, 1)
        }
    }

    func testFailedWriteLeavesPendingAndDoesNotGrantOwnership() async throws {
        try await withPreferences {
            let store = try await WhoopStore.inMemory()
            let repo = Repository(deviceId: "review-strap")
            repo.setStoreForTesting(store)
            let review = WorkoutReview(deviceID: "review-strap", startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            try WorkoutReviewStore().capture(review)
            try await store.registryWriter.write { db in
                try db.execute(sql: """
                    CREATE TEMP TRIGGER reject_review_insert BEFORE INSERT ON workout
                    BEGIN SELECT RAISE(ABORT, 'Test rejected workout insert'); END
                    """)
            }
            do {
                try await repo.setWorkoutReview(review.id, deviceID: "review-strap", decision: .workout)
                XCTFail("Rejected database writes must not report a saved workout")
            } catch { }
            let pending = try XCTUnwrap(WorkoutReviewStore().reviews(deviceID: "review-strap").first)
            XCTAssertEqual(pending.id, review.id)
            XCTAssertEqual(pending.decision, .pending)
            XCTAssertNil(pending.linkedWorkout)
            let rows = try await store.workouts(deviceId: "review-strap-noop", from: 0, to: 4000, limit: -1)
            XCTAssertTrue(rows.isEmpty)
        }
    }

    func testRelabelCannotDeleteManualReplacementOrHideADeletionFailure() async throws {
        try await withPreferences {
            let device = "review-strap"
            let store = try await WhoopStore.inMemory()
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store)
            let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            try WorkoutReviewStore().capture(review)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            try await store.registryWriter.write { db in
                try db.execute(sql: """
                    CREATE TEMP TRIGGER reject_review_delete BEFORE DELETE ON workout
                    BEGIN SELECT RAISE(ABORT, 'Test rejected workout delete'); END
                    """)
            }
            do {
                try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
                XCTFail("A failed deletion must leave the Workout label intact")
            } catch { }
            XCTAssertEqual(try WorkoutReviewStore().reviews(deviceID: device).first?.decision, .workout)
            let manual = WorkoutRow(startTs: 1000, endTs: 1900, sport: "Workout", source: "manual",
                durationS: 900, energyKcal: nil, avgHr: 132, maxHr: nil, strain: nil,
                distanceM: nil, zonesJSON: nil, notes: "Manual replacement", steps: nil)
            try await store.upsertWorkouts([manual], deviceId: device + "-noop")
            do {
                try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
                XCTFail("The same natural key must not confer ownership of a manual replacement")
            } catch WorkoutReviewError.changedRecording { }
            catch { XCTFail("Expected explicit changed-recording protection, got \(error)") }
            let remaining = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            XCTAssertEqual(remaining, [manual])
        }
    }

    func testRemovedRecordingIsReportedAndRequiresExplicitResave() async throws {
        try await withPreferences {
            let device = "review-strap"
            let store = try await WhoopStore.inMemory()
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store)
            let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            try WorkoutReviewStore().capture(review)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            let rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            try await repo.deleteCardioWorkout(XCTUnwrap(rows.first))
            let reviewed = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(reviewed.first?.decision, .workout)
            XCTAssertEqual(reviewed.first?.recordingRemoved, true)
            let absent = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            XCTAssertTrue(absent.isEmpty, "Review reload must not resurrect a deleted workout")
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            let restored = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(restored.first?.recordingRemoved, false)
        }
    }

    func testExactLegacyRejectionCanBeReviewedUsingActiveDeviceHR() async throws {
        try await withPreferences {
            let device = "review-strap"
            let store = try await WhoopStore.inMemory()
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store)
            let start = Int(Date().timeIntervalSince1970) - 7200
            let samples = (0...900).map { HRSample(ts: start + $0, bpm: 140) }
            try await store.insert(Streams(hr: samples), deviceId: device)
            UserDefaults.standard.set(true, forKey: PuffinExperiment.autoDetectWorkoutsKey)
            UserDefaults.standard.set(["\(start):\(start + 900)"], forKey: "workouts.autoDetectDismissed")
            let reviews = try await repo.workoutReviews(discover: true)
            XCTAssertEqual(reviews.count, 1)
            XCTAssertEqual(reviews.first?.decision, .notWorkout)
            try await repo.setWorkoutReview(XCTUnwrap(reviews.first).id, deviceID: device, decision: .workout)
            let rows = try await store.workouts(deviceId: device + "-noop", from: start, to: start + 1000, limit: -1)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "workouts.autoDetectDismissed"), [])
        }
    }
    private func journal() -> WorkoutReviewOperationJournal {
        WorkoutReviewOperationJournal(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("review-crash-test-" + UUID().uuidString))
    }

    private func fixtureRow(device: String, source: String? = nil) -> WorkoutRow {
        WorkoutRow(startTs: 1000, endTs: 1900, sport: "Workout", source: source ?? device + "-noop",
            durationS: 900, energyKcal: nil, avgHr: 130, maxHr: 160, strain: nil,
            distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }

    func testInterruptedAcceptanceRecoversExactOwnershipEvenWhenPreferencesWereNotFlushed() async throws {
        try await withPreferences {
            let device = "crash-strap", store = try await WhoopStore.inMemory(), journal = journal()
            let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            let link = WorkoutReview.Link(owner: device + "-noop", startSec: 1000, endSec: 1900,
                                          sport: "Workout", source: device + "-noop")
            let intent = WorkoutReviewOperation(before: review, decision: .workout, link: link)
            try journal.save(intent)
            // Simulate SQLite committed, then process exit before the preference link was written.
            try await store.upsertWorkouts([fixtureRow(device: device)], deviceId: device + "-noop")
            let rowID = try await store.registryWriter.read { db in
                try XCTUnwrap(Int64.fetchOne(db, sql: "SELECT rowid FROM workout"))
            }
            try await store.setCursor(intent.receiptKey, Int(rowID))
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store, workoutReviewJournal: journal)
            let recovered = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(recovered.count, 1)
            XCTAssertEqual(recovered.first?.decision, .workout)
            XCTAssertEqual(recovered.first?.linkedWorkout?.sqliteRowID, rowID)
            XCTAssertEqual(recovered.first?.id, review.id)
            // The completed journal also survives losing a buffered preference write after recovery.
            UserDefaults.standard.removeObject(forKey: WorkoutReviewStore.key)
            let replayed = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(replayed.first?.decision, .workout)
            XCTAssertEqual(replayed.first?.linkedWorkout?.sqliteRowID, rowID)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
            let rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            XCTAssertTrue(rows.isEmpty, "The recovered link must make rejection remove its saved recording")
        }
    }

    func testUncommittedIntentNeverClaimsPreexistingManualOrDetectedRecording() async throws {
        try await withPreferences {
            for isManual in [true, false] {
                let device = "uncommitted-\(isManual)", store = try await WhoopStore.inMemory(), journal = journal()
                let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                           avgBpm: 130, peakBpm: 160, durationMin: 15)
                let link = WorkoutReview.Link(owner: device + "-noop", startSec: 1000, endSec: 1900,
                                              sport: "Workout", source: device + "-noop")
                let existing = fixtureRow(device: device, source: isManual ? "manual" : device + "-noop")
                try await store.upsertWorkouts([existing], deviceId: device + "-noop")
                try journal.save(WorkoutReviewOperation(before: review, decision: .workout, link: link))
                let repo = Repository(deviceId: device)
                repo.setStoreForTesting(store, workoutReviewJournal: journal)
                let recovered = try await repo.workoutReviews(discover: false)
                XCTAssertEqual(recovered.first?.decision, .pending)
                XCTAssertNil(recovered.first?.linkedWorkout, "An intent without a receipt does not prove ownership")
                try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
                let rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
                XCTAssertEqual(rows, [existing])
            }
        }
    }

    func testInterruptedRejectionRestoresNotWorkoutDecisionAndReceiptsStayBounded() async throws {
        try await withPreferences {
            let device = "reject-crash", store = try await WhoopStore.inMemory(), journal = journal()
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store, workoutReviewJournal: journal)
            let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            try WorkoutReviewStore().capture(review)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .workout)
            let accepted = try XCTUnwrap(WorkoutReviewStore().reviews(deviceID: device).first)
            let intent = WorkoutReviewOperation(before: accepted, decision: .notWorkout, link: accepted.linkedWorkout)
            try journal.save(intent)
            // Simulate the rejection transaction completed but its preference write did not.
            try await store.registryWriter.write { db in
                try db.execute(sql: "DELETE FROM workout")
                try db.execute(sql: "DELETE FROM cursors WHERE name GLOB ?", arguments: [intent.receiptPrefix + "*"])
                try db.execute(sql: "INSERT INTO cursors (name,value) VALUES (?,0)", arguments: [intent.receiptKey])
            }
            let recovered = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(recovered.first?.decision, .notWorkout)
            XCTAssertNil(recovered.first?.linkedWorkout)
            for decision: WorkoutReview.Decision in [.workout, .notWorkout, .workout] {
                try await repo.setWorkoutReview(review.id, deviceID: device, decision: decision)
            }
            let receipts = try await store.registryWriter.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM cursors WHERE name GLOB ?", arguments: [intent.receiptPrefix + "*"])
            }
            XCTAssertEqual(receipts, 1)
            XCTAssertEqual(try journal.operations(deviceID: device).count, 1)
        }
    }

    func testRecoveryRejectsRowWithDifferentIdentityAndConcurrentReadsCannotUndoDecision() async throws {
        try await withPreferences {
            let device = "identity-strap", store = try await WhoopStore.inMemory(), journal = journal()
            let review = WorkoutReview(deviceID: device, startSec: 1000, endSec: 1900,
                                       avgBpm: 130, peakBpm: 160, durationMin: 15)
            let link = WorkoutReview.Link(owner: device + "-noop", startSec: 1000, endSec: 1900,
                                          sport: "Workout", source: device + "-noop")
            let intent = WorkoutReviewOperation(before: review, decision: .workout, link: link)
            try journal.save(intent)
            try await store.upsertWorkouts([fixtureRow(device: device)], deviceId: device + "-noop")
            let rowID = try await store.registryWriter.read { db in try XCTUnwrap(Int64.fetchOne(db, sql: "SELECT rowid FROM workout")) }
            try await store.setCursor(intent.receiptKey, Int(rowID + 100))
            let repo = Repository(deviceId: device)
            repo.setStoreForTesting(store, workoutReviewJournal: journal)
            let recovered = try await repo.workoutReviews(discover: false)
            XCTAssertEqual(recovered.first?.recordingRemoved, true)
            XCTAssertNil(recovered.first?.linkedWorkout)
            async let reload = repo.workoutReviews(discover: false)
            try await repo.setWorkoutReview(review.id, deviceID: device, decision: .notWorkout)
            _ = try await reload
            XCTAssertEqual(try WorkoutReviewStore().reviews(deviceID: device).first?.decision, .notWorkout)
            let rows = try await store.workouts(deviceId: device + "-noop", from: 0, to: 4000, limit: -1)
            XCTAssertEqual(rows, [fixtureRow(device: device)], "A same-span replacement is not the receipted row")
        }
    }

}
