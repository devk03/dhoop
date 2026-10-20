import XCTest

@MainActor
final class WorkoutRefreshTests: XCTestCase {
    private func row(_ id: Int, load: Double? = nil) -> WorkoutTrackerDashboard.SetLog {
        .init(id: id, setNumber: id, setType: "work", plannedLoad: 100, plannedReps: 8, actualLoad: load, actualReps: nil, rir: nil, completed: load != nil)
    }
    private func session(_ sets: [WorkoutTrackerDashboard.SetLog]) -> WorkoutTrackerDashboard.Session {
        let exercise = WorkoutTrackerDashboard.Exercise(id: 5, exerciseKey: "press", name: "Press", orderIndex: 1, loadMode: "barbell", progressionType: "double", plannedSets: 2, plannedReps: 8, plannedLoad: 100, targetRir: 2, notes: "", slotKey: "press", movementPattern: "push", originalExerciseKey: "press", originalExerciseName: "Press", isPriming: false, sets: sets)
        return .init(id: 10, mesocycleId: 1, weekNumber: 2, sessionKey: "upper", kind: "strength", title: "Upper", scheduledDate: "2026-10-19", orderIndex: 1, status: "planned", readiness: "", rating: "", notes: "", metrics: [:], sheetItemId: "", linkedSessionId: nil, completedAt: "", exercises: [exercise], finisher: nil)
    }
    private func page(_ sets: [WorkoutTrackerDashboard.SetLog], revision: Int = 2) -> WorkoutTrackerDashboard {
        let cycle = WorkoutTrackerDashboard.Cycle(id: 1, name: "Program", startDate: "2026-10-01", durationWeeks: 8, status: "active", goals: [:], config: [:], createdAt: "", updatedAt: "")
        return .init(schemaVersion: 1, lifeRevision: revision, dashboard: .init(lifeRevision: revision, mesocycles: [cycle], activeMesocycle: cycle, benchmarks: [], sessions: [session(sets)], exerciseLibrary: [], sportSeasons: []), pagination: .init(cursor: 0, limit: 1, totalSessions: 1, nextCursor: nil), capabilities: .init(manualCommands: true, frontendStart: false))
    }
    func testChangedOrRemovedDirtySetRetainsDisplayedRevisionUntilDiscardOrRelease() throws {
        let original = session([row(1), row(2)])
        var snapshot = WorkoutEditableSnapshot(session: original, revision: 1, readAt: nil)
        try snapshot.receive(page([row(1, load: 110), row(2)]), readAt: Date(), protectedSetIDs: [1, 2])
        XCTAssertEqual(snapshot.current.session, original); XCTAssertEqual(snapshot.current.revision, 1)
        XCTAssertEqual(snapshot.pending?.revision, 2)
        // Saving set 1 releases only its protection; set 2's unchanged baseline can safely retain input.
        snapshot.reconsider(protectedSetIDs: [2])
        XCTAssertNil(snapshot.pending); XCTAssertEqual(snapshot.current.revision, 2)
        XCTAssertEqual(snapshot.current.session.exercises[0].sets[1], row(2))
        try snapshot.receive(page([row(1, load: 110)], revision: 3), readAt: Date(), protectedSetIDs: [2])
        XCTAssertEqual(snapshot.current.session.exercises[0].sets.count, 2)
        XCTAssertEqual(snapshot.current.revision, 2)
        snapshot.usePendingAfterDiscard()
        XCTAssertEqual(snapshot.current.session.exercises[0].sets.count, 1); XCTAssertEqual(snapshot.current.revision, 3)
    }
    func testUnchangedDirtyBaselineAcceptsCleanUpdatesButOlderReadCannotRebase() throws {
        var snapshot = WorkoutEditableSnapshot(session: session([row(1), row(2)]), revision: 1, readAt: nil)
        try snapshot.receive(page([row(1), row(2, load: 100)]), readAt: Date(), protectedSetIDs: [1])
        XCTAssertEqual(snapshot.current.revision, 2); XCTAssertNil(snapshot.pending)
        XCTAssertThrowsError(try snapshot.receive(page([row(1)], revision: 1), readAt: Date(), protectedSetIDs: [1]))
        XCTAssertEqual(snapshot.current.revision, 2)
        XCTAssertEqual(snapshot.current.session.exercises[0].sets.count, 2)
    }
    func testConcurrentSameContextRefreshCoalescesAndReportsOnlyActualCompletion() async throws {
        let state = WorkoutRefreshController()
        var resume: CheckedContinuation<Void, Never>?
        var reads = 0
        let first = Task { try await state.refresh(identity: "same") {
            reads += 1; await withCheckedContinuation { resume = $0 }
        } }
        for _ in 0..<30 { if resume != nil { break }; await Task.yield() }
        XCTAssertNotNil(resume); XCTAssertTrue(state.busy); XCTAssertNil(state.lastSuccess)
        let second = Task { try await state.refresh(identity: "same") { reads += 1 } }
        await Task.yield(); XCTAssertEqual(reads, 1)
        resume?.resume(); try await first.value; try await second.value
        XCTAssertEqual(reads, 1); XCTAssertFalse(state.busy); XCTAssertNotNil(state.lastSuccess); XCTAssertNil(state.errorMessage)
    }
    func testLateFailureAndExplicitCancellationCannotReplaceNewContextSuccess() async throws {
        let state = WorkoutRefreshController()
        var resume: CheckedContinuation<Void, Never>?
        let old = Task { try await state.refresh(identity: "old") {
            await withCheckedContinuation { resume = $0 }
            throw URLError(.notConnectedToInternet)
        } }
        for _ in 0..<30 { if resume != nil { break }; await Task.yield() }
        try await state.refresh(identity: "new") { }
        let acceptedAt = state.lastSuccess
        resume?.resume(); _ = await old.result
        XCTAssertNil(state.errorMessage); XCTAssertEqual(state.lastSuccess, acceptedAt); XCTAssertFalse(state.busy)
        do { try await state.refresh(identity: "new") { throw URLError(.notConnectedToInternet) }; XCTFail("Offline must surface") } catch { }
        XCTAssertNotNil(state.errorMessage); XCTAssertEqual(state.lastSuccess, acceptedAt)
        state.reset(); XCTAssertNil(state.lastSuccess); XCTAssertNil(state.errorMessage)
    }
}
