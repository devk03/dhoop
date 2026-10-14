import Foundation
import WhoopStore

struct WorkoutCapturePayload: Encodable {
    struct Binding: Encodable {
        let kind = "programmed"
        let cycleId: Int
        let sessionId: Int
    }
    struct Session: Encodable {
        let title: String
        let status: String
        let startedAt: String
        let endedAt: String?
        let timeZone: String
        let notes: String?
        let rpe: Double?
        enum CodingKeys: String, CodingKey { case title, status, startedAt, endedAt, timeZone, notes, rpe }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(title, forKey: .title); try c.encode(status, forKey: .status)
            try c.encode(startedAt, forKey: .startedAt); try c.encode(endedAt, forKey: .endedAt)
            try c.encode(timeZone, forKey: .timeZone); try c.encode(notes, forKey: .notes)
            try c.encode(rpe, forKey: .rpe)
        }
    }
    struct PlanAtStart: Encodable {
        let manifestRevision: String?
        let provenance: WorkoutTrackerCaptureBinding.PlanAtStart.Provenance
        let fetchedAt: String?
        enum CodingKeys: String, CodingKey { case manifestRevision, provenance, fetchedAt }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(manifestRevision, forKey: .manifestRevision)
            try c.encode(provenance, forKey: .provenance)
            try c.encode(fetchedAt, forKey: .fetchedAt)
        }
    }
    struct Occurrence: Encodable {
        let occurrenceKind: String
        let sourceOccurrenceId: String
        let sessionExerciseId: Int?
        let programSlotId: Int?
        let slotKey: String?
        let exerciseKey: String
        let name: String?
        let loadMode: WorkoutTrackerLoadMode?
        let executionOrder: Int?
        let sets: [WorkoutSetObservation]
        var replacesSourceOccurrenceId: String? = nil
        enum CodingKeys: String, CodingKey { case occurrenceKind, sourceOccurrenceId, sessionExerciseId, programSlotId, slotKey, exerciseKey, name, loadMode, executionOrder, sets, replacesSourceOccurrenceId }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(occurrenceKind, forKey: .occurrenceKind); try c.encode(sourceOccurrenceId, forKey: .sourceOccurrenceId)
            try c.encodeIfPresent(sessionExerciseId, forKey: .sessionExerciseId); try c.encodeIfPresent(programSlotId, forKey: .programSlotId)
            try c.encodeIfPresent(slotKey, forKey: .slotKey); try c.encode(exerciseKey, forKey: .exerciseKey)
            try c.encodeIfPresent(name, forKey: .name); try c.encodeIfPresent(loadMode, forKey: .loadMode)
            try c.encode(executionOrder, forKey: .executionOrder); try c.encode(sets, forKey: .sets)
            try c.encodeIfPresent(replacesSourceOccurrenceId, forKey: .replacesSourceOccurrenceId)
        }
    }
    let schemaVersion = 1
    let kind = "strength_workout"
    let eventId: String
    let sourceWorkoutId: String
    let installationId: String
    let sourceRevision: Int
    let operation: String
    let baseLifeRevision: Int
    let manifestRevision: String
    let binding: Binding
    let session: Session
    let exerciseOccurrences: [Occurrence]
    let deletedSetIds: [String]
    var planAtStart: PlanAtStart? = nil

    static func make(record: LiftSessionRow, sets: [LiftSetRow], binding: WorkoutTrackerCaptureBinding,
                     installationId: UUID, revision: Int, eventId: UUID = UUID(),
                     heartRateEvidence: [UUID: WorkoutObservedHeartRate] = [:],
                     baseLifeRevision: Int? = nil, writeManifestRevision: String? = nil, deletedSetIds: [UUID] = [], deleting: Bool = false) throws -> WorkoutCapturePayload {
        try binding.validate()
        guard UUID(uuidString: record.id) == binding.sourceWorkoutId, revision > 0,
              writeManifestRevision.map({ !$0.isEmpty && $0.count <= 100 }) ?? true,
              sets.allSatisfy({ $0.sessionId == record.id && $0.deviceId == record.deviceId }),
              let end = record.endTs, end >= record.startTs else { throw WorkoutTrackerContractError.invalidSnapshot }
        if let rpe = record.sessionRpe, !rpe.isFinite || !(0...10).contains(rpe) { throw WorkoutTrackerContractError.invalidSnapshot }
        let ids = Set(sets.map(\.id))
        guard ids.count == sets.count, sets.count <= 200,
              deletedSetIds.count <= 200, Set(deletedSetIds).count == deletedSetIds.count,
              Set(deletedSetIds).isDisjoint(with: sets.compactMap { UUID(uuidString: $0.id) }) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let known = Set((binding.occurrences.flatMap(\.sets) + (binding.additionalOccurrences ?? []).flatMap(\.sets)).map { $0.sourceSetId.uuidString.lowercased() })
        // Additional sets need an explicit occurrence binding; never attach them by a display name.
        guard ids.isSubset(of: known) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let formatter = ISO8601DateFormatter()
        func date(_ seconds: Int) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(seconds))) }
        func knownOrder(_ row: LiftSetRow, id: UUID) -> Int? {
            if let explicit = binding.observedSetOrder { return explicit[id] }
            // Older captures with measured start/end anchors retain their recorded completion order.
            guard let start = row.startTs, let setEnd = row.endTs, start >= record.startTs, setEnd <= end, setEnd >= start else { return nil }
            return row.ord
        }
        func observe(_ identity: WorkoutTrackerCaptureBinding.SetBinding, basis: String) throws -> WorkoutSetObservation? {
            guard let row = sets.first(where: { UUID(uuidString: $0.id) == identity.sourceSetId }) else { return nil }
            var observed = WorkoutSetObservation(sourceSetId: identity.sourceSetId, setType: row.isWarmup ? .warmup : .work, loadBasis: try self.basis(basis))
            observed.lifeSetId = identity.lifeSetId.map(WorkoutObservationPatch.value) ?? .clear
            observed.completed = (row.reps ?? 0) > 0
            observed.loadKg = row.weightKg.map(WorkoutObservationPatch.value) ?? .clear
            observed.reps = row.reps.map(WorkoutObservationPatch.value) ?? .clear
            observed.rpe = row.rpe.map(WorkoutObservationPatch.value) ?? .clear
            observed.notes = row.note.map(WorkoutObservationPatch.value) ?? .clear
            observed.enteredLoad = .clear
            observed.startedAt = row.startTs.map { .value(date($0)) } ?? .clear
            observed.endedAt = row.endTs.map { .value(date($0)) } ?? .clear
            observed.heartRateSummary = heartRateEvidence[identity.sourceSetId].map(WorkoutObservationPatch.value) ?? .clear
            observed.executionOrder = knownOrder(row, id: identity.sourceSetId).map(WorkoutObservationPatch.value) ?? .clear
            try observed.validate(); return observed
        }
        var occurrences: [Occurrence] = []
        for identity in binding.occurrences where !deleting {
            guard let prescribed = binding.manifest.exerciseOccurrences.first(where: { $0.sessionExerciseId == identity.sessionExerciseId }) else {
                throw WorkoutTrackerContractError.invalidSnapshot
            }
            let observations = try identity.sets.compactMap { try observe($0, basis: prescribed.loadBasis) }
            occurrences.append(Occurrence(occurrenceKind: "prescribed", sourceOccurrenceId: identity.sourceOccurrenceId.uuidString.lowercased(),
                sessionExerciseId: identity.sessionExerciseId, programSlotId: prescribed.programSlotId,
                slotKey: prescribed.slotKey, exerciseKey: prescribed.exerciseKey, name: nil, loadMode: prescribed.loadMode,
                executionOrder: observations.compactMap { if case .value(let order) = $0.executionOrder { return order }; return nil }.min(), sets: observations))
        }
        if !deleting {
            for extra in binding.additionalOccurrences ?? [] {
                let observations = try extra.sets.compactMap { try observe($0, basis: extra.loadMode.loadBasis) }
                occurrences.append(Occurrence(occurrenceKind: "actual_only", sourceOccurrenceId: extra.sourceOccurrenceId.uuidString.lowercased(),
                    sessionExerciseId: nil, programSlotId: nil, slotKey: nil, exerciseKey: extra.exerciseKey, name: extra.name, loadMode: extra.loadMode,
                    executionOrder: observations.compactMap { if case .value(let order) = $0.executionOrder { return order }; return nil }.min(),
                    sets: observations, replacesSourceOccurrenceId: extra.replacesSourceOccurrenceId?.uuidString.lowercased()))
            }
        }
        return WorkoutCapturePayload(eventId: eventId.uuidString.lowercased(), sourceWorkoutId: binding.sourceWorkoutId.uuidString.lowercased(),
            installationId: installationId.uuidString.lowercased(), sourceRevision: revision, operation: deleting ? "delete" : "upsert",
            baseLifeRevision: baseLifeRevision ?? binding.manifest.lifeRevision, manifestRevision: writeManifestRevision ?? binding.manifest.manifestRevision,
            binding: Binding(cycleId: binding.manifest.cycleId, sessionId: binding.manifest.sessionId),
            session: Session(title: record.programName ?? binding.manifest.title, status: deleting ? "cancelled" : "completed",
                startedAt: date(record.startTs), endedAt: date(end), timeZone: binding.timeZone, notes: record.note, rpe: record.sessionRpe),
            exerciseOccurrences: occurrences, deletedSetIds: deleting ? [] : deletedSetIds.map { $0.uuidString.lowercased() }.sorted(),
            planAtStart: binding.planAtStart.map { PlanAtStart(manifestRevision: $0.manifestRevision, provenance: $0.provenance,
                fetchedAt: $0.fetchedAt.map { formatter.string(from: $0) }) })
    }
    /// Stored strap readings only; no extrapolated coverage or statistics for untimed sets.
    static func measuredEvidence(record: LiftSessionRow, sets: [LiftSetRow], store: WhoopStore) async throws -> [UUID: WorkoutObservedHeartRate] {
        guard let workoutEnd = record.endTs else { return [:] }
        var result: [UUID: WorkoutObservedHeartRate] = [:]
        for set in sets {
            guard set.sessionId == record.id, set.deviceId == record.deviceId,
                  let id = UUID(uuidString: set.id), let start = set.startTs, let end = set.endTs,
                  start >= record.startTs, end <= workoutEnd, end > start else { continue }
            let measured = try await store.measuredHeartRateStats(deviceId: record.deviceId, from: start, toExclusive: end)
            result[id] = WorkoutObservedHeartRate(sampleCount: measured.n, coverageFraction: nil,
                averageBpm: measured.avg, maximumBpm: measured.max.map(Double.init))
        }
        return result
    }
    private static func basis(_ raw: String) throws -> WorkoutSetObservation.LoadBasis {
        guard let basis = WorkoutSetObservation.LoadBasis(rawValue: raw) else { throw WorkoutTrackerContractError.invalidSnapshot }
        return basis
    }
    func bytes() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(self)
        guard bytes.count <= WorkoutSyncTransport.bodyLimit else { throw WorkoutSyncTransportError.payloadTooLarge }
        return bytes
    }
}

