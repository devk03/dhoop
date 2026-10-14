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
    var reviewedManifest: WorkoutTrackerManifest? = nil
    // Nil is legacy/unknown. Persist true before starting a POST so relaunch cannot mistake
    // an interrupted submission for a never-sent correction.
    var submissionAttempted: Bool? = nil
    var isHistoryOnly: Bool {
        guard let bytes, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return false }
        return object["projectionPolicy"] as? String == "capture_only"
    }
    /// Source acceptance survives retired canonical targets. It does not claim canonical application.
    var hasVerifiedSourceReceipt: Bool {
        guard valid, operation != .delete, let acknowledgement,
              let ack = try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: acknowledgement),
              (try? ack.validate(eventId: id, sourceWorkoutId: sourceWorkoutId, revision: revision)) != nil,
              (try? ack.validate(binding: binding, sets: sets)) != nil else { return false }
        return ack.acceptedSourceRevision == revision && (ack.currentSourceRevision ?? revision) == revision &&
            ack.currentTombstone != true && ["applied", "captured_only", "manual_preserved", "duplicate"].contains(ack.outcome)
    }
    var writeManifestRevision: String? {
        guard let bytes, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        return object["manifestRevision"] as? String
    }
    var canArchive: Bool {
        if paused == true && localPersistenceConfirmed == true { return true }
        guard status == .accepted, !needsReconciliation, let acknowledgement,
              let ack = try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: acknowledgement),
              (try? ack.validate(eventId: id, sourceWorkoutId: sourceWorkoutId, revision: revision)) != nil,
              (try? ack.validate(binding: binding, sets: operation == .delete ? [] : sets)) != nil else { return false }
        return !ack.needsSourceReview(revision: revision, deleting: operation == .delete, expectingHistoryOnly: isHistoryOnly)
    }
    func sameIntent(as other: WorkoutTrackerDelivery) -> Bool {
        id == other.id && sourceWorkoutId == other.sourceWorkoutId && installationId == other.installationId && origin == other.origin &&
            revision == other.revision && bytes == other.bytes && record == other.record && sets == other.sets && binding == other.binding &&
            (operation ?? .upsert) == (other.operation ?? .upsert) && recoveryOf == other.recoveryOf && reviewedManifest == other.reviewedManifest
    }
    var needsReconciliation: Bool {
        status == .accepted && acknowledgement.flatMap {
            try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: $0)
        }?.reconciliation.pending == true
    }
    var valid: Bool {
        (bytes?.count ?? 0) <= WorkoutSyncTransport.bodyLimit && revision > 0 && revision <= 9_007_199_254_740_991 && record.id.lowercased() == sourceWorkoutId.uuidString.lowercased()
            && recoveryOf != id
            && (reviewedManifest.map { (try? $0.validate()) != nil && $0.cycleId == binding.manifest.cycleId && $0.sessionId == binding.manifest.sessionId && $0.manifestRevision == writeManifestRevision } ?? true)
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
              (object["operation"] as? String) == (operation ?? .upsert).rawValue,
              object["projectionPolicy"] == nil || ["apply", "capture_only"].contains(object["projectionPolicy"] as? String ?? ""),
              !isHistoryOnly || (operation != .delete && (object["deletedSetIds"] as? [Any])?.isEmpty == true &&
                  (object["deletedOccurrenceIds"] == nil || (object["deletedOccurrenceIds"] as? [Any])?.isEmpty == true)) else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}

/// An owner-reviewed source-history correction. No current routine or canonical write is implied.
struct WorkoutTrackerHistoryReview: Identifiable {
    let id: UUID
    let original: WorkoutTrackerDelivery
    let accepted: WorkoutTrackerDelivery
    let capture: WorkoutTrackerCaptureSnapshot
    let checkedAt: Date

