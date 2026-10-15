import Foundation
import XCTest

@MainActor
final class WorkoutConnectionProvisionerTests: XCTestCase {
    private final class Vault { var source: WorkoutSyncConfiguration?; var editor: WorkoutSyncConfiguration? }
    private let id = UUID()
    private func envelope() -> WorkoutConnectionProvisioner.Envelope {
        .init(schemaVersion: 1, installationId: id, baseURL: "https://track.kunjadia.dev",
            sourceToken: String(repeating: "a", count: 64), frontendToken: String(repeating: "b", count: 64),
            accessClientId: "test-workout-only.access", accessClientSecret: String(repeating: "c", count: 64))
    }
    private func fixture(vault: Vault, lifecycle: Bool = false, failRead: Bool = false) throws -> WorkoutConnectionProvisioner {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceFile = WorkoutTrackerFileStore(url: root.appendingPathComponent("source.json"))
        var state = WorkoutTrackerState(); state.installationId = id; try sourceFile.save(state)
        let source = WorkoutTrackerClient(store: sourceFile, send: { endpoint, body, _ in
            XCTAssertEqual(endpoint, .dashboard(mesocycleId: nil, sessionId: nil, cursor: 0, limit: 10)); XCTAssertNil(body)
            if failRead { throw URLError(.timedOut) }
            return Data(#"{"schemaVersion":1,"lifeRevision":4,"dashboard":{"lifeRevision":4,"mesocycles":[],"activeMesocycle":null,"benchmarks":[],"sessions":[],"exerciseLibrary":[],"sportSeasons":[]},"pagination":{"cursor":0,"limit":10,"totalSessions":0,"nextCursor":null},"capabilities":{"manualCommands":false,"frontendStart":false}}"#.utf8)
        }, readCredential: { vault.source }, saveCredential: { vault.source = $0 })
        let editor = WorkoutFrontendClient(store: .init(url: root.appendingPathComponent("editor.json")), send: { endpoint, body, _ in
            XCTAssertEqual(endpoint, .frontendCapabilities); XCTAssertNil(body)
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true,
                "frontendStart": lifecycle, "actions": ["update_set"], "lifeRevision": 4])
        }, readCredential: { vault.editor }, saveCredential: { vault.editor = $0 })
        return .init(tracker: source, frontend: editor, sourceCredential: { vault.source }, frontendCredential: { vault.editor })
    }
    func testLocalSetupUsesSeparateKeychainCredentialsAndReadsOnly() async throws {
        let vault = Vault()
        let owner = try fixture(vault: vault)
        try await owner.install(envelope())
        XCTAssertTrue(owner.tracker.state.enabled); XCTAssertTrue(owner.frontend.state.enabled)
        XCTAssertNotEqual(vault.source?.credential, vault.editor?.credential)
        XCTAssertEqual(vault.source?.installationId, id); XCTAssertEqual(vault.editor?.installationId, id)
        XCTAssertEqual(vault.source?.accessClientId, "test-workout-only.access")
        XCTAssertTrue(owner.frontend.state.operations.isEmpty); XCTAssertTrue(owner.tracker.state.deliveries.isEmpty)
    }
    func testExistingDifferentCredentialCannotBeReplaced() async throws {
        let vault = Vault()
        vault.source = .init(origin: "https://track.kunjadia.dev", installationId: id, credential: String(repeating: "d", count: 64))
        let owner = try fixture(vault: vault)
        do { try await owner.install(envelope()); XCTFail("An existing credential must not be replaced") }
        catch WorkoutConnectionProvisioner.Failure.existingConnection { }
        XCTAssertEqual(vault.source?.credential, String(repeating: "d", count: 64)); XCTAssertNil(vault.editor)
        XCTAssertFalse(owner.tracker.state.enabled)
    }
    func testUnverifiedReadRetainsPrivateEnvelopeForRetryAndDoesNotEnableEditing() async throws {
        let owner = try fixture(vault: Vault(), failRead: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let input = try JSONEncoder().encode(envelope()); try input.write(to: file)
        do { try await owner.consumeFile(at: file); XCTFail("A failed read must remain unverified") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), input)
        XCTAssertFalse(owner.frontend.state.enabled)
    }
    func testUnexpectedLifecyclePermissionIsDisabledRatherThanSilentlyAccepted() async throws {
        let owner = try fixture(vault: Vault(), lifecycle: true)
        do { try await owner.install(envelope()); XCTFail("Source lifecycle is not ready") }
        catch WorkoutConnectionProvisioner.Failure.permission { }
        XCTAssertFalse(owner.frontend.state.enabled); XCTAssertNil(owner.frontend.state.capabilities)
    }
    func testOnlyVerifiedSetupRetiresTransferContentsAndCanResumeAnInterruptedImport() async throws {
        let owner = try fixture(vault: Vault())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let input = try JSONEncoder().encode(envelope()); try input.write(to: file)
        try await owner.install(envelope())
        try await owner.consumeFile(at: file)
        XCTAssertNotEqual(try Data(contentsOf: file), input)
        let marker = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(marker["consumed"] as? Bool, true)
        XCTAssertNil(marker["sourceToken"]); XCTAssertNil(marker["frontendToken"])
    }
    func testPartialAccessPairAndSharedBearerCannotProvision() throws {
        let e = envelope()
        let partial = WorkoutConnectionProvisioner.Envelope(schemaVersion: 1, installationId: id, baseURL: e.baseURL,
            sourceToken: e.sourceToken, frontendToken: e.frontendToken, accessClientId: e.accessClientId, accessClientSecret: nil)
        XCTAssertThrowsError(try partial.configurations())
        let shared = WorkoutConnectionProvisioner.Envelope(schemaVersion: 1, installationId: id, baseURL: e.baseURL,
            sourceToken: e.sourceToken, frontendToken: e.sourceToken, accessClientId: nil, accessClientSecret: nil)
        XCTAssertThrowsError(try shared.configurations())
    }
}