struct WorkoutCaptureAcknowledgement: Decodable {
    struct Mappings: Decodable {
        struct Session: Decodable { let kind: String; let cycleId: Int?; let sessionId: Int? }
        struct SetTarget: Decodable {
            let kind: String
            let lifeSetId: Int?
            let sessionExerciseId: Int?
            let sourceWorkoutId: UUID?
            let sourceSetId: UUID?
        }
        struct OccurrenceTarget: Decodable {
            let kind: String
            let sessionExerciseId: Int?
            let programSlotId: Int?
            let slotKey: String?
            let exerciseKey: String
            let sourceWorkoutId: UUID?
            let sourceOccurrenceId: UUID?
        }
        let session: Session
        let sets: [String: Int]
        let setTargets: [String: SetTarget]?
        let occurrenceTargets: [String: OccurrenceTarget]?
    }
    struct Reconciliation: Decodable {
        let state: String
        var pending: Bool { state == "pending" }
    }
    let schemaVersion: Int
    let eventId: UUID
    let sourceWorkoutId: UUID
    let acceptedSourceRevision: Int
    let outcome: String
    let lifeRevision: Int
    let receiptLifeRevision: Int
    let preservedFields: [String]
    let mappings: Mappings
    let reconciliation: Reconciliation
    let currentSourceRevision: Int?
    let currentTombstone: Bool?
    let projectionState: String?
    let currentProjectionState: String?
    let projectionPolicy: String?

