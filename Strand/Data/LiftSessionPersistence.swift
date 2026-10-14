import Foundation
import WhoopStore
import StrandAnalytics

// Crash-safety for an in-flight gym session.
//
// A session is written to UserDefaults on every tap and rehydrated on launch, so a crash, a phone
// call, a flat battery or simply swiping the app away mid-workout costs nothing. This mirrors
// `ActiveWorkoutPersistence` exactly — a small `Codable` snapshot, unix-second anchors, and an
// encode/decode pair that is pure (no UserDefaults dependency of its own) so the round-trip is
// testable without touching the defaults database.
//
// Unix seconds rather than `Date` for the same reason the store uses them: an absolute instant
// survives suspension, timezone changes and a relaunch, and it is the only anchor that keeps a rest
// countdown honest.

enum LiftSessionPersistence {

    /// The durable shape of an in-flight session — the minimum needed to rebuild the engine and still
    /// finish and save the session after a relaunch.
    struct Snapshot: Codable, Equatable {
        var startSec: Int
        var programId: String?
        var programName: String?
        /// The plan, flattened at start. Stored rather than re-read from the program so that editing
        /// or deleting the program mid-session cannot change what is being run.
        var plan: [PlanItem]
        var stage: StageBox
        var sets: [RecordedSet]
        var stageStartedAt: Int
        /// Numbers typed into sets that have NOT happened yet, and slots marked a warm-up in
        /// advance. Both are intent the user has already expressed, so a crash must not cost them —
        /// that is the whole point of this snapshot.
        ///
        /// Optional because a snapshot written before these existed does not carry them: it decodes
        /// as absent and the session resumes with nothing pending, which is exactly right.
        var pendingValues: [PendingValue]?
        var pendingWarmups: [SlotBox]?
        /// Optional for legacy snapshots; old sessions retain an explicitly unknown capture source.
        var sourceDeviceId: String? = nil
        var recordingId: String? = nil
        var trackerBinding: WorkoutTrackerCaptureBinding? = nil
        var setIdentities: [SetIdentity]? = nil
        var setNotes: [SetNote]? = nil
        var exerciseOrder: [Int]? = nil
        var exerciseReplacements: [Int: Int]? = nil

        struct SetNote: Codable, Equatable {
            let exerciseIndex: Int
            let setIndex: Int
            let text: String
        }

        struct SetIdentity: Codable, Equatable {
            var exerciseIndex: Int
            var setIndex: Int
            var id: String
        }

        struct PendingValue: Codable, Equatable {
            var exerciseIndex: Int
            var setIndex: Int
            var weightKg: Double?
            var reps: Int?
            var rpe: Double?
        }

        struct SlotBox: Codable, Equatable {
            var exerciseIndex: Int
            var setIndex: Int
        }

        struct PlanItem: Codable, Equatable {
            var exercise: String
            var primaryMuscle: String?
            var secondaryMuscles: [String]
            var targetSets: Int
            var restSec: Int
            var targetRepsLow: Int?
            var targetRepsHigh: Int?
            var targetRpe: Double?
            var targetWeightKg: Double?
            var note: String?
            /// The program line this was flattened from. Absent from a snapshot written before the
            /// set count could be changed mid-session, which decodes to nil and simply skips the
            /// write-back — the session itself is unaffected.
            var programItemId: String?
            /// True for a line added during the session. Absent from a snapshot written before lines
            /// could be added, which decodes to nil: a line from the program.
            var addedInSession: Bool?
            var sourceLoadMode: WorkoutTrackerLoadMode? = nil
        }

        /// The stage as a flat, forward-compatible record rather than an encoded enum: a persisted
        /// enum with associated values is a migration hazard the moment a case is added, and this
        /// shape decodes to "warm-up" rather than to garbage if it is ever read by an older build.
        struct StageBox: Codable, Equatable {
            var kind: String        // warmup | working | resting | cooldown | finished
            var item: Int?
            var set: Int?
            var endsAt: Int?
        }

        struct RecordedSet: Codable, Equatable {
            var exerciseIndex: Int
            var setIndex: Int
            var weightKg: Double?
            var reps: Int?
            var rpe: Double?
            var isWarmup: Bool
            var startTs: Int
            var endTs: Int
            var restSec: Int?
        }
    }

    /// The single UserDefaults key (JSON-encoded `Snapshot`), namespaced like `noop.activeWorkout`.
    static let defaultsKey = "noop.activeLiftSession"

    // MARK: - Codec

