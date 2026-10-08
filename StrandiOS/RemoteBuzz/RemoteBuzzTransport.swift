#if os(iOS)
import Foundation

/// Dedicated device transport. Credentials never follow redirects or enter logs/cookies.
final class RemoteBuzzTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func send(_ bytes: Data, enrollment: RemoteBuzzEnrollment) async throws -> [String: Any] {
        guard enrollment.endpoint == RemoteBuzzV2.endpoint,
              RemoteBuzzV2.bearer(enrollment.deviceBearer), bytes.count <= 8192,
              let url = URL(string: enrollment.endpoint) else { throw RemoteBuzzEnrollmentError.invalid }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = bytes
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + enrollment.deviceBearer, forHTTPHeaderField: "Authorization")
        request.setValue(enrollment.accessClientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(enrollment.accessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType == "application/json", response.expectedContentLength <= 8192
        else { throw RemoteBuzzEnrollmentError.invalid }
        var result = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard result.count < 8192 else { throw RemoteBuzzEnrollmentError.invalid }
            result.append(byte)
        }
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any]
        else { throw RemoteBuzzEnrollmentError.invalid }
        return object
    }
}
#endif