    static func validate(original: WorkoutTrackerDelivery, accepted: WorkoutTrackerDelivery,
                         capture: WorkoutTrackerCaptureSnapshot) throws {
        try original.validateBody(); try accepted.validateBody()
        guard original.valid, accepted.valid, original.localPersistenceConfirmed == true,
              original.operation != .delete, accepted.operation != .delete,
              accepted.hasVerifiedSourceReceipt,
              original.sourceWorkoutId == accepted.sourceWorkoutId, original.origin == accepted.origin,
              original.installationId == accepted.installationId,
              original.binding.connection == accepted.binding.connection,
              original.binding.connection?.origin == original.origin,
              original.binding.connection?.installationId == original.installationId,
              original.binding.manifest == accepted.binding.manifest,
              original.binding.planAtStart == accepted.binding.planAtStart,
              original.revision >= accepted.revision, capture.sourceRevision == accepted.revision,
              capture.nextCursor == nil, capture.readEvidence?.isEmpty == false, !capture.tombstone else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        // Unknown network outcomes must recover their exact original receipt first.
        let knownRejected = original.status == .review && original.acknowledgement == nil &&
            [.lifeRevisionConflict, .manifestConflict, .sessionRetired, .setRetired, .prescriptionInconsistent].contains(original.rejection)
        let neverSubmitted = [.ready, .review].contains(original.status) && original.submissionAttempted == false &&
            original.acknowledgement == nil && original.rejection == nil
        guard original.hasVerifiedSourceReceipt || neverSubmitted || knownRejected else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        try capture.validate(for: original.binding)
        try capture.validateKnownBindings(binding: original.binding)
        guard Set(accepted.sets.compactMap { UUID(uuidString: $0.id) }).isSubset(of: Set(capture.sets.map(\.sourceSetId))) else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        guard let bytes = original.bytes, let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              (object["deletedSetIds"] as? [Any])?.isEmpty == true,
              object["deletedOccurrenceIds"] == nil || (object["deletedOccurrenceIds"] as? [Any])?.isEmpty == true else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        guard let acceptedBytes = accepted.bytes,
              let acceptedObject = try JSONSerialization.jsonObject(with: acceptedBytes) as? [String: Any],
              let evidence = capture.readEvidence?.first,
              let remoteObject = try JSONSerialization.jsonObject(with: evidence) as? [String: Any],
              NSDictionary(dictionary: ["start": object["planAtStart"] ?? NSNull()]).isEqual(to: ["start": acceptedObject["planAtStart"] ?? NSNull()]),
              NSDictionary(dictionary: ["start": object["planAtStart"] ?? NSNull()]).isEqual(to: ["start": remoteObject["planAtStart"] ?? NSNull()]) else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
    }

    func replacement(eventId: UUID = UUID()) throws -> WorkoutTrackerDelivery {
        try Self.validate(original: original, accepted: accepted, capture: capture)
        guard let bytes = original.bytes, var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              original.revision < 9_007_199_254_740_991, eventId != original.id else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        object["eventId"] = eventId.uuidString.lowercased()
        object["sourceRevision"] = original.revision + 1
        object["baseLifeRevision"] = capture.lifeRevision
        object["projectionPolicy"] = "capture_only"
        object["deletedSetIds"] = []
        let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        var result = WorkoutTrackerDelivery(id: eventId, sourceWorkoutId: original.sourceWorkoutId,
            installationId: original.installationId, origin: original.origin, revision: original.revision + 1,
            bytes: body, record: original.record, sets: original.sets, binding: original.binding)
        result.status = .ready; result.localPersistenceConfirmed = true; result.paused = true
        result.submissionAttempted = false
        result.createdAt = Date(); result.recoveryOf = original.id; result.reviewedManifest = original.reviewedManifest
        result.message = "History-only correction prepared locally. Not sent; website sets and progression will not be updated."
        guard result.valid else { throw WorkoutTrackerContractError.invalidSnapshot }
        try result.validateBody()
        return result
    }
}

/// A review is ephemeral; it is not a new recording, receipt or upload permission.
struct WorkoutTrackerRecoveryReview: Identifiable {
    let id: UUID
    let original: WorkoutTrackerDelivery
    let comparison: WorkoutTrackerReviewComparison
    var priorManifest: WorkoutTrackerManifest { original.reviewedManifest ?? original.binding.manifest }
    var prescriptionChanged: Bool { original.writeManifestRevision != comparison.manifest.manifestRevision }

    static func validate(original: WorkoutTrackerDelivery, comparison: WorkoutTrackerReviewComparison) throws {
        try original.validateBody()
        guard original.valid, original.localPersistenceConfirmed == true, original.status == .review,
              [.lifeRevisionConflict, .manifestConflict].contains(original.rejection), original.acknowledgement == nil,
              original.binding.connection?.origin == original.origin,
              original.binding.connection?.installationId == original.installationId,
              original.writeManifestRevision != nil, original.operation != .delete else { throw WorkoutTrackerContractError.invalidSnapshot }
        guard (original.reviewedManifest ?? original.binding.manifest).manifestRevision == original.writeManifestRevision else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        let frozen = original.binding.manifest, current = comparison.manifest
        try current.validate()
        guard current.cycleId == frozen.cycleId, current.sessionId == frozen.sessionId,
              current.sessionKey == frozen.sessionKey,
              current.ownership != nil,
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
                  remote.ownership == current.ownership,
                  remote.nextCursor == nil, remote.lifeRevision == current.lifeRevision, remote.sourceRevision < original.revision else {
                throw WorkoutTrackerContractError.invalidSnapshot
            }
            try remote.validateKnownBindings(binding: original.binding)
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
        result.submissionAttempted = false
        result.paused = true; result.createdAt = Date(); result.recoveryOf = original.id
        result.reviewedManifest = comparison.manifest
        result.message = "Reviewed delivery prepared locally. Not sent; open this delivery to send its exact event."
        guard result.valid else { throw WorkoutTrackerContractError.invalidSnapshot }
        try result.validateBody()
        return result
    }
}
