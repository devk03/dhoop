import Foundation

/// A durable edit buffer. Prescription values are hints, never performed work.
struct WorkoutInlineSetDraft: Codable, Equatable {
    let baseline: WorkoutTrackerDashboard.SetLog
    let massScale: Double
    let localeIdentifier: String
    var load: String
    var reps: String
    var rir: String
    var completed: Bool

    init(row: WorkoutTrackerDashboard.SetLog, massScale: Double, locale: Locale = .current) {
        baseline = row; self.massScale = massScale; localeIdentifier = locale.identifier; completed = row.completed
        func text(_ value: Double?) -> String {
            value.map { $0.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...8))) } ?? ""
        }
        load = text(row.actualLoad.map { $0 / massScale })
        reps = row.actualReps.map(String.init) ?? ""
        rir = text(row.rir)
    }
    var isDirty: Bool { self != Self(row: baseline, massScale: massScale, locale: Locale(identifier: localeIdentifier)) }
    func conflicts(with row: WorkoutTrackerDashboard.SetLog) -> Bool { isDirty && row != baseline }

    func command(sessionID: Int, programID: Int, mode: WorkoutTrackerLoadMode, completed: Bool, locale: Locale = .current) throws -> [String: WorkoutTrackerValue] {
        let initial = Self(row: baseline, massScale: massScale, locale: Locale(identifier: localeIdentifier))
        var result: [String: WorkoutTrackerValue] = ["action": .string("update_set"),
            "sessionId": .number(Double(sessionID)), "mesocycleId": .number(Double(programID)),
            "setId": .number(Double(baseline.id))]
        if !completed && baseline.completed {
            // Life's uncheck operation clears all performed values, including omitted fields.
            result["completed"] = .bool(false)
            if mode.hasMass { result["actualLoad"] = .null }
            if mode != .duration { result["actualReps"] = .null; result["rir"] = .null }
            return result
        }
        if !completed && [load, reps, rir].contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw NeedsCompletion()
        }
        func number(_ text: String, range: ClosedRange<Double>, integer: Bool = false, scale: Double = 1) throws -> WorkoutTrackerValue {
            let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { return .null }
            guard let value = try? Double(input, format: .number.locale(locale)), value.isFinite,
                  scale.isFinite, scale > 0, range.contains(value * scale), !integer || value.rounded() == value else {
                throw Invalid()
            }
            return .number(value * scale)
        }
        if mode.hasMass, load != initial.load { result["actualLoad"] = try number(load, range: 0...5000, scale: massScale) }
        if mode != .duration {
            if reps != initial.reps { result["actualReps"] = try number(reps, range: 0...100, integer: true) }
            if rir != initial.rir { result["rir"] = try number(rir, range: 0...5, integer: true) }
        }
        if completed != baseline.completed { result["completed"] = .bool(completed) }
        guard result.count > 4 else { throw Invalid() }
        return result
    }
    func rebased(from anchor: Self, onto row: WorkoutTrackerDashboard.SetLog) -> Self {
        var result = Self(row: row, massScale: massScale, locale: Locale(identifier: localeIdentifier))
        if load != anchor.load { result.load = load }
        if reps != anchor.reps { result.reps = reps }
        if rir != anchor.rir { result.rir = rir }
        if completed != anchor.completed { result.completed = completed }
        return result
    }
    struct NeedsCompletion: LocalizedError {
        var errorDescription: String? { "Mark sets with entered results as done before saving the workout. Your input is saved on this phone." }
    }
    struct Invalid: LocalizedError {
        var errorDescription: String? { "Enter valid weight, whole repetitions (0–100), and optional RIR (0–5), or clear an actual value." }
    }
}
