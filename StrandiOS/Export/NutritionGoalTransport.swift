import Foundation

/// Only the existing protein credential can access this independently gated goal resource.
final class NutritionGoalTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func send(_ write: NutritionGoalWrite?, connection: NutritionGoalConnection) async throws -> Data {
        guard connection.valid else { throw NutritionGoalFailure.unavailable }
        var components = URLComponents(string: connection.credentials.endpoint)!
        if write == nil { components.queryItems = [.init(name: "resource", value: "nutrition-goals")] }
        let settings = URLSessionConfiguration.ephemeral; settings.httpShouldSetCookies = false; settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil; settings.urlCache = nil; settings.timeoutIntervalForRequest = 12; settings.timeoutIntervalForResource = 20
        let session = URLSession(configuration: settings, delegate: self, delegateQueue: nil); defer { session.invalidateAndCancel() }
        var request = URLRequest(url: components.url!); request.httpMethod = write == nil ? "GET" : "POST"
        if let write {
            let bytes = try JSONEncoder().encode(write); guard bytes.count <= 16384 else { throw NutritionGoalFailure.invalid }
            request.httpBody = bytes; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DhoopNutritionGoals/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer " + connection.credentials.proteinBearer!, forHTTPHeaderField: "Authorization")
        request.setValue(connection.installationId, forHTTPHeaderField: "X-Dhoop-Installation-Id")
        request.setValue(connection.credentials.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(connection.credentials.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NutritionGoalFailure.unconfirmed }
        guard http.mimeType == "application/json" else {
            if http.statusCode != 200 { throw NutritionGoalFailure.response(http.statusCode, nil) }
            throw NutritionGoalFailure.unconfirmed
        }
        let limit = http.statusCode == 200 ? 131072 : 4096
        guard http.expectedContentLength <= limit else { throw NutritionGoalFailure.unconfirmed }
        var data = Data()
        for try await byte in stream { try Task.checkCancellation(); guard data.count < limit else { throw NutritionGoalFailure.unconfirmed }; data.append(byte) }
        if http.statusCode != 200 {
            struct Rejection: Decodable { let error: String }
            let code = try? JSONDecoder().decode(Rejection.self, from: data).error
            let allowed = ["unauthorized", "installation_conflict", "nutrition_goal_conflict", "invalid_nutrition_goal", "nutrition_goals_not_enabled", "nutrition_goals_unavailable", "invalid_query"]
            throw NutritionGoalFailure.response(http.statusCode, code.flatMap { allowed.contains($0) ? $0 : nil })
        }
        return data
    }
}
