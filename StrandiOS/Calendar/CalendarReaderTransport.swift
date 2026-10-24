import Foundation

/// A separate GET-only transport. Calendar credentials never enter the workout transport.
final class CalendarReaderTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let responseLimit = 1024 * 1024
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func send(_ endpoint: CalendarReaderEndpoint, configuration: CalendarReaderConfiguration) async throws -> Data {
        guard configuration.enabled else { throw CalendarReaderFailure.disabled }
        guard configuration.valid else { throw CalendarReaderFailure.configuration }
        try Task.checkCancellation()
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false; settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil
        settings.urlCache = nil; settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 12; settings.timeoutIntervalForResource = 20
        let session = URLSession(configuration: settings, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try endpoint.url(origin: configuration.origin)); request.httpMethod = "GET"
        request.setValue("Bearer " + configuration.readToken, forHTTPHeaderField: "Authorization")
        request.setValue(configuration.installationId.uuidString.lowercased(), forHTTPHeaderField: "X-Dhoop-Installation-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DhoopCalendar/1.0", forHTTPHeaderField: "User-Agent")
        if let id = configuration.accessClientId, let secret = configuration.accessClientSecret {
            request.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CalendarReaderFailure.invalidResponse }
        let success = response.statusCode == 200
        let limit = success ? Self.responseLimit : 4096
        guard response.mimeType?.lowercased() == "application/json", response.expectedContentLength <= limit else {
            throw success ? CalendarReaderFailure.invalidResponse : CalendarReaderFailure.http(response.statusCode)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw success ? CalendarReaderFailure.http(413) : CalendarReaderFailure.http(response.statusCode) }
            data.append(byte)
        }
        if !success {
            struct Failure: Decodable { struct Problem: Decodable { let code: String }; let error: Problem }
            if response.statusCode == 409, (try? JSONDecoder().decode(Failure.self, from: data).error.code) == "CALENDAR_SNAPSHOT_CONFLICT" {
                throw CalendarReaderFailure.snapshotChanged
            }
            throw CalendarReaderFailure.http(response.statusCode)
        }
        return data
    }
}
