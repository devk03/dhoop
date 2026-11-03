import Foundation
import CryptoKit

/// Personal Life frontend contract; no strap database or physiological inference is involved.
struct HealthJournalConnection: Codable, Equatable {
    var schemaVersion = 1
    var endpoint: String
    var bearerToken: String
    var installationId: UUID
    var accessClientId: String
    var accessClientSecret: String
    var valid: Bool {
        schemaVersion == 1 && endpoint == Self.endpoint && bearerToken.count >= 43 && bearerToken.count <= 1024 && bearerToken.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil &&
        [bearerToken, accessClientId, accessClientSecret].allSatisfy { !$0.isEmpty && !$0.contains(where: { $0.isNewline || $0.isWhitespace }) }
    }
    static let endpoint = "https://track.kunjadia.dev/api/integrations/dhoop/health"
}

struct HealthJournalTopic: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var bodyArea: String
    var side: String
    var status: String
    var version: Int
    let createdAt: String
    var updatedAt: String
}
struct HealthJournalImage: Codable, Identifiable, Equatable {
    let id: String
    let observationId: String
    let contentType: String
    let bytes: Int
    let sha256: String
    let filename: String
    let recordedAt: String
    let source: String
    let url: String
    var valid: Bool {
        UUID(uuidString: id) != nil && UUID(uuidString: observationId) != nil && bytes > 0 && bytes <= HealthJournalMedia.limit &&
        HealthJournalMedia.types.contains(contentType) && sha256.count == 64 && sha256.allSatisfy(\.isHexDigit) &&
        url == "/api/integrations/dhoop/health/images/" + id
    }
}
struct HealthJournalObservation: Codable, Identifiable, Equatable {
    let id: String
    let topicId: String
    var observedAt: String
    var timeZone: String
    let recordedAt: String
    var notes: String
    var symptoms: String
    let source: String
    var version: Int
    var updatedAt: String
    // Write receipts omit images; timeline/detail responses include them.
    var images: [HealthJournalImage]?
}
struct HealthJournalRevision: Codable, Identifiable, Equatable {
    let version: Int
    let snapshot: HealthJournalObservation
    let recordedAt: String
    let source: String
    var id: Int { version }
}
struct HealthJournalDocument: Codable, Equatable {
    var topics: [HealthJournalTopic]
    var observations: [HealthJournalObservation]
    var nextOffset: Int?
    var revisions: [HealthJournalRevision]?
    var nextBeforeVersion: Int?
    static let empty = Self(topics: [], observations: [], nextOffset: nil)
    func validate() throws {
        guard topics.count <= 500, observations.count <= 50, (nextOffset ?? 0) >= 0,
              Set(topics.map(\.id)).count == topics.count, Set(observations.map(\.id)).count == observations.count,
              topics.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.version > 0 }),
              observations.allSatisfy({ row in
                  UUID(uuidString: row.id) != nil && UUID(uuidString: row.topicId) != nil && row.version > 0 &&
                  HealthJournalDates.valid(row.observedAt, zone: row.timeZone) && (row.images ?? []).count <= 8 &&
                  (row.images ?? []).allSatisfy { $0.valid && $0.observationId == row.id }
              }) else { throw HealthJournalFailure.invalidResponse }
    }
}
struct HealthJournalFilter: Codable, Equatable {
    var topicId: String?
    var from: String?
    var through: String?
    var valid: Bool {
        (topicId == nil || UUID(uuidString: topicId!) != nil) && [from, through].compactMap { $0 }.allSatisfy(HealthJournalDates.validDay) &&
        (from == nil || through == nil || from! <= through!)
    }
}

struct HealthJournalCapabilities: Decodable {
    let schemaVersion: Int
    let read: Bool
    let write: Bool
    let imagesOptional: Bool
    let correctionHistory: Bool
    var inlineTopicCreation: Bool? = nil
    var valid: Bool { schemaVersion == 1 && read && write && imagesOptional && correctionHistory }
}

struct HealthJournalNewTopic: Codable, Equatable {
    var title: String
    var bodyArea: String
    var side: String
    var status: String
    var normalized: Self {
        .init(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
              bodyArea: bodyArea.trimmingCharacters(in: .whitespacesAndNewlines), side: side, status: status)
    }
    func validate() throws {
        let value = normalized
        guard !value.title.isEmpty, value.title.utf16.count <= 120,
              !value.bodyArea.isEmpty, value.bodyArea.utf16.count <= 120,
              ["left", "right", "both", "center", "unspecified"].contains(side),
              ["open", "closed"].contains(status) else { throw HealthJournalFailure.validation }
    }
}

