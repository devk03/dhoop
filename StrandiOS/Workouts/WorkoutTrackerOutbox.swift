import Foundation
import WhoopStore

struct WorkoutTrackerDelivery: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case prepared, ready, accepted, review, failed }
    enum Operation: String, Codable { case upsert, delete }
    let id: UUID
    let sourceWorkoutId: UUID
    let installationId: UUID
    let origin: String
    let revision: Int
    let bytes: Data?
    let record: LiftSessionRow
    let sets: [LiftSetRow]
    let binding: WorkoutTrackerCaptureBinding
    var operation: Operation? = nil
    var status: Status = .prepared
    var message = "Waiting for verified local persistence"
    var acknowledgement: Data?
    var paused: Bool? = nil
    var localPersistenceConfirmed: Bool? = nil
    var createdAt: Date? = nil
    var rejection: WorkoutSyncRejection? = nil
    var recoveryOf: UUID? = nil
    var canArchive: Bool {
        if paused == true && localPersistenceConfirmed == true { return true }
        guard status == .accepted, !needsReconciliation, let acknowledgement,
              let ack = try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: acknowledgement),
              (try? ack.validate(eventId: id, sourceWorkoutId: sourceWorkoutId, revision: revision)) != nil,
              (try? ack.validate(binding: binding, sets: operation == .delete ? [] : sets)) != nil else { return false }
        return !ack.needsSourceReview(revision: revision, deleting: operation == .delete)
    }
    func sameIntent(as other: WorkoutTrackerDelivery) -> Bool {
        id == other.id && sourceWorkoutId == other.sourceWorkoutId && installationId == other.installationId && origin == other.origin &&
            revision == other.revision && bytes == other.bytes && record == other.record && sets == other.sets && binding == other.binding &&
            (operation ?? .upsert) == (other.operation ?? .upsert) && recoveryOf == other.recoveryOf
    }
    var needsReconciliation: Bool {
        status == .accepted && acknowledgement.flatMap {
            try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: $0)
        }?.reconciliation.pending == true
    }
    var valid: Bool {
        (bytes?.count ?? 0) <= WorkoutSyncTransport.bodyLimit && revision > 0 && revision <= 9_007_199_254_740_991 && record.id.lowercased() == sourceWorkoutId.uuidString.lowercased()
            && recoveryOf != id
            && sets.allSatisfy { $0.sessionId == record.id && $0.deviceId == record.deviceId }
            && (try? WorkoutSyncEndpoint.observations.url(origin: origin)) != nil
            && (try? binding.validate()) != nil && binding.sourceWorkoutId == sourceWorkoutId
            && (binding.connection.map { $0.origin == origin && $0.installationId == installationId } ?? true)
    }
    /// The queue cannot claim persistence until the exact UUID-bound recording is present.
    func matches(store: WhoopStore) async throws -> Bool {
        let rows = try await store.liftSessions(deviceId: record.deviceId, fromTs: record.startTs, toTs: record.startTs)
        if operation == .delete {
            guard !rows.contains(where: { $0.id == record.id }), try await store.liftSets(sessionId: record.id).isEmpty else { return false }
            let workouts = try await store.workouts(deviceId: record.deviceId, from: record.startTs, to: record.startTs, limit: 100)
            return !workouts.contains { $0.startTs == record.startTs && $0.sport == record.sport && $0.source == "manual" }
        }
        guard rows.contains(record) else { return false }
        let saved = try await store.liftSets(sessionId: record.id)
        guard saved.sorted(by: { $0.id < $1.id }) == sets.sorted(by: { $0.id < $1.id }) else { return false }
        let workouts = try await store.workouts(deviceId: record.deviceId, from: record.startTs, to: record.startTs, limit: 100)
        return workouts.contains { $0.startTs == record.startTs && $0.endTs == record.endTs && $0.sport == record.sport && $0.source == "manual" }
    }
    func validateBody() throws {
        guard let bytes,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              (object["schemaVersion"] as? Int) == 1, (object["kind"] as? String) == "strength_workout",
              (object["eventId"] as? String).flatMap(UUID.init(uuidString:)) == id,
              (object["sourceWorkoutId"] as? String).flatMap(UUID.init(uuidString:)) == sourceWorkoutId,
              (object["installationId"] as? String).flatMap(UUID.init(uuidString:)) == installationId,
              (object["sourceRevision"] as? Int) == revision,
              (object["operation"] as? String) == (operation ?? .upsert).rawValue else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}

/// A review is ephemeral; it is not a new recording, receipt or upload permission.
struct WorkoutTrackerRecoveryReview: Identifiable {
    let id: UUID
    let original: WorkoutTrackerDelivery
    let comparison: WorkoutTrackerReviewComparison
    var prescriptionChanged: Bool { original.binding.manifest.manifestRevision != comparison.manifest.manifestRevision }

