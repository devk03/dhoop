import Foundation

enum WorkoutTrackerContractError: LocalizedError {
    case invalidSnapshot, unavailableCapture
    var errorDescription: String? {
        switch self {
        case .invalidSnapshot: return "The tracker returned an inconsistent workout snapshot. Refresh before starting."
        case .unavailableCapture: return "This tracker workout already has observations. Review it before starting another capture."
        }
    }
}

enum WorkoutTrackerLoadMode: String, Codable {
    case barbell, machine, dumbbellEach = "dumbbell_each", bodyweightAdded = "bodyweight_added", bodyweight, duration
    var loadBasis: String {
        switch self {
        case .dumbbellEach: return "per_hand"
        case .bodyweightAdded: return "added"
        case .bodyweight, .duration: return "none"
        default: return "total"
        }
    }
    var hasMass: Bool { loadBasis != "none" }
}

struct WorkoutTrackerIndex: Codable, Equatable {
    struct Cycle: Codable, Equatable { let id: Int; let name: String; let status: String }
    struct Session: Codable, Equatable, Identifiable {
        var id: Int { sessionId }
        let sessionId: Int
        let block: Int
        let sessionKey: String
        let title: String
        let status: String
        let scheduledDate: String?
    }
    let schemaVersion: Int
    let cycle: Cycle?
    let sessions: [Session]
    let lifeRevision: Int
    let nextCursor: Int?
    func validate() throws {
        guard schemaVersion == 1, lifeRevision >= 0, sessions.count <= 600,
              Set(sessions.map(\.sessionId)).count == sessions.count,
              sessions.allSatisfy({ $0.sessionId > 0 && !$0.title.isEmpty && $0.title.count <= 200 }),
              nextCursor.map({ $0 > (sessions.last?.sessionId ?? 0) - 1 }) ?? true,
              (cycle?.id ?? 1) > 0 else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}

struct WorkoutTrackerManifest: Codable, Equatable {
    struct PlannedSet: Codable, Equatable {
        let lifeSetId: Int
        let setNumber: Int
        let setType: String
        let plannedLoad: Double?
        let plannedReps: Int?
        let loadOverride: Bool
        let repsOverride: Bool
        let actualLoad: Double?
        let actualReps: Int?
        let rir: Int?
        let completed: Bool
    }
    struct Occurrence: Codable, Equatable {
        let sessionExerciseId: Int
        let programSlotId: Int?
        let slotKey: String?
        let exerciseKey: String
        let originalExerciseKey: String
        let name: String
        let order: Int
        let measurementKind: String
        let loadMode: WorkoutTrackerLoadMode
        let loadBasis: String
        let unit: String?
        let targetRir: Int?
        let restTargetSeconds: Int?
        let sets: [PlannedSet]

        func kilograms(for set: PlannedSet) throws -> Double? {
            guard loadMode.hasMass else { return nil }
            guard let amount = set.plannedLoad else { return nil }
            guard amount.isFinite, amount >= 0 else { throw WorkoutTrackerContractError.invalidSnapshot }
            switch unit {
            case "lb": return amount * 0.45359237
            case "kg": return amount
            default: throw WorkoutTrackerContractError.invalidSnapshot
            }
        }
    }
    let schemaVersion: Int
    let cycleId: Int
    let sessionId: Int
    let sessionKey: String
    let title: String
    let scheduledDate: String?
    let status: String
    let manifestRevision: String
    let lifeRevision: Int
    let exerciseOccurrences: [Occurrence]
    let sourceWorkoutId: String?

    var hasObservations: Bool {
        sourceWorkoutId != nil || exerciseOccurrences.contains { $0.sets.contains { $0.completed || $0.actualLoad != nil || $0.actualReps != nil || $0.rir != nil } }
    }

