import Foundation
import WhoopStore

// The session state machine: the heart of the Lift Log.
//
// A GYM IS NOT A QUEUE. The first version walked the plan strictly in order, one set at a time, and
// the first real session killed that: when a machine is occupied you move on and come back. So the
// plan is a SHEET of slots — every set of every exercise, all visible — and any pending slot can be
// started at any time. Order is a suggestion the session follows by default, not a rail.
//
// PURE (no timers, no store, no SwiftUI): it is the piece most likely to be wrong in a way that
// costs someone a logged set, and the only part testable with no strap, no database, no simulator.
//
// TIME ENTERS ONLY AS A PARAMETER, so a test can drive a whole session through a known timeline.
// Rest is an ABSOLUTE end instant, never a decrementing counter — a phone that sleeps through a rest
// must wake up telling the truth.
//
// THERE IS NO COOL-DOWN STAGE. Warm-up is the time before the first set and cool-down the time after
// the last; both fall out of the timestamps, so neither needs a stage of its own. The session ends
// when the user says it does.

/// One set of one exercise — a position on the sheet. `setIndex` is 1-based within its exercise.
struct LiftSlot: Hashable, Codable {
    var exerciseIndex: Int
    var setIndex: Int
}

/// One planned exercise line, flattened from a program for the session to run.
struct LiftPlanItem: Equatable {
    var exercise: String
    var primaryMuscle: LiftMuscle?
    var secondaryMuscles: [LiftMuscle]
    /// Planned working sets. Always >= 1 — a line scheduling zero sets could not be tapped through.
    var targetSets: Int
    /// Intended rest after each set, in seconds.
    var restSec: Int
    var targetRepsLow: Int?
    var targetRepsHigh: Int?
    var targetRpe: Double?
    /// The weight the program plans, in kilograms.
    var targetWeightKg: Double?
    var note: String?
    /// The `liftProgramItem.id` this line was flattened from, so a set count changed during the session
    /// can be offered back to the program when it is finished. Nil for a line with no program behind
    /// it, which is then never offered. A line added during the session carries the id its program
    /// line will have if finishing adds it (`addedInSession`).
    var programItemId: String?
    /// Added while the session ran (`LiftSessionEngine.addExercise`), so the program has no line for it
    /// yet; finishing offers to add one.
    var addedInSession: Bool
    var sourceLoadMode: WorkoutTrackerLoadMode?
    var supersetGroupId: String?

    /// Rest used when a program line does not specify one. Two minutes sits in the middle of the
    /// range the hypertrophy literature uses for compound work, and is only a starting value: what
    /// is actually rested is measured from the taps.
    static let defaultRestSec = 120

    init(exercise: String,
         primaryMuscle: LiftMuscle? = nil,
         secondaryMuscles: [LiftMuscle] = [],
         targetSets: Int? = nil,
         restSec: Int? = nil,
         targetRepsLow: Int? = nil,
         targetRepsHigh: Int? = nil,
         targetRpe: Double? = nil,
         targetWeightKg: Double? = nil,
         note: String? = nil,
         programItemId: String? = nil,
         addedInSession: Bool = false, sourceLoadMode: WorkoutTrackerLoadMode? = nil, supersetGroupId: String? = nil) {
        self.exercise = exercise
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.targetSets = max(1, targetSets ?? 1)
        self.restSec = max(0, restSec ?? LiftPlanItem.defaultRestSec)
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.targetRpe = targetRpe
        self.targetWeightKg = targetWeightKg
        self.note = note
        self.programItemId = programItemId
        self.addedInSession = addedInSession
        self.sourceLoadMode = sourceLoadMode
        self.supersetGroupId = supersetGroupId
    }
}

/// One set as actually performed.
struct LiftRecordedSet: Equatable {
    var exerciseIndex: Int
    var setIndex: Int
    var weightKg: Double?
    var reps: Int?
    var rpe: Double?
    var isWarmup: Bool
    var startTs: Int
    var endTs: Int
    /// Rest actually taken after this set. Nil while the rest is still running, or when the user
    /// moved on without resting.
    var restSec: Int?

