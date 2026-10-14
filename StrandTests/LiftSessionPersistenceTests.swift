import XCTest
@testable import Strand
import WhoopStore

/// The crash-safe snapshot of an in-flight session, and the one question that decides whether an
/// update can be installed OVER the previous build or needs a wipe: **does data written by the
/// previous build still read?**
///
/// The session snapshot is the only thing this feature persists outside SQLite (UserDefaults,
/// `noop.activeLiftSession`), so it is the only place an app-layer change can strand something the
/// old build wrote. A schema change is the other half of that question and is answered by the
/// migration, not here.
final class LiftSessionPersistenceTests: XCTestCase {
    private var existingActiveSession: Any?
    override func setUp() {
        super.setUp()
        existingActiveSession = UserDefaults.standard.object(forKey: LiftSessionPersistence.defaultsKey)
    }
    override func tearDown() {
        if let existingActiveSession { UserDefaults.standard.set(existingActiveSession, forKey: LiftSessionPersistence.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: LiftSessionPersistence.defaultsKey) }
        super.tearDown()
    }

    func testOnlyKnownActiveStrengthSourceIsExcludedFromWorkoutSuggestions() throws {
        var snapshot = try XCTUnwrap(LiftSessionPersistence.decode(snapshotJSONWithoutProgramItemId()))
        XCTAssertNil(LiftSessionPersistence.activeWorkoutSpan(snapshot, deviceID: "strap", now: t0 + 100))
        snapshot.sourceDeviceId = "strap"
        let span = try XCTUnwrap(LiftSessionPersistence.activeWorkoutSpan(snapshot, deviceID: "strap", now: t0 + 100))
        XCTAssertEqual(span.startSec, t0)
        XCTAssertEqual(span.endSec, t0 + 100)
        XCTAssertNil(LiftSessionPersistence.activeWorkoutSpan(snapshot, deviceID: "other", now: t0 + 100))
        XCTAssertNil(LiftSessionPersistence.activeWorkoutSpan(snapshot, deviceID: "strap", now: t0 - 1))
        snapshot.stage.kind = "finished"
        XCTAssertNil(LiftSessionPersistence.activeWorkoutSpan(snapshot, deviceID: "strap", now: t0 + 100))
    }

