import Foundation

struct HealthJournalPendingPhoto: Codable, Identifiable, Equatable {
    let id: String
    let observationId: String
    let contentType: String
    let filename: String
    let bytes: Int
    let sha256: String
    var accepted = false
}
struct HealthJournalDraft: Codable, Identifiable, Equatable {
    let id: UUID
    var mutation: HealthJournalMutation
    var body: Data?
    var bodyAccepted = false
    var photos: [HealthJournalPendingPhoto] = []
    var queued = false
    var installationId: UUID?
    var conflict = false
    var needsEditing = false
    var lastError: String?
    var completed: Bool { bodyAccepted && photos.allSatisfy(\.accepted) }
    var editable: Bool { !queued && !bodyAccepted }
    var status: String {
        if completed { return "Saved to Life" }
        if conflict { return "Review conflict" }
        if bodyAccepted { return "Entry saved; photo pending" }
        if queued { return "Pending — retry to send" }
        return "Draft on this phone"
    }
    init(mutation: HealthJournalMutation) { self.id = UUID(); self.mutation = mutation }
}
struct HealthJournalState: Codable {
    var schemaVersion = 1
    var installationId: UUID?
    var drafts: [HealthJournalDraft] = []
}

/// Separate original files avoid rewriting photo bytes whenever the owner types a note.
struct HealthJournalArchive {
    let folder: URL
    static var standard: Self {
        .init(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HealthJournal", isDirectory: true))
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var directory = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
        #endif
    }
    func read() throws -> HealthJournalState {
        try prepare(); let file = folder.appendingPathComponent("drafts.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        let state = try JSONDecoder().decode(HealthJournalState.self, from: Data(contentsOf: file))
        guard state.schemaVersion == 1, Set(state.drafts.map(\.id)).count == state.drafts.count else { throw HealthJournalFailure.storage }
        return state
    }
    func save(_ state: HealthJournalState) throws { try prepare(); try protectedWrite(JSONEncoder().encode(state), to: folder.appendingPathComponent("drafts.json")) }
    func savePhoto(_ data: Data, observationId: String) throws -> HealthJournalPendingPhoto {
        try prepare(); let type = try HealthJournalMedia.type(data), id = UUID().uuidString.lowercased()
        let photo = HealthJournalPendingPhoto(id: id, observationId: observationId, contentType: type.mime,
            filename: "health-" + id + "." + type.ext, bytes: data.count, sha256: HealthJournalMedia.digest(data))
        try protectedWrite(data, to: try photoURL(photo)); return photo
    }
    func photoURL(_ photo: HealthJournalPendingPhoto) throws -> URL {
        guard UUID(uuidString: photo.id) != nil else { throw HealthJournalFailure.storage }
        return folder.appendingPathComponent(photo.id + ".original")
    }
    func photo(_ photo: HealthJournalPendingPhoto) throws -> Data {
        let data = try Data(contentsOf: photoURL(photo))
        guard data.count == photo.bytes, HealthJournalMedia.digest(data) == photo.sha256 else { throw HealthJournalFailure.storage }
        return data
    }
    private func protectedWrite(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var file = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try file.setResourceValues(values)
    }
}