    var supersetGroupId: String? = nil
    var roundIndex: Int? = nil

    var slot: LiftSlot { LiftSlot(exerciseIndex: exerciseIndex, setIndex: setIndex) }
}

/// The numbers a set shows in grey: what it would save if completed without anything typed.
///
/// Only weight and reps. RPE is deliberately absent — see `carry(for:lastSession:)`.
struct LiftSetCarry: Equatable {
    var weightKg: Double?
    var reps: Int?

    static let none = LiftSetCarry(weightKg: nil, reps: nil)
}

/// One observed phase. Slot references are resolved to stable set IDs only at the storage boundary.
struct LiftObservedPhase: Equatable, Codable {
    var id: UUID
    var kind: LiftActivityInterval.Kind
    var slot: LiftSlot?
    var startedAt: Int
    var endedAt: Int?
}

struct LiftSessionPause: Equatable, Codable {
    var remainingRest: Int?
    var recovered: Bool
}

struct LiftSessionEngine: Equatable {

    enum Stage: Equatable {
        /// Before the first set — the warm-up.
        case warmup
        /// Performing a set.
        case working(LiftSlot)
        /// Resting after a set. `endsAt` is an absolute unix second.
        case resting(LiftSlot, endsAt: Int)
        /// Ended; ready to save.
        case finished
    }

    /// The lines being worked. MUTABLE in two ways only, both because a gym decides them as it goes:
    /// how many sets a line holds — a fifth set on a line that planned four, or dropping the last one
    /// when the tank is empty — and a line added at the end for an exercise the program does not have.
    /// Nothing about a line already there changes mid-session, so the plan stays the snapshot it was at
    /// start, plus whatever was added.
    private(set) var plan: [LiftPlanItem]
    /// Presentation and suggestion order. Slot indices stay fixed so moving a card never relabels data.
    private(set) var exerciseOrder: [Int]
    /// Original indices remain present as history; only their unfinished slots are replaced.
    private(set) var exerciseReplacements: [Int: Int]
    /// When the session began (unix seconds).
    let startTs: Int
    private(set) var stage: Stage
    /// Completed sets in COMPLETION order — which is the order they happened, not the plan's order,
    /// and is what `ord` is written from.
    private(set) var sets: [LiftRecordedSet]
    /// When the current stage began, so a set's duration is measurable.
    private(set) var stageStartedAt: Int
    private(set) var activityPhases: [LiftObservedPhase]? = []
    private(set) var pauseState: LiftSessionPause?
    private var openPhaseID: UUID?
    var isPaused: Bool { pauseState != nil }
    var phaseCapacityReached: Bool { (activityPhases?.count ?? 0) >= LiftActivityLedger.maximumIntervals }

    /// Stop observed work/rest without pretending that a suspended app continued executing.
    mutating func pause(now: Int) {
        guard !isPaused, !isFinished, !phaseCapacityReached, validTime(now) else { return }
        let remainder = restRemaining(now: now)
        closePhase(now: now)
        pauseState = .init(remainingRest: remainder, recovered: false)
        let pausedSlot: LiftSlot? = { if case .working(let slot) = stage { return slot }; return nil }()
        beginPhase(.pause, slot: pausedSlot, now: now)
    }

    mutating func resume(now: Int) {
        guard let paused = pauseState, !isFinished, !phaseCapacityReached, validTime(now) else { return }
        closePhase(now: now)
        pauseState = nil
        switch stage {
        case .working(let slot): beginPhase(.work, slot: slot, now: now)
        case .resting(let slot, _):
            stage = .resting(slot, endsAt: now + (paused.remainingRest ?? 0))
            beginPhase(.rest, slot: slot, now: now)
        case .warmup, .finished: break
        }
    }

