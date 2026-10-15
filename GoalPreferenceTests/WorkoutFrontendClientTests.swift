import Foundation
import XCTest

@MainActor
final class WorkoutFrontendClientTests: XCTestCase {
    private let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev",
        installationId: UUID(), credential: String(repeating: "c", count: 64))

    private func store() -> WorkoutFrontendFileStore {
        .init(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("commands.json"))
    }
    private func capabilities() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true,
            "frontendStart": true, "lifeRevision": 4, "actions": ["update_set", "update_session", "start_session", "create_mesocycle"]])
    }
    private func enable(_ client: WorkoutFrontendClient) async throws {
        try client.configure(origin: config.origin, installationId: config.installationId, token: config.credential)
        try client.setEnabled(true)
        try await client.checkCapabilities()
    }
    private var change: [String: WorkoutTrackerValue] {
        ["action": .string("update_set"), "mesocycleId": .number(1), "sessionId": .number(10),
         "setId": .number(20), "actualLoad": .number(80), "actualReps": .number(8), "completed": .bool(true)]
    }
    // This fixture follows the service's public receipt schema, including the original request.
    private func receipt(_ intent: WorkoutFrontendIntent, state: String = "committed") throws -> Data {
        var object: [String: Any] = ["schemaVersion": 1, "operationId": intent.operationId.uuidString.lowercased(),
            "state": state, "lifeRevision": 7, "result": NSNull()]
        if state != "not_observed" {
            object["request"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(intent))
            object["requestHash"] = String(repeating: "a", count: 64)
            object["receiptLifeRevision"] = 7
            if state == "committed" { object["result"] = ["mesocycleId": 1, "sessionId": 10, "setId": 20, "invalidate": "workout_tracker"] }
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testDefaultOffAndCapabilitiesAreReadOnly() async throws {
        var writes = 0, requests = 0
        let client = WorkoutFrontendClient(store: store(), send: { endpoint, body, _ in
            requests += 1; XCTAssertEqual(endpoint, .frontendCapabilities); XCTAssertNil(body)
            return try self.capabilities()
        }, readCredential: { self.config }, saveCredential: { _ in writes += 1 })
        XCTAssertFalse(client.state.enabled)
        XCTAssertThrowsError(try client.prepare(command: change, revision: 4))
        XCTAssertEqual(requests, 0)
        try await enable(client)
        XCTAssertEqual(writes, 1); XCTAssertEqual(requests, 1)
        XCTAssertTrue(client.supports("update_set"))
        XCTAssertTrue(client.state.operations.isEmpty)
    }

    func testTimeoutRetainsExactIntentAcrossRelaunchAndRecoveryNeverRepeatsWrite() async throws {
        let file = store()
        var posts: [Data] = []
        let client = WorkoutFrontendClient(store: file, send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            posts.append(try XCTUnwrap(body)); throw URLError(.timedOut)
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(client)
        let id = try client.prepare(command: change, revision: 4)
        let intent = try XCTUnwrap(client.unresolved?.intent)
        let original = try XCTUnwrap(client.unresolved?.bytes)
        do { try await client.submit(id); XCTFail("Timeout cannot imply acceptance") } catch { }
        XCTAssertEqual(client.unresolved?.state, .uncertain)
        XCTAssertThrowsError(try client.prepare(command: change, revision: 4))
        let restored = WorkoutFrontendClient(store: file, send: { endpoint, body, _ in
            XCTAssertEqual(endpoint, .frontendReceipt(id)); XCTAssertNil(body)
            return try self.receipt(intent)
        }, readCredential: { self.config }, saveCredential: { _ in })
        do { try await restored.submit(id); XCTFail("An uncertain POST cannot be blindly repeated") } catch { }
        try await restored.recover(id)
        XCTAssertNil(restored.unresolved)
        XCTAssertEqual(restored.state.operations.first?.state, .committed)
        XCTAssertEqual(restored.state.operations.first?.bytes, original)
        XCTAssertEqual(posts, [original])
    }

    func testWrongSetOrOmittedClearCannotBecomeAReceiptForThisInput() async throws {
        let client = WorkoutFrontendClient(store: store(), send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            let original = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(body))
            var changed = original.command; changed["setId"] = .number(21)
            return try self.receipt(.init(operationId: original.operationId,
                expectedLifeRevision: original.expectedLifeRevision, command: changed))
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(client)
        var cleared = change; cleared["actualLoad"] = .null
        let id = try client.prepare(command: cleared, revision: 4)
        do { try await client.submit(id); XCTFail("Wrong target receipt must fail") } catch { }
        XCTAssertEqual(client.unresolved?.state, .uncertain)
        XCTAssertEqual(client.unresolved?.intent.command["actualLoad"], .null)
        let intent = try XCTUnwrap(client.unresolved?.intent)
        var omitted = intent.command; omitted.removeValue(forKey: "actualLoad")
        let other = WorkoutFrontendIntent(operationId: id, expectedLifeRevision: 4, command: omitted)
        let response = try JSONDecoder().decode(WorkoutFrontendReceipt.self, from: receipt(other))
        XCTAssertThrowsError(try response.validate(for: intent, prior: nil))
    }

    func testKnownRunningFenceCannotBeErasedByNegativeLookup() async throws {
        var intent: WorkoutFrontendIntent?
        let client = WorkoutFrontendClient(store: store(), send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            if endpoint == .frontendCommand {
                intent = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(body))
                return try self.receipt(XCTUnwrap(intent), state: "running")
            }
            return try self.receipt(XCTUnwrap(intent), state: "not_observed")
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(client)
        let id = try client.prepare(command: change, revision: 4)
        do { try await client.submit(id); XCTFail("Running is not completed") } catch { }
        try await client.recover(id)
        XCTAssertEqual(client.unresolved?.state, .uncertain)
        XCTAssertEqual(client.unresolved?.receipt?.state, .running)
        do { try await client.submit(id); XCTFail("A negative lookup cannot remove a known server fence") } catch { }
        XCTAssertThrowsError(try client.cancelUnsent(id))
    }

    func testNotObservedRetryUsesSameLowercaseOperationAndFrozenBytes() async throws {
        var intent: WorkoutFrontendIntent?
        var posts: [Data] = []
        let client = WorkoutFrontendClient(store: store(), send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            if endpoint == .frontendCommand {
                let bytes = try XCTUnwrap(body); posts.append(bytes)
                intent = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: bytes)
                if posts.count == 1 { throw URLError(.networkConnectionLost) }
                return try self.receipt(XCTUnwrap(intent))
            }
            return try self.receipt(XCTUnwrap(intent), state: "not_observed")
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(client)
        let id = try client.prepare(command: change, revision: 4)
        do { try await client.submit(id); XCTFail("Lost response remains unknown") } catch { }
        try await client.recover(id)
        XCTAssertEqual(client.unresolved?.state, .notObserved)
        try await client.submit(id)
        XCTAssertEqual(posts.count, 2); XCTAssertEqual(posts[0], posts[1])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: posts[0]) as? [String: Any])
        XCTAssertEqual(object["operationId"] as? String, id.uuidString.lowercased())
    }

    func testUnsentCancellationAndServerNameNormalizationPreserveIdentity() async throws {
        var sends = 0
        let client = WorkoutFrontendClient(store: store(), send: { _, _, _ in sends += 1; return try self.capabilities() },
            readCredential: { self.config }, saveCredential: { _ in })
        try await enable(client)
        let id = try client.prepare(command: ["action": .string("create_mesocycle"),
            "name": .string("  My program\n"), "startDate": .string("2026-10-14")], revision: 4)
        XCTAssertEqual(client.unresolved?.intent.command["name"], .string("My program"))
        try client.cancelUnsent(id)
        XCTAssertEqual(client.state.operations.first?.state, .cancelled)
        XCTAssertNil(client.unresolved); XCTAssertEqual(sends, 1)
    }

    func testCorruptQueueIsRetainedAndCannotBeResetThroughConfiguration() throws {
        let file = store()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("retained invalid state".utf8); try corrupt.write(to: file.url)
        let client = WorkoutFrontendClient(store: file, readCredential: { self.config }, saveCredential: { _ in XCTFail("Must not overwrite credentials") })
        XCTAssertTrue(client.storageUnavailable)
        XCTAssertThrowsError(try client.configure(origin: config.origin, installationId: config.installationId, token: config.credential))
        XCTAssertEqual(try Data(contentsOf: file.url), corrupt)
    }
}