    static func encode(_ snapshot: Snapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    /// Decode a snapshot, bound-checking the untrusted persisted values. Returns nil for
    /// nil/garbage/empty input or an implausible start time, so a corrupt write is treated as "no
    /// session in flight" rather than reviving a broken screen the user cannot get out of.
    static func decode(_ data: Data?) -> Snapshot? {
        guard let data, !data.isEmpty,
              let raw = try? JSONDecoder().decode(Snapshot.self, from: data),
              raw.startSec > 1_000_000_000,                       // after 2001; not a zero/garbage anchor
              raw.startSec < Int(Date().timeIntervalSince1970) + 86_400,
              !raw.plan.isEmpty
        else { return nil }
        if let id = raw.recordingId, UUID(uuidString: id) == nil { return nil }
        if let binding = raw.trackerBinding {
            guard (try? binding.validate()) != nil,
                  raw.recordingId.flatMap(UUID.init(uuidString:)) == binding.sourceWorkoutId else { return nil }
        }
        if let identities = raw.setIdentities {
            guard identities.count <= 1000, identities.allSatisfy({ $0.exerciseIndex >= 0 && $0.setIndex > 0 && UUID(uuidString: $0.id) != nil }),
                  Set(identities.map(\.id)).count == identities.count else { return nil }
        }
        if let order = raw.exerciseOrder, order.count != raw.plan.count || Set(order) != Set(raw.plan.indices) { return nil }
        if let replacements = raw.exerciseReplacements {
            guard Set(replacements.values).count == replacements.count,
                  replacements.allSatisfy({ raw.plan.indices.contains($0.key) && raw.plan.indices.contains($0.value) && $0.value > $0.key }) else { return nil }
            if raw.stage.kind == "working", let index = raw.stage.item, replacements[index] != nil { return nil }
        }
        return raw
    }

    // MARK: - UserDefaults

    @discardableResult
    static func store(_ snapshot: Snapshot?, into d: UserDefaults = .standard) -> Bool {
        guard let snapshot else {
            d.removeObject(forKey: defaultsKey)
            return true
        }
        guard let data = encode(snapshot) else { return false }
        d.set(data, forKey: defaultsKey)
        return true
    }

    static func load(from d: UserDefaults = .standard) -> Snapshot? {
        decode(d.data(forKey: defaultsKey))
    }

    /// Exclude a known active capture from suggestions, without attributing legacy data to a strap.
    static func activeWorkoutSpan(_ snapshot: Snapshot?, deviceID: String, now: Int) -> SavedWorkoutSpan? {
        guard let snapshot, snapshot.sourceDeviceId == deviceID, snapshot.stage.kind != "finished",
              snapshot.startSec > 0, now > snapshot.startSec else { return nil }
        return SavedWorkoutSpan(startSec: snapshot.startSec, endSec: now)
    }

    static func clear(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: defaultsKey)
    }

    // MARK: - Engine bridge

    static func snapshot(engine: LiftSessionEngine,
                         programId: String?,
                         programName: String?,
                         pendingValues: [LiftSlot: LiftSessionController.PendingSetValues],
                         pendingWarmups: Set<LiftSlot>, sourceDeviceId: String? = nil,
                         recordingId: String? = nil, trackerBinding: WorkoutTrackerCaptureBinding? = nil,
                         setNotes: [Snapshot.SetNote]? = nil,
                         setIdentities: [Snapshot.SetIdentity]? = nil) -> Snapshot {
        Snapshot(
            startSec: engine.startTs,
            programId: programId,
            programName: programName,
            plan: engine.plan.map {
                Snapshot.PlanItem(exercise: $0.exercise,
                                  primaryMuscle: $0.primaryMuscle?.rawValue,
                                  secondaryMuscles: $0.secondaryMuscles.map(\.rawValue),
                                  targetSets: $0.targetSets,
                                  restSec: $0.restSec,
                                  targetRepsLow: $0.targetRepsLow,
                                  targetRepsHigh: $0.targetRepsHigh,
                                  targetRpe: $0.targetRpe,
                                  targetWeightKg: $0.targetWeightKg,
                                  note: $0.note,
                                  programItemId: $0.programItemId,
                                  // Written only when true, so a session nobody added to encodes as before.
                                  addedInSession: $0.addedInSession ? true : nil, sourceLoadMode: $0.sourceLoadMode)
            },
            stage: box(engine.stage),
            sets: engine.sets.map {
                Snapshot.RecordedSet(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex,
                                     weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe,
                                     isWarmup: $0.isWarmup, startTs: $0.startTs, endTs: $0.endTs,
                                     restSec: $0.restSec)
            },
            stageStartedAt: engine.stageStartedAt,
            // Sorted so the encoded snapshot is stable: a dictionary and a set have no order, and an
            // unstable encoding would rewrite the defaults blob on every tick for no reason.
            pendingValues: pendingValues
                .sorted { ($0.key.exerciseIndex, $0.key.setIndex) < ($1.key.exerciseIndex, $1.key.setIndex) }
                .map { slot, values in
                    Snapshot.PendingValue(exerciseIndex: slot.exerciseIndex, setIndex: slot.setIndex,
                                          weightKg: values.weightKg, reps: values.reps, rpe: values.rpe)
                },
            pendingWarmups: pendingWarmups
                .sorted { ($0.exerciseIndex, $0.setIndex) < ($1.exerciseIndex, $1.setIndex) }
                .map { Snapshot.SlotBox(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex) },
            sourceDeviceId: sourceDeviceId, recordingId: recordingId, trackerBinding: trackerBinding,
            setIdentities: setIdentities?.sorted { ($0.exerciseIndex, $0.setIndex) < ($1.exerciseIndex, $1.setIndex) },
            setNotes: setNotes?.sorted { ($0.exerciseIndex, $0.setIndex) < ($1.exerciseIndex, $1.setIndex) },
            exerciseOrder: engine.exerciseOrder, exerciseReplacements: engine.exerciseReplacements)
    }