    /// A crash leaves the prior phase unresolved. No new end is inferred from relaunch time.
    mutating func markRecovered(now: Int) {
        guard !isFinished else { return }
        openPhaseID = nil
        if pauseState == nil {
            let remainder: Int? = { if case .resting(_, let end) = stage { return max(0, end - stageStartedAt) }; return nil }()
            pauseState = .init(remainingRest: remainder, recovered: true)
        } else { pauseState?.recovered = true }
    }

    private func validTime(_ now: Int) -> Bool {
        now >= startTs && now >= (activityPhases?.last?.startedAt ?? stageStartedAt)
    }

    private mutating func beginPhase(_ kind: LiftActivityInterval.Kind, slot: LiftSlot?, now: Int) {
        if activityPhases == nil { activityPhases = [] }
        let id = UUID()
        activityPhases?.append(.init(id: id, kind: kind, slot: slot, startedAt: now, endedAt: nil))
        openPhaseID = id
    }

    private mutating func closePhase(now: Int) {
        if let id = openPhaseID, let index = activityPhases?.firstIndex(where: { $0.id == id }) {
            activityPhases?[index].endedAt = now
        }
        openPhaseID = nil
    }

    func observedWorkSeconds(for slot: LiftSlot?, now: Int) -> Int {
        guard let slot else { return 0 }
        return (activityPhases ?? []).filter { $0.kind == .work && $0.slot == slot }.reduce(0) { total, phase in
            let end = phase.endedAt ?? (phase.id == openPhaseID ? now : phase.startedAt)
            return total + max(0, end - phase.startedAt)
        }
    }

    private func observedRest(for slot: LiftSlot, fallback: Int) -> Int? {
        guard let phases = activityPhases else { return fallback }
        let rest = phases.filter { $0.kind == .rest && $0.slot == slot }
        guard !rest.isEmpty, rest.allSatisfy({ $0.endedAt != nil }) else { return nil }
        return rest.reduce(0) { $0 + max(0, ($1.endedAt ?? $1.startedAt) - $1.startedAt) }
    }

    /// Undo stack: whole-state snapshots rather than inverse operations. A gym is a bad place to be
    /// one tap ahead of yourself, and restoring a snapshot cannot get the arithmetic wrong the way a
    /// hand-written inverse can.
    private var history: [Snapshot] = []

    /// The plan travels in the snapshot with the stage and the sets, and is restored with them.
    ///
    /// It has to. Once the set count can move, a stage saved under one count is only meaningful
    /// under that count: undoing back past a removed set would otherwise leave the session working
    /// a slot the sheet no longer draws — and completing it would write a set nobody could see.
    private struct Snapshot: Equatable {
        var plan: [LiftPlanItem]
        var exerciseOrder: [Int]
        var exerciseReplacements: [Int: Int]
        var stage: Stage
        var sets: [LiftRecordedSet]
        var stageStartedAt: Int
        var activityPhases: [LiftObservedPhase]?
        var pauseState: LiftSessionPause?
        var openPhaseID: UUID?
    }

    init(plan: [LiftPlanItem], startTs: Int) {
        self.plan = plan
        self.exerciseOrder = Array(plan.indices)
        self.exerciseReplacements = [:]
        self.startTs = startTs
        self.stage = .warmup
        self.sets = []
        self.stageStartedAt = startTs
    }

    /// Rebuild an interrupted session — see `LiftSessionPersistence`.
    ///
    /// The undo history is deliberately NOT restored: it is a within-sitting convenience, and a
    /// stack that survives a relaunch invites reaching back past a save boundary.
    init(restoring plan: [LiftPlanItem], startTs: Int, stage: Stage,
         sets: [LiftRecordedSet], stageStartedAt: Int, exerciseOrder: [Int]? = nil, exerciseReplacements: [Int: Int] = [:], activityPhases: [LiftObservedPhase]? = nil, pauseState: LiftSessionPause? = nil) {
        self.plan = plan
        self.exerciseOrder = exerciseOrder.flatMap { $0.count == plan.count && Set($0) == Set(plan.indices) ? $0 : nil } ?? Array(plan.indices)
        self.exerciseReplacements = exerciseReplacements
        self.activityPhases = activityPhases
        self.pauseState = pauseState
        self.startTs = startTs
        self.stage = stage
        self.sets = sets
        self.stageStartedAt = stageStartedAt
    }

