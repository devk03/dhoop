import XCTest
import CryptoKit

final class SleepWebhookDeliveryTests: XCTestCase {
    private let endpoint = "https://track.kunjadia.dev/api/webhooks/sleep"
    private let now = Date(timeIntervalSince1970: 1_791_223_200)
    private var summary: SleepWebhookSummary { .init(wakeDate: "2026-10-05", sleepMinutes: 455.5, method: "dhoop_estimate", timeZone: "America/Los_Angeles") }
    private func receipt(_ event: SleepWebhookEvent, change: [String: Any] = [:]) throws -> Data {
        var ack: [String: Any] = ["schemaVersion": 1, "eventId": event.eventId, "installationId": event.installationId,
            "revision": event.revision, "wakeDate": event.wakeDate, "status": "accepted", "outcome": "stored"]
        change.forEach { ack[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject: ack)
    }
    private func temporaryStore() -> SleepWebhookFileStore {
        SleepWebhookFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-webhook-test-" + UUID().uuidString + "/state.json"))
    }
    func testCrashRecoveryPreservesExactBytesAndDoesNotReuseRevision() throws {
        let store = temporaryStore()
        var state = try store.load()
        try state.delivery.configure(endpoint: endpoint)
        let first = try XCTUnwrap(state.delivery.prepare(summary, now: now))
        try store.save(state)
        var reopened = try store.load()
        let retry = try XCTUnwrap(reopened.delivery.prepare(.init(wakeDate: "2026-10-06", sleepMinutes: 480, method: "whoop_import", timeZone: "America/Los_Angeles")))
        XCTAssertEqual(first.bytes, retry.bytes)
        XCTAssertEqual(first.event, retry.event)
        XCTAssertTrue(first.event.generationDate.hasSuffix("Z"))
        XCTAssertEqual(first.event.sleepMinutes, 455.5)
        try reopened.delivery.accept(receipt(first.event))
        try store.save(reopened)
        reopened = try store.load()
        XCTAssertNil(try reopened.delivery.prepare(summary))
        let corrected = SleepWebhookSummary(wakeDate: summary.wakeDate, sleepMinutes: 490, method: summary.method, timeZone: summary.timeZone)
        let second = try XCTUnwrap(reopened.delivery.prepare(corrected))
        XCTAssertEqual(second.event.revision, first.event.revision + 1)
        XCTAssertEqual(second.event.installationId, first.event.installationId)
        XCTAssertNotEqual(second.event.eventId, first.event.eventId)
    }
    func testWrongAcknowledgementsNeverAdvancePending() throws {
        var delivery = SleepWebhookDelivery(); try delivery.configure(endpoint: endpoint)
        let pending = try XCTUnwrap(delivery.prepare(summary))
        for change in [["schemaVersion": 2], ["eventId": UUID().uuidString.lowercased()], ["installationId": UUID().uuidString.lowercased()],
                       ["revision": 999], ["wakeDate": "2026-10-04"], ["status": "ok"]] as [[String: Any]] {
            XCTAssertThrowsError(try delivery.accept(receipt(pending.event, change: change)))
            XCTAssertEqual(delivery.pending?.bytes, pending.bytes)
            XCTAssertTrue(delivery.acknowledged.isEmpty)
        }
        XCTAssertThrowsError(try delivery.accept(Data("<html>Sign in</html>".utf8)))
        XCTAssertThrowsError(try delivery.accept(Data(repeating: 32, count: 16_385)))
        try delivery.accept(receipt(pending.event, change: ["outcome": "manual_preserved"]))
        XCTAssertNil(delivery.pending)
        XCTAssertEqual(delivery.lastOutcome, "manual_preserved")
        XCTAssertEqual(delivery.lastAcceptedEvent, pending.event)
    }
    func testCorruptCheckpointFailsClosedWithoutResettingIdentity() throws {
        let store = temporaryStore()
        var state = SleepWebhookCheckpoint(); try state.delivery.configure(endpoint: endpoint)
        let pending = try XCTUnwrap(state.delivery.prepare(summary))
        try store.save(state)
        state.delivery.pending = .init(event: pending.event, bytes: Data("{}".utf8))
        // Simulate a corrupt file, bypassing the production writer's validation.
        try JSONEncoder().encode(state).write(to: store.url, options: .atomic)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(state))
    }
    func testEndpointChangeKeepsRevisionButClearsReceipt() throws {
        var delivery = SleepWebhookDelivery(); try delivery.configure(endpoint: endpoint)
        let first = try XCTUnwrap(delivery.prepare(summary))
        try delivery.accept(receipt(first.event))
        try delivery.configure(endpoint: "https://tracker.kunjadia.dev/api/webhooks/sleep")
        XCTAssertNil(delivery.lastAcceptedAt); XCTAssertNil(delivery.lastAcceptedEvent)
        let next = try XCTUnwrap(delivery.prepare(summary))
        XCTAssertEqual(next.event.revision, 2)
        XCTAssertEqual(next.event.installationId, first.event.installationId)
        // Credential rotation doesn't call an endpoint reset.
        try delivery.configure(endpoint: delivery.endpoint)
        XCTAssertEqual(delivery.pending?.bytes, next.bytes)
    }
    func testTravelDisabledAndBackoffGates() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertTrue(SleepWebhookPolicy.canSend(enabled: true, timeZone: pacific, nextAttempt: nil, now: now))
        XCTAssertFalse(SleepWebhookPolicy.canSend(enabled: false, timeZone: pacific, nextAttempt: nil, now: now))
        XCTAssertFalse(SleepWebhookPolicy.canSend(enabled: true, timeZone: TimeZone(identifier: "America/New_York")!, nextAttempt: nil, now: now))
        XCTAssertFalse(SleepWebhookPolicy.canSend(enabled: true, timeZone: pacific, nextAttempt: now.addingTimeInterval(60), now: now))
        XCTAssertEqual(SleepWebhookPolicy.retryDelay(failures: 1), 60)
        XCTAssertEqual(SleepWebhookPolicy.retryDelay(failures: 2), 120)
        XCTAssertLessThanOrEqual(SleepWebhookPolicy.retryDelay(failures: 100), 21_600)
    }
    func testStrictPayloadAndEndpointValidation() {
        for day in ["2026-02-30", "2026-1-01", "0001-01-01", "not-a-date"] {
            XCTAssertFalse(SleepWebhookSummary(wakeDate: day, sleepMinutes: 480, method: "whoop_import", timeZone: summary.timeZone).isValid)
        }
        for minutes in [0, -1, 1441, .infinity, .nan] {
            XCTAssertFalse(SleepWebhookSummary(wakeDate: summary.wakeDate, sleepMinutes: minutes, method: summary.method, timeZone: summary.timeZone).isValid)
        }
        for url in ["http://track.kunjadia.dev/api/webhooks/sleep", "https://user:secret@example.com/path", "https://example.com/path?token=x", "https://example.com/path#fragment"] {
            XCTAssertNil(SleepWebhookDelivery.endpointURL(url))
        }
    }
    func testSealedSetupRoundTripAndWrongPhoneTamperExpiryRejected() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let invite = SleepWebhookSecureSetup.Invitation(version: 1, setupId: UUID().uuidString.lowercased(),
            installationId: UUID().uuidString.lowercased(), publicKey: key.publicKey.x963Representation, expiresAt: now.addingTimeInterval(1800))
        let credentials = SleepWebhookCredentials(endpoint: endpoint, bearer: String(repeating: "t", count: 43), clientId: "test.access", clientSecret: "test-secret")
        let envelope = try SleepWebhookSecureSetup.seal(credentials, invitation: invite, now: now)
        let clear = try SleepWebhookSecureSetup.open(envelope, invitation: invite, privateKey: key, now: now)
        XCTAssertEqual(clear.bearer, credentials.bearer)
        XCTAssertNil(try JSONEncoder().encode(envelope).range(of: Data(credentials.bearer.utf8)))
        XCTAssertThrowsError(try SleepWebhookSecureSetup.open(envelope, invitation: invite, privateKey: P256.KeyAgreement.PrivateKey(), now: now))
        XCTAssertThrowsError(try SleepWebhookSecureSetup.open(envelope, invitation: invite, privateKey: key, now: now.addingTimeInterval(1900)))
        let altered = SleepWebhookSecureSetup.Invitation(version: 2, setupId: invite.setupId,
            installationId: invite.installationId, publicKey: invite.publicKey, expiresAt: invite.expiresAt)
        let metadataTampered = SleepWebhookSecureSetup.Envelope(invitation: altered, ephemeralPublicKey: envelope.ephemeralPublicKey, sealed: envelope.sealed)
        XCTAssertThrowsError(try SleepWebhookSecureSetup.open(metadataTampered, invitation: invite, privateKey: key, now: now))
        var tampered = envelope.sealed; tampered[0] ^= 1
        let bad = SleepWebhookSecureSetup.Envelope(invitation: invite, ephemeralPublicKey: envelope.ephemeralPublicKey, sealed: tampered)
        XCTAssertThrowsError(try SleepWebhookSecureSetup.open(bad, invitation: invite, privateKey: key, now: now))
    }
}

