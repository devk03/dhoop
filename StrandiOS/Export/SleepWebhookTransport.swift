import Foundation

/// Ephemeral transport with no cookie jar/cache and no redirect following. Neither errors nor logs
/// contain receiver bodies, endpoint URLs or credentials.
final class SleepWebhookTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func send(_ bytes: Data, credentials: SleepWebhookCredentials,
              configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        guard credentials.isValid, let url = SleepWebhookDelivery.endpointURL(credentials.endpoint), bytes.count <= 16_384 else {
            throw SleepWebhookFailure.invalidConfiguration
        }
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bytes
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Dhoop/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer " + credentials.bearer, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(credentials.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw SleepWebhookFailure.invalidAcknowledgement }
        guard http.statusCode == 200 else { throw SleepWebhookFailure.http(http.statusCode) }
        guard http.mimeType?.lowercased() == "application/json" else { throw SleepWebhookFailure.invalidAcknowledgement }
        if response.expectedContentLength > 16_384 { throw SleepWebhookFailure.responseTooLarge }
        var result = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard result.count < 16_384 else { throw SleepWebhookFailure.responseTooLarge }
            result.append(byte)
        }
        return result
    }
}
