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
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method; request.httpBody = body
        request.setValue("Bearer " + credentials.credential, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.installationId.uuidString.lowercased(), forHTTPHeaderField: "X-Dhoop-Installation-Id")
        if let id = credentials.accessClientId, let secret = credentials.accessClientSecret {
            request.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DhoopWorkout/1.0", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let reader = BoundedHTTPDataRequest(invalidResponse: WorkoutSyncTransportError.invalidResponse, validate: { http in
            if http.statusCode != 200 {
                guard [404, 409].contains(http.statusCode), http.mimeType?.lowercased() == "application/json" else {
                    throw WorkoutSyncTransportError.http(http.statusCode)
                }
                return 4096
            }
            guard http.mimeType?.lowercased() == "application/json" else { throw WorkoutSyncTransportError.invalidResponse }
            return Self.responseLimit
        }, overflow: { http in
            http.statusCode == 200 ? WorkoutSyncTransportError.responseTooLarge : WorkoutSyncTransportError.http(http.statusCode)
        })
        let (result, http) = try await reader.read(request, configuration: configuration)
        try Task.checkCancellation()
        if http.statusCode != 200 {
            // Only reviewed codes survive; private response details never enter the UI.
            struct Rejection: Decodable { let error: String }
            if let body = try? JSONDecoder().decode(Rejection.self, from: result) {
                if http.statusCode == 404, case .captures = endpoint, body.error == "capture_not_found" {
                    throw WorkoutSyncTransportError.captureNotFound
                }
                if http.statusCode == 409, let reason = WorkoutSyncRejection(rawValue: body.error) {
                    throw WorkoutSyncTransportError.rejected(reason)
                }
            }
            throw WorkoutSyncTransportError.http(http.statusCode)
        }
        return result
    }
}
