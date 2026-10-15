import XCTest

final class WorkoutHistoryPageTests: XCTestCase {
    private func row(_ id: Int) -> WorkoutHistoryPage.Session {
        .init(id: id, mesocycleId: 1, weekNumber: 1, sessionKey: "x", kind: "strength", title: "Workout", scheduledDate: "2026-10-01", status: "completed", completedAt: "", exerciseCount: 2, completedSetCount: 4, totalSetCount: 6)
    }
    private func page(_ ids: [Int], revision: Int = 9, next: String? = nil) -> WorkoutHistoryPage {
        .init(schemaVersion: 1, lifeRevision: revision, view: "history", sessions: ids.map(row), filters: .init(), pagination: .init(limit: 20, hasMore: next != nil, nextCursor: next))
    }
    func testThreePagesHaveNoDuplicatesAndConflictDoesNotEraseLoadedRows() throws {
        var chain = WorkoutHistoryPageChain()
        try chain.accept(page(Array((41...60).reversed()), next: "page2"), requestedFilters: .init(), cursor: nil)
        try chain.accept(page(Array((21...40).reversed()), next: "page3"), requestedFilters: .init(), cursor: "page2")
        let retained = chain.sessions
        XCTAssertThrowsError(try chain.accept(page([20], revision: 10), requestedFilters: .init(), cursor: "page3"))
        XCTAssertEqual(chain.sessions, retained)
        XCTAssertEqual(chain.nextCursor, "page3")
        XCTAssertThrowsError(try chain.accept(page([21]), requestedFilters: .init(), cursor: "page3"))
        try chain.accept(page(Array((1...20).reversed())), requestedFilters: .init(), cursor: "page3")
        XCTAssertEqual(chain.sessions.map(\.id), Array((1...60).reversed()))
        XCTAssertNil(chain.nextCursor)
    }
    func testFiltersAndCursorCannotCrossPageChainsAndRefreshReplaces() throws {
        var chain = WorkoutHistoryPageChain()
        try chain.accept(page(Array((1...20).reversed()), next: "next"), requestedFilters: .init(), cursor: nil)
        var changed = WorkoutHistoryFilters(); changed.kind = "run"
        XCTAssertThrowsError(try chain.accept(page([30]), requestedFilters: changed, cursor: "next"))
        XCTAssertThrowsError(try chain.accept(page([30]), requestedFilters: .init(), cursor: "wrong"))
        try chain.accept(page([100], revision: 10), requestedFilters: .init(), cursor: nil)
        XCTAssertEqual(chain.sessions.map(\.id), [100])
        XCTAssertEqual(chain.revision, 10)
    }
    func testFreshReopenedDetailLeavesCompletedHistoryWithoutErasingOtherPages() throws {
        var chain = WorkoutHistoryPageChain()
        try chain.accept(page(Array((21...40).reversed()), next: "next"), requestedFilters: .init(), cursor: nil)
        try chain.accept(page(Array((1...20).reversed()), next: "third"), requestedFilters: .init(), cursor: "next")
        let reopened = WorkoutTrackerDashboard.Session(id: 25, mesocycleId: 1, weekNumber: 1, sessionKey: "x", kind: "strength", title: "Workout", scheduledDate: "2026-10-01", orderIndex: 1, status: "planned", readiness: "", rating: "", notes: "", metrics: [:], sheetItemId: "task-25", linkedSessionId: nil, completedAt: "", exercises: [], finisher: nil)
        chain.reconcile(reopened, readRevision: 8)
        XCTAssertEqual(chain.sessions.count, 40)
        chain.reconcile(reopened, readRevision: 10)
        XCTAssertEqual(chain.sessions.map(\.id), Array((1...40).reversed()).filter { $0 != 25 })
        XCTAssertTrue(chain.requiresRefresh)
        XCTAssertThrowsError(try chain.accept(page([100]), requestedFilters: .init(), cursor: "third"))
        try chain.accept(page([40], revision: 10), requestedFilters: .init(), cursor: nil)
        XCTAssertFalse(chain.requiresRefresh)
    }

    func testEndpointUsesOpaqueKeysetCursorAndTwentyLimitNotOffset() throws {
        let url = try WorkoutSyncEndpoint.history(.init(), cursor: "opaque+/=").url(origin: "https://track.kunjadia.dev")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        XCTAssertEqual(values["limit"], "20"); XCTAssertEqual(values["historyCursor"], "opaque+/=")
        XCTAssertNil(values["cursor"])
        XCTAssertEqual(values["view"], "history")
    }
}