    // MARK: - The sheet

    /// Every slot of one exercise, in order — the rows the sheet draws.
    func slots(forExercise index: Int) -> [LiftSlot] {
        guard plan.indices.contains(index) else { return [] }
        return (1...plan[index].targetSets).map { LiftSlot(exerciseIndex: index, setIndex: $0) }
    }

    /// Every slot in the whole session, in plan order.
    var allSlots: [LiftSlot] {
        exerciseOrder.flatMap { index in slots(forExercise: index).filter { exerciseReplacements[index] == nil || isCompleted($0) } }
    }

    func recordedSet(for slot: LiftSlot) -> LiftRecordedSet? {
        sets.first { $0.slot == slot }
    }

    func isCompleted(_ slot: LiftSlot) -> Bool { recordedSet(for: slot) != nil }

    /// The slot being worked or rested from.
    var currentSlot: LiftSlot? {
        switch stage {
        case .working(let s): return s
        case .resting(let s, _): return s
        case .warmup, .finished: return nil
        }
    }

    /// The next slot the plan would suggest — the first uncompleted one in plan order. Nil when the
    /// whole sheet is done.
    ///
    /// This is the SHEET's answer, used to open a session and to know when everything is done. It is
    /// deliberately NOT what `advance` follows after a set — see `slotAfter(_:)`.
    var nextPendingSlot: LiftSlot? {
        allSlots.first { !isCompleted($0) }
    }

    /// Where the session goes after finishing `slot`: the next uncompleted set of the SAME exercise,
    /// and only once that exercise is finished, the first uncompleted slot in plan order.
    ///
    /// Plan order alone is wrong, and wrong in a way that costs sets. A gym is not a queue — the
    /// whole point of being able to start any pending set is that machines get occupied — so a user
    /// who skips exercise 1 and starts exercise 3 has an EARLIER slot still uncompleted. Following
    /// plan order then throws them back to the machine they just walked away from, mid-exercise,
    /// after every single set. Reported from a real session: "when I double-tap for the next set, it
    /// reverts to the first set of the exercise I couldn't do earlier."
    ///
    /// Staying on the current exercise until it is finished is also simply what lifting is: you do
    /// your sets on the machine you are standing at. The skipped exercise is not forgotten — it is
    /// still pending, and it is what you get once the current one is done.
    func slotAfter(_ slot: LiftSlot) -> LiftSlot? {
        if let group = planItem(for: slot)?.supersetGroupId,
           let next = pendingInGroup(group, excluding: nil) { return next }
        return (exerciseReplacements[slot.exerciseIndex] == nil ? slots(forExercise: slot.exerciseIndex).first { !isCompleted($0) } : nil) ?? nextPendingSlot
    }

    /// Presentation labels follow first appearance; the UUID remains the stored identity.
    static func groupNumber(_ group: String, in groups: [String?]) -> Int? {
        var seen = Set<String>()
        let ordered = groups.compactMap { $0 }.filter { seen.insert($0).inserted }
        return ordered.firstIndex(of: group).map { $0 + 1 }
    }

    private func pendingInGroup(_ group: String, excluding excluded: LiftSlot?) -> LiftSlot? {
        let members = exerciseOrder.filter { plan[$0].supersetGroupId == group && exerciseReplacements[$0] == nil }
        return members.flatMap { slots(forExercise: $0) }.filter { !isCompleted($0) && $0 != excluded }.sorted {
            if $0.setIndex != $1.setIndex { return $0.setIndex < $1.setIndex }
            return (members.firstIndex(of: $0.exerciseIndex) ?? 0) < (members.firstIndex(of: $1.exerciseIndex) ?? 0)
        }.first
    }

