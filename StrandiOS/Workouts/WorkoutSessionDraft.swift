import Foundation

/// A pending edit of one canonical Life workout, never a separate workout log or WHOOP recording.
struct WorkoutSessionDraft: Codable, Equatable {
    struct Submission: Codable, Equatable {
        let id: UUID
        let revision: Int
        let command: [String: WorkoutTrackerValue]
        let edits: [String: WorkoutInlineSetDraft]
        let finishing: Bool
    }
    struct Remote: Codable, Equatable {
        let session: WorkoutTrackerDashboard.Session
        let revision: Int
    }
    var version = 1
    let origin: String
    let installationId: UUID
    var baseline: WorkoutTrackerDashboard.Session
    var revision: Int
    let massScale: Double
    let localeIdentifier: String
    var edits: [String: WorkoutInlineSetDraft] = [:]
    var pending: Submission?
    var finishQueued = false
    var remote: Remote?
    var lastAcceptedAt: Date?
    var dirtyIDs: Set<Int> { Set(edits.values.filter(\.isDirty).map { $0.baseline.id }) }
    var hasChanges: Bool { !dirtyIDs.isEmpty }
    var hasNewerEdits: Bool {
        guard let pending else { return hasChanges }
        return Set(edits.keys).union(pending.edits.keys).contains { id in
            guard let row = row(Int(id) ?? -1) else { return true }
            let initial = WorkoutInlineSetDraft(row: row, massScale: massScale, locale: Locale(identifier: localeIdentifier))
            return (edits[id] ?? initial) != (pending.edits[id] ?? initial)
        }
    }
    var isProtected: Bool { hasChanges || pending != nil || finishQueued }

