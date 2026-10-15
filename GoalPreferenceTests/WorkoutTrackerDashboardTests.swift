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
