import Foundation

/// Only reviewed machine codes cross the HTTP boundary; receiver prose is never displayed.
enum LifeSyncReceiverCode: String, Codable, Sendable {
    case unauthorized, notConfigured = "not_configured", saveFailed = "save_failed", writeConflict = "write_conflict"
    case identityConflict = "identity_conflict", installationConflict = "installation_conflict"
    case eventConflict = "event_conflict", revisionConflict = "revision_conflict"
    case invalidPayload = "invalid_payload", invalidOrigin = "invalid_origin", payloadTooLarge = "payload_too_large"
    case unsupportedMediaType = "unsupported_media_type", unsupportedEncoding = "unsupported_encoding"
    case unsupportedSchema = "unsupported_schemaVersion", unsupportedSource = "unsupported_source"
    case unsupportedMethod = "unsupported_method", unsupportedTimeZone = "unsupported_timeZone"
    case legacyTimeZone = "unsupported_time_zone", unsupportedKind = "unsupported_kind", unsupportedCoverage = "unsupported_coverage"
    case notFound = "not_found"
    func matches(status: Int) -> Bool {
        switch self {
        case .unauthorized: return status == 401
        case .notConfigured, .saveFailed, .writeConflict: return status == 503
        case .identityConflict, .installationConflict, .eventConflict, .revisionConflict: return status == 409
        case .invalidPayload, .invalidOrigin: return status == 400
        case .payloadTooLarge: return status == 413
        case .unsupportedMediaType, .unsupportedEncoding: return status == 415
        case .unsupportedMethod: return status == 405 || status == 422
        case .notFound: return status == 404
        default: return status == 422
        }
    }
    var guidance: String {
        switch self {
        case .unauthorized, .invalidOrigin: return "Life rejected the connection. Review the connection settings; your pending summary is retained."
        case .notConfigured: return "Life's receiver is not configured. Review the website connection before retrying."
        case .saveFailed, .writeConflict: return "Life could not save the summary yet. Retry later; the same pending event is retained."
        case .identityConflict, .installationConflict, .eventConflict, .revisionConflict:
            return "Life found a delivery identity conflict. Review the connection; do not replace the pending event."
        case .notFound: return "The Life receiver could not be found. Review the endpoint in connection settings."
        default: return "Life could not accept this summary format. Update the app or review the connection; the pending event is retained."
        }
    }
}

/// Estimates use the last completed snapshot, never an interrupted pass or a changed read fence.
struct SleepExportReadiness: Equatable {
    let computing: Bool
    let rescoreOwed: Bool
    let generation: String?
    let completedPass: Bool
    init(computing: Bool, rescoreOwed: Bool, generation: String?, completedPass: Bool = false) {
        self.computing = computing
        self.rescoreOwed = rescoreOwed
        self.generation = generation
        self.completedPass = completedPass
    }
    func allows(estimated: Bool, after read: Self) -> Bool {
        // Official imports are already committed independently of local scoring.
        guard estimated else { return true }
        guard self == read, !computing else { return false }
        guard rescoreOwed else { return true }
        // A completed pass may leave newer debt outstanding. Its persisted estimate can be
        // corrected later; this does not claim that the newer raw inputs have been scored.
        return completedPass && generation?.isEmpty == false
    }
}