    @discardableResult
    mutating func groupWithPreviousExercise(_ index: Int, newGroupID: String) -> Bool {
        guard !isFinished, plan.indices.contains(index), exerciseReplacements[index] == nil,
              let position = exerciseOrder.firstIndex(of: index),
              let previous = exerciseOrder.prefix(position).last(where: { exerciseReplacements[$0] == nil }) else { return false }
        let group = plan[previous].supersetGroupId ?? newGroupID
        guard plan[index].supersetGroupId != group || plan[previous].supersetGroupId != group else { return false }
        pushHistory()
        plan[previous].supersetGroupId = group
        plan[index].supersetGroupId = group
        return true
    }

    /// Grouping is explicit. Historical sets retain the group actually used at completion.
    @discardableResult
    mutating func setSupersetGroup(_ group: String?, forExercise index: Int) -> Bool {
        guard !isFinished, plan.indices.contains(index), exerciseReplacements[index] == nil else { return false }
        guard plan[index].supersetGroupId != group else { return false }
        pushHistory()
        plan[index].supersetGroupId = group
        return true
    }

    /// The set the session is heading to after the current one — what the minimised bar and the Lock
    /// Screen name as "next". During the warm-up it is the set `advance` starts; while a set is worked
    /// or rested from, it is where `advance` goes once that set is done: `slotAfter(_:)`, with the
    /// current set counted as done. Never a rest, which sits between sets rather than being one of
    /// them. Nil when nothing is left to do after the current set.
    var upcomingSlot: LiftSlot? {
        switch stage {
        case .warmup:
            return nextPendingSlot
        case .working(let slot), .resting(let slot, _):
            if let group = planItem(for: slot)?.supersetGroupId, let next = pendingInGroup(group, excluding: slot) { return next }
            return (exerciseReplacements[slot.exerciseIndex] == nil ? slots(forExercise: slot.exerciseIndex).first { !isCompleted($0) && $0 != slot } : nil)
                ?? allSlots.first { !isCompleted($0) && $0 != slot }
        case .finished:
            return nil
        }
    }

    var allCompleted: Bool { nextPendingSlot == nil }
    var isFinished: Bool { stage == .finished }
    var canUndo: Bool { !history.isEmpty }

    var plannedWorkingSets: Int { allSlots.count }
    var completedWorkingSets: Int { sets.filter { !$0.isWarmup }.count }

    func planItem(for slot: LiftSlot) -> LiftPlanItem? {
        plan.indices.contains(slot.exerciseIndex) ? plan[slot.exerciseIndex] : nil
    }

    /// Seconds left in the current rest, floored at zero. Nil when not resting.
    ///
    /// Floored rather than negative so an overrun rest reads "0:00" and waits, which is what it
    /// actually means: the user has not moved on yet.
    func restRemaining(now: Int) -> Int? {
        if let paused = pauseState { return paused.remainingRest }
        guard case .resting(_, let endsAt) = stage else { return nil }
        return max(0, endsAt - now)
    }

    /// The nearest earlier set of this exercise already performed in THIS session. Nil for the first
    /// set, or when nothing before it has been done yet.
    func previousSetInSession(for slot: LiftSlot) -> LiftRecordedSet? {
        (1..<max(1, slot.setIndex)).reversed()
            .compactMap { recordedSet(for: LiftSlot(exerciseIndex: slot.exerciseIndex, setIndex: $0)) }
            .first
    }

