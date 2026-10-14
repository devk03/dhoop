import Foundation

enum WorkoutSyncEndpoint: Equatable {
    case catalog
    case manifest(Int)
    case sessionIndex(cursor: Int, limit: Int)
    case changes(cursor: Int, limit: Int)
    case captures(UUID, cursor: Int, limit: Int)
    case observations
    case reconcile

    var method: String {
        switch self { case .observations, .reconcile: return "POST"; default: return "GET" }
    }

    /// This integration has one reviewed owner origin. No default configuration is implied.
    func url(origin: String) throws -> URL {
        guard var parts = URLComponents(string: origin), parts.scheme == "https",
              parts.host?.lowercased() == "track.kunjadia.dev", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw WorkoutSyncTransportError.configuration }
        let prefix = "/api/integrations/dhoop/workouts/"
        var items: [URLQueryItem] = []
        switch self {
        case .catalog: parts.path = prefix + "catalog"
        case .manifest(let id):
            guard id > 0 else { throw WorkoutSyncTransportError.configuration }
            parts.path = prefix + "manifest"; items = [URLQueryItem(name: "sessionId", value: String(id))]
        case .sessionIndex(let cursor, let limit):
            guard cursor >= 0, (1...100).contains(limit) else { throw WorkoutSyncTransportError.configuration }
            parts.path = prefix + "manifest"; items = pagination(cursor, limit)
        case .changes(let cursor, let limit):
            guard cursor >= 0, (1...100).contains(limit) else { throw WorkoutSyncTransportError.configuration }
            parts.path = prefix + "changes"; items = pagination(cursor, limit)
        case .captures(let id, let cursor, let limit):
            guard cursor >= 0, (1...50).contains(limit) else { throw WorkoutSyncTransportError.configuration }
            parts.path = prefix + "captures"
            items = [URLQueryItem(name: "sourceWorkoutId", value: id.uuidString.lowercased())] + pagination(cursor, limit)
        case .observations: parts.path = "/api/webhooks/workouts"
        case .reconcile: parts.path = prefix + "reconcile"
        }
        parts.queryItems = items.isEmpty ? nil : items
        guard let url = parts.url else { throw WorkoutSyncTransportError.configuration }
        return url
    }

    private func pagination(_ cursor: Int, _ limit: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "cursor", value: String(cursor)), URLQueryItem(name: "limit", value: String(limit))]
    }
}

enum WorkoutSyncTransportError: LocalizedError {
    case disabled, configuration, payloadTooLarge, invalidResponse, responseTooLarge, http(Int)
    var errorDescription: String? {
        switch self {
        case .disabled: return "Workout sync is off. Your workouts remain on this device."
        case .configuration: return "Workout sync configuration is invalid. No request was sent."
        case .payloadTooLarge: return "Workout sync exceeds the receiver's payload limit. Local entries are kept."
        case .invalidResponse: return "Workout sync received an invalid acknowledgement."
        case .responseTooLarge: return "Workout sync response exceeded its size limit."
        case .http(let code): return "Workout sync returned HTTP \(code). Local entries are kept."
        }
    }
}

/// An explicitly configured dedicated credential; never a sleep, buzz, MCP, or cookie credential.
struct WorkoutSyncConfiguration {
    var enabled = false
    var origin: String
    var installationId: UUID
    var credential: String
}