    /// The numbers typed in advance, back as the controller holds them.
    static func pendingValues(from s: Snapshot) -> [LiftSlot: LiftSessionController.PendingSetValues] {
        var out: [LiftSlot: LiftSessionController.PendingSetValues] = [:]
        for p in s.pendingValues ?? [] {
            out[LiftSlot(exerciseIndex: p.exerciseIndex, setIndex: p.setIndex)] =
                LiftSessionController.PendingSetValues(weightKg: p.weightKg, reps: p.reps, rpe: p.rpe)
        }
        return out
    }

    /// The warm-up marks made in advance, back as the controller holds them.
    static func pendingWarmups(from s: Snapshot) -> Set<LiftSlot> {
        Set((s.pendingWarmups ?? []).map { LiftSlot(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex) })
    }

    /// Rebuild an engine from a snapshot. Unknown muscle tokens are dropped rather than failing the
    /// read, matching `LiftMuscle.decodeList`: a snapshot written by a newer build must not strand a
    /// session in an older one.
    static func engine(from s: Snapshot) -> LiftSessionEngine {
        let plan = s.plan.map {
            LiftPlanItem(exercise: $0.exercise,
                         primaryMuscle: $0.primaryMuscle.flatMap(LiftMuscle.init(rawValue:)),
                         secondaryMuscles: $0.secondaryMuscles.compactMap(LiftMuscle.init(rawValue:)),
                         targetSets: $0.targetSets,
                         restSec: $0.restSec,
                         targetRepsLow: $0.targetRepsLow,
                         targetRepsHigh: $0.targetRepsHigh,
                         targetRpe: $0.targetRpe,
                         targetWeightKg: $0.targetWeightKg,
                         note: $0.note,
                         programItemId: $0.programItemId,
                         addedInSession: $0.addedInSession ?? false, sourceLoadMode: $0.sourceLoadMode)
        }
        let sets = s.sets.map {
            LiftRecordedSet(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex,
                            weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe,
                            isWarmup: $0.isWarmup, startTs: $0.startTs, endTs: $0.endTs,
                            restSec: $0.restSec)
        }
        return LiftSessionEngine(restoring: plan, startTs: s.startSec,
                                 stage: unbox(s.stage), sets: sets, stageStartedAt: s.stageStartedAt, exerciseOrder: s.exerciseOrder,
                                 exerciseReplacements: s.exerciseReplacements ?? [:])
    }

    private static func box(_ stage: LiftSessionEngine.Stage) -> Snapshot.StageBox {
        switch stage {
        case .warmup:
            return .init(kind: "warmup", item: nil, set: nil, endsAt: nil)
        case .working(let slot):
            return .init(kind: "working", item: slot.exerciseIndex, set: slot.setIndex, endsAt: nil)
        case .resting(let slot, let endsAt):
            return .init(kind: "resting", item: slot.exerciseIndex, set: slot.setIndex, endsAt: endsAt)
        case .finished:
            return .init(kind: "finished", item: nil, set: nil, endsAt: nil)
        }
    }

    /// Anything unrecognised — a `working`/`resting` box missing its indices, or the retired
    /// "cooldown" kind written by an earlier build — falls back to the warm-up.
    ///
    /// That is a real recovery, not a shrug: every COMPLETED set is carried in `sets` regardless, so
    /// nothing logged is lost. Only the cursor's position is forgotten, and the next tap simply
    /// resumes at the first set still outstanding.
    private static func unbox(_ box: Snapshot.StageBox) -> LiftSessionEngine.Stage {
        switch box.kind {
        case "working":
            guard let i = box.item, let s = box.set else { return .warmup }
            return .working(LiftSlot(exerciseIndex: i, setIndex: s))
        case "resting":
            guard let i = box.item, let s = box.set, let e = box.endsAt else { return .warmup }
            return .resting(LiftSlot(exerciseIndex: i, setIndex: s), endsAt: e)
        case "finished":
            return .finished
        default:
            return .warmup
        }
    }
}
