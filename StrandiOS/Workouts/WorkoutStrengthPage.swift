import Foundation

/// Life selects the active typed lifting program. The phone never infers program type from a name.
struct WorkoutStrengthPage: Codable, Equatable {
    struct Counts: Codable, Equatable { let pending: Int; let scheduled: Int; let unscheduled: Int }
    struct Pagination: Codable, Equatable { let limit: Int; let scheduledHasMore: Bool; let unscheduledHasMore: Bool }
    let schemaVersion: Int
    let lifeRevision: Int
    let view: String
    let date: String
    let program: WorkoutTrackerDashboard.Cycle?
    let programs: [WorkoutTrackerDashboard.Cycle]
    let nextUp: WorkoutHistoryPage.Session?
    let scheduled: [WorkoutHistoryPage.Session]
    let unscheduled: [WorkoutHistoryPage.Session]
    let counts: Counts
    let pagination: Pagination
    func validate() throws {
        guard schemaVersion == 1, lifeRevision >= 0, view == "strength", date.count == 10,
              pagination.limit == 8, scheduled.count <= 8, unscheduled.count <= 8,
              counts.pending >= 0, counts.scheduled >= 0, counts.unscheduled >= 0,
              counts.pending == counts.scheduled + counts.unscheduled,
              programs.count <= 1,
              program.map({ $0.status == "active" && $0.config["programType"] == .string("four_lift_strength") && programs == [$0] }) ?? (programs.isEmpty && counts.pending == 0),
              (nextUp != nil) == (counts.pending > 0),
              (scheduled + unscheduled + (nextUp.map { [$0] } ?? [])).allSatisfy({
                  $0.kind == "strength" && $0.mesocycleId == program?.id && ["planned", "in_progress"].contains($0.status)
              }),
              Set(scheduled.map(\.id)).count == scheduled.count, Set(unscheduled.map(\.id)).count == unscheduled.count,
              Set(scheduled.map(\.id)).isDisjoint(with: unscheduled.map(\.id))
        else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}