    /// The numbers a slot shows in grey, in order of preference: this exercise earlier in THIS
    /// session, then the same set number LAST session, then the program's target.
    ///
    /// "Earlier in this session" means what that set COUNTS AS (`values(of:lastSession:)`), so set 2
    /// follows set 1 whether or not anything was typed there, and moves again if set 1 is corrected.
    ///
    /// GREY STAYS GREY. Finishing a set records its timing and nothing else; a number becomes the
    /// set's own only when it is typed. What a set without typed numbers is worth is decided once,
    /// when the session is finished: the user completes all of them with these numbers or discards
    /// them (`LiftSessionController.setsToSave`). Both earlier rules lost something. Recording nothing
    /// let 19 sets from a real session save with no numbers at all, and writing the grey numbers in at
    /// "set done" turned a suggestion into an entry the user then had to type over.
    ///
    /// RPE is NOT carried. Weight and reps are a plan, knowable in advance; RPE is how hard a set
    /// FELT, knowable only afterwards, and carrying one forward would invent the one figure nobody
    /// can guess for you. It would also silently corrupt the coverage the RPE card reports — every
    /// set would read as rated, and "14 of 19 sets unrated" could never be shown again.
    ///
    /// `lastSession` is this exercise's previous session by set number — the one layer the engine
    /// cannot know. The caller supplies it; a set number it lacks falls through to the target.
    func carry(for slot: LiftSlot, lastSession: [Int: LiftSetCarry]) -> LiftSetCarry {
        let previous = previousSetInSession(for: slot).map { values(of: $0.slot, lastSession: lastSession) }
        let last = lastSession[slot.setIndex]
        let item = planItem(for: slot)
        return LiftSetCarry(
            weightKg: previous?.weightKg ?? last?.weightKg ?? item?.targetWeightKg,
            reps: previous?.reps ?? last?.reps ?? item?.targetRepsLow)
    }

    /// What a slot counts as: each number typed into it, else its grey number.
    func values(of slot: LiftSlot, lastSession: [Int: LiftSetCarry]) -> LiftSetCarry {
        let grey = carry(for: slot, lastSession: lastSession)
        guard let set = recordedSet(for: slot) else { return grey }
        return LiftSetCarry(weightKg: set.weightKg ?? grey.weightKg, reps: set.reps ?? grey.reps)
    }

    /// Slots never performed. Finishing the session asks once what happens to all of them; a set that
    /// was performed is complete whether or not anything was typed into it (Utku, 21 Sep 2026).
    var unperformedSlots: [LiftSlot] {
        allSlots.filter { !isCompleted($0) }
    }

    // MARK: - Actions

    /// Begin a specific set. Works from any stage, which is the whole point: a machine being busy
    /// must not block the session.
    ///
    /// Starting a set while ANOTHER set is in progress abandons that one — nothing is recorded,
    /// because nothing was finished. Starting an already-completed slot re-opens it for a redo,
    /// dropping its previous record so the set is not counted twice.
    mutating func start(_ slot: LiftSlot, now: Int) {
        guard !isPaused, !phaseCapacityReached, validTime(now), let item = planItem(for: slot), (1...item.targetSets).contains(slot.setIndex), exerciseReplacements[slot.exerciseIndex] == nil else { return }
        pushHistory()
        closePhase(now: now)
        // Starting a redo explicitly replaces that slot's earlier attempt, like its set row.
        activityPhases?.removeAll { $0.slot == slot }
        sets.removeAll { $0.slot == slot }
        stage = .working(slot)
        stageStartedAt = now
        beginPhase(.work, slot: slot, now: now)
    }

