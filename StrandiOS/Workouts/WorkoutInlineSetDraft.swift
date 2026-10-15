import Foundation

/// A transient edit buffer. Prescription values are hints, never performed work.
struct WorkoutInlineSetDraft: Equatable {
    let baseline: WorkoutTrackerDashboard.SetLog
    let massScale: Double
    var load: String
    var reps: String
    var rir: String

    init(row: WorkoutTrackerDashboard.SetLog, massScale: Double) {
        baseline = row; self.massScale = massScale
        func text(_ value: Double?) -> String {
            value.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...8))) } ?? ""
        }
        load = text(row.actualLoad.map { $0 / massScale })
        reps = row.actualReps.map(String.init) ?? ""
        rir = text(row.rir)
    }
    var isDirty: Bool { self != Self(row: baseline, massScale: massScale) }
    func conflicts(with row: WorkoutTrackerDashboard.SetLog) -> Bool { isDirty && row != baseline }

    func command(sessionID: Int, programID: Int, mode: WorkoutTrackerLoadMode, completed: Bool) throws -> [String: WorkoutTrackerValue] {
        let initial = Self(row: baseline, massScale: massScale)
        var result: [String: WorkoutTrackerValue] = ["action": .string("update_set"),
            "sessionId": .number(Double(sessionID)), "mesocycleId": .number(Double(programID)),
            "setId": .number(Double(baseline.id))]
        func number(_ text: String, range: ClosedRange<Double>, integer: Bool = false, scale: Double = 1) throws -> WorkoutTrackerValue {
            let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { return .null }
            guard let value = try? Double(input, format: .number.locale(.current)), value.isFinite,
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
    struct Invalid: LocalizedError {
        var errorDescription: String? { "Enter valid weight, whole repetitions (0–100), and optional RIR (0–5), or clear an actual value." }
    }
}
