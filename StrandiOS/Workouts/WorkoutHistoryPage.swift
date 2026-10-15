import Foundation

struct WorkoutHistoryFilters: Codable, Equatable, Hashable {
    var mesocycleId: Int? = nil
    var status = "completed"
    var kind: String? = nil
    var since: String? = nil
    var until: String? = nil
    var valid: Bool {
        (mesocycleId.map { $0 > 0 } ?? true) && ["completed", "in_progress", "skipped", "planned"].contains(status) &&
        (kind.map { ["strength", "run", "yoga", "airbike"].contains($0) } ?? true) &&
        [since, until].allSatisfy { $0.map { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil } ?? true } &&
        (since == nil || until == nil || since! <= until!)
    }
}
struct WorkoutHistoryPage: Codable, Equatable {
    struct Session: Codable, Identifiable, Equatable {
        let id: Int
        let mesocycleId: Int
        let weekNumber: Int
        let sessionKey: String
        let kind: String
        let title: String
        let scheduledDate: String
        let status: String
        let completedAt: String
        let exerciseCount: Int
        let completedSetCount: Int
        let totalSetCount: Int
        var orderIndex: Int? = nil
        var timing: String? = nil
    }
    struct Pagination: Codable, Equatable {
        let limit: Int
        let hasMore: Bool
        let nextCursor: String?
    }
    let schemaVersion: Int
    let lifeRevision: Int
    let view: String
    let sessions: [Session]
    let filters: WorkoutHistoryFilters
    let pagination: Pagination
    func validate() throws {
        guard schemaVersion == 1, lifeRevision >= 0, view == "history", filters.valid,
              pagination.limit == 20, sessions.count <= 20,
              pagination.hasMore == (pagination.nextCursor != nil),
              !pagination.hasMore || (sessions.count == 20 && !(pagination.nextCursor?.isEmpty ?? true)),
              (pagination.nextCursor?.utf8.count ?? 0) <= 4096,
              Set(sessions.map(\.id)).count == sessions.count,
              sessions.allSatisfy({ $0.id > 0 && $0.mesocycleId > 0 && $0.exerciseCount >= 0 &&
                  $0.completedSetCount >= 0 && $0.totalSetCount >= $0.completedSetCount })
        else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}

/// A revision-bound page chain. Invalid or overlapping pages never partially replace visible history.
struct WorkoutHistoryPageChain {
    private(set) var sessions: [WorkoutHistoryPage.Session] = []
    private(set) var revision: Int?
    private(set) var filters: WorkoutHistoryFilters?
    private(set) var nextCursor: String?
    private(set) var requiresRefresh = false

    /// Reconcile a freshly read detail without throwing away loaded rows or reusing a stale cursor.
    mutating func reconcile(_ session: WorkoutTrackerDashboard.Session, readRevision: Int) {
        guard let revision, readRevision > revision, let filters,
              let index = sessions.firstIndex(where: { $0.id == session.id && $0.mesocycleId == session.mesocycleId }) else { return }
        requiresRefresh = true
        let day = session.scheduledDate.isEmpty ? String(session.completedAt.prefix(10)) : session.scheduledDate
        guard session.status == filters.status,
              filters.kind.map({ $0 == session.kind }) ?? true,
              filters.since.map({ day >= $0 }) ?? true, filters.until.map({ day <= $0 }) ?? true else {
            sessions.remove(at: index); return
        }
        sessions[index] = .init(id: session.id, mesocycleId: session.mesocycleId, weekNumber: session.weekNumber,
            sessionKey: session.sessionKey, kind: session.kind, title: session.title, scheduledDate: session.scheduledDate,
            status: session.status, completedAt: session.completedAt, exerciseCount: session.exercises.count,
            completedSetCount: session.exercises.reduce(0) { $0 + $1.sets.filter(\.completed).count },
            totalSetCount: session.exercises.reduce(0) { $0 + $1.sets.count }, orderIndex: session.orderIndex)
    }
    mutating func accept(_ page: WorkoutHistoryPage, requestedFilters: WorkoutHistoryFilters, cursor: String?) throws {
        try page.validate()
        guard page.filters == requestedFilters else { throw WorkoutTrackerContractError.invalidSnapshot }
        if let cursor {
            guard !requiresRefresh, cursor == nextCursor, page.lifeRevision == revision, page.filters == filters,
                  Set(sessions.map(\.id)).isDisjoint(with: page.sessions.map(\.id)),
                  page.pagination.nextCursor != cursor else { throw WorkoutTrackerContractError.invalidSnapshot }
            sessions += page.sessions
        } else { sessions = page.sessions; requiresRefresh = false }
        filters = page.filters; revision = page.lifeRevision; nextCursor = page.pagination.nextCursor
    }
}
