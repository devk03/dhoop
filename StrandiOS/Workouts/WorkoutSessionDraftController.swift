import Foundation
import Combine

/// Immediate local edits and finite delivery attempts share one durable draft per Life workout.
@MainActor
final class WorkoutSessionDraftController: ObservableObject {
    private final class Reference {
        weak var value: WorkoutSessionDraftController?
        init(_ value: WorkoutSessionDraftController) { self.value = value }
    }
    private static var opened: [String: Reference] = [:]
    static func open(session: WorkoutTrackerDashboard.Session, revision: Int, origin: String,
                     installationId: UUID, massScale: Double) -> WorkoutSessionDraftController {
        let key = "\(installationId.uuidString.lowercased())-\(session.mesocycleId)-\(session.id)"
        if let existing = opened[key]?.value, existing.state.origin == origin { return existing }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let initial = WorkoutSessionDraft(origin: origin, installationId: installationId, baseline: session,
            revision: revision, massScale: massScale, localeIdentifier: Locale.current.identifier)
        let value = WorkoutSessionDraftController(initial: initial,
            store: .init(url: root.appendingPathComponent("Dhoop/WorkoutDrafts/\(key).json")), frontend: .shared)
        opened[key] = Reference(value); return value
    }
    private static var restoringPending = false
    /// Foreground/relaunch recovery is finite and uses only explicitly saved pending intentions.
    /// Draft typing never enters this path, and a changed connection cannot redirect a retained save.
    static func resumePendingWorkouts(frontend: WorkoutFrontendClient = .shared, directory: URL? = nil,
        read: ((WorkoutSessionDraft) async throws -> WorkoutSessionDraft.Remote)? = nil) async {
        guard !restoringPending, frontend.state.enabled,
              let origin = frontend.state.origin, let installation = frontend.state.installationId else { return }
        restoringPending = true; defer { restoringPending = false }
        // Older app versions saved standalone set operations without a whole-workout draft.
        // They share the same queue and must be resolved before a new draft can enter it.
        if let earlier = frontend.unresolved { _ = try? await frontend.deliverRetained(earlier.id) }
        guard frontend.state.capabilities?.sessionBatchSave == true else { return }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dhoop/WorkoutDrafts")
        let retained = await Task.detached(priority: .utility) { () -> [(URL, WorkoutSessionDraft)] in
            let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(1000).compactMap { url in
                guard let state = try? WorkoutSessionDraftFileStore(url: url).load(), state.pending != nil,
                      state.origin == origin, state.installationId == installation else { return nil }
                return (url, state)
            }
        }.value
        for (url, initial) in retained.prefix(20) {
            guard frontend.state.enabled, frontend.state.origin == origin, frontend.state.installationId == installation else { break }
            let key = "\(installation.uuidString.lowercased())-\(initial.baseline.mesocycleId)-\(initial.baseline.id)"
            let controller: WorkoutSessionDraftController
            if let existing = opened[key]?.value, existing.state.origin == origin { controller = existing }
            else {
                controller = WorkoutSessionDraftController(initial: initial, store: .init(url: url), frontend: frontend)
                opened[key] = Reference(controller)
            }
            if let read {
                controller.setRefresh { [weak controller] in
                    guard let controller else { throw CancellationError() }
                    return try await read(controller.state)
                }
            } else { controller.setRefresh(reader(for: initial)) }
            controller.resume(); await controller.waitForDelivery()
        }
    }
    /// Capture only source identity, not a SwiftUI screen or its retained draft controller.
    static func reader(for draft: WorkoutSessionDraft) -> () async throws -> WorkoutSessionDraft.Remote {
        let origin = draft.origin, installation = draft.installationId
        let cycleId = draft.baseline.mesocycleId, sessionId = draft.baseline.id
        return {
            let tracker = WorkoutTrackerClient.shared
            guard tracker.state.origin == origin, tracker.state.installationId == installation, tracker.state.enabled else { throw WorkoutSyncTransportError.configuration }
            try await tracker.refreshDashboard(mesocycleId: cycleId, sessionId: sessionId)
            guard tracker.state.origin == origin, tracker.state.installationId == installation,
                  let page = tracker.state.frontendPage,
                  let session = page.dashboard.sessions.first(where: { $0.id == sessionId && $0.mesocycleId == cycleId }) else { throw WorkoutTrackerContractError.invalidSnapshot }
            return .init(session: session, revision: page.lifeRevision)
        }
    }
    @Published private(set) var state: WorkoutSessionDraft
    @Published private(set) var message: String?
    @Published private(set) var storageUnavailable = false
    @Published private(set) var working = false
    @Published private(set) var checkingLatest = false
    private var loadFailed = false
    var canRetryLocalStorage: Bool { storageUnavailable && !loadFailed }
    private let store: WorkoutSessionDraftFileStore
    private let frontend: WorkoutFrontendClient
    private var worker: Task<Void, Never>?
    private var refresh: (() async throws -> WorkoutSessionDraft.Remote)?
    init(initial: WorkoutSessionDraft, store: WorkoutSessionDraftFileStore, frontend: WorkoutFrontendClient) {
        self.state = initial; self.store = store; self.frontend = frontend
        do {
            if var loaded = try store.load() {
                guard loaded.origin == initial.origin, loaded.installationId == initial.installationId,
                      loaded.baseline.id == initial.baseline.id, loaded.baseline.mesocycleId == initial.baseline.mesocycleId else {
                    throw WorkoutSessionDraft.Failure.changed
                }
                try loaded.receive(initial.baseline, revision: initial.revision); state = loaded
            }
        } catch { loadFailed = true; storageUnavailable = true; message = "Local workout changes could not be read. Existing input is retained; editing is paused." }
    }
    var canEdit: Bool { !storageUnavailable && !state.finishQueued && state.pending?.finishing != true }
    private var connectionCanSend: Bool {
        !storageUnavailable && !frontend.storageUnavailable && frontend.state.enabled &&
        (state.baseline.status != "completed" || frontend.state.capabilities?.historicalSessionEditing == true) &&
        frontend.state.capabilities?.manualCommands == true && frontend.state.capabilities?.actions.contains("update_session") == true &&
        frontend.state.origin == state.origin && frontend.state.installationId == state.installationId &&
        frontend.state.capabilities?.sessionBatchSave == true
    }
    var canSend: Bool { connectionCanSend && state.remote == nil }
    private func commit(_ next: WorkoutSessionDraft) throws { try store.save(next); state = next }
    func edit(_ entry: WorkoutInlineSetDraft) {
        guard canEdit else { return }
        do {
            var next = state; try next.edit(entry); try commit(next)
            if state.pending == nil { message = "Saved on this phone" }
            else { message = state.hasNewerEdits ? "Sending workout · newer edits stay on this phone" : "Sending saved workout to Life" }
        } catch {
            message = "Couldn't save this edit on your phone. Keep this workout open and retry."
            // Keep the latest input visible even if storage fills; it must not be sent as durable input.
            var retained = state; try? retained.edit(entry); state = retained; storageUnavailable = true
        }
    }
    func retryLocalStorage() {
        guard !loadFailed else { return }
        do { try store.save(state); storageUnavailable = false; message = "Saved on this phone" }
        catch { message = "Couldn't save this edit on your phone. Keep this workout open and retry." }
    }
    func receive(_ remote: WorkoutSessionDraft.Remote) throws {
        var next = state; try next.receive(remote.session, revision: remote.revision); try commit(next)
    }
    func resolveRemote(keepEdits: Bool) throws {
        var next = state; try next.resolveRemote(keepEdits: keepEdits); try commit(next)
        message = keepEdits ? "Your edits are kept locally. Save workout to send them." : "Latest Life workout loaded"
    }
    func requestSave(finishing: Bool, refresh: @escaping () async throws -> WorkoutSessionDraft.Remote) throws {
        guard canSend, !finishing || frontend.state.capabilities?.sessionCompletion == true else { throw WorkoutFrontendClient.Failure.disabled }
        var next = state; try next.freeze(finishing: finishing); try commit(next)
        self.refresh = refresh
        message = state.finishQueued ? "Finish queued after the current save" : "Workout saved on this phone · sending to Life"
        resume()
    }
    /// Refresh before creating a NEW immutable submission. Offline reads do not prevent a durable
    /// save; a retained submission or queued Finish always keeps its existing identity and bytes.
    func requestSaveAfterRefreshing(finishing: Bool, refresh: @escaping () async throws -> WorkoutSessionDraft.Remote) async throws {
        guard !checkingLatest else { throw WorkoutFrontendClient.Failure.unresolved }
        if state.pending == nil {
            checkingLatest = true
            defer { checkingLatest = false }
            message = "Checking the latest workout. Your edits stay on this phone."
            if let earlier = frontend.unresolved { _ = try? await frontend.deliverRetained(earlier.id) }
            let latest: WorkoutSessionDraft.Remote?
            do { latest = try await refresh() }
            catch { latest = nil }
            try Task.checkCancellation()
            if let latest { try receive(latest) }
            try requestSave(finishing: finishing, refresh: refresh)
        } else {
            try requestSave(finishing: finishing, refresh: refresh)
        }
    }
    func setRefresh(_ value: @escaping () async throws -> WorkoutSessionDraft.Remote) { refresh = value }
    /// At most the saved batch and an explicitly queued Finish. No polling or per-set sender exists.
    func resume() {
        guard !working, worker == nil, !storageUnavailable, state.pending != nil, connectionCanSend else { return }
        working = true; message = "Syncing retained workout"
        worker = Task { @MainActor [self] in
            defer { working = false; worker = nil }
            for _ in 0..<2 {
                guard let submission = state.pending else { break }
                do {
                    if let earlier = frontend.unresolved, earlier.id != submission.id {
                        message = "Recovering an earlier Life change. This workout stays on your phone."
                        _ = try await frontend.deliverRetained(earlier.id)
                    }
                    let id = try frontend.prepare(command: submission.command, revision: submission.revision, operationId: submission.id)
                    guard let operation = frontend.state.operations.first(where: { $0.id == id }) else { throw WorkoutFrontendClient.Failure.unavailable }
                    if operation.state == .cancelled {
                        var cancelled = state; cancelled.pending = nil; cancelled.finishQueued = false; try commit(cancelled)
                        message = "Queued sync cancelled. Your local edits are retained."
                        break
                    }
                    _ = try await frontend.deliverRetained(id)
                    guard let accepted = frontend.state.operations.first(where: { $0.id == id }),
                          accepted.state == .committed, let receipt = accepted.receipt,
                          let revision = receipt.receiptLifeRevision else { throw WorkoutFrontendClient.Failure.needsRecovery }
                    var next = state; try next.accept(submission, revision: revision); try commit(next)
                    message = savedMessage(finishing: submission.finishing, refreshed: true)
                    // One read per whole-workout ACK; a failed read never erases its success.
                    if let refresh {
                        do { let latest = try await refresh(); try receive(latest) }
                        catch { message = savedMessage(finishing: submission.finishing, refreshed: false) }
                    }
                    if state.finishQueued {
                        guard state.remote == nil else { message = "Life changed. Review your retained edits before finishing."; break }
                        var queued = state; queued.finishQueued = false
                        do {
                            if queued.baseline.status != "completed" { try queued.freeze(finishing: true) }
                            try commit(queued)
                        } catch {
                            queued.pending = nil; queued.finishQueued = false; try commit(queued)
                            message = "Finish could not be queued. Your workout changes remain saved; review its schedule."
                            break
                        }
                    }
                } catch {
                    // Retain both frozen operation and newer local edits. The next attempt recovers the
                    // SAME receipt/bytes; it never manufactures a new ID after an unknown result.
                    if let earlier = frontend.unresolved, earlier.id != submission.id {
                        message = "An earlier Life change is unresolved. Your workout is saved on this phone; retry sync when connected."
                    } else if frontend.state.operations.first(where: { $0.id == submission.id })?.state == .rejected {
                        message = "Life rejected this save. Your edits are retained; review the latest workout."
                    } else {
                        message = "Workout retained on this phone. Retry sync to recover the same save."
                    }
                    break
                }
            }
        }
    }
    private func savedMessage(finishing: Bool, refreshed: Bool) -> String {
        if state.hasChanges { return "Saved in Life · newer edits are on this phone. Save workout to send them." }
        if !refreshed { return "Saved in Life. Refresh the workout when connected." }
        return finishing ? "Workout finished in Life" : "Workout saved in Life"
    }
    func cancelQueuedFinish() throws {
        guard state.pending?.finishing != true else { throw WorkoutFrontendClient.Failure.needsRecovery }
        var next = state; next.finishQueued = false; try commit(next)
        message = "Queued finish cancelled. Your local edits are retained."
    }
    func waitForDelivery() async { await worker?.value }
    /// Rejected operations cannot be replayed; explicit review retains the draft for a new Save.
    func reviewRejected() throws {
        guard let pending = state.pending,
              frontend.state.operations.first(where: { $0.id == pending.id })?.state == .rejected else { throw WorkoutFrontendClient.Failure.needsRecovery }
        var next = state; next.pending = nil; next.finishQueued = false
        if let remote = next.remote { next.remote = nil; try next.receive(remote.session, revision: remote.revision) }
        try commit(next)
        message = "Life rejected this save. Refresh and review your retained edits before saving again."
    }
}
