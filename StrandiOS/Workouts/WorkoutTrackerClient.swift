#if canImport(Combine) && canImport(Security)
import Foundation
import Combine
import WhoopStore

/// Explicit, bounded reads. Local strength capture never depends on a successful network request.
@MainActor
final class WorkoutTrackerClient: ObservableObject {
    static let shared = WorkoutTrackerClient()
    @Published private(set) var state = WorkoutTrackerState()
    @Published private(set) var busy = false
    @Published private(set) var storageUnavailable = false
    private let store: WorkoutTrackerFileStore
    private let send: (WorkoutSyncEndpoint, Data?, WorkoutSyncConfiguration) async throws -> Data
    private let readCredential: () throws -> WorkoutSyncConfiguration?
    private let saveCredential: (WorkoutSyncConfiguration) throws -> Void
    private var generation = 0
    private var preparingCaptures: Set<UUID> = []
    private var transmittingCaptures: Set<UUID> = []
    private var archiveCache: [UUID: WorkoutTrackerDelivery] = [:]
    private var stateRevision = 0
    private var metadataRestoring = false
    private var recoveryReview: WorkoutTrackerRecoveryReview?
    private var historyReview: WorkoutTrackerHistoryReview?
    private var deletionReview: WorkoutTrackerDeletionReview?

