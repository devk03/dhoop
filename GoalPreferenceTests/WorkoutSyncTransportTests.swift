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
        WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), credential: String(repeating: "x", count: 32))
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
}
