import Foundation

/// Life owns inference and nightly recomputation. Native stores only an explicit preference edit.
struct WorkoutProgressionPreference: Codable, Equatable {
    enum Mode: String, Codable { case auto, manual }
    let mode: Mode
    let repMin: Int?
    let repMax: Int?
    let targetRir: Int
    func validate() throws {
        guard (0...5).contains(targetRir), (repMin == nil) == (repMax == nil),
              mode != .manual || repMin != nil else { throw WorkoutTrackerContractError.invalidSnapshot }
        if let low = repMin, let high = repMax {
            guard (1...30).contains(low), (low...30).contains(high) else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
    }
}

struct WorkoutProgressionPreferenceDraft: Equatable {
    var automatic: Bool
    var minimum: Int
    var maximum: Int
    var targetRIR: Int
    init(exercise: WorkoutTrackerDashboard.Exercise) {
        let preference = exercise.progressionPreference
        automatic = preference?.mode != .manual
        let fallback = min(30, max(1, exercise.plannedReps))
        let low = preference?.repMin ?? exercise.repMin ?? fallback
        let high = preference?.repMax ?? exercise.repMax ?? fallback
        let validRange = (1...30).contains(low) && (1...30).contains(high) && low <= high
        minimum = validRange ? low : fallback
        maximum = validRange ? high : fallback
        targetRIR = preference?.targetRir ?? (exercise.targetRir.isFinite && (0...5).contains(exercise.targetRir) ? Int(exercise.targetRir.rounded()) : 2)
    }
    func command(mesocycleId: Int, sessionExerciseId: Int) throws -> [String: WorkoutTrackerValue] {
        let value = WorkoutProgressionPreference(mode: automatic ? .auto : .manual,
            repMin: automatic ? nil : minimum, repMax: automatic ? nil : maximum, targetRir: targetRIR)
        try value.validate()
        guard mesocycleId > 0, sessionExerciseId > 0 else { throw WorkoutTrackerContractError.invalidSnapshot }
        var result: [String: WorkoutTrackerValue] = ["action": .string("update_progression_preferences"),
            "mesocycleId": .number(Double(mesocycleId)), "sessionExerciseId": .number(Double(sessionExerciseId)),
            "mode": .string(value.mode.rawValue), "targetRir": .number(Double(targetRIR))]
        if !automatic { result["repMin"] = .number(Double(minimum)); result["repMax"] = .number(Double(maximum)) }
        return result
    }
}