    static func validate(original: WorkoutTrackerDelivery, comparison: WorkoutTrackerReviewComparison) throws {
        try original.validateBody()
        guard original.localPersistenceConfirmed == true, original.status == .review,
              [.lifeRevisionConflict, .manifestConflict].contains(original.rejection), original.acknowledgement == nil,
              original.binding.connection?.origin == original.origin,
              original.binding.connection?.installationId == original.installationId,
              original.operation != .delete else { throw WorkoutTrackerContractError.invalidSnapshot }
        let frozen = original.binding.manifest, current = comparison.manifest
        try current.validate()
        guard current.cycleId == frozen.cycleId, current.sessionId == frozen.sessionId,
              current.sessionKey == frozen.sessionKey,
              ["planned", "in_progress", "completed"].contains(current.status),
              current.sourceWorkoutId.map({ UUID(uuidString: $0) == original.sourceWorkoutId }) ?? true,
              current.exerciseOccurrences.count == frozen.exerciseOccurrences.count else { throw WorkoutTrackerContractError.invalidSnapshot }
        // Compare identity sets, never the presentation position. Load units may change; basis may not.
        for old in frozen.exerciseOccurrences {
            guard let new = current.exerciseOccurrences.first(where: { $0.sessionExerciseId == old.sessionExerciseId }),
                  old.programSlotId == new.programSlotId, old.slotKey == new.slotKey,
                  old.exerciseKey == new.exerciseKey, old.originalExerciseKey == new.originalExerciseKey,
                  old.measurementKind == new.measurementKind, old.loadMode == new.loadMode, old.loadBasis == new.loadBasis,
                  Set(old.sets.map(\.lifeSetId)) == Set(new.sets.map(\.lifeSetId)),
                  old.sets.allSatisfy({ target in new.sets.contains { $0.lifeSetId == target.lifeSetId && $0.setType == target.setType } }) else {
                throw WorkoutTrackerContractError.invalidSnapshot
            }
        }
        if let remote = comparison.capture {
            try remote.validate(for: original.binding)
            guard !remote.tombstone, remote.projectionState == "current", remote.projectionPolicy == "apply",
                  remote.nextCursor == nil, remote.lifeRevision == current.lifeRevision, remote.sourceRevision < original.revision else {
                throw WorkoutTrackerContractError.invalidSnapshot
            }
            guard let remoteOccurrences = remote.occurrences else { throw WorkoutTrackerContractError.invalidSnapshot }
            for (key, observed) in remoteOccurrences {
                guard let id = UUID(uuidString: key), observed.raw.deleted != true else { throw WorkoutTrackerContractError.invalidSnapshot }
                if let occurrence = original.binding.occurrences.first(where: { $0.sourceOccurrenceId == id }),
                   let prescribed = frozen.exerciseOccurrences.first(where: { $0.sessionExerciseId == occurrence.sessionExerciseId }) {
                    guard observed.kind == "prescribed", observed.sessionExerciseId == occurrence.sessionExerciseId,
                          observed.programSlotId == prescribed.programSlotId, observed.slotKey == prescribed.slotKey,
                          observed.exerciseKey == prescribed.exerciseKey, observed.loadMode == prescribed.loadMode.rawValue else {
                        throw WorkoutTrackerContractError.invalidSnapshot
                    }
                } else if let extra = original.binding.additionalOccurrences?.first(where: { $0.sourceOccurrenceId == id }) {
                    guard observed.kind == "actual_only", observed.sessionExerciseId == nil, observed.exerciseKey == extra.exerciseKey,
                          observed.loadMode == extra.loadMode.rawValue, observed.raw.replacesSourceOccurrenceId == extra.replacesSourceOccurrenceId else {
                        throw WorkoutTrackerContractError.invalidSnapshot
                    }
                } else { throw WorkoutTrackerContractError.invalidSnapshot }
            }
            for set in remote.sets {
                guard set.raw.deleted != true else { throw WorkoutTrackerContractError.invalidSnapshot }
                if let occurrence = original.binding.occurrences.first(where: { $0.sourceOccurrenceId == set.sourceOccurrenceId }),
                   let identity = occurrence.sets.first(where: { $0.sourceSetId == set.sourceSetId }),
                   let prescribed = frozen.exerciseOccurrences.first(where: { $0.sessionExerciseId == occurrence.sessionExerciseId }) {
                    guard identity.lifeSetId == set.lifeSetId, occurrence.sessionExerciseId == set.sessionExerciseId,
                          prescribed.exerciseKey == set.exerciseKey,
                          set.raw.loadBasis.map({ $0 == prescribed.loadBasis }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
                } else if let extra = original.binding.additionalOccurrences?.first(where: { $0.sourceOccurrenceId == set.sourceOccurrenceId }) {
                    guard extra.sets.contains(where: { $0.sourceSetId == set.sourceSetId }), set.lifeSetId == nil,
                          set.sessionExerciseId == nil, set.exerciseKey == extra.exerciseKey,
                          set.raw.loadBasis.map({ $0 == extra.loadMode.loadBasis }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
                } else { throw WorkoutTrackerContractError.invalidSnapshot }
            }
        }
    }

    /// Copy the original observations exactly. Only reviewed write preconditions and event metadata change.
    func replacement(eventId: UUID = UUID()) throws -> WorkoutTrackerDelivery {
        try Self.validate(original: original, comparison: comparison)
        guard let bytes = original.bytes, var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              original.revision < 9_007_199_254_740_991 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let revision = prescriptionChanged ? original.revision + 1 : original.revision
        object["eventId"] = eventId.uuidString.lowercased()
        object["baseLifeRevision"] = comparison.manifest.lifeRevision
        object["manifestRevision"] = comparison.manifest.manifestRevision
        object["sourceRevision"] = revision
        let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        var result = WorkoutTrackerDelivery(id: eventId, sourceWorkoutId: original.sourceWorkoutId,
            installationId: original.installationId, origin: original.origin, revision: revision, bytes: body,
            record: original.record, sets: original.sets, binding: original.binding)
        result.operation = original.operation
        result.status = .ready; result.localPersistenceConfirmed = true
        result.paused = true; result.createdAt = Date(); result.recoveryOf = original.id
        result.message = "Reviewed delivery prepared locally. Not sent; open this delivery to send its exact event."
        guard result.valid else { throw WorkoutTrackerContractError.invalidSnapshot }
        try result.validateBody()
        return result
    }
}
