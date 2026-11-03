import Foundation

struct HealthJournalRequest {
    var path: String
    var query: [URLQueryItem] = []
    var body: Data?
    var image: HealthJournalPendingPhoto?
    var expectedImage: HealthJournalImage?
    static func entries(_ filter: HealthJournalFilter = .init(), offset: Int = 0, observationId: String? = nil, before: Int? = nil) throws -> Self {
        guard filter.valid, offset >= 0, offset <= 100000 else { throw HealthJournalFailure.validation }
        var q = [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: String(offset))]
        for (k,v) in [("topicId",filter.topicId),("from",filter.from),("through",filter.through),("observationId",observationId),("beforeVersion",before.map(String.init))] {
            if let v { q.append(.init(name: k, value: v)) }
        }
        return .init(path: "entries", query: q)
    }
    func url(_ connection: HealthJournalConnection) throws -> URL {
        guard connection.valid, path == "entries" || path == "capabilities" ||
                (path.hasPrefix("images/") && UUID(uuidString: String(path.dropFirst(7))) != nil) else { throw HealthJournalFailure.configuration }
        var c = URLComponents(string: connection.endpoint + "/" + path)!
        c.queryItems = query.isEmpty ? nil : query
        guard let url = c.url else { throw HealthJournalFailure.configuration }; return url
    }
}

/// Dedicated ephemeral session; even same-origin redirects are refused. Credentials never follow a photo URL.
final class HealthJournalTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func send(_ input: HealthJournalRequest, connection: HealthJournalConnection) async throws -> Data {
        var request = URLRequest(url: try input.url(connection))
        request.httpMethod = input.body == nil ? "GET" : "POST"; request.httpBody = input.body
        request.setValue("Bearer " + connection.bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue(connection.installationId.uuidString.lowercased(), forHTTPHeaderField: "X-Dhoop-Installation-Id")
        request.setValue(connection.accessClientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(connection.accessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.setValue("DhoopHealth/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(input.expectedImage?.contentType ?? "application/json", forHTTPHeaderField: "Accept")
        if let image = input.image {
            request.setValue(image.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(image.observationId, forHTTPHeaderField: "X-Health-Observation")
            request.setValue(image.filename, forHTTPHeaderField: "X-Health-Filename")
        } else if input.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false; settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil; settings.urlCache = nil
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData; settings.timeoutIntervalForRequest = 20; settings.timeoutIntervalForResource = 45
        let reader = BoundedHTTPDataRequest(invalidResponse: HealthJournalFailure.invalidResponse, validate: { response in
            let success = response.statusCode == 200
            guard response.mimeType?.lowercased() == (success ? input.expectedImage?.contentType ?? "application/json" : "application/json") else {
                throw HealthJournalFailure.http(response.statusCode)
            }
            return success ? (input.expectedImage == nil ? 8 * 1024 * 1024 : HealthJournalMedia.limit) : 8192
        }, overflow: { _ in HealthJournalFailure.invalidResponse })
        let (data, response) = try await reader.read(request, configuration: settings)
        try Task.checkCancellation()
        let success = response.statusCode == 200
        if !success {
            struct Problem: Decodable { let code: String }
            let code = try? JSONDecoder().decode(Problem.self, from: data).code
            if response.statusCode == 409, code == "HEALTH_CHANGED" { throw HealthJournalFailure.conflict }
            if response.statusCode == 400 { throw HealthJournalFailure.validation }
            throw HealthJournalFailure.http(response.statusCode)
        }
        if let expected = input.expectedImage {
            guard expected.valid, data.count == expected.bytes, HealthJournalMedia.digest(data) == expected.sha256.lowercased(),
                  response.value(forHTTPHeaderField: "X-Health-SHA256")?.lowercased() == expected.sha256.lowercased() else {
                throw HealthJournalFailure.invalidResponse
            }
        }
        return data
    }
}