private final class SleepWebhookMockProtocol: URLProtocol {
    static var status = 200
    static var mime = "application/json"
    static var body = Data("{}".utf8)
    static var observed: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.observed = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SleepWebhookTransportTests: XCTestCase {
    private var credentials: SleepWebhookCredentials {
        .init(endpoint: "https://track.kunjadia.dev/api/webhooks/sleep", bearer: String(repeating: "t", count: 43), clientId: "test.access", clientSecret: "test-secret")
    }
    private var config: URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral; value.protocolClasses = [SleepWebhookMockProtocol.self]; return value
    }
    override func setUp() {
        SleepWebhookMockProtocol.status = 200; SleepWebhookMockProtocol.mime = "application/json"
        SleepWebhookMockProtocol.body = Data("{}".utf8); SleepWebhookMockProtocol.observed = nil
    }
    func testDedicatedHeadersAndExactSuccessfulResponse() async throws {
        let result = try await SleepWebhookTransport().send(Data("{\"test\":true}".utf8), credentials: credentials, configuration: config)
        XCTAssertEqual(result, Data("{}".utf8))
        let request = try XCTUnwrap(SleepWebhookMockProtocol.observed)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + credentials.bearer)
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "test.access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "test-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.url?.absoluteString, credentials.endpoint)
    }
    func testProteinRequiresItsOwnBearerAndNeverFallsBackToSleepToken() async throws {
        do { _ = try await SleepWebhookTransport().send(Data("{}".utf8), credentials: credentials, protein: true, configuration: config); XCTFail("Missing protein bearer was accepted") }
        catch SleepWebhookFailure.credentials {} catch { XCTFail("Unexpected failure type") }
        XCTAssertNil(SleepWebhookMockProtocol.observed)
        let separate = SleepWebhookCredentials(endpoint: credentials.endpoint, bearer: credentials.bearer,
            clientId: credentials.clientId, clientSecret: credentials.clientSecret, proteinBearer: String(repeating: "p", count: 43))
        _ = try await SleepWebhookTransport().send(Data("{}".utf8), credentials: separate, protein: true, configuration: config)
        XCTAssertEqual(SleepWebhookMockProtocol.observed?.value(forHTTPHeaderField: "Authorization"), "Bearer " + separate.proteinBearer!)
    }
    func testNon200AndHTMLAreNotAcknowledgements() async throws {
        for (status, mime) in [(204, "application/json"), (302, "text/html"), (403, "text/html"), (500, "application/json"), (200, "text/html")] {
            SleepWebhookMockProtocol.status = status; SleepWebhookMockProtocol.mime = mime
            do { _ = try await SleepWebhookTransport().send(Data("{}".utf8), credentials: credentials, configuration: config); XCTFail("Unacceptable receiver response accepted") }
            catch { XCTAssertTrue(error is SleepWebhookFailure) }
        }
    }
    func testOversizedStreamRejectedWithoutContentLength() async throws {
        SleepWebhookMockProtocol.body = Data(repeating: 32, count: 16_385)
        do { _ = try await SleepWebhookTransport().send(Data("{}".utf8), credentials: credentials, configuration: config); XCTFail("Oversized response accepted") }
        catch SleepWebhookFailure.responseTooLarge {} catch { XCTFail("Unexpected failure type") }
    }
    func testRedirectDelegateAlwaysRefusesEvenSameHost() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: credentials.endpoint)!)
        let task = session.dataTask(with: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var refused = false
        SleepWebhookTransport().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { refused = $0 == nil }
        XCTAssertTrue(refused)
    }
}