    func validate() throws {
        let sets = exerciseOccurrences.flatMap(\.sets)
        guard schemaVersion == 1, cycleId > 0, sessionId > 0, lifeRevision >= 0,
              !manifestRevision.isEmpty, manifestRevision.count <= 100,
              !title.isEmpty, title.count <= 200, exerciseOccurrences.count <= 50, sets.count <= 200,
              Set(exerciseOccurrences.map(\.sessionExerciseId)).count == exerciseOccurrences.count,
              Set(sets.map(\.lifeSetId)).count == sets.count,
              sets.allSatisfy({ $0.lifeSetId > 0 && $0.setNumber > 0 && ["warmup", "work"].contains($0.setType) && ($0.plannedReps ?? 0) >= 0 }),
              exerciseOccurrences.allSatisfy({ $0.sessionExerciseId > 0 && !$0.name.isEmpty && $0.name.count <= 200 && !$0.exerciseKey.isEmpty && $0.loadBasis == $0.loadMode.loadBasis })
        else { throw WorkoutTrackerContractError.invalidSnapshot }
        for occurrence in exerciseOccurrences {
            for set in occurrence.sets { _ = try occurrence.kilograms(for: set) }
        }
    }
}

/// Exact IDs and prescription snapshot, retained when the connection or app process disappears.
struct WorkoutTrackerCaptureBinding: Codable, Equatable {
    struct Connection: Codable, Equatable {
        let origin: String
        let installationId: UUID
    }
    struct Occurrence: Codable, Equatable {
        let sourceOccurrenceId: UUID
        let sessionExerciseId: Int
        let sets: [SetBinding]
    }
    struct SetBinding: Codable, Equatable {
        let sourceSetId: UUID
        let lifeSetId: Int
        let slotIndex: Int
    }
    let sourceWorkoutId: UUID
    let manifest: WorkoutTrackerManifest
    let timeZone: String
    let connection: Connection?
    let occurrences: [Occurrence]

    init(manifest: WorkoutTrackerManifest, timeZone: String = TimeZone.current.identifier, connection: Connection? = nil) throws {
        try manifest.validate()
        guard !manifest.hasObservations, manifest.status == "planned" else { throw WorkoutTrackerContractError.unavailableCapture }
        guard TimeZone(identifier: timeZone) != nil else { throw WorkoutTrackerContractError.invalidSnapshot }
        self.sourceWorkoutId = UUID(); self.manifest = manifest; self.timeZone = timeZone; self.connection = connection
        self.occurrences = manifest.exerciseOccurrences.map { occurrence in
            Occurrence(sourceOccurrenceId: UUID(), sessionExerciseId: occurrence.sessionExerciseId,
                sets: occurrence.sets.enumerated().map { SetBinding(sourceSetId: UUID(), lifeSetId: $0.element.lifeSetId, slotIndex: $0.offset + 1) })
        }
    }

    func validate() throws {
        try manifest.validate()
        guard TimeZone(identifier: timeZone) != nil, occurrences.count == manifest.exerciseOccurrences.count,
              occurrences.map(\.sessionExerciseId) == manifest.exerciseOccurrences.map(\.sessionExerciseId),
              Set(occurrences.map(\.sourceOccurrenceId)).count == occurrences.count else { throw WorkoutTrackerContractError.invalidSnapshot }
        var ids: Set<UUID> = []
        for occurrence in occurrences {
            guard let prescribed = manifest.exerciseOccurrences.first(where: { $0.sessionExerciseId == occurrence.sessionExerciseId }),
                  occurrence.sets.count == prescribed.sets.count,
                  Set(occurrence.sets.map(\.slotIndex)).count == occurrence.sets.count else { throw WorkoutTrackerContractError.invalidSnapshot }
            for set in occurrence.sets {
                guard set.slotIndex > 0, set.slotIndex <= prescribed.sets.count,
                      prescribed.sets.contains(where: { $0.lifeSetId == set.lifeSetId }), ids.insert(set.sourceSetId).inserted else {
                    throw WorkoutTrackerContractError.invalidSnapshot
                }
            }
        }
    }
}
