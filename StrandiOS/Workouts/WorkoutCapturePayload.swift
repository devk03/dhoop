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
    struct Occurrence: Encodable {
        let sourceOccurrenceId: String
        let sessionExerciseId: Int
        let programSlotId: Int?
        let slotKey: String?
        let exerciseKey: String
        let executionOrder: Int
        let sets: [WorkoutSetObservation]
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

    static func make(record: LiftSessionRow, sets: [LiftSetRow], binding: WorkoutTrackerCaptureBinding,
                     installationId: UUID, revision: Int, eventId: UUID = UUID(),
                     heartRateEvidence: [UUID: WorkoutObservedHeartRate] = [:]) throws -> WorkoutCapturePayload {
        try binding.validate()
        guard UUID(uuidString: record.id) == binding.sourceWorkoutId, revision > 0,
              sets.allSatisfy({ $0.sessionId == record.id && $0.deviceId == record.deviceId }),
              let end = record.endTs, end >= record.startTs else { throw WorkoutTrackerContractError.invalidSnapshot }
        if let rpe = record.sessionRpe, !rpe.isFinite || !(0...10).contains(rpe) { throw WorkoutTrackerContractError.invalidSnapshot }
        let ids = Set(sets.map(\.id))
        guard ids.count == sets.count else { throw WorkoutTrackerContractError.invalidSnapshot }
        let known = Set(binding.occurrences.flatMap(\.sets).map { $0.sourceSetId.uuidString.lowercased() })
        // Additional sets need an explicit occurrence binding; never attach them by a display name.
        guard ids.isSubset(of: known) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let formatter = ISO8601DateFormatter()
        func date(_ seconds: Int) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(seconds))) }
        var occurrences: [Occurrence] = []
        for (order, identity) in binding.occurrences.enumerated() {
            guard let prescribed = binding.manifest.exerciseOccurrences.first(where: { $0.sessionExerciseId == identity.sessionExerciseId }) else {
                throw WorkoutTrackerContractError.invalidSnapshot
            }
            var observations: [WorkoutSetObservation] = []
            for set in identity.sets {
                guard let row = sets.first(where: { UUID(uuidString: $0.id) == set.sourceSetId }) else { continue }
                var observed = WorkoutSetObservation(sourceSetId: set.sourceSetId,
                    setType: row.isWarmup ? .warmup : .work,
                    loadBasis: try basis(prescribed.loadBasis))
                observed.lifeSetId = .value(set.lifeSetId)
                observed.completed = (row.reps ?? 0) > 0
                observed.loadKg = row.weightKg.map(WorkoutObservationPatch.value) ?? .clear
                observed.reps = row.reps.map(WorkoutObservationPatch.value) ?? .clear
                observed.rpe = row.rpe.map(WorkoutObservationPatch.value) ?? .clear
                observed.startedAt = row.startTs.map { .value(date($0)) } ?? .clear
                observed.endedAt = row.endTs.map { .value(date($0)) } ?? .clear
                if let evidence = heartRateEvidence[set.sourceSetId] {
                    observed.heartRateSummary = .value(evidence)
                }
                observed.executionOrder = row.ord
                try observed.validate()
                observations.append(observed)
            }
            occurrences.append(Occurrence(sourceOccurrenceId: identity.sourceOccurrenceId.uuidString.lowercased(),
                sessionExerciseId: identity.sessionExerciseId, programSlotId: prescribed.programSlotId,
                slotKey: prescribed.slotKey, exerciseKey: prescribed.exerciseKey,
                executionOrder: order, sets: observations))
        }
        return WorkoutCapturePayload(eventId: eventId.uuidString.lowercased(), sourceWorkoutId: binding.sourceWorkoutId.uuidString.lowercased(),
            installationId: installationId.uuidString.lowercased(), sourceRevision: revision, operation: "upsert",
            baseLifeRevision: binding.manifest.lifeRevision, manifestRevision: binding.manifest.manifestRevision,
            binding: Binding(cycleId: binding.manifest.cycleId, sessionId: binding.manifest.sessionId),
            session: Session(title: record.programName ?? binding.manifest.title, status: "completed",
                startedAt: date(record.startTs), endedAt: date(end), timeZone: binding.timeZone, notes: record.note, rpe: record.sessionRpe),
            exerciseOccurrences: occurrences, deletedSetIds: [])
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
        let session: Session
        let sets: [String: Int]
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

    func validate(eventId: UUID, sourceWorkoutId: UUID, revision: Int) throws {
        guard schemaVersion == 1, self.eventId == eventId, self.sourceWorkoutId == sourceWorkoutId,
              acceptedSourceRevision >= revision, lifeRevision >= receiptLifeRevision, receiptLifeRevision >= 0,
              ["done", "pending", "not_pending", "not_applicable"].contains(reconciliation.state),
              ["applied", "duplicate", "stale", "manual_preserved", "deleted"].contains(outcome) else {
            throw WorkoutSyncTransportError.invalidResponse
        }
    }
    func validate(binding: WorkoutTrackerCaptureBinding, sets: [LiftSetRow]) throws {
        guard mappings.session.kind == "programmed", mappings.session.cycleId == binding.manifest.cycleId,
              mappings.session.sessionId == binding.manifest.sessionId else { throw WorkoutSyncTransportError.invalidResponse }
        let prescribed = Dictionary(uniqueKeysWithValues: binding.occurrences.flatMap(\.sets).map {
            ($0.sourceSetId.uuidString.lowercased(), $0.lifeSetId)
        })
        for row in sets {
            guard let expected = prescribed[row.id.lowercased()], mappings.sets[row.id.lowercased()] == expected else {
                throw WorkoutSyncTransportError.invalidResponse
            }
        }
    }
}
