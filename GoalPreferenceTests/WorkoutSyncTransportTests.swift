import XCTest
@testable import DhoopGoalTests

private final class WorkoutMockProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let (status, headers, body) = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WorkoutSyncTransportTests: XCTestCase {
    override func tearDown() { WorkoutMockProtocol.handler = nil; super.tearDown() }
    private func config() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WorkoutMockProtocol.self]
        return config
    }
    private func credentials() -> WorkoutSyncConfiguration {
        WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), credential: String(repeating: "a", count: 64))
    }
    func testConfiguredReadUsesOnlyDedicatedAuthAndInstallationHeaders() async throws {
        let credentials = credentials()
        let observed = expectation(description: "Intercepted configured request")
        WorkoutMockProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + credentials.credential)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Dhoop-Installation-Id"), credentials.installationId.uuidString.lowercased())
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"))
            observed.fulfill()
            return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        let body = try await WorkoutSyncTransport().send(to: .catalog, credentials: credentials, configuration: config())
        XCTAssertEqual(body, Data("{}".utf8))
        await fulfillment(of: [observed], timeout: 2)
    }
    func testReceiptLookupPostsOriginalBodyToReadOnlyRouteWithDedicatedHeaders() async throws {
        let credential = credentials(), original = Data("{\"eventId\":\"unchanged\"}".utf8)
        let observed = expectation(description: "Exact lookup route")
        WorkoutMockProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/integrations/dhoop/workouts/receipts/lookup")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + credential.credential)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            var sent = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    sent.append(contentsOf: buffer.prefix(count))
                }
            }
            XCTAssertEqual(sent, original)
            observed.fulfill()
            return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        _ = try await WorkoutSyncTransport().send(to: .receiptLookup, body: original, credentials: credential, configuration: config())
        await fulfillment(of: [observed], timeout: 2)
    }

    func testConflictIsNotAcceptedAsSuccessOrExposedWithResponseBody() async {
        WorkoutMockProtocol.handler = { _ in (409, ["Content-Type": "application/json"], Data("private response text".utf8)) }
        do {
            _ = try await WorkoutSyncTransport().send(to: .catalog, credentials: credentials(), configuration: config())
            XCTFail("A conflict needs explicit review")
        } catch WorkoutSyncTransportError.http(let status) { XCTAssertEqual(status, 409) }
        catch { XCTFail("Unexpected transport result") }
    }
    func testUntrustedContentAndOversizedResponsesAreRejected() async {
        for (headers, expectedLarge) in [(["Content-Type": "text/html"], false),
                                       (["Content-Type": "application/json", "Content-Length": "2000000"], true)] {
            WorkoutMockProtocol.handler = { _ in (200, headers, Data("{}".utf8)) }
            do {
                _ = try await WorkoutSyncTransport().send(to: .catalog, credentials: credentials(), configuration: config())
                XCTFail("The response must fail closed")
            } catch WorkoutSyncTransportError.responseTooLarge { XCTAssertTrue(expectedLarge) }
            catch WorkoutSyncTransportError.invalidResponse { XCTAssertFalse(expectedLarge) }
            catch { XCTFail("Unexpected transport result") }
        }
    }
    func testKnownConflictCodeIsRetainedWithoutPrivateDetailsAndUnknownBodiesStayGeneric() async {
        for (body, reason) in [("{\"error\":\"life_revision_conflict\",\"details\":\"private owner data\"}", WorkoutSyncRejection.lifeRevisionConflict),
                               ("{\"error\":\"manifest_conflict\"}", WorkoutSyncRejection.manifestConflict)] {
            WorkoutMockProtocol.handler = { _ in (409, ["Content-Type": "application/json"], Data(body.utf8)) }
            do {
                _ = try await WorkoutSyncTransport().send(to: .catalog, credentials: credentials(), configuration: config())
                XCTFail("A reviewed code is still a rejection")
            } catch WorkoutSyncTransportError.rejected(let received) {
                XCTAssertEqual(received, reason)
                XCTAssertFalse(received.explanation.contains("private owner data"))
            } catch { XCTFail("Known conflict must retain its reason") }
        }
        for body in ["{\"error\":\"private arbitrary text\"}", String(repeating: "x", count: 4097)] {
            WorkoutMockProtocol.handler = { _ in (409, ["Content-Type": "application/json"], Data(body.utf8)) }
            do {
                _ = try await WorkoutSyncTransport().send(to: .catalog, credentials: credentials(), configuration: config())
                XCTFail("Untrusted conflict body cannot be accepted")
            } catch WorkoutSyncTransportError.http(let status) { XCTAssertEqual(status, 409) }
            catch { XCTFail("Unknown or oversized conflict must stay generic") }
        }
    }
    func testRedirectDelegateNeverForwardsARequestOrItsCredentials() throws {
        let transport = WorkoutSyncTransport()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let origin = try XCTUnwrap(URL(string: "https://track.kunjadia.dev"))
        let target = try XCTUnwrap(URL(string: "https://attacker.invalid"))
        let task = session.dataTask(with: origin)
        let response = try XCTUnwrap(HTTPURLResponse(url: origin, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]))
        var called = false
        transport.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: target)) {
            called = true
            XCTAssertNil($0)
        }
        XCTAssertTrue(called)
    }

    func testOnlyCaptureEndpointRecognizesTypedAbsenceAndOther404sRemainFailures() async {
        let cases: [(WorkoutSyncEndpoint, String, String, Bool)] = [
            (.captures(UUID(), cursor: 0, limit: 50), "application/json", "{\"error\":\"capture_not_found\"}", true),
            (.catalog, "application/json", "{\"error\":\"capture_not_found\"}", false),
            (.captures(UUID(), cursor: 0, limit: 50), "text/html", "not found", false),
            (.captures(UUID(), cursor: 0, limit: 50), "application/json", "{\"error\":\"route_not_found\"}", false)
        ]
        for (endpoint, type, body, absent) in cases {
            WorkoutMockProtocol.handler = { _ in (404, ["Content-Type": type], Data(body.utf8)) }
            do {
                _ = try await WorkoutSyncTransport().send(to: endpoint, credentials: credentials(), configuration: config())
                XCTFail("Absence is not a success receipt")
            } catch WorkoutSyncTransportError.captureNotFound { XCTAssertTrue(absent) }
            catch WorkoutSyncTransportError.http(let status) { XCTAssertFalse(absent); XCTAssertEqual(status, 404) }
            catch { XCTFail("Unexpected transport result: \(error)") }
        }
    }
}