    /// The big button. Context decides what it means.
    mutating func advance(now: Int, isWarmup: Bool = false) {
        guard !isPaused, !phaseCapacityReached, validTime(now) else { return }
        switch stage {
        case .warmup:
            guard let next = nextPendingSlot else { return }
            start(next, now: now)

        case .working(let slot):
            pushHistory()
            closePhase(now: now)
            // Timing only: the numbers stay grey until typed (see `carry(for:lastSession:)`).
            let group = isWarmup ? nil : planItem(for: slot)?.supersetGroupId
            let round = group.map { id in sets.filter { $0.exerciseIndex == slot.exerciseIndex && $0.supersetGroupId == id && !$0.isWarmup }.count }
            sets.append(LiftRecordedSet(
                exerciseIndex: slot.exerciseIndex, setIndex: slot.setIndex,
                weightKg: nil, reps: nil, rpe: nil, isWarmup: isWarmup,
                startTs: stageStartedAt, endTs: now, restSec: nil, supersetGroupId: group, roundIndex: round))
            if let group, let next = slotAfter(slot), next.exerciseIndex != slot.exerciseIndex,
               planItem(for: next)?.supersetGroupId == group, next.setIndex == slot.setIndex {
                stage = .working(next)
                stageStartedAt = now
                beginPhase(.work, slot: next, now: now)
                return
            }
            let rest = planItem(for: slot)?.restSec ?? LiftPlanItem.defaultRestSec
            stage = .resting(slot, endsAt: now + rest)
            stageStartedAt = now
            beginPhase(.rest, slot: slot, now: now)

        case .resting(let slot, _):
            pushHistory()
            closePhase(now: now)
            // Record what was ACTUALLY rested — the figure each set row shows, and the one thing
            // only the taps can know.
            if let i = sets.firstIndex(where: { $0.slot == slot }) {
                sets[i].restSec = observedRest(for: slot, fallback: max(0, now - stageStartedAt))
            }
            if let next = slotAfter(slot) {
                stage = .working(next)
                stageStartedAt = now
                beginPhase(.work, slot: next, now: now)
            } else {
                // Sheet complete: stay put rather than inventing a stage. The user finishes when
                // they are ready, and the time until then is the cool-down.
                stage = .resting(slot, endsAt: now)
                stageStartedAt = now
                beginPhase(.rest, slot: slot, now: now)
            }

        case .finished:
            break
        }
    }

    /// Fill in (or correct) what a set actually was. Editing, never appending — the set already
    /// exists, so typing can never create a phantom. No-op for a slot that has not been completed.
    mutating func updateSet(_ slot: LiftSlot,
                            weightKg: Double?, reps: Int?, rpe: Double?, isWarmup: Bool) {
        guard let i = sets.firstIndex(where: { $0.slot == slot }) else { return }
        sets[i].weightKg = weightKg
        sets[i].reps = reps
        sets[i].rpe = rpe
        sets[i].isWarmup = isWarmup
    }

    // MARK: - Changing how many sets a line holds
    //
    // A program is what you INTENDED, and a gym argues with it. Five sets when the program says four
    // is ordinary; so is stopping at three because the tank is empty. Until this existed the fifth
    // set simply could not be recorded — the sheet drew exactly `1...targetSets` and there was no
    // way past it — so the set was done and then lost, which is the failure this feature exists to
    // prevent.

    /// The most sets one line may hold. A bound against a stuck finger, not a recommendation: every
    /// added set is a row on the sheet and a slot in the crash snapshot.
    static let maxSetsPerExercise = 20

    /// Append one set to an exercise's line. Returns false when the line is already at the bound, so
    /// a caller can tell "did nothing" from "done" without re-deriving the rule.
    @discardableResult
    mutating func addSet(toExercise index: Int) -> Bool {
        guard plan.indices.contains(index),
              exerciseReplacements[index] == nil,
              plan[index].targetSets < LiftSessionEngine.maxSetsPerExercise else { return false }
        pushHistory()
        plan[index].targetSets += 1
        return true
    }

    /// Whether the last set of a line can be dropped.
    ///
    /// Only the LAST one, and only while it is still pending. Set numbers are positions — the sheet
    /// draws `1...targetSets` — so removing from the middle would renumber every set after it and
    /// silently re-label what was already recorded. And a completed set is DATA: dropping it here
    /// would delete a set the user actually performed, from a button whose job is to edit a plan.
    /// The set being worked or rested from is excluded for the same reason it cannot be renumbered:
    /// the session is standing on it.
    func canRemoveSet(fromExercise index: Int) -> Bool {
        guard plan.indices.contains(index), exerciseReplacements[index] == nil, plan[index].targetSets > 1 else { return false }
        let last = LiftSlot(exerciseIndex: index, setIndex: plan[index].targetSets)
        return !isCompleted(last) && currentSlot != last
    }

    /// Drop the last (pending) set of an exercise's line. Returns false when the rule above says no.
    @discardableResult
    mutating func removeSet(fromExercise index: Int) -> Bool {
        guard canRemoveSet(fromExercise: index) else { return false }
        pushHistory()
        plan[index].targetSets -= 1
        return true
    }