    func needsSourceReview(revision: Int, deleting: Bool, expectingHistoryOnly: Bool = false) -> Bool {
        let mismatchedPolicy = expectingHistoryOnly
            ? deleting || projectionPolicy != "capture_only" || !["capture_only", "retired"].contains(projectionState ?? "") ||
                !["captured_only", "duplicate"].contains(outcome) || reconciliation.state != "not_requested"
            : outcome == "captured_only" || projectionPolicy == "capture_only" || projectionState == "capture_only" ||
                (!deleting && (projectionState == "retired" || currentProjectionState == "retired"))
        return outcome == "stale" || acceptedSourceRevision != revision ||
            (currentSourceRevision ?? revision) > revision || (currentTombstone == true && !deleting) ||
            mismatchedPolicy
    }

    func validate(eventId: UUID, sourceWorkoutId: UUID, revision: Int) throws {
        guard schemaVersion == 1, self.eventId == eventId, self.sourceWorkoutId == sourceWorkoutId,
              acceptedSourceRevision >= revision, lifeRevision >= receiptLifeRevision, receiptLifeRevision >= 0,
              currentSourceRevision.map({ $0 >= acceptedSourceRevision }) ?? true,
              projectionState.map({ ["current", "retired", "capture_only"].contains($0) }) ?? true,
              currentProjectionState.map({ ["current", "retired", "capture_only"].contains($0) }) ?? true,
              projectionPolicy.map({ ["apply", "capture_only"].contains($0) }) ?? true,
              ["done", "pending", "not_pending", "not_applicable", "not_requested"].contains(reconciliation.state),
              ["applied", "captured_only", "duplicate", "stale", "manual_preserved", "deleted"].contains(outcome) else {
            throw WorkoutSyncTransportError.invalidResponse
        }
    }
    func validate(binding: WorkoutTrackerCaptureBinding, sets: [LiftSetRow]) throws {
        guard mappings.session.kind == "programmed", mappings.session.cycleId == binding.manifest.cycleId,
              mappings.session.sessionId == binding.manifest.sessionId else { throw WorkoutSyncTransportError.invalidResponse }
        for row in sets {
            guard let id = UUID(uuidString: row.id) else { throw WorkoutSyncTransportError.invalidResponse }
            let occurrence = binding.occurrences.first(where: { $0.sets.contains(where: { $0.sourceSetId == id }) })
            let extra = binding.additionalOccurrences?.first(where: { $0.sets.contains(where: { $0.sourceSetId == id }) })
            guard let identity = (occurrence?.sets ?? extra?.sets)?.first(where: { $0.sourceSetId == id }) else {
                throw WorkoutSyncTransportError.invalidResponse
            }
            let target = mappings.setTargets?[row.id.lowercased()]
            if let expected = identity.lifeSetId {
                guard mappings.sets[row.id.lowercased()] == expected else { throw WorkoutSyncTransportError.invalidResponse }
                if let target {
                    guard target.kind == "workout_set", target.lifeSetId == expected,
                          target.sessionExerciseId == occurrence?.sessionExerciseId else { throw WorkoutSyncTransportError.invalidResponse }
                }
            } else {
                guard let target, target.kind == "capture_set", target.sourceWorkoutId == binding.sourceWorkoutId,
                      target.sourceSetId == id, mappings.sets[row.id.lowercased()] == nil else { throw WorkoutSyncTransportError.invalidResponse }
            }
            if let extra {
                guard let target = mappings.occurrenceTargets?[extra.sourceOccurrenceId.uuidString.lowercased()],
                      target.kind == "capture_occurrence", target.sourceWorkoutId == binding.sourceWorkoutId,
                      target.sourceOccurrenceId == extra.sourceOccurrenceId, target.exerciseKey == extra.exerciseKey else { throw WorkoutSyncTransportError.invalidResponse }
            }
        }
    }
}
