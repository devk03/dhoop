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
    private func commit(_ next: WorkoutTrackerState) throws {
        guard !storageUnavailable else { throw WorkoutTrackerContractError.invalidSnapshot }
        try store.save(next); state = next
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
    func configure(origin: String, token: String, installationId: UUID) throws {
        guard !busy else { throw WorkoutSyncTransportError.configuration }
        let value = WorkoutSyncConfiguration(origin: origin, installationId: installationId, credential: token)
        guard value.valid else { throw WorkoutSyncTransportError.configuration }
        var next = state
        next.enabled = false; next.origin = origin; next.installationId = installationId
        next.index = nil; next.manifests = [:]; next.capturedAt = nil
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
        let bytes = try await send(.manifest(sessionId), nil, config)
        let manifest = try JSONDecoder().decode(WorkoutTrackerManifest.self, from: bytes)
        try manifest.validate()
        guard manifest.sessionId == sessionId, !Task.isCancelled, currentGeneration == generation, state.enabled else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        var next = state; next.manifests[String(sessionId)] = manifest; next.capturedAt = Date()
        try commit(next)
        return manifest
    }

    func captureSnapshot(deliveryId: UUID) async throws -> WorkoutTrackerCaptureSnapshot {
        guard !busy else { throw WorkoutTrackerContractError.deliveryInProgress }
        guard let item = state.deliveries.first(where: { $0.id == deliveryId }) else { throw WorkoutTrackerContractError.invalidSnapshot }
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        guard config.origin == item.origin, config.installationId == item.installationId else { throw WorkoutSyncTransportError.configuration }
        busy = true; defer { busy = false }
        let initialGeneration = generation
        var cursor = 0, result: WorkoutTrackerCaptureSnapshot?
        for _ in 0..<5 {
            let data = try await send(.captures(item.sourceWorkoutId, cursor: cursor, limit: 50), nil, config)
            var page = try JSONDecoder().decode(WorkoutTrackerCaptureSnapshot.self, from: data)
            try page.validate(for: item.binding)
            guard page.sets.count <= 50 else { throw WorkoutTrackerContractError.invalidSnapshot }
            let pageCount = page.sets.count
            if let previous = result {
                guard previous.sourceRevision == page.sourceRevision, previous.lifeRevision == page.lifeRevision else { throw WorkoutTrackerContractError.invalidSnapshot }
                page.sets = previous.sets + page.sets
                try page.validate(for: item.binding)
            }
            result = page
            guard let next = page.nextCursor else { break }
            guard pageCount > 0, next == cursor + pageCount, next <= 200 else { throw WorkoutTrackerContractError.invalidSnapshot }
            cursor = next
        }
        guard let result, result.nextCursor == nil, initialGeneration == generation, state.enabled, !Task.isCancelled else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        return result
    }

    func captureBinding(manifest: WorkoutTrackerManifest) throws -> WorkoutTrackerCaptureBinding {
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        return try WorkoutTrackerCaptureBinding(manifest: manifest,
            connection: .init(origin: config.origin, installationId: config.installationId))
    }

    /// Persist the complete local intent before SQLite. Unsupported bindings remain reviewable.
    func prepare(record: LiftSessionRow, sets: [LiftSetRow], binding: WorkoutTrackerCaptureBinding, store: WhoopStore,
                 deleting: Bool = false, isHistoricalChange: Bool = false) async throws -> UUID {
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
        let previousRevision = state.deliveries.filter { $0.sourceWorkoutId == binding.sourceWorkoutId }.map(\.revision).max() ?? 0
        guard previousRevision < 9_007_199_254_740_991 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let revision = previousRevision + 1
        let event = UUID()
        var bytes: Data?
        var message = "Waiting for verified local persistence"
        do {
            guard binding.connection != nil else { throw WorkoutTrackerContractError.invalidSnapshot }
            let previous = state.deliveries.filter { $0.sourceWorkoutId == binding.sourceWorkoutId }
            let verifiedRevision = previous.filter { $0.status == .accepted }.map(\.revision).max() ?? 0
            // A local correction cannot resolve an unknown previous server outcome by replaying it.
            if isHistoricalChange, previous.contains(where: { $0.status != .accepted && $0.revision > verifiedRevision }) {
                throw WorkoutTrackerContractError.unavailableCapture
            }
            let acknowledged = previous.last(where: { $0.status == .accepted })
            let receipt = acknowledged?.acknowledgement.flatMap { try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: $0) }
            let removed = Set(previous.filter { $0.status == .accepted }.flatMap(\.sets).map(\.id)).subtracting(sets.map(\.id))
            let evidence = deleting ? [:] : try await WorkoutCapturePayload.measuredEvidence(record: record, sets: sets, store: store)
            bytes = try WorkoutCapturePayload.make(record: record, sets: sets, binding: binding,
                installationId: destination.installationId, revision: revision, eventId: event, heartRateEvidence: evidence,
                baseLifeRevision: receipt?.lifeRevision, deletedSetIds: removed.compactMap(UUID.init(uuidString:)), deleting: deleting).bytes()
        }
        catch { message = "Saved intent needs binding review before upload. Local values are retained." }
        var next = state
        next.deliveries.append(WorkoutTrackerDelivery(id: event, sourceWorkoutId: binding.sourceWorkoutId,
            installationId: destination.installationId, origin: destination.origin, revision: revision, bytes: bytes,
            record: record, sets: sets, binding: binding, operation: operation, message: message,
            paused: state.deliveries.last(where: { $0.sourceWorkoutId == binding.sourceWorkoutId })?.paused))
        try commit(next)
        return event
    }

    /// History changes retain the same capture IDs. An unknown earlier receipt requires review.
    func prepareHistoryChange(record: LiftSessionRow, sets: [LiftSetRow], store: WhoopStore, deleting: Bool = false) async throws -> UUID? {
        guard let previous = state.deliveries.last(where: { $0.sourceWorkoutId.uuidString.lowercased() == record.id.lowercased() }) else { return nil }
        return try await prepare(record: record, sets: sets, binding: previous.binding, store: store, deleting: deleting, isHistoricalChange: true)
    }

    func confirmPersistence(_ id: UUID, store: WhoopStore) async throws {
        guard let item = state.deliveries.first(where: { $0.id == id }), try await item.matches(store: store) else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        var next = state
        guard let index = next.deliveries.firstIndex(where: { $0.id == id }) else { return }
        next.deliveries[index].status = item.bytes == nil ? .review : .ready
        next.deliveries[index].message = item.bytes == nil ? "Saved locally · review capture bindings or an earlier unverified receipt" : (item.operation == .delete ? "Deleted locally · waiting for tracker tombstone receipt" : "Saved locally · waiting for tracker receipt")
        if item.paused == true { next.deliveries[index].status = .review; next.deliveries[index].message = "Kept locally · automatic tracker delivery is paused" }
        next.message = "Workout saved locally. Tracker delivery is separate."
        try commit(next)
    }

    func keepLocally(deliveryId: UUID) throws {
        guard !busy, let item = state.deliveries.first(where: { $0.id == deliveryId }),
              !preparingCaptures.contains(item.sourceWorkoutId), !transmittingCaptures.contains(item.sourceWorkoutId) else {
            throw WorkoutTrackerContractError.deliveryInProgress
        }
        var next = state
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
        let config = try credentials()
        guard config.enabled else { throw WorkoutSyncTransportError.disabled }
        busy = true; defer { busy = false }
        let currentGeneration = generation
        let candidates = state.deliveries.filter { item in
            if let deliveryId { return item.id == deliveryId }
            return item.paused != true && ([.prepared, .ready, .failed].contains(item.status) || item.needsReconciliation)
        }
        if deliveryId != nil && candidates.isEmpty { throw WorkoutTrackerContractError.invalidSnapshot }
        for item in candidates.prefix(10) {
            guard currentGeneration == generation, state.enabled, !Task.isCancelled else { return }
            guard !preparingCaptures.contains(item.sourceWorkoutId) else { throw WorkoutTrackerContractError.deliveryInProgress }
            transmittingCaptures.insert(item.sourceWorkoutId)
            defer { transmittingCaptures.remove(item.sourceWorkoutId) }
            guard item.origin == config.origin, item.installationId == config.installationId,
                  try await item.matches(store: store) else {
                try updateDelivery(item.id, status: .review, message: "Local recording or connection changed; review before upload")
                if deliveryId != nil { throw WorkoutTrackerContractError.invalidSnapshot }
                continue
            }
            guard let body = item.bytes else {
                try updateDelivery(item.id, status: .review, message: "Review extra exercise/set bindings before upload")
                if deliveryId != nil { throw WorkoutTrackerContractError.invalidSnapshot }
                continue
            }
            try item.validateBody()
            do {
                let response = try await send(.observations, body, config)
                let ack = try JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: response)
                try ack.validate(eventId: item.id, sourceWorkoutId: item.sourceWorkoutId, revision: item.revision)
                guard currentGeneration == generation, state.enabled else { return }
                if ack.needsSourceReview(revision: item.revision, deleting: item.operation == .delete) {
                    try updateDelivery(item.id, status: .review, message: "Tracker capture or projection state differs; review before retrying", acknowledgement: response)
                } else {
                    try ack.validate(binding: item.binding, sets: item.operation == .delete ? [] : item.sets)
                    let receipt = !ack.preservedFields.isEmpty || ack.outcome == "manual_preserved" ? "Tracker accepted observations and preserved website edits" : "Tracker accepted this capture revision"
                    try updateDelivery(item.id, status: .accepted,
                        message: ack.reconciliation.pending ? "\(receipt) · derived progress is pending; Sync retries the same receipt" : receipt,
                        acknowledgement: response)
                }
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

    private func updateDelivery(_ id: UUID, status: WorkoutTrackerDelivery.Status, message: String, acknowledgement: Data? = nil) throws {
        var next = state
        guard let index = next.deliveries.firstIndex(where: { $0.id == id }) else { return }
        next.deliveries[index].status = status; next.deliveries[index].message = message
        if let acknowledgement { next.deliveries[index].acknowledgement = acknowledgement }
        try commit(next)
    }
}
#endif