    // MARK: - Adding an exercise

    /// Move a card and its next-set suggestion, without changing recorded slots or the current stage.
    @discardableResult
    mutating func moveExercise(_ index: Int, by offset: Int) -> Bool {
        guard stage != .finished, offset == -1 || offset == 1,
              let position = exerciseOrder.firstIndex(of: index), exerciseOrder.indices.contains(position + offset) else { return false }
        pushHistory()
        exerciseOrder.swapAt(position, position + offset)
        return true
    }

    /// The most lines one session may hold: the importer's cap on one program, so a session grown during
    /// the workout stays inside the bound its crash snapshot (written on every change) was sized for.
    static let maxExercises = 200

    func canReplaceExercise(_ index: Int) -> Bool {
        guard stage != .finished, plan.indices.contains(index), exerciseReplacements[index] == nil,
              plan.count < Self.maxExercises else { return false }
        if case .working(let slot) = stage, slot.exerciseIndex == index { return false }
        return slots(forExercise: index).contains { !isCompleted($0) }
    }

    /// A replacement is a new exercise. Completed original sets and an ongoing rest remain intact.
    @discardableResult
    mutating func replaceExercise(_ index: Int, with item: LiftPlanItem) -> Int? {
        guard canReplaceExercise(index), let position = exerciseOrder.firstIndex(of: index) else { return nil }
        pushHistory()
        var replacement = item
        replacement.targetSets = max(1, slots(forExercise: index).filter { !isCompleted($0) }.count)
        replacement.programItemId = nil; replacement.addedInSession = false
        replacement.supersetGroupId = plan[index].supersetGroupId
        let replacementIndex = plan.count
        plan.append(replacement)
        exerciseReplacements[index] = replacementIndex
        exerciseOrder.insert(replacementIndex, at: position + 1)
        return replacementIndex
    }

    /// Append an exercise the program does not have, as ONE set at the end of the sheet (Utku, 21 Sep
    /// 2026). Any set count the caller gives is ignored: a line starts with one set, and ⊕/⊖ change it
    /// like any other. Undoable, like adding a set. Returns false when nothing was added — the session
    /// is finished, or already at `maxExercises`.
    @discardableResult
    mutating func addExercise(_ item: LiftPlanItem) -> Bool {
        guard stage != .finished, plan.count < LiftSessionEngine.maxExercises else { return false }
        pushHistory()
        var line = item
        line.targetSets = 1
        plan.append(line)
        exerciseOrder.append(plan.count - 1)
        return true
    }

    /// End the session. The rest that was running is closed out first, so its measured duration is
    /// not silently lost.
    mutating func finish(now: Int) {
        guard stage != .finished, validTime(now) else { return }
        pushHistory()
        closePhase(now: now)
        pauseState = nil
        if case .resting(let slot, _) = stage,
           let i = sets.firstIndex(where: { $0.slot == slot }), sets[i].restSec == nil {
            sets[i].restSec = observedRest(for: slot, fallback: max(0, now - stageStartedAt))
        }
        stage = .finished
        stageStartedAt = now
    }

    mutating func undo() {
        guard !isPaused, let previous = history.popLast() else { return }
        plan = previous.plan
        exerciseOrder = previous.exerciseOrder
        exerciseReplacements = previous.exerciseReplacements
        stage = previous.stage
        sets = previous.sets
        stageStartedAt = previous.stageStartedAt
        activityPhases = previous.activityPhases
        pauseState = previous.pauseState
        openPhaseID = previous.openPhaseID
    }

    private mutating func pushHistory() {
        history.append(Snapshot(plan: plan, exerciseOrder: exerciseOrder, exerciseReplacements: exerciseReplacements, stage: stage,
                                sets: sets, stageStartedAt: stageStartedAt, activityPhases: activityPhases, pauseState: pauseState, openPhaseID: openPhaseID))
    }
}
