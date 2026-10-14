import Foundation

/// Read evidence only. Creating this value neither replaces a delivery nor authorizes a write.
struct WorkoutTrackerReviewComparison {
    let manifest: WorkoutTrackerManifest
    let capture: WorkoutTrackerCaptureSnapshot?
    let checkedAt: Date
}

/// A consistent read of source observations and canonical projections; these are different facts.
struct WorkoutTrackerCaptureSnapshot: Decodable, Equatable {
    struct Binding: Decodable, Equatable { let kind: String; let cycleId: Int?; let sessionId: Int? }
    struct Session: Decodable, Equatable { let title: String?; let status: String?; let notes: String?; let rpe: Double?; let timeZone: String }
    typealias Owner = WorkoutTrackerManifest.Owner
    struct Occurrence: Decodable, Equatable {
        struct Metadata: Decodable, Equatable { let deleted: Bool?; let replacesSourceOccurrenceId: UUID? }
        let kind: String
        let sessionExerciseId: Int?
        let programSlotId: Int?
        let slotKey: String?
        let exerciseKey: String
        let loadMode: String
        let raw: Metadata
    }
    struct Observation: Decodable, Equatable {
        struct Metadata: Decodable, Equatable { let name: String?; let loadMode: String? }
        let sourceSetId: UUID?
        let completed: Bool?
        let loadKg: Double?
        let loadBasis: String?
        let reps: Int?
        let rpe: Double?
        let notes: String?
        let startedAt: String?
        let endedAt: String?
        let deleted: Bool?
        let occurrence: Metadata?
    }
    struct Projection: Decodable, Equatable {
        let loadLb: Double?
        let reps: Int?
        let rir: Int?
        let completed: Bool?
        enum CodingKeys: String, CodingKey { case loadLb = "actual_load", reps = "actual_reps", rir, completed }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            loadLb = try c.decodeIfPresent(Double.self, forKey: .loadLb)
            reps = try c.decodeIfPresent(Int.self, forKey: .reps)
            rir = try c.decodeIfPresent(Int.self, forKey: .rir)
            if let boolean = try? c.decode(Bool.self, forKey: .completed) { completed = boolean }
            else if let number = try c.decodeIfPresent(Int.self, forKey: .completed), (0...1).contains(number) { completed = number == 1 }
            else if try c.decodeIfPresent(Int.self, forKey: .completed) == nil { completed = nil }
            else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
    }
    struct SetObservation: Decodable, Equatable, Identifiable {
        var id: UUID { sourceSetId }
        let sourceSetId: UUID
        let sourceOccurrenceId: UUID
        let sessionExerciseId: Int?
        let lifeSetId: Int?
        let exerciseKey: String
        let setType: String
        let raw: Observation
        let projection: Projection?
    }
    let schemaVersion: Int
    let sourceWorkoutId: UUID
    let sourceRevision: Int
    let lifeRevision: Int
    let binding: Binding
    let tombstone: Bool
    let session: Session
    let ownership: [String: Owner]
    var occurrences: [String: Occurrence]? = nil
    let projectionPolicy: String
    let projectionState: String
    var sets: [SetObservation]
    let nextCursor: Int?
    // Full canonical response evidence is ephemeral. It includes fields not rendered by the UI
    // so a review cannot overlook a change to accepted provenance or another raw observation.
    var readEvidence: [Data]? = nil

    func validate(for capture: WorkoutTrackerCaptureBinding) throws {
        guard schemaVersion == 1, sourceWorkoutId == capture.sourceWorkoutId, sourceRevision > 0,
              lifeRevision >= 0, binding.kind == "programmed", binding.cycleId == capture.manifest.cycleId,
              binding.sessionId == capture.manifest.sessionId, TimeZone(identifier: session.timeZone) != nil,
              ["apply", "capture_only"].contains(projectionPolicy), ["current", "retired", "capture_only"].contains(projectionState),
              sets.count <= 200, Set(sets.map(\.sourceSetId)).count == sets.count,
              (occurrences?.count ?? 0) <= 50,
              occurrences?.keys.allSatisfy({ UUID(uuidString: $0) != nil }) ?? true,
              nextCursor.map({ $0 >= 0 }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
        for set in sets {
            guard !set.exerciseKey.isEmpty, ["warmup", "work"].contains(set.setType),
                  set.raw.sourceSetId == nil || set.raw.sourceSetId == set.sourceSetId,
                  set.raw.loadKg.map({ $0.isFinite && (0...2267).contains($0) }) ?? true,
                  set.raw.rpe.map({ $0.isFinite && (0...10).contains($0) }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
    }

    /// Accepted source identity is checked against captured UUID bindings, never display names.
    func validateKnownBindings(binding: WorkoutTrackerCaptureBinding) throws {
        let remote = self
        guard let remoteOccurrences = remote.occurrences else { throw WorkoutTrackerContractError.invalidSnapshot }
        for (key, observed) in remoteOccurrences {
            guard let id = UUID(uuidString: key), observed.raw.deleted != true else { throw WorkoutTrackerContractError.invalidSnapshot }
            if let occurrence = binding.occurrences.first(where: { $0.sourceOccurrenceId == id }),
               let prescribed = binding.manifest.exerciseOccurrences.first(where: { $0.sessionExerciseId == occurrence.sessionExerciseId }) {
                guard observed.kind == "prescribed", observed.sessionExerciseId == occurrence.sessionExerciseId,
                      observed.programSlotId == prescribed.programSlotId, observed.slotKey == prescribed.slotKey,
                      observed.exerciseKey == prescribed.exerciseKey, observed.loadMode == prescribed.loadMode.rawValue else {
                    throw WorkoutTrackerContractError.invalidSnapshot
                }
            } else if let extra = binding.additionalOccurrences?.first(where: { $0.sourceOccurrenceId == id }) {
                guard observed.kind == "actual_only", observed.sessionExerciseId == nil, observed.exerciseKey == extra.exerciseKey,
                      observed.loadMode == extra.loadMode.rawValue, observed.raw.replacesSourceOccurrenceId == extra.replacesSourceOccurrenceId else {
                    throw WorkoutTrackerContractError.invalidSnapshot
                }
            } else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
        for set in remote.sets {
            guard set.raw.deleted != true else { throw WorkoutTrackerContractError.invalidSnapshot }
            if let occurrence = binding.occurrences.first(where: { $0.sourceOccurrenceId == set.sourceOccurrenceId }),
               let identity = occurrence.sets.first(where: { $0.sourceSetId == set.sourceSetId }),
               let prescribed = binding.manifest.exerciseOccurrences.first(where: { $0.sessionExerciseId == occurrence.sessionExerciseId }) {
                guard identity.lifeSetId == set.lifeSetId, occurrence.sessionExerciseId == set.sessionExerciseId,
                      prescribed.exerciseKey == set.exerciseKey,
                      set.raw.loadBasis.map({ $0 == prescribed.loadBasis }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
            } else if let extra = binding.additionalOccurrences?.first(where: { $0.sourceOccurrenceId == set.sourceOccurrenceId }) {
                guard extra.sets.contains(where: { $0.sourceSetId == set.sourceSetId }), set.lifeSetId == nil,
                      set.sessionExerciseId == nil, set.exerciseKey == extra.exerciseKey,
                      set.raw.loadBasis.map({ $0 == extra.loadMode.loadBasis }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
            } else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
    }
}
