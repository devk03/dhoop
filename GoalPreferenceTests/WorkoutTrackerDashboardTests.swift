import Foundation
import XCTest

@MainActor
final class WorkoutTrackerDashboardTests: XCTestCase {
    private func page(revision: Int = 4, cursor: Int = 0, next: Int? = nil, total: Int = 1) throws -> Data {
        let cycle: [String:Any] = ["id":1,"name":"Owner program","startDate":"2026-10-01","durationWeeks":8,"status":"active","goals":[:],"config":["bodyweight":180],"createdAt":"2026-10-01","updatedAt":"2026-10-14"]
        let session: [String:Any] = ["id":10,"mesocycleId":1,"weekNumber":1,"sessionKey":"upper_a","kind":"strength","title":"Upper A","scheduledDate":"2026-10-14","orderIndex":1,"status":"planned","readiness":"","rating":"","notes":"","metrics":[:],"sheetItemId":"","linkedSessionId":NSNull(),"completedAt":"","exercises":[]]
        return try JSONSerialization.data(withJSONObject:["schemaVersion":1,"lifeRevision":revision,
            "dashboard":["lifeRevision":revision,"mesocycles":[cycle],"activeMesocycle":cycle,"benchmarks":[],"sessions":[session],"exerciseLibrary":[],"sportSeasons":[]],
            "pagination":["cursor":cursor,"limit":10,"totalSessions":total,"nextCursor":next as Any? ?? NSNull()],
            "capabilities":["manualCommands":false,"frontendStart":false]])
    }
    func testWorkoutOnlyNameSurvivesRoundTripWithoutRenamingCatalogOrOtherSessions() throws {
        let exercise = WorkoutTrackerDashboard.Exercise(id: 11, exerciseKey: "press", name: "Bench press", orderIndex: 1,
            loadMode: "barbell", progressionType: "double", plannedSets: 3, plannedReps: 8, plannedLoad: 135,
            targetRir: 2, notes: "", slotKey: "press", movementPattern: "push", originalExerciseKey: "press",
            originalExerciseName: "Bench press", isPriming: false, sets: [])
        for (value, expected) in [(WorkoutTrackerValue.string("  Cable press  "), "Cable press"),
                                  (.string("  "), "Bench press"), (.number(4), "Bench press")] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: page()) as? [String: Any])
            var dashboard = try XCTUnwrap(object["dashboard"] as? [String: Any])
            var sessions = try XCTUnwrap(dashboard["sessions"] as? [[String: Any]])
            sessions[0]["exercises"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([exercise]))
            let metrics: [String: WorkoutTrackerValue] = ["exerciseSubstitutions": .object(["press": .object(["name": value])])]
            sessions[0]["metrics"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics))
            dashboard["sessions"] = sessions; object["dashboard"] = dashboard
            let decoded = try JSONDecoder().decode(WorkoutTrackerDashboard.self, from: JSONSerialization.data(withJSONObject: object))
            let saved = try JSONDecoder().decode(WorkoutTrackerDashboard.Session.self,
                from: JSONEncoder().encode(try XCTUnwrap(decoded.dashboard.sessions.first)))
            XCTAssertEqual(saved.displayName(for: exercise), expected)
            XCTAssertEqual(saved.exercises[0].name, "Bench press", "Catalog name must remain unchanged")
            // The same canonical name in a different session has no workout-only overlay.
            let untouched = try JSONDecoder().decode(WorkoutTrackerDashboard.self, from: page()).dashboard.sessions[0]
            XCTAssertEqual(untouched.displayName(for: exercise), "Bench press")
        }
    }

    func testCanonicalPageRoundTripRetainsRevisionAndDoesNotEnableCommands() throws {
        let response = try JSONDecoder().decode(WorkoutTrackerDashboard.self,from:page())
        try response.validate()
        XCTAssertEqual(response.dashboard.sessions.first?.id,10)
        XCTAssertEqual(response.lifeRevision,4)
        XCTAssertFalse(response.capabilities.manualCommands)
        XCTAssertFalse(response.capabilities.frontendStart)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutTrackerDashboard.self,from:JSONEncoder().encode(response)),response)
    }
    func testInvalidPaginationAndMismatchedCycleCannotBecomeAnEmptyOrDifferentTracker() throws {
        let noProgress = try JSONDecoder().decode(WorkoutTrackerDashboard.self,from:page(next:0,total:10))
        XCTAssertThrowsError(try noProgress.validate())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:page()) as? [String:Any])
        var dashboard = try XCTUnwrap(object["dashboard"] as? [String:Any]); dashboard["lifeRevision"] = 3
        object["dashboard"] = dashboard
        let mismatch = try JSONDecoder().decode(WorkoutTrackerDashboard.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertThrowsError(try mismatch.validate())
    }
    func testRefreshFailureRetainsDatedCache() async throws {
        let file = WorkoutTrackerFileStore(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let config = WorkoutSyncConfiguration(enabled:true,origin:"https://track.kunjadia.dev",installationId:UUID(),credential:String(repeating:"a",count:64))
        var state = WorkoutTrackerState();state.enabled=true;state.origin=config.origin;state.installationId=config.installationId
        try file.save(state)
        var shouldFail=false
        let data = try page()
        let client = WorkoutTrackerClient(store:file,send:{ endpoint,body,_ in
            XCTAssertEqual(endpoint,.dashboard(mesocycleId:nil,sessionId:nil,cursor:0,limit:10));XCTAssertNil(body)
            if shouldFail { throw URLError(.timedOut) };return data
        },readCredential:{config},saveCredential:{_ in})
        try await client.refreshDashboard()
        let saved = client.state.frontendPage, readAt=client.state.frontendReadAt
        shouldFail=true
        do { try await client.refreshDashboard();XCTFail("Read failure must surface") } catch { }
        XCTAssertEqual(client.state.frontendPage,saved);XCTAssertEqual(client.state.frontendReadAt,readAt)
        XCTAssertEqual(try file.load().frontendPage,saved)
    }
    func testDashboardEndpointRejectsUnboundedAndNonpositiveTargets() throws {
        XCTAssertEqual(try WorkoutSyncEndpoint.dashboard(mesocycleId:1,sessionId:nil,cursor:0,limit:10).url(origin:"https://track.kunjadia.dev").path,"/api/integrations/dhoop/workouts/dashboard")
        for endpoint in [WorkoutSyncEndpoint.dashboard(mesocycleId:0,sessionId:nil,cursor:0,limit:10),.dashboard(mesocycleId:nil,sessionId:-1,cursor:0,limit:10),.dashboard(mesocycleId:nil,sessionId:nil,cursor:0,limit:26)] {
            XCTAssertThrowsError(try endpoint.url(origin:"https://track.kunjadia.dev"))
        }
    }
}
