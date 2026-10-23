import Foundation

/// One server-resolved comparison. No prescription values or local history search are involved.
struct WorkoutPreviousSetPage: Codable, Equatable {
    struct Current: Codable, Equatable {
        let mesocycleId: Int
        let sessionId: Int
        let weekNumber: Int
        let sessionKey: String
        let sessionExerciseId: Int
        let setId: Int
        let slotKey: String?
        let exerciseKey: String
        let loadMode: String
        let setType: String
        let setNumber: Int
    }
    struct Previous: Codable, Equatable {
        let mesocycleId: Int
        let sessionId: Int
        let title: String
        let weekNumber: Int
        let scheduledDate: String
        let completedAt: String
        let sessionExerciseId: Int
        let setId: Int
        let slotKey: String?
        let exerciseKey: String
        let loadMode: String
        let setType: String
        let setNumber: Int
        let actualLoad: Double?
        let actualReps: Int
        let loadUnit: String?
        let loadBasis: String
        let measurementKind: String
        var rir: Double? = nil
    }
    let schemaVersion: Int
    let lifeRevision: Int
    let view: String
    let comparison: String
    let current: Current
    let previousWeekNumber: Int?
    let availability: String
    let unavailableReason: String?
    let previous: Previous?

    func validate(session: WorkoutTrackerDashboard.Session, exercise: WorkoutTrackerDashboard.Exercise,
                  set: WorkoutTrackerDashboard.SetLog) throws {
        guard schemaVersion == 1, lifeRevision >= 0, view == "previous_set", comparison == "previous_program_week",
              current.mesocycleId == session.mesocycleId, current.sessionId == session.id,
              current.weekNumber == session.weekNumber, current.sessionKey == session.sessionKey,
              current.sessionExerciseId == exercise.id, current.exerciseKey == exercise.exerciseKey,
              current.loadMode == exercise.loadMode, current.slotKey == (exercise.slotKey.isEmpty ? nil : exercise.slotKey),
              current.setId == set.id, current.setType == set.setType, current.setNumber == set.setNumber,
              previousWeekNumber == (session.weekNumber > 1 ? session.weekNumber - 1 : nil)
        else { throw WorkoutTrackerContractError.invalidSnapshot }
        if availability == "unavailable" {
            guard previous == nil, unavailableReason?.isEmpty == false else { throw WorkoutTrackerContractError.invalidSnapshot }
            return
        }
        guard availability == "available", unavailableReason == nil, let previous, let mode = WorkoutTrackerLoadMode(rawValue: current.loadMode),
              session.weekNumber > 1, previous.weekNumber == previousWeekNumber,
              previous.mesocycleId == current.mesocycleId, previous.sessionId > 0, previous.sessionId != current.sessionId,
              previous.sessionExerciseId > 0, previous.setId > 0, previous.setId != current.setId,
              previous.slotKey != nil, previous.slotKey == current.slotKey,
              previous.exerciseKey == current.exerciseKey, previous.loadMode == current.loadMode,
              previous.setType == current.setType, previous.setNumber == current.setNumber,
              previous.actualReps >= 0, previous.scheduledDate.count == 10,
              previous.rir.map({ $0.isFinite && (0...5).contains($0) && $0.rounded() == $0 }) ?? true,
              previous.loadBasis == mode.loadBasis,
              previous.measurementKind == (mode.hasMass ? "mass_reps" : mode == .duration ? "duration" : "bodyweight_reps"),
              mode.hasMass ? (previous.loadUnit == "lb" && previous.actualLoad.map { $0.isFinite && $0 >= 0 } == true)
                  : (previous.loadUnit == nil && previous.actualLoad == nil)
        else { throw WorkoutTrackerContractError.invalidSnapshot }
    }

    func report(exerciseName: String, system: UnitSystem) -> WorkoutPreviousSetReport {
        guard let previous, availability == "available" else {
            return .init(exerciseName: exerciseName, setLabel: "Set \(current.setNumber)",
                weekLabel: previousWeekNumber.map { "Program week \($0)" } ?? "First program week",
                workoutTitle: nil, dateLabel: nil, completionLabel: nil, result: nil, loadDetail: nil,
                unavailable: unavailableExplanation)
        }
        let result: String
        if let load = previous.actualLoad {
            let mass = (load / (system == .imperial ? 1 : UnitFormatter.poundsPerKilogram))
                .formatted(.number.precision(.fractionLength(0...2)))
            result = "\(mass) \(system == .imperial ? "lb" : "kg") × \(previous.actualReps) reps"
        } else if previous.measurementKind == "duration" {
            result = "\(previous.actualReps) seconds"
        } else { result = "\(previous.actualReps) reps" }
        let detail: String
        switch previous.loadBasis {
        case "per_hand": detail = "Weight per hand"
        case "added": detail = "Added weight · body weight excluded"
        case "none": detail = previous.measurementKind == "duration" ? "Recorded duration" : "Bodyweight exercise"
        default: detail = "Total weight"
        }
        let completed = ISO8601DateFormatter().date(from: previous.completedAt)
            ?? ISO8601DateFormatter.withFractionalSeconds.date(from: previous.completedAt)
        return .init(exerciseName: exerciseName, setLabel: "Set \(previous.setNumber) · \(previous.setType.capitalized)",
            weekLabel: "Program week \(previous.weekNumber)", workoutTitle: previous.title,
            dateLabel: "Scheduled \(previous.scheduledDate)",
            completionLabel: completed.map { "Completed \($0.formatted(date: .abbreviated, time: .shortened))" },
            result: result, loadDetail: detail, unavailable: nil,
            rirLabel: previous.rir.map { "RIR \($0.formatted(.number.precision(.fractionLength(0))))" })
    }

    private var unavailableExplanation: String {
        switch unavailableReason {
        case "first_program_week": return "This is the first week of the program. There is no previous program week to compare."
        case "previous_session_not_completed", "set_not_completed": return "Last week's matching workout or set has not been marked complete in Life."
        case "exercise_changed", "load_mode_changed": return "The exercise or weight basis changed. Last week's set is not directly comparable."
        case "actuals_missing", "actuals_invalid": return "Last week's set has no usable recorded weight and reps. Planned targets are not shown as results."
        case "previous_session_missing", "previous_set_missing": return "No matching set was recorded in the previous program week. Older weeks are not substituted."
        case "unsupported_load_mode": return "Previous results are not available for this measurement type."
        default: return "No comparable recorded result is available for this set in the previous program week."
        }
    }
}

private extension ISO8601DateFormatter {
    static var withFractionalSeconds: ISO8601DateFormatter {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }
}
