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
    @Published private(set) var savedCopyReadAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var storageError = false
    @Published private(set) var capabilities: HealthJournalCapabilities?
    @Published private(set) var checkingCapabilities = false
    private var capabilityFailure: Error?
    private var capabilityReadAt: Date?
    private var capabilityTask: Task<HealthJournalCapabilities, Error>?
    private var capabilityTaskGeneration: Int?
    private var capabilityReadId: UUID?
    private var corruptArchive = false
    private var generation = 0
    private var readTicket = UUID()
    private let photoReads = HealthJournalPhotoReads()
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
        do { connection = try read(); guard connection?.valid != false, state.installationId == nil || connection?.installationId == state.installationId else { throw HealthJournalFailure.configuration } }
        catch { connection = nil; self.error = HealthJournalFailure.configuration.localizedDescription }
        restoreSnapshot()
    }
    private func restoreSnapshot() {
        guard !loaded, let connection, let snapshot = try? archive.readSnapshot(),
              snapshot.installationId == connection.installationId else { return }
        document = snapshot.document; filter = snapshot.filter; loaded = true; savedCopyReadAt = snapshot.readAt
    }
    func reloadWhenAccessible() {
        if corruptArchive {
            do { state = try archive.read(); corruptArchive = false; storageError = false; error = nil } catch { return }
        }
        if storageError {
            // A protected/temporarily unavailable file must not strand retained input after unlock.
            do {
                try persist(state)
                if error == HealthJournalFailure.storage.localizedDescription { error = nil }
            } catch { return }
        }
        if connection == nil {
            do {
                let candidate = try credentialRead()
                guard candidate?.valid != false, state.installationId == nil || candidate?.installationId == state.installationId else { return }
                connection = candidate; if candidate != nil { error = nil }
            } catch { }
        }
        restoreSnapshot()
    }
    private func persist(_ next: HealthJournalState) throws {
        guard !corruptArchive else { throw HealthJournalFailure.storage }
        state = next
        do { try archive.save(next); storageError = false }
        catch { storageError = true; self.error = HealthJournalFailure.storage.localizedDescription; throw HealthJournalFailure.storage }
    }
    func flush() { do { try persist(state) } catch { self.error = Self.message(error) } }
    func draft(_ id: UUID) -> HealthJournalDraft? { state.drafts.first { $0.id == id } }
    /// Opens a durable composer immediately; a missing topic is created atomically on explicit Save.
    func createEntry(topicId: String? = nil) throws -> UUID {
        if let topic = document.topics.first(where: { $0.id == topicId }) ?? document.topics.first(where: { $0.status == "open" }) {
            return try create(.entry(topicId: topic.id))
        }
        return try create(.newEntry())
    }
    /// Session-local capability reads coalesce and never delay typing or require connection setup.
    func refreshCapabilities(force: Bool = false) async {
        guard let connection, connection.valid else { return }
        if !force, capabilities != nil, let at = capabilityReadAt, (0..<60).contains(Date().timeIntervalSince(at)) { return }
        let version = generation
        let task: Task<HealthJournalCapabilities, Error>, identity: UUID
        if capabilityTaskGeneration == version, let current = capabilityTask, let id = capabilityReadId {
            task = current; identity = id
        } else {
            identity = UUID(); capabilityReadId = identity; capabilityTaskGeneration = version
            task = Task { @MainActor in
                let data = try await self.transport(.init(path: "capabilities"), connection)
                let result = try JSONDecoder().decode(HealthJournalCapabilities.self, from: data)
                guard result.valid else { throw HealthJournalFailure.invalidResponse }; return result
            }
            capabilityTask = task
        }
        checkingCapabilities = true
        defer { if capabilityReadId == identity { capabilityTask = nil; capabilityReadId = nil; checkingCapabilities = false } }
        do {
            let result = try await task.value; try Task.checkCancellation()
            guard generation == version, self.connection == connection else { return }
            capabilities = result; capabilityReadAt = Date(); capabilityFailure = nil
        } catch {
            if generation == version, !(error is CancellationError) { capabilityFailure = error }
        }
    }
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
        let capability = try JSONDecoder().decode(HealthJournalCapabilities.self, from: await transport(.init(path: "capabilities"), candidate))
        guard capability.valid else { throw HealthJournalFailure.invalidResponse }
        let page = try await readPage(.entries(), candidate)
        try Task.checkCancellation(); guard version == generation else { throw CancellationError() }
        // Save and verify credential only after authenticated reads; never replay drafts during setup.
        try credentialSave(candidate); guard try credentialRead() == candidate else { throw HealthJournalFailure.configuration }
        var next = state; next.installationId = candidate.installationId; try persist(next)
        capabilityTask?.cancel(); capabilityTask = nil; capabilityReadId = nil
        capabilities = capability; capabilityReadAt = Date(); checkingCapabilities = false
        savedCopyReadAt = nil
        try? archive.saveSnapshot(.init(installationId: candidate.installationId, document: page, filter: .init(), readAt: Date()))
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
        if desired != filter { filter = desired; document = .empty; loaded = false; savedCopyReadAt = nil }
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
            } else {
                document = page; savedCopyReadAt = nil
                // Cache the first page with its exact cursor, never a truncated merged page that skips history.
                try? archive.saveSnapshot(.init(installationId: connection.installationId, document: page, filter: desired, readAt: Date()))
            }
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
    func localPhoto(_ photo: HealthJournalPendingPhoto) async throws -> Data {
        let store = archive
        return try await Task.detached(priority: .utility) { try store.photo(photo) }.value
    }
    func image(_ image: HealthJournalImage) async throws -> Data {
        guard let connection, image.valid else { throw HealthJournalFailure.configuration }
        let version = generation
        if let local = state.drafts.lazy.filter({ $0.installationId == connection.installationId && $0.mutation.id == image.observationId }).flatMap(\.photos).first(where: {
            $0.id == image.id && $0.sha256 == image.sha256.lowercased() && $0.bytes == image.bytes && $0.contentType == image.contentType
        }) {
            let store = archive
            if let bytes = try? await Task.detached(priority: .utility, operation: { try store.photo(local) }).value {
                try Task.checkCancellation()
                guard version == generation, self.connection == connection else { throw HealthJournalFailure.configuration }
                return bytes
            }
        }
        try await photoReads.acquire()
        defer { photoReads.release() }
        try Task.checkCancellation()
        guard generation == version, self.connection == connection else { throw HealthJournalFailure.configuration }
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
            if state.drafts[index].body == nil, state.drafts[index].mutation.newTopic != nil {
                await refreshCapabilities(force: capabilities?.inlineTopicCreation != true)
                guard capabilities?.inlineTopicCreation == true else { throw capabilityFailure ?? HealthJournalFailure.inlineTopicUnavailable }
            }
            var next = state, item = next.drafts[index]
            guard item.installationId == nil || item.installationId == connection.installationId else { throw HealthJournalFailure.configuration }
            if item.body == nil {
                item.mutation.newTopic = item.mutation.newTopic?.normalized
                try item.mutation.validate(); item.body = try JSONEncoder().encode(item.mutation)
                guard item.body!.count <= 131072 else { throw HealthJournalFailure.validation }
            }
            item.queued = true; item.installationId = connection.installationId; item.lastError = nil; item.needsEditing = false
            next.drafts[index] = item; try persist(next)
            if !item.bodyAccepted {
                let data = try await transport(.init(path: "entries", body: item.body), connection)
                struct Receipt: Decodable { let id: String; let version: Int }
                let receipt = try JSONDecoder().decode(Receipt.self, from: data)
                guard receipt.id == item.mutation.id, receipt.version == (item.mutation.expectedVersion ?? 0) + 1 else { throw HealthJournalFailure.invalidResponse }
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

/// At most two private originals are downloaded at once. Cancelled offscreen previews free their place.
@MainActor
final class HealthJournalPhotoReads {
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    func acquire() async throws {
        try Task.checkCancellation()
        if active < 2 { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel(id) } }
        do { try Task.checkCancellation() }
        catch { release(); throw error }
    }
    func release() {
        if !waiting.isEmpty { waiting.removeFirst().1.resume() }
        else { active -= 1 }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
}
