import Foundation

/// The only native Calendar mutation is an explicit self Accept using its independently enrolled credential.
final class CalendarRSVPTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func send(configuration: CalendarRSVPConfiguration, accept: CalendarAcceptRequest?) async throws -> Data {
        guard configuration.valid, configuration.enabled else { throw CalendarRSVPFailure.configuration }
        let suffix = accept == nil ? "capabilities" : "accept"
        let settings = URLSessionConfiguration.ephemeral; settings.httpShouldSetCookies = false; settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil; settings.urlCache = nil; settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 12; settings.timeoutIntervalForResource = 20
        let session = URLSession(configuration: settings, delegate: self, delegateQueue: nil); defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: configuration.origin + "/api/integrations/dhoop/calendar-rsvp/" + suffix)!)
        request.httpMethod = accept == nil ? "GET" : "POST"
        if let accept {
            let body = try JSONEncoder().encode(accept); guard body.count <= 4096 else { throw CalendarRSVPFailure.ineligible }
            request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer " + configuration.acceptToken, forHTTPHeaderField: "Authorization")
        request.setValue(configuration.installationId.uuidString.lowercased(), forHTTPHeaderField: "X-Dhoop-Installation-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("DhoopCalendarRSVP/1.0", forHTTPHeaderField: "User-Agent")
        if let id = configuration.accessClientId, let secret = configuration.accessClientSecret {
            request.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id"); request.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CalendarRSVPFailure.unconfirmed }
        let limit = response.statusCode == 200 ? 1024 * 1024 : 4096
        guard response.mimeType?.lowercased() == "application/json", response.expectedContentLength <= limit else {
            throw CalendarRSVPFailure.http(response.statusCode)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation(); guard data.count < limit else { throw CalendarRSVPFailure.unconfirmed }; data.append(byte)
        }
        if response.statusCode == 409 { throw CalendarRSVPFailure.conflict }
        guard response.statusCode == 200 else { throw CalendarRSVPFailure.http(response.statusCode) }
        return data
    }
}