/// All optional fields are omitted by Codable, matching Life's strict discriminated schema.
struct HealthJournalMutation: Codable, Equatable {
    var action: String
    var requestId: String
    var id: String
    var topicId: String?
    var expectedVersion: Int?
    var title: String?
    var bodyArea: String?
    var side: String?
    var status: String?
    var observedAt: String?
    var timeZone: String?
    var notes: String?
    var symptoms: String?
    var newTopic: HealthJournalNewTopic? = nil
    func validate() throws {
        guard UUID(uuidString: id) != nil, UUID(uuidString: requestId) != nil else { throw HealthJournalFailure.validation }
        if let newTopic {
            guard action == "observe" else { throw HealthJournalFailure.validation }; try newTopic.validate()
        }
        if action == "topic" {
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 120,
                  let bodyArea, !bodyArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, bodyArea.utf16.count <= 120,
                  ["left", "right", "both", "center", "unspecified"].contains(side ?? ""), ["open", "closed"].contains(status ?? ""),
                  let expectedVersion, expectedVersion >= 0, topicId == nil, observedAt == nil, notes == nil, symptoms == nil, timeZone == nil else {
                throw HealthJournalFailure.validation
            }
        } else {
            guard ["observe", "correct"].contains(action), let observedAt, let timeZone,
                  HealthJournalDates.valid(observedAt, zone: timeZone), let notes, notes.utf16.count <= 20000,
                  let symptoms, symptoms.utf16.count <= 4000, title == nil, bodyArea == nil, side == nil, status == nil else {
                throw HealthJournalFailure.validation
            }
            guard action == "observe" ? (topicId.flatMap(UUID.init(uuidString:)) != nil && expectedVersion == nil) :
                    (topicId == nil && (expectedVersion ?? 0) >= 1) else { throw HealthJournalFailure.validation }
        }
    }
    static func entry(topicId: String, now: Date = Date(), zone: String = TimeZone.current.identifier) -> Self {
        .init(action: "observe", requestId: UUID().uuidString.lowercased(), id: UUID().uuidString.lowercased(), topicId: topicId,
              observedAt: HealthJournalDates.timestamp(now, zone: zone), timeZone: zone, notes: "", symptoms: "")
    }
    static func newEntry(now: Date = Date(), zone: String = TimeZone.current.identifier) -> Self {
        var result = entry(topicId: UUID().uuidString.lowercased(), now: now, zone: zone)
        result.newTopic = .init(title: NSLocalizedString("General", comment: ""), bodyArea: NSLocalizedString("Unspecified", comment: ""), side: "unspecified", status: "open")
        return result
    }
    static func correction(_ entry: HealthJournalObservation) -> Self {
        .init(action: "correct", requestId: UUID().uuidString.lowercased(), id: entry.id, expectedVersion: entry.version,
              observedAt: entry.observedAt, timeZone: entry.timeZone, notes: entry.notes, symptoms: entry.symptoms)
    }
    static func topic(_ topic: HealthJournalTopic? = nil) -> Self {
        .init(action: "topic", requestId: UUID().uuidString.lowercased(), id: topic?.id ?? UUID().uuidString.lowercased(),
              expectedVersion: topic?.version ?? 0, title: topic?.title ?? "", bodyArea: topic?.bodyArea ?? "",
              side: topic?.side ?? "unspecified", status: topic?.status ?? "open")
    }
}

enum HealthJournalDates {
    static func instant(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: value)
    }
    static func timestamp(_ date: Date, zone: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: zone); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return f.string(from: date)
    }
    static func valid(_ text: String, zone: String) -> Bool {
        guard let timeZone = TimeZone(identifier: zone), let date = instant(text), text.count >= 20 else { return false }
        let offset = text.hasSuffix("Z") || text.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return offset && f.string(from: date) == String(text.prefix(19))
    }
    static func validDay(_ day: String) -> Bool {
        guard day.count == 10 else { return false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: day).map { f.string(from: $0) == day } ?? false
    }
    static func display(_ text: String, zone: String) -> String {
        guard let date = instant(text), let zone = TimeZone(identifier: zone) else { return text }
        let f = DateFormatter(); f.locale = .current; f.timeZone = zone; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date) + " " + (zone.abbreviation(for: date) ?? zone.identifier)
    }
}

enum HealthJournalMedia {
    static let limit = 10 * 1024 * 1024
    static let types = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func type(_ data: Data) throws -> (mime: String, ext: String) {
        guard !data.isEmpty, data.count <= limit else { throw HealthJournalFailure.media }
        let a = Array(data.prefix(64))
        if a.count >= 4, a[0...2].elementsEqual([255, 216, 255]) { return ("image/jpeg", "jpg") }
        if a.count >= 24, a.prefix(8).elementsEqual([137,80,78,71,13,10,26,10]) { return ("image/png", "png") }
        if a.count >= 16, String(bytes: a[0..<4], encoding: .ascii) == "RIFF", String(bytes: a[8..<12], encoding: .ascii) == "WEBP" { return ("image/webp", "webp") }
        if a.count >= 24, String(bytes: a[4..<8], encoding: .ascii) == "ftyp" {
            let brands = String(bytes: a[8...], encoding: .ascii) ?? ""
            if ["heic", "heix", "hevc", "hevx"].contains(where: brands.contains) { return ("image/heic", "heic") }
            if ["mif1", "msf1"].contains(where: brands.contains) { return ("image/heif", "heif") }
        }
        throw HealthJournalFailure.media
    }
}

enum HealthJournalFailure: Error, LocalizedError, Equatable {
    case configuration, invalidResponse, validation, media, storage, conflict, inlineTopicUnavailable, http(Int)
    var errorDescription: String? {
        switch self {
        case .inlineTopicUnavailable: return "New topic creation is unavailable. Your entry stays on this phone."
        case .configuration: return "Connect Health to Life. Your drafts are kept."
        case .invalidResponse: return "Health data could not be verified. Refresh to try again."
        case .validation: return "Check the topic, date, notes and symptoms. Your draft is kept."
        case .media: return "Choose up to eight JPEG, PNG, WebP or HEIC photos, each up to 10 MB."
        case .storage: return "The draft could not be saved on this phone. Keep this screen open and try again."
        case .conflict: return "This entry changed. Review the latest version before saving your draft."
        case .http(let status):
            if [401,403,302].contains(status) { return "Health access needs reconnecting. Your drafts are kept." }
            if status == 409 { return "Health connection or entry changed. Refresh and review your draft." }
            return "Life could not be reached. Your draft is kept; retry when connected."
        }
    }
}
