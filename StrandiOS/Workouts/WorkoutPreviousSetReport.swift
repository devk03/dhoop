import Foundation

/// Immutable display text, kept separate from the current set's edit buffer.
struct WorkoutPreviousSetReport: Equatable {
    let exerciseName: String
    let setLabel: String
    let weekLabel: String
    let workoutTitle: String?
    let dateLabel: String?
    let completionLabel: String?
    let result: String?
    let loadDetail: String?
    let unavailable: String?
    var rirLabel: String? = nil
}
