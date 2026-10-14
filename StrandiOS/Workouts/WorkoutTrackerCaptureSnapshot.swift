import Foundation

/// A consistent read of source observations and canonical projections; these are different facts.
struct WorkoutTrackerCaptureSnapshot: Decodable {
    struct Binding: Decodable { let kind: String; let cycleId: Int?; let sessionId: Int? }
    struct Session: Decodable { let title: String?; let status: String?; let notes: String?; let rpe: Double?; let timeZone: String }
    struct Owner: Decodable { let origin: String; let sourceWorkoutId: UUID? }
    struct Observation: Decodable {
        struct Metadata: Decodable { let name: String?; let loadMode: String? }
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
    struct Projection: Decodable {
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
    struct SetObservation: Decodable, Identifiable {
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
    let projectionPolicy: String
    let projectionState: String
    var sets: [SetObservation]
    let nextCursor: Int?

    func validate(for capture: WorkoutTrackerCaptureBinding) throws {
        guard schemaVersion == 1, sourceWorkoutId == capture.sourceWorkoutId, sourceRevision > 0,
              lifeRevision >= 0, binding.kind == "programmed", binding.cycleId == capture.manifest.cycleId,
              binding.sessionId == capture.manifest.sessionId, TimeZone(identifier: session.timeZone) != nil,
              ["apply", "capture_only"].contains(projectionPolicy), ["current", "retired", "capture_only"].contains(projectionState),
              sets.count <= 200, Set(sets.map(\.sourceSetId)).count == sets.count,
              nextCursor.map({ $0 >= 0 }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
        for set in sets {
            guard !set.exerciseKey.isEmpty, ["warmup", "work"].contains(set.setType),
                  set.raw.sourceSetId == nil || set.raw.sourceSetId == set.sourceSetId,
                  set.raw.loadKg.map({ $0.isFinite && (0...2267).contains($0) }) ?? true,
                  set.raw.rpe.map({ $0.isFinite && (0...10).contains($0) }) ?? true else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
    }
}
