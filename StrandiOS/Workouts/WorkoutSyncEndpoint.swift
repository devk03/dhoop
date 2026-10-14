import Foundation

enum WorkoutSyncEndpoint: Equatable {
    case catalog
    case manifest(Int)
    case sessionIndex(cursor: Int, limit: Int)
    case changes(cursor: Int, limit: Int)
    case captures(UUID, cursor: Int, limit: Int)
    case observations
    case receiptLookup
    case reconcile

    var method: String {
        switch self { case .observations, .reconcile, .receiptLookup: return "POST"; default: return "GET" }
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
        case .receiptLookup: parts.path = prefix + "receipts/lookup"
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

/// Only reviewed machine codes cross the transport boundary; arbitrary response text stays private.
enum WorkoutSyncRejection: String, Codable {
    case lifeRevisionConflict = "life_revision_conflict"
    case manifestConflict = "manifest_conflict"
    case revisionConflict = "revision_conflict"
    case prescriptionInconsistent = "prescription_inconsistent"
    case sessionRetired = "session_retired"
    case setRetired = "set_retired"
    case sourceWorkoutDeleted = "source_workout_deleted"
    case eventConflict = "event_conflict"
    case installationConflict = "installation_conflict"
    case bindingConflict = "binding_conflict"
    case exerciseBindingConflict = "exercise_binding_conflict"
    case occurrenceBindingConflict = "occurrence_binding_conflict"
    case setBindingConflict = "set_binding_conflict"

    var explanation: String {
        switch self {
        case .lifeRevisionConflict: return "The website revision changed. Compare the current tracker before reviewing a new delivery."
        case .manifestConflict: return "The prescription changed. Original workout IDs are retained; targets will not be guessed."
        case .revisionConflict: return "The tracker has different content for this source revision. Review current observations before preparing another event."
        case .prescriptionInconsistent: return "The tracker prescription is inconsistent. Review it in Life before starting."
        case .sessionRetired, .setRetired: return "The original workout target has retired. Compare its history before deciding how to correct it."
        case .sourceWorkoutDeleted: return "The tracker capture was deleted. An earlier delivery cannot restore it."
        case .eventConflict: return "The tracker has different content for this event ID. The retained delivery needs review."
        case .installationConflict: return "The original installation does not match this connection. Review the connection before sending."
        case .bindingConflict, .exerciseBindingConflict, .occurrenceBindingConflict, .setBindingConflict:
            return "The workout, exercise or set binding changed. Original IDs are retained for review."
        }
    }
}

enum WorkoutSyncTransportError: LocalizedError {
    case disabled, configuration, payloadTooLarge, invalidResponse, responseTooLarge, http(Int)
    case captureNotFound
    case rejected(WorkoutSyncRejection)
    var errorDescription: String? {
        switch self {
        case .disabled: return "Workout sync is off. Your workouts remain on this device."
        case .configuration: return "Workout sync configuration is invalid. No request was sent."
        case .payloadTooLarge: return "Workout sync exceeds the receiver's payload limit. Local entries are kept."
        case .invalidResponse: return "Workout sync received an invalid acknowledgement."
        case .responseTooLarge: return "Workout sync response exceeded its size limit."
        case .captureNotFound: return "No capture is visible for this installation. This does not prove an earlier delivery was rejected."
        case .http(let code): return "Workout sync returned HTTP \(code). Local entries are kept."
        case .rejected(let reason): return reason.explanation + " Local entries are kept."
        }
    }
}

/// An explicitly configured dedicated credential; never a sleep, buzz, MCP, or cookie credential.
struct WorkoutSyncConfiguration: Codable {
    var enabled = false
    var origin: String
    var installationId: UUID
    var credential: String
    var valid: Bool {
        (try? WorkoutSyncEndpoint.catalog.url(origin: origin)) != nil && (
            credential.range(of: #"^[0-9a-fA-F]{64,1024}$"#, options: .regularExpression) != nil ||
            credential.range(of: #"^[A-Za-z0-9_-]{43,1024}$"#, options: .regularExpression) != nil)
    }
}
