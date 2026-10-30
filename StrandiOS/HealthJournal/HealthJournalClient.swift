import Foundation
import Combine

/// Foreground, owner-driven Health operations. The Life backend remains the record authority.
@MainActor
final class HealthJournalClient: ObservableObject {
    static let shared = HealthJournalClient()
    @Published private(set) var connection: HealthJournalConnection?
    @Published private(set) var state = HealthJournalState()
    @Published private(set) var document = HealthJournalDocument.empty
    @Published private(set) var filter = HealthJournalFilter()
    @Published private(set) var loading = false
    @Published private(set) var sending = false
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    @Published private(set) var storageError = false
    private var corruptArchive = false
    private var generation = 0
    private var readTicket = UUID()
    private let archive: HealthJournalArchive
    private let credentialRead: () throws -> HealthJournalConnection?
    private let credentialSave: (HealthJournalConnection) throws -> Void
    private let transport: (HealthJournalRequest, HealthJournalConnection) async throws -> Data
    var pending: [HealthJournalDraft] { state.drafts.filter { !$0.completed } }
    init(archive: HealthJournalArchive = .standard,
         read: @escaping () throws -> HealthJournalConnection? = HealthJournalKeychain.read,
         save: @escaping (HealthJournalConnection) throws -> Void = HealthJournalKeychain.save,
         send: @escaping (HealthJournalRequest, HealthJournalConnection) async throws -> Data = { try await HealthJournalTransport().send($0, connection: $1) }) {
        self.archive = archive; credentialRead = read; credentialSave = save; transport = send
        do { state = try archive.read() } catch { storageError = true; corruptArchive = true; self.error = HealthJournalFailure.storage.localizedDescription }
        do { connection = try read(); guard connection?.valid != false else { throw HealthJournalFailure.configuration } }
        catch { connection = nil; self.error = HealthJournalFailure.configuration.localizedDescription }
    }
    func reloadWhenAccessible() {
        if corruptArchive {
            do { state = try archive.read(); corruptArchive = false; storageError = false; error = nil } catch { return }
        }
        if connection == nil {
            do {
                let candidate = try credentialRead()
                guard candidate?.valid != false, state.installationId == nil || candidate?.installationId == state.installationId else { return }
                connection = candidate
            } catch { }
        }
    }
    private func persist(_ next: HealthJournalState) throws {
        guard !corruptArchive else { throw HealthJournalFailure.storage }
        state = next
        do { try archive.save(next); storageError = false }
        catch { storageError = true; self.error = HealthJournalFailure.storage.localizedDescription; throw HealthJournalFailure.storage }
    }
    func flush() { do { try persist(state) } catch { self.error = Self.message(error) } }
    func draft(_ id: UUID) -> HealthJournalDraft? { state.drafts.first { $0.id == id } }
    func create(_ mutation: HealthJournalMutation) throws -> UUID {
        let draft = HealthJournalDraft(mutation: mutation)
        var next = state; next.drafts.append(draft); try persist(next); return draft.id
    }
    func edit(_ id: UUID, mutation: HealthJournalMutation) {
        guard let index = state.drafts.firstIndex(where: { $0.id == id }), state.drafts[index].editable else { return }
        var next = state; next.drafts[index].mutation = mutation
        do { try persist(next) } catch { self.error = Self.message(error) }
    }
    func addPhoto(_ data: Data, draftId: UUID, existingCount: Int = 0) async throws {
        guard let initial = draft(draftId), initial.editable, initial.mutation.action != "topic", initial.photos.count + existingCount < 8 else { throw HealthJournalFailure.media }
        let store = archive, parent = initial.mutation.id
        let photo = try await Task.detached(priority: .utility) { try store.savePhoto(data, observationId: parent) }.value
        guard let index = state.drafts.firstIndex(where: { $0.id == draftId }), state.drafts[index].editable,
              state.drafts[index].photos.count + existingCount < 8 else { throw HealthJournalFailure.media }
        var next = state; next.drafts[index].photos.append(photo); try persist(next)
    }
    func removePhoto(_ id: String, draftId: UUID) throws {
        guard let index = state.drafts.firstIndex(where: { $0.id == draftId }), state.drafts[index].editable else { return }
        var next = state; next.drafts[index].photos.removeAll { $0.id == id }; try persist(next)
        // Original files are retained; no server record or original is deleted by editing a draft.
    }
    func install(_ candidate: HealthJournalConnection) async throws {
        guard candidate.valid, !sending else { throw HealthJournalFailure.configuration }
        if let old = try credentialRead(), old.endpoint != candidate.endpoint || old.installationId != candidate.installationId { throw HealthJournalFailure.configuration }
        if let old = state.installationId, old != candidate.installationId { throw HealthJournalFailure.configuration }
        let version = generation
        struct Capability: Decodable { let schemaVersion: Int; let read: Bool; let write: Bool; let imagesOptional: Bool; let correctionHistory: Bool }
        let capability = try JSONDecoder().decode(Capability.self, from: await transport(.init(path: "capabilities"), candidate))
        guard capability.schemaVersion == 1, capability.read, capability.write, capability.imagesOptional, capability.correctionHistory else { throw HealthJournalFailure.invalidResponse }
        let page = try await readPage(.entries(), candidate)
        try Task.checkCancellation(); guard version == generation else { throw CancellationError() }
        // Save and verify credential only after authenticated reads; never replay drafts during setup.
        try credentialSave(candidate); guard try credentialRead() == candidate else { throw HealthJournalFailure.configuration }
        var next = state; next.installationId = candidate.installationId; try persist(next)
        generation += 1; connection = candidate; readTicket = UUID(); loading = false; filter = .init(); document = page; loaded = true; error = nil
    }
    func refresh(_ selected: HealthJournalFilter? = nil, more: Bool = false) async {
        guard let connection, connection.valid else { error = HealthJournalFailure.configuration.localizedDescription; return }
        let desired = selected ?? filter
        guard desired.valid else { error = HealthJournalFailure.validation.localizedDescription; return }
        let isMore = more && desired == filter && loaded
        guard !isMore || document.nextOffset != nil else { return }
        let offset = isMore ? document.nextOffset! : 0, ticket = UUID(), version = generation
        readTicket = ticket; loading = true; error = nil
        if desired != filter { filter = desired; document = .empty; loaded = false }
        defer { if ticket == readTicket { loading = false } }
        do {
            let page = try await readPage(.entries(desired, offset: offset), connection)
            try Task.checkCancellation(); guard ticket == readTicket, version == generation else { return }
            if isMore {
                var next = page
                var merged = document.observations
                for row in page.observations {
                    if let i = merged.firstIndex(where: { $0.id == row.id }) { merged[i] = row } else { merged.append(row) }
                }
                next.observations = merged; document = next
            } else { document = page }
            loaded = true
        } catch is CancellationError { }
        catch { if ticket == readTicket, version == generation { self.error = Self.message(error) } }
    }
    func detail(_ id: String, before: Int? = nil) async throws -> HealthJournalDocument {
        guard let connection else { throw HealthJournalFailure.configuration }
        let version = generation
        let result = try await readPage(.entries(observationId: id, before: before), connection)
        try Task.checkCancellation(); guard version == generation, result.observations.count == 1, result.observations.first?.id == id else { throw HealthJournalFailure.invalidResponse }
        return result
    }
    private func readPage(_ request: HealthJournalRequest, _ connection: HealthJournalConnection) async throws -> HealthJournalDocument {
        let data = try await transport(request, connection)
        let result = try JSONDecoder().decode(HealthJournalDocument.self, from: data); try result.validate(); return result
    }
    func image(_ image: HealthJournalImage) async throws -> Data {
        guard let connection, image.valid else { throw HealthJournalFailure.configuration }
        let version = generation
        let bytes = try await transport(.init(path: "images/" + image.id, expectedImage: image), connection)
        try Task.checkCancellation()
        guard version == generation, bytes.count == image.bytes, HealthJournalMedia.digest(bytes) == image.sha256.lowercased() else { throw HealthJournalFailure.invalidResponse }
        return bytes
    }
    func send(_ id: UUID) async {
        guard !sending, !corruptArchive, let connection, connection.valid,
              let index = state.drafts.firstIndex(where: { $0.id == id }), !state.drafts[index].completed else { return }
        guard !state.drafts[index].conflict else { error = HealthJournalFailure.conflict.localizedDescription; return }
        sending = true; error = nil
        defer { sending = false }
        do {
            var next = state, item = next.drafts[index]
            guard item.installationId == nil || item.installationId == connection.installationId else { throw HealthJournalFailure.configuration }
            if item.body == nil {
                try item.mutation.validate(); item.body = try JSONEncoder().encode(item.mutation)
                guard item.body!.count <= 131072 else { throw HealthJournalFailure.validation }
            }
            item.queued = true; item.installationId = connection.installationId; item.lastError = nil; item.needsEditing = false
            next.drafts[index] = item; try persist(next)
            if !item.bodyAccepted {
                let data = try await transport(.init(path: "entries", body: item.body), connection)
                struct Receipt: Decodable { let id: String; let version: Int }
                let receipt = try JSONDecoder().decode(Receipt.self, from: data)
                guard receipt.id == item.mutation.id, receipt.version > 0 else { throw HealthJournalFailure.invalidResponse }
                next = state; next.drafts[index].bodyAccepted = true; try persist(next)
            }
            // Each successful photo receipt is durable before attempting the next original.
            for photoIndex in state.drafts[index].photos.indices where !state.drafts[index].photos[photoIndex].accepted {
                let photo = state.drafts[index].photos[photoIndex], store = archive
                let bytes = try await Task.detached(priority: .utility) { try store.photo(photo) }.value
                let data = try await transport(.init(path: "images/" + photo.id, body: bytes, image: photo), connection)
                let receipt = try JSONDecoder().decode(HealthJournalImage.self, from: data)
                guard receipt.valid, receipt.id == photo.id, receipt.observationId == photo.observationId,
                      receipt.sha256 == photo.sha256, receipt.bytes == photo.bytes, receipt.contentType == photo.contentType,
                      receipt.filename == photo.filename else { throw HealthJournalFailure.invalidResponse }
                next = state; next.drafts[index].photos[photoIndex].accepted = true; try persist(next)
            }
            next = state; next.drafts[index].lastError = nil; try persist(next)
            await refresh()
        } catch {
            var next = state
            next.drafts[index].lastError = Self.message(error)
            next.drafts[index].conflict = (error as? HealthJournalFailure) == .conflict
            next.drafts[index].needsEditing = (error as? HealthJournalFailure) == .validation
            do { try persist(next) } catch { }
            self.error = Self.message(error)
        }
    }
    /// Explicit review creates a new request, retaining notes/photos and using a freshly read version.
    func review(_ id: UUID, reviewedVersion: Int? = nil) async throws {
        guard !sending, let index = state.drafts.firstIndex(where: { $0.id == id }), !state.drafts[index].bodyAccepted else { throw HealthJournalFailure.conflict }
        let item = state.drafts[index]
        guard item.conflict || item.needsEditing else { throw HealthJournalFailure.conflict }
        var mutation = item.mutation
        if item.conflict {
            if mutation.action == "correct" {
                let latest = try await detail(mutation.id); guard reviewedVersion == latest.observations[0].version else { throw HealthJournalFailure.conflict }; mutation.expectedVersion = reviewedVersion
            } else if mutation.action == "topic" {
                guard let connection else { throw HealthJournalFailure.configuration }
                let latest = try await readPage(.entries(), connection)
                guard let topic = latest.topics.first(where: { $0.id == mutation.id }) else { throw HealthJournalFailure.conflict }
                guard reviewedVersion == topic.version else { throw HealthJournalFailure.conflict }; mutation.expectedVersion = reviewedVersion
            } else { throw HealthJournalFailure.conflict }
        }
        mutation.requestId = UUID().uuidString.lowercased()
        var next = state; next.drafts[index].mutation = mutation; next.drafts[index].body = nil
        next.drafts[index].queued = false; next.drafts[index].conflict = false; next.drafts[index].needsEditing = false
        next.drafts[index].lastError = nil; try persist(next)
    }
    func latestForReview(_ id: UUID) async throws -> HealthJournalMutation {
        guard let item = draft(id), item.conflict, !item.bodyAccepted else { throw HealthJournalFailure.conflict }
        if item.mutation.action == "correct" { return .correction(try await detail(item.mutation.id).observations[0]) }
        guard item.mutation.action == "topic", let connection else { throw HealthJournalFailure.conflict }
        let latest = try await readPage(.entries(), connection)
        guard let topic = latest.topics.first(where: { $0.id == item.mutation.id }) else { throw HealthJournalFailure.conflict }
        return .topic(topic)
    }
    static func message(_ error: Error) -> String {
        (error as? HealthJournalFailure)?.localizedDescription ?? HealthJournalFailure.http(503).localizedDescription
    }
}
