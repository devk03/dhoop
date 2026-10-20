import Foundation

/// A displayed workout and its revision travel together; refresh cannot remove or rebase dirty sets.
struct WorkoutEditableSnapshot {
    struct Value {
        let session: WorkoutTrackerDashboard.Session
        let revision: Int?
        let readAt: Date?
        let library: [WorkoutTrackerDashboard.LibraryItem]
    }
    private(set) var current: Value
    private(set) var pending: Value?
    init(session: WorkoutTrackerDashboard.Session, revision: Int?, readAt: Date?, library: [WorkoutTrackerDashboard.LibraryItem] = []) {
        current = .init(session: session, revision: revision, readAt: readAt, library: library)
    }
    mutating func receive(_ page: WorkoutTrackerDashboard, readAt: Date, protectedSetIDs: Set<Int>) throws {
        try page.validate()
        guard let session = page.dashboard.sessions.first(where: { $0.id == current.session.id && $0.mesocycleId == current.session.mesocycleId }),
              page.lifeRevision >= (current.revision ?? 0) else { throw WorkoutTrackerContractError.invalidSnapshot }
        if let pending, page.lifeRevision < (pending.revision ?? 0) { return }
        let value = Value(session: session, revision: page.lifeRevision, readAt: readAt, library: page.dashboard.exerciseLibrary)
        if compatible(value, protectedSetIDs: protectedSetIDs) { current = value; pending = nil }
        else { pending = value }
    }
    mutating func reconsider(protectedSetIDs: Set<Int>) {
        guard let pending, compatible(pending, protectedSetIDs: protectedSetIDs) else { return }
        current = pending; self.pending = nil
    }
    mutating func usePendingAfterDiscard() {
        guard let pending else { return }
        current = pending; self.pending = nil
    }
    private func compatible(_ next: Value, protectedSetIDs: Set<Int>) -> Bool {
        protectedSetIDs.allSatisfy { id in
            guard let oldExercise = current.session.exercises.first(where: { $0.sets.contains { $0.id == id } }),
                  let newExercise = next.session.exercises.first(where: { $0.id == oldExercise.id }),
                  oldExercise.exerciseKey == newExercise.exerciseKey, oldExercise.loadMode == newExercise.loadMode,
                  let old = oldExercise.sets.first(where: { $0.id == id }), let new = newExercise.sets.first(where: { $0.id == id })
            else { return false }
            return old == new
        }
    }
}
