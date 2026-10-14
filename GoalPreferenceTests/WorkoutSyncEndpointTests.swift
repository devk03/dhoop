import XCTest
@testable import DhoopGoalTests

final class WorkoutSyncEndpointTests: XCTestCase {
    func testOriginCannotEscapeToAnotherHostOrCarryURLCredentials() throws {
        for origin in ["http://track.kunjadia.dev", "https://track.kunjadia.dev.attacker.test",
                       "https://owner:password@track.kunjadia.dev", "https://track.kunjadia.dev/settings",
                       "https://track.kunjadia.dev?token=secret", "https://track.kunjadia.dev#fragment"] {
            XCTAssertThrowsError(try WorkoutSyncEndpoint.catalog.url(origin: origin))
        }
        XCTAssertEqual(try WorkoutSyncEndpoint.manifest(282).url(origin: "https://track.kunjadia.dev").absoluteString,
            "https://track.kunjadia.dev/api/integrations/dhoop/workouts/manifest?sessionId=282")
        XCTAssertEqual(try WorkoutSyncEndpoint.observations.url(origin: "https://track.kunjadia.dev/").path, "/api/webhooks/workouts")
    }
    func testPaginationAndBindingsAreValidatedRatherThanSilentlyChanged() {
        XCTAssertThrowsError(try WorkoutSyncEndpoint.manifest(0).url(origin: "https://track.kunjadia.dev"))
        XCTAssertThrowsError(try WorkoutSyncEndpoint.changes(cursor: -1, limit: 10).url(origin: "https://track.kunjadia.dev"))
        XCTAssertThrowsError(try WorkoutSyncEndpoint.changes(cursor: 0, limit: 101).url(origin: "https://track.kunjadia.dev"))
    }
    func testDisabledSyncNeverStartsANetworkRequest() async {
        let credentials = WorkoutSyncConfiguration(origin: "https://track.kunjadia.dev", installationId: UUID(), credential: "")
        do {
            _ = try await WorkoutSyncTransport().send(to: .catalog, credentials: credentials)
            XCTFail("An unconfigured client must not connect")
        } catch WorkoutSyncTransportError.disabled { }
        catch { XCTFail("Expected disabled before any request: \(error)") }
    }
}