    func row(_ id: Int) -> WorkoutTrackerDashboard.SetLog? {
        baseline.exercises.lazy.flatMap(\.sets).first { $0.id == id }
    }
    func entry(_ id: Int) -> WorkoutInlineSetDraft? {
        edits[String(id)] ?? row(id).map { WorkoutInlineSetDraft(row: $0, massScale: massScale, locale: Locale(identifier: localeIdentifier)) }
    }
    mutating func edit(_ value: WorkoutInlineSetDraft) throws {
        guard !finishQueued, pending?.finishing != true, let original = row(value.baseline.id),
              original == value.baseline, value.massScale == massScale else { throw Failure.changed }
        // Reverting to the OLD clean baseline while a different value is sending is itself a new
        // deliberate edit. Keep that entry until the frozen receipt has been reconciled.
        let undoingPending = pending?.edits[String(original.id)].map { $0 != value } ?? false
        if value.isDirty || undoingPending { edits[String(original.id)] = value } else { edits[String(original.id)] = nil }
    }
    func command(finishing: Bool) throws -> [String: WorkoutTrackerValue] {
        guard remote == nil else { throw Failure.conflict }
        guard !finishing || (!baseline.scheduledDate.isEmpty && ["planned", "in_progress"].contains(baseline.status)) else { throw Failure.unscheduled }
        var command: [String: WorkoutTrackerValue] = ["action": .string("update_session"),
            "mesocycleId": .number(Double(baseline.mesocycleId)), "sessionId": .number(Double(baseline.id))]
        var sets: [WorkoutTrackerValue] = []
        for exercise in baseline.exercises {
            guard let mode = WorkoutTrackerLoadMode(rawValue: exercise.loadMode) else {
                if exercise.sets.contains(where: { edits[String($0.id)] != nil }) { throw Failure.changed }
                continue
            }
            for row in exercise.sets {
                guard let entry = edits[String(row.id)], entry.isDirty else { continue }
                var fields = try entry.command(sessionID: baseline.id, programID: baseline.mesocycleId,
                    mode: mode, completed: entry.completed, locale: Locale(identifier: localeIdentifier))
                fields["action"] = nil; fields["mesocycleId"] = nil; fields["sessionId"] = nil
                sets.append(.object(fields))
            }
        }
        guard sets.count <= 200 else { throw Failure.tooMany }
        if !sets.isEmpty { command["sets"] = .array(sets) }
        if finishing { command["status"] = .string("completed") }
        guard !sets.isEmpty || finishing else { throw Failure.empty }
        return command
    }
    mutating func freeze(finishing: Bool) throws {
        guard pending == nil else {
            if finishing && pending?.finishing != true {
                guard !baseline.scheduledDate.isEmpty, ["planned", "in_progress"].contains(baseline.status) else { throw Failure.unscheduled }
                finishQueued = true
            }
            return
        }
        pending = try .init(id: UUID(), revision: revision, command: command(finishing: finishing), edits: edits, finishing: finishing)
    }
    /// Only acknowledged fields enter the new baseline. Edits made after freezing remain unsent.
    mutating func accept(_ submission: Submission, revision newRevision: Int) throws {
        guard pending?.id == submission.id, newRevision >= submission.revision else { throw Failure.changed }
        var updated = baseline
        if case .array(let sets) = submission.command["sets"] {
            for value in sets {
                guard case .object(let fields) = value, case .number(let setID) = fields["setId"] else { throw Failure.changed }
                for i in updated.exercises.indices {
                    for j in updated.exercises[i].sets.indices where updated.exercises[i].sets[j].id == Int(setID) {
                        var row = updated.exercises[i].sets[j]
                        if let value = fields["actualLoad"] { row.actualLoad = value.optionalNumber }
                        if let value = fields["actualReps"] { row.actualReps = value.optionalNumber.map(Int.init) }
                        if let value = fields["rir"] { row.rir = value.optionalNumber }
                        if case .bool(let completed) = fields["completed"] {
                            row.completed = completed
                            if !completed { row.actualLoad = nil; row.actualReps = nil; row.rir = nil }
                        }
                        updated.exercises[i].sets[j] = row
                    }
                }
            }
        }
        if submission.finishing { updated.status = "completed" }
        baseline = updated; revision = newRevision; pending = nil; lastAcceptedAt = Date()
        for (id, anchor) in submission.edits {
            guard let current = edits[id], let row = row(anchor.baseline.id) else { continue }
            let rebased = current.rebased(from: anchor, onto: row)
            edits[id] = rebased.isDirty ? rebased : nil
        }
        if let latest = remote {
            remote = nil
            if latest.revision >= revision { try receive(latest.session, revision: latest.revision) }
        }
    }
    mutating func receive(_ latest: WorkoutTrackerDashboard.Session, revision newRevision: Int) throws {
        guard latest.id == baseline.id, latest.mesocycleId == baseline.mesocycleId else { throw Failure.changed }
        guard newRevision >= revision else { return }
        if let remote, newRevision < remote.revision { return }
        let incoming = Remote(session: latest, revision: newRevision)
        if pending != nil { remote = incoming; return }
        let identitiesMatch = edits.values.allSatisfy { entry in
            guard let before = baseline.exercises.first(where: { $0.sets.contains(where: { $0.id == entry.baseline.id }) }),
                  let after = latest.exercises.first(where: { $0.id == before.id }),
                  before.exerciseKey == after.exerciseKey, before.loadMode == after.loadMode,
                  let row = after.sets.first(where: { $0.id == entry.baseline.id }) else { return false }
            return row == entry.baseline
        }
        if isProtected && (!identitiesMatch || latest.status != baseline.status || latest.scheduledDate != baseline.scheduledDate) {
            remote = incoming; return
        }
        baseline = latest; revision = newRevision; remote = nil
    }
    /// Explicit conflict review can keep deliberate fields; untouched fields adopt the newer source.
    mutating func resolveRemote(keepEdits: Bool) throws {
        guard pending == nil, let remote else { throw Failure.changed }
        var next: [String: WorkoutInlineSetDraft] = [:]
        if keepEdits {
            for (id, edit) in edits {
                guard let old = baseline.exercises.first(where: { $0.sets.contains(where: { $0.id == edit.baseline.id }) }),
                      let exercise = remote.session.exercises.first(where: { $0.id == old.id && $0.exerciseKey == old.exerciseKey && $0.loadMode == old.loadMode }),
                      let row = exercise.sets.first(where: { $0.id == edit.baseline.id }) else { throw Failure.changed }
                let entry = edit.rebased(from: .init(row: edit.baseline, massScale: massScale, locale: Locale(identifier: localeIdentifier)), onto: row)
                if entry.isDirty { next[id] = entry }
            }
        }
        baseline = remote.session; revision = remote.revision; edits = next; self.remote = nil; finishQueued = false
    }
    func validate() throws {
        guard version == 1, !origin.isEmpty, baseline.id > 0, baseline.mesocycleId > 0, revision >= 0,
              massScale.isFinite, massScale > 0, edits.count <= 1000,
              edits.allSatisfy({ $0.key == String($0.value.baseline.id) && $0.value.massScale == massScale && $0.value.localeIdentifier == localeIdentifier && row($0.value.baseline.id) == $0.value.baseline }),
              baseline.exercises.count <= 200 else { throw Failure.changed }
        if let pending {
            guard pending.revision == revision, pending.command["action"] == .string("update_session"),
                  pending.command["sessionId"] == .number(Double(baseline.id)),
                  pending.command["mesocycleId"] == .number(Double(baseline.mesocycleId)) else { throw Failure.changed }
            var frozen = self; frozen.pending = nil; frozen.remote = nil; frozen.finishQueued = false; frozen.edits = pending.edits
            guard try frozen.command(finishing: pending.finishing) == pending.command else { throw Failure.changed }
        }
    }
    enum Failure: LocalizedError {
        case changed, conflict, empty, unscheduled, tooMany
        var errorDescription: String? {
            switch self {
            case .changed: return "This workout or exercise changed. Your local input is retained; review the latest workout."
            case .conflict: return "Life has newer values. Review them before sending your local workout changes."
            case .empty: return "No workout changes to send."
            case .unscheduled: return "Schedule this workout before finishing it. Your local changes are retained."
            case .tooMany: return "A workout save supports at most 200 changed sets. Your local input is retained."
            }
        }
    }
}
private extension WorkoutTrackerValue {
    var optionalNumber: Double? { if case .number(let value) = self { return value }; return nil }
}
struct WorkoutSessionDraftFileStore {
    let url: URL
    func load() throws -> WorkoutSessionDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw WorkoutSessionDraft.Failure.changed }
        let draft = try JSONDecoder().decode(WorkoutSessionDraft.self, from: data)
        try draft.validate(); return draft
    }
    func save(_ draft: WorkoutSessionDraft) throws {
        try draft.validate()
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 2 * 1024 * 1024 else { throw WorkoutSessionDraft.Failure.changed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
