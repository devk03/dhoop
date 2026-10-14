import Foundation

/// Bounded ephemeral requests. It does not schedule, retry, activate, or log credentials.
final class WorkoutSyncTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let bodyLimit = 128 * 1024
    static let responseLimit = 1024 * 1024

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func send(to endpoint: WorkoutSyncEndpoint, body: Data? = nil, credentials: WorkoutSyncConfiguration,
              configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        try Task.checkCancellation()
        guard credentials.enabled else { throw WorkoutSyncTransportError.disabled }
        guard credentials.valid else {
            throw WorkoutSyncTransportError.configuration
        }
        let url = try endpoint.url(origin: credentials.origin)
        guard (body?.count ?? 0) <= Self.bodyLimit else { throw WorkoutSyncTransportError.payloadTooLarge }
        guard (endpoint.method == "GET" && body == nil) || (endpoint.method == "POST" && body != nil) else {
            throw WorkoutSyncTransportError.configuration
        }
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method; request.httpBody = body
        request.setValue("Bearer " + credentials.credential, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.installationId.uuidString.lowercased(), forHTTPHeaderField: "X-Dhoop-Installation-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw WorkoutSyncTransportError.invalidResponse }
        guard http.statusCode == 200 else { throw WorkoutSyncTransportError.http(http.statusCode) }
        guard http.mimeType?.lowercased() == "application/json" else { throw WorkoutSyncTransportError.invalidResponse }
        guard response.expectedContentLength <= Self.responseLimit else { throw WorkoutSyncTransportError.responseTooLarge }
        var result = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard result.count < Self.responseLimit else { throw WorkoutSyncTransportError.responseTooLarge }
            result.append(byte)
        }
        return result
    }
}
