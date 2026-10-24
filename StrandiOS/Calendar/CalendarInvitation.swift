import Foundation

struct CalendarInvitation: Decodable, Equatable {
    struct Identity: Decodable, Equatable {
        let email: String?
        let displayName: String?
        let isSelf: Bool
        enum CodingKeys: String, CodingKey { case email, displayName; case isSelf = "self" }
        var label: String? { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? email }
    }
    let organizer: Identity?
    let creator: Identity?
    let selfAttendee: Identity?
    let responseStatus: String?
    let isInvitation: Bool
    let pending: Bool
    let canAccept: Bool
    let acceptBlockedReason: String?
    let scope: String
    let recurringEventId: String?
    struct OriginalStart: Decodable, Equatable { let dateTime: String?; let date: String? }
    let originalStartTime: OriginalStart?
    enum CodingKeys: String, CodingKey {
        case organizer, creator, responseStatus, isInvitation, pending, canAccept, acceptBlockedReason, scope, recurringEventId, originalStartTime
        case selfAttendee = "self"
    }
    var eligibleToAccept: Bool {
        isInvitation && canAccept && acceptBlockedReason == nil && selfAttendee?.isSelf == true
            && ["needsAction", "tentative", "declined"].contains(responseStatus ?? "")
            && ["event", "occurrence"].contains(scope) && organizer?.isSelf == false
    }
    var responseLabel: String {
        switch responseStatus {
        case "needsAction": return "Needs response"
        case "accepted": return "Accepted"
        case "tentative": return "Maybe"
        case "declined": return "Declined"
        default: return "Response unknown"
        }
    }
}

struct CalendarRSVPConfiguration: Codable, Equatable {
    var enabled = true
    let origin: String
    let installationId: UUID
    let acceptToken: String
    let accessClientId: String?
    let accessClientSecret: String?
    var valid: Bool {
        guard origin == "https://track.kunjadia.dev", acceptToken.range(of: #"^[A-Za-z0-9_-]{43,1024}$"#, options: .regularExpression) != nil else { return false }
        if accessClientId == nil && accessClientSecret == nil { return true }
        guard let id = accessClientId, let secret = accessClientSecret else { return false }
        return id.range(of: #"^[A-Za-z0-9._-]{10,256}$"#, options: .regularExpression) != nil
            && secret.range(of: #"^[A-Za-z0-9_+./=-]{20,1024}$"#, options: .regularExpression) != nil
    }
}

struct CalendarAcceptRequest: Encodable, Equatable {
    let date: String
    let eventId: String
    let expectedEtag: String
    init(date: String, event: CalendarReaderEvent) throws {
        guard CalendarReaderDates.date(date) != nil, event.source == "google", event.invitation?.eligibleToAccept == true,
              let etag = event.etag, Self.strongEtag(etag) else { throw CalendarRSVPFailure.ineligible }
        try event.validate(); self.date = date; eventId = event.id; expectedEtag = etag
    }
    static func strongEtag(_ value: String) -> Bool {
        value.utf8.count <= 1024 && value.utf8.count >= 3 && value.first == "\"" && value.last == "\""
            && !value.dropFirst().dropLast().contains(where: { $0 == "\"" || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
    }
}

struct CalendarAcceptResponse: Decodable {
    let schemaVersion: Int; let date: String; let readAt: String; let outcome: String; let event: CalendarReaderEvent
    func validate(_ request: CalendarAcceptRequest) throws {
        guard schemaVersion == 1, date == request.date, CalendarReaderDates.instant(readAt) != nil,
              ["accepted", "already_accepted"].contains(outcome), event.id == request.eventId, event.source == "google",
              event.invitation?.isInvitation == true,
              event.invitation?.responseStatus == "accepted", event.invitation?.selfAttendee?.isSelf == true,
              event.etag.map(CalendarAcceptRequest.strongEtag) == true else { throw CalendarRSVPFailure.unconfirmed }
        try event.validate()
    }
}

enum CalendarRSVPFailure: Error, LocalizedError {
    case configuration, ineligible, busy, conflict, unconfirmed, http(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Invitation acceptance is not connected. Calendar reading still works."
        case .ineligible: return "This invitation cannot be accepted here. Refresh its details."
        case .busy: return "An invitation response is already in progress."
        case .conflict: return "Invitation changed. Refresh, then tap Accept again."
        case .unconfirmed: return "Acceptance is unconfirmed. Refresh before trying again."
        case .http(let code):
            switch code {
            case 401, 403: return "Invitation acceptance access could not be verified."
            case 404: return "This invitation is no longer available."
            case 503: return "Invitation acceptance is unavailable. Refresh before retrying."
            default: return "The response could not be verified. Refresh before retrying."
            }
        }
    }
}