    private convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(store: WorkoutTrackerFileStore(url: root.appendingPathComponent("WorkoutTracker/state.json")))
    }

    init(store: WorkoutTrackerFileStore,
         send: @escaping (WorkoutSyncEndpoint, Data?, WorkoutSyncConfiguration) async throws -> Data = { endpoint, body, config in
             try await WorkoutSyncTransport().send(to: endpoint, body: body, credentials: config)
         },
         readCredential: @escaping () throws -> WorkoutSyncConfiguration? = WorkoutTrackerKeychain.read,
         saveCredential: @escaping (WorkoutSyncConfiguration) throws -> Void = WorkoutTrackerKeychain.save) {
        self.store = store; self.send = send; self.readCredential = readCredential; self.saveCredential = saveCredential
        do { state = try store.load() }
        catch { storageUnavailable = true; state.message = "Tracker state could not be read. Connection is paused; local workouts are preserved." }
    }
    var configured: Bool { (try? credentials()) != nil }
    private func credentials() throws -> WorkoutSyncConfiguration {
        guard let value = try readCredential(), value.valid,
              value.origin == state.origin, value.installationId == state.installationId else { throw WorkoutSyncTransportError.configuration }
        var config = value; config.enabled = state.enabled
        return config
    }
    private func commit(_ next: WorkoutTrackerState, protecting extra: Set<UUID> = []) throws {
        guard !storageUnavailable else { throw WorkoutTrackerContractError.invalidSnapshot }
        let compacted = try store.compact(next, protecting: preparingCaptures.union(transmittingCaptures).union(extra))
        try store.save(compacted); state = compacted
        stateRevision += 1
        archiveCache = [:]
    }

    var historyReferences: [WorkoutTrackerArchiveReference] {
        let active = Set(state.deliveries.map(\.id))
        return (state.deliveries.map { WorkoutTrackerArchiveReference(delivery: $0, fileId: $0.id) } + state.archives.values.filter { !active.contains($0.id) })
            .sorted { ($0.startedAt, $0.createdAt ?? .distantPast, $0.revision) > ($1.startedAt, $1.createdAt ?? .distantPast, $1.revision) }
    }
    func delivery(_ id: UUID) throws -> WorkoutTrackerDelivery? {
        var result: WorkoutTrackerDelivery?
        if let active = state.deliveries.first(where: { $0.id == id }) { result = active }
        else if let reference = state.archives[id.uuidString.lowercased()] {
            if let cached = archiveCache[id] { result = cached }
            else {
                result = try store.archived(reference)
                if archiveCache.count >= 25 { archiveCache = [:] }
                archiveCache[id] = result
            }
        }
        if let source = result?.sourceWorkoutId, state.locallyKeptSources.contains(source) {
            result?.paused = true
            result?.message = "Automatic tracker delivery is paused for this capture. This event's receipt status is shown separately."
        }
        return result
    }
    private func history(for source: UUID) throws -> [WorkoutTrackerDelivery] {
        let active = state.deliveries.filter { $0.sourceWorkoutId == source }
        let ids = Set(active.map(\.id))
        let archived = try state.archives.values.filter { $0.sourceWorkoutId == source && !ids.contains($0.id) }.map { try store.archived($0) }
        return (active + archived).sorted { ($0.revision, $0.createdAt ?? .distantPast) < ($1.revision, $1.createdAt ?? .distantPast) }
    }
    func historyOnlyReplacement(for deliveryId: UUID) throws -> WorkoutTrackerDelivery? {
        try reviewedReplacement(for: deliveryId).flatMap { $0.isHistoryOnly ? $0 : nil }
    }
    func reviewedReplacement(for deliveryId: UUID) throws -> WorkoutTrackerDelivery? {
        guard let original = try delivery(deliveryId), original.status != .accepted else { return nil }
        return try history(for: original.sourceWorkoutId).last { $0.recoveryOf == deliveryId && ($0.isHistoryOnly || $0.operation == .delete) }
    }
    private func activateDelivery(_ id: UUID) throws {
        guard !state.deliveries.contains(where: { $0.id == id }), let item = try delivery(id) else { return }
        var next = state; next.deliveries.append(item)
        try commit(next, protecting: [item.sourceWorkoutId])
    }
    func createInstallationId() throws {
        guard state.installationId == nil else { return }
        var next = state; next.installationId = UUID()
        next.message = "Connection ID created. Tracker is still off."
        try commit(next)
    }

    /// Existing UUID vocabulary IDs are reused. Legacy IDs get a durable key, never a name match.
    func sourceExerciseIdentity(nativeId: String, deviceID: String) throws -> UUID {
        if let id = UUID(uuidString: nativeId) { return id }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let key = "v2:" + String(decoding: try encoder.encode([deviceID, nativeId]), as: UTF8.self)
        guard !nativeId.isEmpty, key.utf16.count <= 1000 else { throw WorkoutTrackerContractError.invalidSnapshot }
        if let id = state.legacyExerciseIdentities[key] { return id }
        // Preserve unambiguous keys from the earlier local format without retaining its delimiter collision.
        if !deviceID.contains("\u{0}"), !nativeId.contains("\u{0}"), let id = state.legacyExerciseIdentities[deviceID + "\u{0}" + nativeId] { return id }
        let id = UUID(); var next = state; next.legacyExerciseIdentities[key] = id
        try commit(next); return id
    }
    func configure(origin: String, token: String, installationId: UUID, accessClientId: String? = nil, accessClientSecret: String? = nil) throws {
        guard !busy else { throw WorkoutSyncTransportError.configuration }
        let value = WorkoutSyncConfiguration(origin: origin, installationId: installationId, credential: token, accessClientId: accessClientId, accessClientSecret: accessClientSecret)
        guard value.valid else { throw WorkoutSyncTransportError.configuration }
        var next = state
        next.enabled = false; next.origin = origin; next.installationId = installationId
        next.index = nil; next.manifests = [:]; next.manifestReadAt = [:]; next.cachedPlanBlocks = [:]; next.capturedAt = nil; next.frontendPage = nil; next.frontendReadAt = nil
        next.message = "Connection saved. Tracker remains off until you enable it."
        try commit(next)
        try saveCredential(value)
        generation += 1
    }
    func setEnabled(_ value: Bool) throws {
        if value { _ = try credentials() }
        var next = state; next.enabled = value
        next.message = value ? "Tracker enabled. Refresh routines to check the connection." : "Tracker is off. Local workouts are kept."
        try commit(next); generation += 1
    }
    func prepareMetadataBackup() async throws -> URL {
        guard !busy, !storageUnavailable, preparingCaptures.isEmpty, transmittingCaptures.isEmpty else { throw WorkoutTrackerContractError.deliveryInProgress }
        busy = true; defer { busy = false }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Dhoop-workout-metadata-" + UUID().uuidString.lowercased() + ".dhoopworkouts", isDirectory: true)
        let fileStore = store, snapshot = state
        try await Task.detached(priority: .utility) { try fileStore.prepareBackup(state: snapshot, destination: target) }.value
        try Task.checkCancellation()
        return target
    }
    func restoreMetadataBackup(from package: URL) async throws {
        guard !busy, !storageUnavailable, preparingCaptures.isEmpty, transmittingCaptures.isEmpty else { throw WorkoutTrackerContractError.deliveryInProgress }
        busy = true; metadataRestoring = true
        defer { busy = false; metadataRestoring = false }
        let fileStore = store, current = state, revision = stateRevision
        let merged = try await Task.detached(priority: .utility) { try fileStore.mergedBackup(from: package, current: current) }.value
        guard revision == stateRevision, !Task.isCancelled else { throw WorkoutTrackerContractError.deliveryInProgress }
        try commit(merged); generation += 1
    }
    func metadataBackupSummary(at package: URL) async throws -> WorkoutTrackerBackupManifest {
        let fileStore = store
        return try await Task.detached(priority: .utility) { try fileStore.backupManifest(at: package) }.value
    }
    /// Read the same canonical dashboard as web/MCP. Failed or superseded reads retain the last cache.
    func refreshDashboard(mesocycleId: Int? = nil, sessionId: Int? = nil, cursor: Int = 0) async throws {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        let ticket = generation
        busy = true; defer { busy = false }
        let bytes = try await send(.dashboard(mesocycleId: mesocycleId, sessionId: sessionId, cursor: cursor, limit: 10), nil, config)
        let page = try JSONDecoder().decode(WorkoutTrackerDashboard.self, from: bytes)
        try page.validate()
        guard !Task.isCancelled, ticket == generation, state.enabled,
              page.pagination.cursor == cursor,
              mesocycleId.map({ page.dashboard.activeMesocycle?.id == $0 }) ?? true,
              sessionId.map({ id in page.dashboard.sessions.count == 1 && page.dashboard.sessions.first?.id == id }) ?? true
        else { throw WorkoutTrackerContractError.invalidSnapshot }
        var next = state
        next.frontendPage = page; next.frontendReadAt = Date()
        next.message = "Website workout snapshot refreshed. Pending WHOOP recordings are tracked separately."
        try commit(next)
    }

    func refreshIndex() async throws {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        busy = true; defer { busy = false }
        let currentGeneration = generation
        var cursor = 0, sessions: [WorkoutTrackerIndex.Session] = [], revision: Int?
        var result: WorkoutTrackerIndex?
        // Six pages is a hard execution bound. No recurring monitor or background timer.
        for _ in 0..<6 {
            let bytes = try await send(.sessionIndex(cursor: cursor, limit: 100), nil, config)
            let page = try JSONDecoder().decode(WorkoutTrackerIndex.self, from: bytes)
            try page.validate()
            guard page.sessions.count <= 100 else { throw WorkoutTrackerContractError.invalidSnapshot }
            guard revision == nil || revision == page.lifeRevision else { throw WorkoutTrackerContractError.invalidSnapshot }
            revision = page.lifeRevision; sessions += page.sessions
            result = WorkoutTrackerIndex(schemaVersion: 1, cycle: page.cycle, sessions: sessions,
                lifeRevision: page.lifeRevision, nextCursor: page.nextCursor)
            if page.nextCursor == nil { break }
            guard let next = page.nextCursor, next > cursor else { throw WorkoutTrackerContractError.invalidSnapshot }
            cursor = next
        }
        guard let result, result.nextCursor == nil, !Task.isCancelled,
              currentGeneration == generation, state.enabled else { throw WorkoutTrackerContractError.invalidSnapshot }
        // A complete index can exceed one page; validate each page and uniqueness of the merged result.
        guard Set(sessions.map(\.sessionId)).count == sessions.count else { throw WorkoutTrackerContractError.invalidSnapshot }
        var next = state
        next.index = result; next.capturedAt = Date(); next.message = "Tracker routines refreshed. Prescriptions are checked again before starting."
        try commit(next)
    }
    func manifest(sessionId: Int) async throws -> WorkoutTrackerManifest {
        guard !busy else { throw WorkoutTrackerContractError.invalidSnapshot }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        busy = true; defer { busy = false }
        let currentGeneration = generation
        let bytes: Data
        do { bytes = try await send(.manifest(sessionId), nil, config) }
        catch {
            if currentGeneration == generation {
                var block: WorkoutTrackerState.CachedPlanBlock?
                if case WorkoutSyncTransportError.rejected(let reason) = error {
                    if reason == .prescriptionInconsistent { block = .inconsistent }
                    if [.sessionRetired, .setRetired].contains(reason) { block = .unavailable }
                }
                if case WorkoutSyncTransportError.http(let status) = error, [404, 410].contains(status) { block = .unavailable }
                if let block { var next = state; next.cachedPlanBlocks[String(sessionId)] = block; try commit(next) }
            }
            throw error
        }
        let manifest: WorkoutTrackerManifest
        do {
            manifest = try JSONDecoder().decode(WorkoutTrackerManifest.self, from: bytes)
            try manifest.validate()
            guard manifest.sessionId == sessionId else { throw WorkoutTrackerContractError.invalidSnapshot }
        } catch {
            if currentGeneration == generation { var next = state; next.cachedPlanBlocks[String(sessionId)] = .invalid; try commit(next) }
            throw error
        }
        guard manifest.sessionId == sessionId, !Task.isCancelled, currentGeneration == generation, state.enabled else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        let readAt = Date()
        var next = state; next.manifests[String(sessionId)] = manifest; next.capturedAt = readAt
        next.manifestReadAt[String(sessionId)] = readAt; next.cachedPlanBlocks[String(sessionId)] = nil
        try commit(next)
        return manifest
    }

    func captureSnapshot(deliveryId: UUID) async throws -> WorkoutTrackerCaptureSnapshot {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        guard let item = try delivery(deliveryId) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        guard config.origin == item.origin, config.installationId == item.installationId else { throw WorkoutSyncTransportError.configuration }
        busy = true; defer { busy = false }
        let initialGeneration = generation
        let result = try await readCapture(item: item, config: config)
        guard initialGeneration == generation, state.enabled, !Task.isCancelled else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        return result
    }

    /// Read-only even though the lookup route accepts POST. Exact bytes are never sent to ingestion.
    func lookupReceipt(deliveryId: UUID) async throws -> WorkoutTrackerReceiptLookup.Status {
        guard !busy, !metadataRestoring else { throw WorkoutTrackerContractError.deliveryInProgress }
        try activateDelivery(deliveryId)
        guard let item = try delivery(deliveryId), !transmittingCaptures.contains(item.sourceWorkoutId),
              preparingCaptures.insert(item.sourceWorkoutId).inserted else { throw WorkoutTrackerContractError.deliveryInProgress }
        defer { preparingCaptures.remove(item.sourceWorkoutId) }
        try item.validateBody()
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        guard config.origin == item.origin, config.installationId == item.installationId else { throw WorkoutSyncTransportError.configuration }
        busy = true; defer { busy = false }
        let initialGeneration = generation, initialRevision = stateRevision
        let response = try await send(.receiptLookup, item.bytes, config)
        let lookup = try JSONDecoder().decode(WorkoutTrackerReceiptLookup.self, from: response)
        try lookup.validate(for: item)
        guard initialGeneration == generation, initialRevision == stateRevision, state.enabled, !Task.isCancelled,
              try delivery(item.id)?.sameIntent(as: item) == true else { throw WorkoutTrackerContractError.sessionChanged }
        var next = state
        guard let index = next.deliveries.firstIndex(where: { $0.id == item.id }) else { throw WorkoutTrackerContractError.sessionChanged }
        next.deliveries[index].receiptLookupEvidence = try JSONEncoder().encode(lookup)
        next.deliveries[index].receiptLookupCheckedAt = Date()
        if lookup.status == .recorded {
            let ack = try lookup.acknowledgement()
            next.deliveries[index].acknowledgement = try JSONEncoder().encode(ack)
            next.deliveries[index].rejection = nil
            let needsReview = ack.needsSourceReview(revision: item.revision, deleting: item.operation == .delete, expectingHistoryOnly: item.isHistoryOnly)
            next.deliveries[index].status = needsReview ? .review : .accepted
            next.deliveries[index].message = needsReview ? "Original event receipt found. Current source or projection differs; no event was replayed. Derived progress is unverified." :
                item.operation == .delete ? "Original deletion receipt found; current tombstone verified. Derived progress is unverified." :
                item.isHistoryOnly ? "Original history-only receipt found. Website sets were not changed by that event; derived work was not checked." :
                "Original event receipt verified. Local records were not restored or replaced; derived progress is unverified."
        } else {
            if item.acknowledgement == nil { next.deliveries[index].status = .review }
            next.deliveries[index].paused = true
            next.deliveries[index].message = item.acknowledgement == nil ? "No receipt was observed. Outcome remains unknown; no event was replayed or replaced." :
                "Lookup did not observe a receipt. Earlier stored evidence is retained; this is not proof of rejection or cancellation."
        }
        try commit(next, protecting: [item.sourceWorkoutId])
        return lookup.status
    }

    /// Bracket the capture read with exact manifest reads. Absence is not receipt recovery.
    func reviewComparison(deliveryId: UUID) async throws -> WorkoutTrackerReviewComparison {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        guard let item = try delivery(deliveryId) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        guard config.origin == item.origin, config.installationId == item.installationId else { throw WorkoutSyncTransportError.configuration }
        busy = true; defer { busy = false }
        let initialGeneration = generation
        func readManifest() async throws -> WorkoutTrackerManifest {
            let bytes = try await send(.manifest(item.binding.manifest.sessionId), nil, config)
            let manifest = try JSONDecoder().decode(WorkoutTrackerManifest.self, from: bytes)
            try manifest.validate()
            guard manifest.sessionId == item.binding.manifest.sessionId, manifest.cycleId == item.binding.manifest.cycleId else {
                throw WorkoutTrackerContractError.invalidSnapshot
            }
            return manifest
        }
        let before = try await readManifest()
        let capture: WorkoutTrackerCaptureSnapshot?
        do { capture = try await readCapture(item: item, config: config) }
        catch WorkoutSyncTransportError.captureNotFound { capture = nil }
        let after = try await readManifest()
        guard before == after, capture.map({ $0.lifeRevision == after.lifeRevision }) ?? true,
              initialGeneration == generation, state.enabled, !Task.isCancelled else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        return WorkoutTrackerReviewComparison(manifest: after, capture: capture, checkedAt: Date())
    }

    private func readCapture(item: WorkoutTrackerDelivery, config: WorkoutSyncConfiguration) async throws -> WorkoutTrackerCaptureSnapshot {
        var cursor = 0, result: WorkoutTrackerCaptureSnapshot?
        var header: Data?
        for _ in 0..<5 {
            let data: Data
            do { data = try await send(.captures(item.sourceWorkoutId, cursor: cursor, limit: 50), nil, config) }
            catch WorkoutSyncTransportError.captureNotFound {
                guard cursor == 0 else { throw WorkoutTrackerContractError.invalidSnapshot }
                throw WorkoutSyncTransportError.captureNotFound
            }
            var page = try JSONDecoder().decode(WorkoutTrackerCaptureSnapshot.self, from: data)
            try page.validate(for: item.binding)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WorkoutTrackerContractError.invalidSnapshot }
            let evidence = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            object.removeValue(forKey: "sets"); object.removeValue(forKey: "nextCursor")
            let pageHeader = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard header == nil || header == pageHeader else { throw WorkoutTrackerContractError.invalidSnapshot }
            header = pageHeader
            page.readEvidence = [evidence]
            guard page.sets.count <= 50 else { throw WorkoutTrackerContractError.invalidSnapshot }
            let pageCount = page.sets.count
            if let previous = result {
                guard previous.sourceRevision == page.sourceRevision, previous.lifeRevision == page.lifeRevision else { throw WorkoutTrackerContractError.invalidSnapshot }
                page.sets = previous.sets + page.sets
                page.readEvidence = (previous.readEvidence ?? []) + [evidence]
                try page.validate(for: item.binding)
            }
            result = page
            guard let next = page.nextCursor else { break }
            guard pageCount > 0, next == cursor + pageCount, next <= 200 else { throw WorkoutTrackerContractError.invalidSnapshot }
            cursor = next
        }
        guard let result, result.nextCursor == nil else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        return result
    }
    private func readStableCapture(deliveryId: UUID) async throws -> WorkoutTrackerCaptureSnapshot {
        let before = try await captureSnapshot(deliveryId: deliveryId)
        let after = try await captureSnapshot(deliveryId: deliveryId)
        guard before == after, !Task.isCancelled else { throw WorkoutTrackerContractError.sessionChanged }
        return after
    }

    func reviewDeletion(deliveryId: UUID) async throws -> WorkoutTrackerDeletionReview {
        deletionReview = nil
        guard !busy, !metadataRestoring, let original = try delivery(deliveryId),
              !preparingCaptures.contains(original.sourceWorkoutId), !transmittingCaptures.contains(original.sourceWorkoutId) else {
            throw WorkoutTrackerContractError.deliveryInProgress
        }
        let history = try history(for: original.sourceWorkoutId)
        guard history.last?.id == original.id, original.operation == .delete,
              let accepted = history.last(where: \.hasVerifiedSourceAcceptance),
              history.filter({ $0.revision > accepted.revision && $0.id != original.id }).allSatisfy(\.submissionOutcomeResolvedForReview) else {
            throw WorkoutTrackerContractError.deletionReviewRequired
        }
        let initialRevision = stateRevision
        let capture = try await readStableCapture(deliveryId: deliveryId)
        guard initialRevision == stateRevision else { throw WorkoutTrackerContractError.sessionChanged }
        try WorkoutTrackerDeletionReview.validate(original: original, accepted: accepted, capture: capture)
        let review = WorkoutTrackerDeletionReview(id: UUID(), original: original, accepted: accepted, capture: capture, checkedAt: Date())
        deletionReview = review
        return review
    }

    func prepareReviewedDeletion(reviewId: UUID, store: WhoopStore) async throws -> UUID {
        guard !busy, !metadataRestoring, let review = deletionReview, review.id == reviewId, review.canPrepare,
              preparingCaptures.insert(review.original.sourceWorkoutId).inserted else { throw WorkoutTrackerContractError.sessionChanged }
        defer { preparingCaptures.remove(review.original.sourceWorkoutId) }
        let original = review.original, initialRevision = stateRevision
        guard try delivery(original.id)?.sameIntent(as: original) == true,
              try history(for: original.sourceWorkoutId).last?.id == original.id,
              try await original.matches(store: store) else { throw WorkoutTrackerContractError.sessionChanged }
        let capture = try await readStableCapture(deliveryId: original.id)
        guard capture == review.capture, initialRevision == stateRevision,
              deletionReview?.id == reviewId, try await original.matches(store: store) else {
            deletionReview = nil; throw WorkoutTrackerContractError.sessionChanged
        }
        guard initialRevision == stateRevision, deletionReview?.id == reviewId, !Task.isCancelled,
              try history(for: original.sourceWorkoutId).last?.id == original.id else { throw WorkoutTrackerContractError.sessionChanged }
        let replacement = try review.replacement()
        var next = state
        if let index = next.deliveries.firstIndex(where: { $0.id == original.id }) {
            next.deliveries[index].paused = true
            next.deliveries[index].message = "Original deletion event retained. A separately reviewed deletion was prepared."
        }
        next.deliveries.append(replacement)
        try commit(next, protecting: [original.sourceWorkoutId])
        deletionReview = nil
        return replacement.id
    }

    /// Historical eligibility comes from the accepted capture; a retired routine need not exist.
    func reviewHistoryOnly(deliveryId: UUID) async throws -> WorkoutTrackerHistoryReview {
        historyReview = nil
        guard !busy, !metadataRestoring, let original = try delivery(deliveryId),
              !preparingCaptures.contains(original.sourceWorkoutId), !transmittingCaptures.contains(original.sourceWorkoutId) else {
            throw WorkoutTrackerContractError.deliveryInProgress
        }
        let history = try history(for: original.sourceWorkoutId)
        guard history.last?.id == original.id, let accepted = history.last(where: \.hasVerifiedSourceAcceptance) else {
            throw WorkoutTrackerContractError.historyReviewRequired
        }
        guard history.filter({ $0.revision > accepted.revision && $0.id != original.id }).allSatisfy(\.submissionOutcomeResolvedForReview) else {
            throw WorkoutTrackerContractError.historyReviewRequired
        }
        let initialRevision = stateRevision
        let after = try await readStableCapture(deliveryId: deliveryId)
        guard initialRevision == stateRevision else { throw WorkoutTrackerContractError.sessionChanged }
        try WorkoutTrackerHistoryReview.validate(original: original, accepted: accepted, capture: after)
        let review = WorkoutTrackerHistoryReview(id: UUID(), original: original, accepted: accepted, capture: after, checkedAt: Date())
        historyReview = review
        return review
    }

    /// Persist an explicit paused correction. No request is sent by preparation.
    func prepareHistoryOnly(reviewId: UUID, store: WhoopStore) async throws -> UUID {
        guard !busy, !metadataRestoring, let review = historyReview, review.id == reviewId,
              preparingCaptures.insert(review.original.sourceWorkoutId).inserted else { throw WorkoutTrackerContractError.sessionChanged }
        defer { preparingCaptures.remove(review.original.sourceWorkoutId) }
        let original = review.original, initialRevision = stateRevision
        guard try delivery(original.id)?.sameIntent(as: original) == true,
              try history(for: original.sourceWorkoutId).last?.id == original.id,
              try await original.matches(store: store) else { throw WorkoutTrackerContractError.sessionChanged }
        let after = try await readStableCapture(deliveryId: original.id)
        guard after == review.capture, initialRevision == stateRevision,
              historyReview?.id == reviewId, !Task.isCancelled,
              try await original.matches(store: store) else {
            historyReview = nil; throw WorkoutTrackerContractError.sessionChanged
        }
        guard initialRevision == stateRevision, historyReview?.id == reviewId,
              try history(for: original.sourceWorkoutId).last?.id == original.id else { throw WorkoutTrackerContractError.sessionChanged }
        let replacement = try review.replacement()
        var next = state
        if let index = next.deliveries.firstIndex(where: { $0.id == original.id }) {
            next.deliveries[index].paused = true
            next.deliveries[index].message = "Original event retained. A separate history-only correction was prepared."
        }
        next.deliveries.append(replacement)
        try commit(next, protecting: [original.sourceWorkoutId])
        historyReview = nil
        return replacement.id
    }

    func reviewRecovery(deliveryId: UUID) async throws -> WorkoutTrackerRecoveryReview {
        recoveryReview = nil
        guard let item = try delivery(deliveryId), !preparingCaptures.contains(item.sourceWorkoutId) else {
            throw WorkoutTrackerContractError.deliveryInProgress
        }
        guard item.status == .review, [.lifeRevisionConflict, .manifestConflict].contains(item.rejection),
              item.acknowledgement == nil else { throw WorkoutTrackerContractError.invalidSnapshot }
        let initialRevision = stateRevision
        let comparison = try await reviewComparison(deliveryId: deliveryId)
        guard initialRevision == stateRevision, try history(for: item.sourceWorkoutId).last?.id == item.id else {
            throw WorkoutTrackerContractError.sessionChanged
        }
        try WorkoutTrackerRecoveryReview.validate(original: item, comparison: comparison)
        let review = WorkoutTrackerRecoveryReview(id: UUID(), original: item, comparison: comparison)
        recoveryReview = review
        return review
    }

    /// Preparation is explicit and local. Sending remains a separate exact-event action.
    func prepareReviewedRecovery(reviewId: UUID, store: WhoopStore) async throws -> UUID {
        guard !busy, !metadataRestoring, let review = recoveryReview, review.id == reviewId,
              preparingCaptures.insert(review.original.sourceWorkoutId).inserted else {
            throw WorkoutTrackerContractError.sessionChanged
        }
        defer { preparingCaptures.remove(review.original.sourceWorkoutId) }
        let initialRevision = stateRevision
        let original = review.original
        guard try delivery(original.id)?.sameIntent(as: original) == true,
              try history(for: original.sourceWorkoutId).last?.id == original.id,
              try await original.matches(store: store) else { throw WorkoutTrackerContractError.sessionChanged }
        let refreshed = try await reviewComparison(deliveryId: original.id)
        guard refreshed.manifest == review.comparison.manifest, refreshed.capture == review.comparison.capture,
              initialRevision == stateRevision, recoveryReview?.id == reviewId,
              try delivery(original.id)?.rejection == original.rejection else {
            recoveryReview = nil
            throw WorkoutTrackerContractError.sessionChanged
        }
        let replacement = try review.replacement()
        var next = state
        if let index = next.deliveries.firstIndex(where: { $0.id == original.id }) {
            next.deliveries[index].paused = true
            next.deliveries[index].message = "Original rejected delivery retained. A separately reviewed replacement was prepared."
        }
        next.deliveries.append(replacement)
        try commit(next, protecting: [original.sourceWorkoutId])
        recoveryReview = nil
        return replacement.id
    }

    func captureBinding(manifest: WorkoutTrackerManifest) throws -> WorkoutTrackerCaptureBinding {
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        guard state.manifests[String(manifest.sessionId)] == manifest else { throw WorkoutTrackerContractError.invalidSnapshot }
        return try WorkoutTrackerCaptureBinding(manifest: manifest,
            connection: .init(origin: config.origin, installationId: config.installationId),
            planAtStart: .init(manifest: manifest, provenance: .live, fetchedAt: state.manifestReadAt[String(manifest.sessionId)]))
    }

    /// Explicit local start. No Keychain access, request, prescription refresh or inferred fetch age.
    func cachedManifest(sessionId: Int) throws -> WorkoutTrackerManifest {
        guard !storageUnavailable, state.origin != nil, state.installationId != nil,
              state.cachedPlanBlocks[String(sessionId)] == nil,
              let manifest = state.manifests[String(sessionId)], !manifest.hasObservations, manifest.status == "planned",
              !manifest.exerciseOccurrences.isEmpty, manifest.exerciseOccurrences.allSatisfy({ $0.loadMode != .duration && !$0.sets.isEmpty }) else { throw WorkoutTrackerContractError.unavailableCapture }
        if let index = state.index {
            guard index.sessions.contains(where: { $0.sessionId == sessionId && $0.status == "planned" }) else { throw WorkoutTrackerContractError.unavailableCapture }
        }
        try manifest.validate(); return manifest
    }
    func cachedCaptureBinding(sessionId: Int) throws -> WorkoutTrackerCaptureBinding {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        let manifest = try cachedManifest(sessionId: sessionId)
        guard let origin = state.origin, let installation = state.installationId else { throw WorkoutSyncTransportError.configuration }
        return try WorkoutTrackerCaptureBinding(manifest: manifest, connection: .init(origin: origin, installationId: installation),
            planAtStart: .init(manifest: manifest, provenance: .cached, fetchedAt: state.manifestReadAt[String(sessionId)]))
    }

    /// Persist the complete local intent before SQLite. Unsupported bindings remain reviewable.
    func prepare(record: LiftSessionRow, sets: [LiftSetRow], binding: WorkoutTrackerCaptureBinding, store: WhoopStore,
                 deleting: Bool = false, isHistoricalChange: Bool = false) async throws -> UUID {
        guard !metadataRestoring else { throw WorkoutTrackerContractError.deliveryInProgress }
        guard !transmittingCaptures.contains(binding.sourceWorkoutId), preparingCaptures.insert(binding.sourceWorkoutId).inserted else {
            throw WorkoutTrackerContractError.deliveryInProgress
        }
        defer { preparingCaptures.remove(binding.sourceWorkoutId) }
        // Saving does not require the Keychain or an enabled connection. The destination belongs
        // to the capture, so changing settings cannot redirect an existing workout's observations.
        let destination = binding.connection ?? state.origin.flatMap { origin in
            state.installationId.map { WorkoutTrackerCaptureBinding.Connection(origin: origin, installationId: $0) }
        }
        guard let destination else { throw WorkoutSyncTransportError.configuration }
        let operation: WorkoutTrackerDelivery.Operation = deleting ? .delete : .upsert
        if let retry = state.deliveries.last(where: { $0.sourceWorkoutId == binding.sourceWorkoutId && $0.status == .prepared && $0.record == record && $0.sets == sets && ($0.operation ?? .upsert) == operation }) {
            return retry.id
        }
        let previous = try history(for: binding.sourceWorkoutId)
        let previousRevision = previous.map(\.revision).max() ?? 0
        guard previousRevision < 9_007_199_254_740_991 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let revision = previousRevision + 1
        let event = UUID()
        var bytes: Data?
        var writeManifest: WorkoutTrackerManifest?
        var message = "Waiting for verified local persistence"
        do {
            guard binding.connection != nil else { throw WorkoutTrackerContractError.invalidSnapshot }
            let verifiedRevision = previous.filter(\.hasVerifiedSourceAcceptance).map(\.revision).max() ?? 0
            // A local correction cannot resolve an unknown previous server outcome by replaying it.
            if isHistoricalChange, previous.contains(where: { !$0.submissionOutcomeResolvedForReview && $0.revision > verifiedRevision }) {
                throw WorkoutTrackerContractError.unavailableCapture
            }
            let acknowledged = previous.last(where: \.hasVerifiedSourceAcceptance)
            writeManifest = acknowledged?.reviewedManifest
            let receipt = acknowledged?.acknowledgement.flatMap { try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: $0) }
            let removed = Set(previous.filter { $0.status == .accepted }.flatMap(\.sets).map(\.id)).subtracting(sets.map(\.id))
            let evidence = deleting ? [:] : try await WorkoutCapturePayload.measuredEvidence(record: record, sets: sets, store: store)
            bytes = try WorkoutCapturePayload.make(record: record, sets: sets, binding: binding,
                installationId: destination.installationId, revision: revision, eventId: event, heartRateEvidence: evidence,
                baseLifeRevision: receipt?.lifeRevision, writeManifestRevision: acknowledged?.reviewedManifest?.manifestRevision,
                deletedSetIds: removed.compactMap(UUID.init(uuidString:)), deleting: deleting).bytes()
        }
        catch let error as WorkoutObservationError { message = "Tracker payload could not be prepared. " + error.localizedDescription }
        catch { message = "Tracker payload needs review before upload. Local values are retained." }
        var next = state
        next.deliveries.append(WorkoutTrackerDelivery(id: event, sourceWorkoutId: binding.sourceWorkoutId,
            installationId: destination.installationId, origin: destination.origin, revision: revision, bytes: bytes,
            record: record, sets: sets, binding: binding, operation: operation, message: message,
            paused: state.locallyKeptSources.contains(binding.sourceWorkoutId) ? true : previous.last?.paused, createdAt: Date(),
            reviewedManifest: bytes == nil ? nil : writeManifest, submissionAttempted: false))
        try commit(next)
        return event
    }

    /// History changes retain the same capture IDs. An unknown earlier receipt requires review.
    func prepareHistoryChange(record: LiftSessionRow, sets: [LiftSetRow], store: WhoopStore, deleting: Bool = false) async throws -> UUID? {
        guard let source = UUID(uuidString: record.id), let previous = try history(for: source).last else { return nil }
        return try await prepare(record: record, sets: sets, binding: previous.binding, store: store, deleting: deleting, isHistoricalChange: true)
    }

    func confirmPersistence(_ id: UUID, store: WhoopStore) async throws {
        guard let item = state.deliveries.first(where: { $0.id == id }), try await item.matches(store: store) else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        var next = state
        guard let index = next.deliveries.firstIndex(where: { $0.id == id }) else { return }
        next.deliveries[index].status = item.bytes == nil ? .review : .ready
        next.deliveries[index].localPersistenceConfirmed = true
        next.deliveries[index].message = item.bytes == nil ? "Saved locally · \(item.message)" : (item.operation == .delete ? "Deleted locally · waiting for tracker tombstone receipt" : "Saved locally · waiting for tracker receipt")
        if item.paused == true { next.deliveries[index].status = .review; next.deliveries[index].message = "Kept locally · automatic tracker delivery is paused" }
        next.message = "Workout saved locally. Tracker delivery is separate."
        try commit(next)
    }

    func keepLocally(deliveryId: UUID) throws {
        guard !busy, let item = try delivery(deliveryId),
              !preparingCaptures.contains(item.sourceWorkoutId), !transmittingCaptures.contains(item.sourceWorkoutId) else {
            throw WorkoutTrackerContractError.deliveryInProgress
        }
        var next = state
        next.locallyKeptSources.insert(item.sourceWorkoutId)
        for index in next.deliveries.indices where next.deliveries[index].sourceWorkoutId == item.sourceWorkoutId {
            next.deliveries[index].paused = true
            if next.deliveries[index].status != .accepted { next.deliveries[index].status = .review }
            next.deliveries[index].message = "Kept locally · automatic tracker delivery is paused. Earlier tracker data stays unchanged."
        }
        try commit(next)
    }

    /// One bounded pass; callers can retry the same immutable event after a timeout or relaunch.
    func synchronize(store: WhoopStore, deliveryId: UUID? = nil) async throws {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        if let deliveryId { try activateDelivery(deliveryId) }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        busy = true; defer { busy = false }
        let currentGeneration = generation
        let candidates = state.deliveries.filter { item in
            if let deliveryId { return item.id == deliveryId }
            return item.paused != true && !state.locallyKeptSources.contains(item.sourceWorkoutId) && ([.prepared, .ready, .failed].contains(item.status) || item.needsReconciliation)
        }
        if deliveryId != nil && candidates.isEmpty { throw WorkoutTrackerContractError.invalidSnapshot }
        for item in candidates.prefix(10) {
            guard currentGeneration == generation, state.enabled, !Task.isCancelled else { return }
            guard !preparingCaptures.contains(item.sourceWorkoutId) else { throw WorkoutTrackerContractError.deliveryInProgress }
            if try reviewedReplacement(for: item.id) != nil { throw WorkoutTrackerContractError.deliverySuperseded }
            transmittingCaptures.insert(item.sourceWorkoutId)
            defer { transmittingCaptures.remove(item.sourceWorkoutId) }
            guard item.origin == config.origin, item.installationId == config.installationId,
                  try await item.matches(store: store) else {
                try updateDelivery(item.id, status: .review, message: "Local recording or connection changed; review before upload")
                if deliveryId != nil { throw WorkoutTrackerContractError.invalidSnapshot }
                continue
            }
            guard let body = item.bytes else {
                try updateDelivery(item.id, status: .review, message: item.message)
                if deliveryId != nil { throw WorkoutTrackerContractError.invalidSnapshot }
                continue
            }
            try item.validateBody()
            do {
                var attempting = state
                guard let index = attempting.deliveries.firstIndex(where: { $0.id == item.id }) else { throw WorkoutTrackerContractError.sessionChanged }
                attempting.deliveries[index].submissionAttempted = true
                try commit(attempting, protecting: [item.sourceWorkoutId])
                let response = try await send(.observations, body, config)
                let ack = try JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: response)
                try ack.validate(eventId: item.id, sourceWorkoutId: item.sourceWorkoutId, revision: item.revision)
                guard currentGeneration == generation, state.enabled else { return }
                if ack.needsSourceReview(revision: item.revision, deleting: item.operation == .delete, expectingHistoryOnly: item.isHistoryOnly) {
                    try updateDelivery(item.id, status: .review, message: "Tracker capture or projection state differs; review before retrying", acknowledgement: response)
                } else {
                    try ack.validate(binding: item.binding, sets: item.operation == .delete ? [] : item.sets)
                    let receipt = item.operation == .delete ? (!ack.preservedFields.isEmpty || ack.outcome == "manual_preserved" ? "Tracker source tombstone verified · manual website edits preserved" : "Tracker source tombstone verified") :
                        item.isHistoryOnly ? "Tracker saved source history only · website sets and progression were not updated" :
                        !ack.preservedFields.isEmpty || ack.outcome == "manual_preserved" ? "Tracker accepted observations and preserved website edits" : "Tracker accepted this capture revision"
                    try updateDelivery(item.id, status: .accepted,
                        message: ack.reconciliation.pending ? "\(receipt) · derived progress is pending; Sync retries the same receipt" : receipt,
                        acknowledgement: response)
                }
            } catch WorkoutSyncTransportError.rejected(let reason) {
                try updateDelivery(item.id, status: .review, message: reason.explanation + " Local values are retained.", rejection: reason)
                throw WorkoutSyncTransportError.rejected(reason)
            } catch WorkoutSyncTransportError.http(let code) {
                try updateDelivery(item.id, status: code == 409 ? .review : .failed,
                    message: code == 409 ? "Tracker revision or binding changed. Review before retrying." : "Tracker returned HTTP \(code). Saved locally; retry uses the same event.")
                throw WorkoutSyncTransportError.http(code)
            } catch {
                try updateDelivery(item.id, status: .failed, message: "Tracker receipt was not verified. Saved locally; retry uses the same event.")
                throw error
            }
        }
    }

    private func updateDelivery(_ id: UUID, status: WorkoutTrackerDelivery.Status, message: String, acknowledgement: Data? = nil, rejection: WorkoutSyncRejection? = nil) throws {
        var next = state
        guard let index = next.deliveries.firstIndex(where: { $0.id == id }) else { return }
        next.deliveries[index].status = status; next.deliveries[index].message = message
        next.deliveries[index].rejection = rejection
        if let acknowledgement { next.deliveries[index].acknowledgement = acknowledgement }
        try commit(next)
    }
}
#endif