    @MainActor
    func testWorkoutAndSetIdentitiesSurviveRelaunchAndSaveRetries() throws {
        let original = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        original.start(plan: [LiftPlanItem(exercise: "Bench", targetSets: 2)], programId: nil, programName: nil)
        let slot = LiftSlot(exerciseIndex: 0, setIndex: 1)
        let recording = original.recordingId
        let set = original.identity(for: slot)
        original.setNote("Slow, steady\nKeep form consistent", for: slot)
        XCTAssertEqual(original.identity(for: slot), set)
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load())
        let restored = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        restored.resume(from: snapshot)
        XCTAssertEqual(restored.recordingId, recording)
        XCTAssertEqual(restored.identity(for: slot), set)
        XCTAssertEqual(restored.note(for: slot), "Slow, steady\nKeep form consistent")
        restored.setNote("", for: slot)
        XCTAssertNil(restored.note(for: slot))
        XCTAssertNotEqual(restored.identity(for: LiftSlot(exerciseIndex: 0, setIndex: 2)), set)
        original.discard(); restored.discard()
    }

    @MainActor
    func testAddedBodyweightExerciseKeepsIdentityAndNotesWithoutCarryingOldMass() throws {
        let planned = WorkoutTrackerManifest.PlannedSet(lifeSetId: 1, setNumber: 1, setType: "work", plannedLoad: 60, plannedReps: 8,
            loadOverride: false, repsOverride: false, actualLoad: nil, actualReps: nil, rir: nil, completed: false)
        let occurrence = WorkoutTrackerManifest.Occurrence(sessionExerciseId: 2, programSlotId: 3, slotKey: "push", exerciseKey: "bench", originalExerciseKey: "bench", name: "Bench", order: 0,
            measurementKind: "mass_reps", loadMode: .barbell, loadBasis: "total", unit: "kg", targetRir: nil, restTargetSeconds: nil, sets: [planned])
        let manifest = WorkoutTrackerManifest(schemaVersion: 1, cycleId: 4, sessionId: 5, sessionKey: "upper_a", title: "Upper A", scheduledDate: nil, status: "planned", manifestRevision: "hash", lifeRevision: 0,
            exerciseOccurrences: [occurrence], sourceWorkoutId: nil)
        let binding = try WorkoutTrackerCaptureBinding(manifest: manifest)
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        XCTAssertTrue(controller.start(plan: [LiftPlanItem(exercise: "Bench", targetSets: 1)], programId: nil, programName: nil, trackerBinding: binding))
        XCTAssertTrue(controller.addExercise("Pull-up", primaryMuscle: nil, secondaryMuscles: [], sourceExerciseId: UUID(), loadMode: .bodyweight))
        let slot = LiftSlot(exerciseIndex: 1, setIndex: 1), id = controller.identity(for: LiftSlot(exerciseIndex: 1, setIndex: 1))
        controller.setNote("Full range, no added weight", for: slot)
        controller.setLastSession(["Pull-up": [1: LiftSetCarry(weightKg: 25, reps: 8)]])
        XCTAssertNil(controller.carry(for: slot).weightKg, "A no-load exercise cannot inherit a previous added load")
        let originalBinding = controller.trackerBinding
        XCTAssertTrue(controller.moveExercise(1, by: -1))
        XCTAssertEqual(controller.trackerBinding, originalBinding, "Moving a card cannot move its prescribed or additional source IDs")
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load())
        let restored = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        restored.resume(from: snapshot)
        XCTAssertEqual(restored.identity(for: slot), id)
        XCTAssertEqual(restored.note(for: slot), "Full range, no added weight")
        XCTAssertEqual(restored.trackerLoadMode(exerciseIndex: 1), .bodyweight)
        XCTAssertEqual(restored.engine?.exerciseOrder, [1, 0])
        XCTAssertEqual(restored.trackerBinding, originalBinding)
        controller.undo() // Undo the card move before undoing the added exercise.
        controller.undo()
        XCTAssertNil(controller.note(for: slot), "Undoing the added exercise removes its detached note intent")
        XCTAssertTrue(controller.addExercise("Row", primaryMuscle: nil, secondaryMuscles: [], sourceExerciseId: UUID(), loadMode: .machine))
        XCTAssertNotEqual(controller.identity(for: slot), id)
        XCTAssertEqual(controller.trackerBinding?.additionalOccurrences?.first?.name, "Row")
        controller.discard(); restored.discard()
    }

    private let t0 = 1_700_000_000

    /// A snapshot exactly as the PREVIOUS build wrote it: no `programItemId`, because the field did
    /// not exist until the set count could be changed mid-session.
    ///
    /// Written as literal JSON on purpose. Encoding it with today's `Snapshot` would only prove that
    /// today's build can read itself — the whole point is to read bytes the old build produced.
    private func snapshotJSONWithoutProgramItemId() -> Data {
        Data("""
        {
          "startSec": \(t0),
          "programId": "p1",
          "programName": "Upper A",
          "plan": [
            {"exercise": "Bench press", "secondaryMuscles": ["triceps"], "primaryMuscle": "chest",
             "targetSets": 3, "restSec": 90, "targetRepsLow": 8, "targetWeightKg": 60}
          ],
          "stage": {"kind": "resting", "item": 0, "set": 1, "endsAt": \(t0 + 130)},
          "sets": [
            {"exerciseIndex": 0, "setIndex": 1, "weightKg": 60, "reps": 8, "isWarmup": false,
             "startTs": \(t0 + 10), "endTs": \(t0 + 40)}
          ],
          "stageStartedAt": \(t0 + 40)
        }
        """.utf8)
    }

    /// iOS closes NOOP in the background and relaunches it — four times in one gym session (21 Sep 2026).
    /// The session is picked up as the process starts, before any screen, and says so in the strap log.
    @MainActor
    func testASessionIsPickedUpAgainWhenNOOPStartsAndSaysSo() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LiftSessionPersistenceTests.resume"))
        defer { defaults.removePersistentDomain(forName: "LiftSessionPersistenceTests.resume") }
        var lines: [String] = []
        var claimed = false
        func controller() -> LiftSessionController {
            LiftSessionController(buzz: { _ in }, setStrapHandler: { claimed = $0 != nil },
                                  log: { lines.append($0) })
        }

        controller().resumeSaved(from: defaults)
        XCTAssertTrue(lines.isEmpty, "nothing saved, nothing picked up")

        let snapshot = try XCTUnwrap(LiftSessionPersistence.decode(snapshotJSONWithoutProgramItemId()))
        LiftSessionPersistence.store(snapshot, into: defaults)
        let c = controller()
        c.resumeSaved(from: defaults)
        XCTAssertTrue(c.isActive)
        XCTAssertFalse(c.isPresented, "it comes back as the bar, not as a sheet")
        XCTAssertTrue(claimed, "the strap's double-tap is the session's again")
        XCTAssertEqual(lines, ["Lift Log: session picked up again after Dhoop restarted"])

        c.resumeSaved(from: defaults)
        XCTAssertEqual(lines.count, 1, "a running session is not picked up twice")
    }

    /// A session started on the previous build and still running when the update is installed must
    /// come back whole. It is the reason today's change can go on as a plain update rather than a wipe.
    func testASessionWrittenByThePreviousBuildStillResumes() throws {
        let decoded = try XCTUnwrap(LiftSessionPersistence.decode(snapshotJSONWithoutProgramItemId()),
                                    "a snapshot from the previous build must not read as 'no session'")
        let engine = LiftSessionPersistence.engine(from: decoded)

        XCTAssertEqual(engine.startTs, t0)
        XCTAssertEqual(engine.plan.count, 1)
        XCTAssertEqual(engine.plan[0].exercise, "Bench press")
        XCTAssertEqual(engine.plan[0].targetSets, 3)
        XCTAssertEqual(engine.plan[0].primaryMuscle, .chest)
        XCTAssertEqual(engine.stage, .resting(LiftSlot(exerciseIndex: 0, setIndex: 1),
                                              endsAt: t0 + 130))
        XCTAssertEqual(engine.sets.count, 1, "the set already logged survives the update")
        XCTAssertEqual(engine.sets[0].weightKg, 60)
    }

    /// The new field is simply absent, not garbage — so the write-back is skipped for that session
    /// rather than aimed at a program line that was never identified.
    func testAResumedOldSessionCarriesNoProgramLineAndIsStillFullyUsable() throws {
        let decoded = try XCTUnwrap(LiftSessionPersistence.decode(snapshotJSONWithoutProgramItemId()))
        var engine = LiftSessionPersistence.engine(from: decoded)
        XCTAssertNil(engine.plan[0].programItemId)

        // And the set count can still be changed — the session works, the program just is not rewritten.
        XCTAssertTrue(engine.addSet(toExercise: 0))
        XCTAssertEqual(engine.plan[0].targetSets, 4)
    }

    /// Numbers typed for a set that has not happened yet must survive a crash. Losing them to a
    /// relaunch would be the same bug as losing them to a blur, with extra steps.
    func testNumbersTypedForASetNotYetPerformedSurviveARelaunch() throws {
        let plan = [LiftPlanItem(exercise: "Row", targetSets: 3, restSec: 60)]
        let engine = LiftSessionEngine(plan: plan, startTs: t0)
        let slot = LiftSlot(exerciseIndex: 0, setIndex: 3)
        let typed = LiftSessionController.PendingSetValues(weightKg: 72.5, reps: 6, rpe: nil)

        let encoded = try XCTUnwrap(LiftSessionPersistence.encode(
            LiftSessionPersistence.snapshot(engine: engine, programId: nil, programName: nil,
                                            pendingValues: [slot: typed],
                                            pendingWarmups: [LiftSlot(exerciseIndex: 0, setIndex: 1)])))
        let back = try XCTUnwrap(LiftSessionPersistence.decode(encoded))

        XCTAssertEqual(LiftSessionPersistence.pendingValues(from: back), [slot: typed])
        XCTAssertEqual(LiftSessionPersistence.pendingWarmups(from: back),
                       [LiftSlot(exerciseIndex: 0, setIndex: 1)])
    }

    /// A snapshot written before any of this existed carries neither, and must resume with nothing
    /// pending rather than failing to read at all.
    func testAnOldSnapshotResumesWithNothingPending() throws {
        let decoded = try XCTUnwrap(LiftSessionPersistence.decode(snapshotJSONWithoutProgramItemId()))
        XCTAssertTrue(LiftSessionPersistence.pendingValues(from: decoded).isEmpty)
        XCTAssertTrue(LiftSessionPersistence.pendingWarmups(from: decoded).isEmpty)
    }

    /// The round trip today's build performs on itself, including the new field.
    func testTodaysSnapshotRoundTripsWithTheProgramLine() throws {
        let plan = [LiftPlanItem(exercise: "Lat pulldown", primaryMuscle: .lats,
                                 targetSets: 2, restSec: 60, programItemId: "line-7")]
        var engine = LiftSessionEngine(plan: plan, startTs: t0)
        engine.advance(now: t0)
        engine.advance(now: t0 + 30)
        engine.addSet(toExercise: 0)

        let encoded = try XCTUnwrap(LiftSessionPersistence.encode(
            LiftSessionPersistence.snapshot(engine: engine, programId: "p1", programName: "Pull",
                                            pendingValues: [:], pendingWarmups: [])))
        let back = try XCTUnwrap(LiftSessionPersistence.decode(encoded))
        let rebuilt = LiftSessionPersistence.engine(from: back)

        XCTAssertEqual(rebuilt.plan[0].programItemId, "line-7",
                       "without this the added set could not be written back after a relaunch")
        XCTAssertEqual(rebuilt.plan[0].targetSets, 3, "the added set survives a crash")
        XCTAssertEqual(rebuilt.sets.count, 1)
    }
}
