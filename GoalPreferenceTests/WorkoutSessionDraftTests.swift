import XCTest

@MainActor
final class WorkoutSessionDraftTests: XCTestCase {
    private let config = WorkoutSyncConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), credential: String(repeating: "d", count: 64))
    private func file(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name) }
    private func session(load: Double? = nil, reps: Int? = nil, status: String = "planned") -> WorkoutTrackerDashboard.Session {
        let rows = (1...3).map { WorkoutTrackerDashboard.SetLog(id: $0, setNumber: $0, setType: "work", plannedLoad: 135, plannedReps: 8,
            actualLoad: $0 == 1 ? load : nil, actualReps: $0 == 1 ? reps : nil, rir: nil, completed: $0 == 1 && (load != nil || reps != nil)) }
        let exercise = WorkoutTrackerDashboard.Exercise(id: 11, exerciseKey: "press", name: "Bench press", orderIndex: 1, loadMode: "barbell", progressionType: "double", plannedSets: 3, plannedReps: 8, plannedLoad: 135, targetRir: 2, notes: "", slotKey: "press", movementPattern: "push", originalExerciseKey: "press", originalExerciseName: "Press", isPriming: false, sets: rows)
        return .init(id: 10, mesocycleId: 1, weekNumber: 2, sessionKey: "upper", kind: "strength", title: "Upper", scheduledDate: "2026-10-20", orderIndex: 1, status: status, readiness: "", rating: "", notes: "", metrics: [:], sheetItemId: "", linkedSessionId: nil, completedAt: "", exercises: [exercise], finisher: nil)
    }
    private func initial(_ session: WorkoutTrackerDashboard.Session? = nil, massScale: Double = 1) -> WorkoutSessionDraft {
        .init(origin: config.origin, installationId: config.installationId, baseline: session ?? self.session(), revision: 4, massScale: massScale, localeIdentifier: "en_US")
    }
    private func capabilities() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "manualCommands": true, "frontendStart": false,
            "sessionCompletion": true, "sessionBatchSave": true, "lifeRevision": 4, "actions": ["update_session"]])
    }
    private func receipt(_ intent: WorkoutFrontendIntent, revision: Int = 5, state: String = "committed") throws -> Data {
        var value: [String: Any] = ["schemaVersion": 1, "operationId": intent.operationId.uuidString.lowercased(), "state": state, "lifeRevision": revision]
        if state != "not_observed" {
            value["request"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(intent))
            value["requestHash"] = String(repeating: "b", count: 64); value["receiptLifeRevision"] = revision
            if state == "committed" { value["result"] = ["mesocycleId": 1, "sessionId": 10, "invalidate": "workout_tracker"] }
        }
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func enable(_ frontend: WorkoutFrontendClient) async throws {
        try frontend.configure(origin: config.origin, installationId: config.installationId, token: config.credential)
        try frontend.setEnabled(true); try await frontend.checkCapabilities()
    }
    func testRapidLocalEditsAndChecksMakeZeroRequestsAndSurviveRelaunch() async throws {
        var network = 0
        let frontend = WorkoutFrontendClient(store: .init(url: file("commands.json")), send: { _, _, _ in network += 1; return try self.capabilities() }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(frontend); network = 0
        let store = WorkoutSessionDraftFileStore(url: file("draft.json"))
        let controller = WorkoutSessionDraftController(initial: initial(massScale: 2.2046226218), store: store, frontend: frontend)
        let start = Date()
        for index in 1...30 {
            let id = index % 3 + 1
            var entry = try XCTUnwrap(controller.state.entry(id)); entry.load = String(index); entry.reps = "8"; entry.completed = true
            controller.edit(entry)
        }
        print("Thirty durable local edits: \(Int(Date().timeIntervalSince(start) * 1000))ms; network requests: \(network)")
        XCTAssertEqual(network, 0); XCTAssertFalse(frontend.busy); XCTAssertTrue(controller.canEdit)
        XCTAssertTrue(frontend.state.operations.isEmpty)
        let restored = WorkoutSessionDraftController(initial: initial(massScale: 1), store: store, frontend: frontend)
        XCTAssertEqual(restored.state.edits, controller.state.edits)
        XCTAssertEqual(restored.state.massScale, 2.2046226218)
        XCTAssertEqual(restored.state.entry(1)?.load, "30")
        XCTAssertEqual(restored.state.entry(1)?.completed, true)
    }
    func testSaveBatchesAllChangesAndFinishDuringPendingSaveKeepsNewerInput() async throws {
        var commands: [WorkoutFrontendIntent] = [], reads = 0
        var release: CheckedContinuation<Void, Never>?
        let frontend = WorkoutFrontendClient(store: .init(url: file("commands.json")), send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            XCTAssertEqual(endpoint, .frontendCommand)
            let intent = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(body)); commands.append(intent)
            if commands.count == 1 { await withCheckedContinuation { release = $0 } }
            return try self.receipt(intent, revision: commands.count == 1 ? 5 : 6)
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(frontend)
        let controller = WorkoutSessionDraftController(initial: initial(), store: .init(url: file("draft.json")), frontend: frontend)
        for id in 1...3 {
            var edit = try XCTUnwrap(controller.state.entry(id)); edit.load = "135"; edit.reps = "8"; edit.completed = true; controller.edit(edit)
        }
        // The read fixture is independent: canonical first ACK applied 135x8 to all three sets.
        var saved = session()
        for index in saved.exercises[0].sets.indices {
            saved.exercises[0].sets[index].actualLoad = 135; saved.exercises[0].sets[index].actualReps = 8; saved.exercises[0].sets[index].completed = true
        }
        var finished = saved; finished.exercises[0].sets[0].actualReps = 9; finished.status = "completed"
        let refresh: () async throws -> WorkoutSessionDraft.Remote = {
            reads += 1; return .init(session: reads == 1 ? saved : finished, revision: reads == 1 ? 5 : 6)
        }
        try controller.requestSave(finishing: false, refresh: refresh)
        for _ in 0..<500 { if release != nil { break }; await Task.yield() }
        XCTAssertNotNil(release); XCTAssertTrue(frontend.busy); XCTAssertTrue(controller.canEdit)
        var newer = try XCTUnwrap(controller.state.entry(1)); newer.reps = "9"; controller.edit(newer)
        try controller.requestSave(finishing: true, refresh: refresh)
        XCTAssertTrue(controller.state.finishQueued)
        release?.resume(); await controller.waitForDelivery()
        XCTAssertEqual(commands.count, 2); XCTAssertEqual(reads, 2)
        guard case .array(let first) = commands.first?.command["sets"] else { return XCTFail("Missing batch") }
        XCTAssertEqual(first.count, 3); XCTAssertNil(commands[0].command["status"])
        XCTAssertEqual(commands[1].command["status"], .string("completed"))
        XCTAssertEqual(commands[1].expectedLifeRevision, 5)
        XCTAssertEqual(commands[1].command["sets"], .array([.object(["setId": .number(1), "actualReps": .number(9)])]))
        XCTAssertEqual(controller.state.baseline.status, "completed"); XCTAssertNil(controller.state.pending)
        XCTAssertFalse(controller.state.hasChanges); XCTAssertFalse(controller.state.finishQueued)
    }
    func testOfflineRecoveryUsesSameBytesAndCommittedReceiptCannotResendAfterRelaunch() async throws {
        let commandStore = WorkoutFrontendFileStore(url: file("commands.json")), draftStore = WorkoutSessionDraftFileStore(url: file("draft.json"))
        var bytes: Data?
        let frontend = WorkoutFrontendClient(store: commandStore, send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            bytes = body; throw URLError(.timedOut)
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(frontend)
        let controller = WorkoutSessionDraftController(initial: initial(), store: draftStore, frontend: frontend)
        var edit = try XCTUnwrap(controller.state.entry(1)); edit.reps = "8"; edit.completed = true; controller.edit(edit)
        try controller.requestSave(finishing: false, refresh: { throw URLError(.notConnectedToInternet) })
        await controller.waitForDelivery()
        let frozen = try XCTUnwrap(controller.state.pending), unknown = controller.state
        XCTAssertEqual(frontend.unresolved?.state, .uncertain)
        var posts = 0, lookups = 0
        let restoredFrontend = WorkoutFrontendClient(store: commandStore, send: { endpoint, body, _ in
            if case .frontendReceipt(let id) = endpoint {
                lookups += 1; XCTAssertEqual(id, frozen.id); XCTAssertNil(body)
                return try self.receipt(try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(bytes)), state: "not_observed")
            }
            XCTAssertEqual(endpoint, .frontendCommand); posts += 1; XCTAssertEqual(body, bytes)
            return try self.receipt(try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(body)))
        }, readCredential: { self.config }, saveCredential: { _ in })
        let restored = WorkoutSessionDraftController(initial: initial(), store: draftStore, frontend: restoredFrontend)
        restored.resume(); await restored.waitForDelivery()
        XCTAssertEqual(posts, 1); XCTAssertEqual(lookups, 1); XCTAssertNil(restored.state.pending)
        XCTAssertEqual(restoredFrontend.state.operations.count, 1)
        // Crash window: backend receipt was saved, but the draft checkpoint still holds that operation.
        let crashStore = WorkoutSessionDraftFileStore(url: file("crash-window.json")); try crashStore.save(unknown)
        let afterCrash = WorkoutSessionDraftController(initial: initial(), store: crashStore, frontend: restoredFrontend)
        afterCrash.resume(); await afterCrash.waitForDelivery()
        XCTAssertEqual(posts, 1); XCTAssertEqual(lookups, 1); XCTAssertNil(afterCrash.state.pending)
        XCTAssertFalse(afterCrash.state.hasChanges)
    }
    func testConflictsRequireExplicitReviewAndOnlyDeliberateFieldsOverrideRemote() throws {
        var draft = initial(session(load: 135, reps: 8))
        var edit = try XCTUnwrap(draft.entry(1)); edit.reps = "9"; try draft.edit(edit)
        try draft.receive(session(load: 140, reps: 8), revision: 5)
        XCTAssertNotNil(draft.remote); XCTAssertEqual(draft.entry(1)?.reps, "9")
        XCTAssertThrowsError(try draft.freeze(finishing: false))
        try draft.resolveRemote(keepEdits: true)
        XCTAssertEqual(draft.entry(1)?.load, "140"); XCTAssertEqual(draft.entry(1)?.reps, "9")
        XCTAssertEqual(try draft.command(finishing: false)["sets"], .array([.object(["setId": .number(1), "actualReps": .number(9)])]))
        var removed = session(); removed.exercises[0].sets = []
        try draft.receive(removed, revision: 6)
        XCTAssertThrowsError(try draft.resolveRemote(keepEdits: true)); XCTAssertEqual(draft.entry(1)?.reps, "9")
        try draft.resolveRemote(keepEdits: false); XCTAssertFalse(draft.hasChanges)
    }
    func testQueuedFinishEligibilityAndIncompleteRowsNeverBecomeStuckOrSendInvalidActuals() throws {
        for status in ["planned", "completed"] {
            var original = session(status: status)
            if status == "planned" {
                // Preserve the rest of the DTO while making the date absent.
                let bytes = try JSONEncoder().encode(original)
                var value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); value["scheduledDate"] = ""
                original = try JSONDecoder().decode(WorkoutTrackerDashboard.Session.self, from: JSONSerialization.data(withJSONObject: value))
            }
            var draft = initial(original)
            var entry = try XCTUnwrap(draft.entry(1)); entry.reps = "8"; entry.completed = true; try draft.edit(entry)
            try draft.freeze(finishing: false)
            XCTAssertThrowsError(try draft.freeze(finishing: true)); XCTAssertFalse(draft.finishQueued)
        }
        var unchecked = initial()
        var edit = try XCTUnwrap(unchecked.entry(1)); edit.load = "135"; try unchecked.edit(edit)
        XCTAssertThrowsError(try unchecked.freeze(finishing: false))
        XCTAssertNil(unchecked.pending); XCTAssertEqual(unchecked.entry(1)?.load, "135")
    }
    func testUncheckAcknowledgementClearsImpliedActualsEvenIfRefreshIsOffline() throws {
        var draft = initial(session(load: 135, reps: 8))
        var edit = try XCTUnwrap(draft.entry(1)); edit.completed = false; edit.load = "140"; try draft.edit(edit)
        try draft.freeze(finishing: false)
        let pending = try XCTUnwrap(draft.pending)
        guard case .array(let rows) = pending.command["sets"], case .object(let fields) = rows[0] else { return XCTFail("Missing set") }
        XCTAssertEqual(fields["completed"], .bool(false)); XCTAssertEqual(fields["actualLoad"], .null)
        try draft.accept(pending, revision: 5)
        XCTAssertNil(draft.row(1)?.actualLoad); XCTAssertNil(draft.row(1)?.actualReps); XCTAssertNil(draft.row(1)?.rir)
        XCTAssertEqual(draft.row(1)?.completed, false); XCTAssertFalse(draft.hasChanges)
    }
    func testUnreadableDraftCannotBeReplacedByRetryOrEditing() throws {
        let path = file("draft.json"), original = Data("owner input that cannot be decoded".utf8)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: path)
        let frontend = WorkoutFrontendClient(store: .init(url: file("commands.json")), readCredential: { self.config }, saveCredential: { _ in })
        let controller = WorkoutSessionDraftController(initial: initial(), store: .init(url: path), frontend: frontend)
        XCTAssertTrue(controller.storageUnavailable); XCTAssertFalse(controller.canRetryLocalStorage)
        controller.retryLocalStorage()
        var edit = try XCTUnwrap(controller.state.entry(1)); edit.reps = "8"; controller.edit(edit)
        XCTAssertEqual(try Data(contentsOf: path), original); XCTAssertFalse(controller.canEdit)
    }
    func testRealisticNinetySixSetDraftHasZeroNetworkEditsAndKeepsCapturedLocale() async throws {
        var network = 0
        let frontend = WorkoutFrontendClient(store: .init(url: file("commands.json")), send: { _, _, _ in network += 1; return try self.capabilities() }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(frontend); network = 0
        var large = session()
        large.exercises = (1...12).map { exercise in
            let sets = (1...8).map { WorkoutTrackerDashboard.SetLog(id: exercise * 100 + $0, setNumber: $0, setType: "work", plannedLoad: 135, plannedReps: 8, actualLoad: nil, actualReps: nil, rir: nil, completed: false) }
            return .init(id: exercise, exerciseKey: "exercise-\(exercise)", name: "Exercise \(exercise)", orderIndex: exercise,
                loadMode: "barbell", progressionType: "double", plannedSets: 8, plannedReps: 8, plannedLoad: 135, targetRir: 2,
                notes: "", slotKey: "slot-\(exercise)", movementPattern: "push", originalExerciseKey: "", originalExerciseName: "", isPriming: false, sets: sets)
        }
        let draft = WorkoutSessionDraft(origin: config.origin, installationId: config.installationId, baseline: large, revision: 4,
            massScale: 2.2046226218, localeIdentifier: "de_DE")
        let path = file("large.json")
        let controller = WorkoutSessionDraftController(initial: draft, store: .init(url: path), frontend: frontend)
        var durations: [Double] = []
        for row in large.exercises.flatMap(\.sets) {
            var entry = try XCTUnwrap(controller.state.entry(row.id)); entry.load = "62,5"; entry.reps = "8"; entry.completed = true
            let start = Date(); controller.edit(entry); durations.append(Date().timeIntervalSince(start))
        }
        XCTAssertEqual(network, 0); XCTAssertFalse(controller.storageUnavailable)
        let command = try controller.state.command(finishing: false)
        guard case .array(let rows) = command["sets"], case .object(let first) = rows[0], case .number(let load) = first["actualLoad"] else { return XCTFail("Missing batch") }
        XCTAssertEqual(rows.count, 96); XCTAssertEqual(load, 137.7889138625, accuracy: 0.000001)
        let sorted = durations.sorted()
        print("96-set draft checkpoint: p95=\(Int(sorted[91] * 1000))ms, max=\(Int(sorted.last! * 1000))ms; file=\(try Data(contentsOf: path).count)bytes; requests=\(network)")
    }

    func testRevertingToPreSaveValuesWhileSendingRemainsAnUnsentUndoAcrossRelaunch() throws {
        for numbers in [true, false] {
            var draft = initial(numbers ? session(load: 135, reps: 8) : session())
            var edited = try XCTUnwrap(draft.entry(1))
            if numbers { edited.load = "140" } else { edited.completed = true }
            try draft.edit(edited); try draft.freeze(finishing: false)
            let submitted = try XCTUnwrap(draft.pending)
            let undo = WorkoutInlineSetDraft(row: try XCTUnwrap(draft.row(1)), massScale: 1, locale: Locale(identifier: "en_US"))
            XCTAssertFalse(undo.isDirty)
            try draft.edit(undo)
            let store = WorkoutSessionDraftFileStore(url: file("undo.json")); try store.save(draft)
            var restored = try XCTUnwrap(store.load())
            try restored.accept(submitted, revision: 5)
            XCTAssertTrue(restored.hasChanges)
            let command = try restored.command(finishing: false)
            guard case .array(let rows) = command["sets"], case .object(let row) = rows[0] else { return XCTFail("Undo missing") }
            if numbers { XCTAssertEqual(row["actualLoad"], .number(135)); XCTAssertEqual(restored.entry(1)?.load, "135") }
            else { XCTAssertEqual(row["completed"], .bool(false)); XCTAssertEqual(restored.entry(1)?.completed, false) }
        }
    }

    func testForegroundRecoveryFindsOnlyExplicitlySavedWorkoutsWithoutOpeningTheirScreen() async throws {
        var posts = 0
        let frontend = WorkoutFrontendClient(store: .init(url: file("commands.json")), send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            XCTAssertEqual(endpoint, .frontendCommand); posts += 1
            return try self.receipt(try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(body)))
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(frontend)
        let directory = file("drafts")
        var saved = initial(); var edit = try XCTUnwrap(saved.entry(1)); edit.reps = "8"; edit.completed = true; try saved.edit(edit)
        let unsaved = saved
        try saved.freeze(finishing: false)
        let pendingID = try XCTUnwrap(saved.pending?.id)
        let savedStore = WorkoutSessionDraftFileStore(url: directory.appendingPathComponent("saved.json")); try savedStore.save(saved)
        let unsavedStore = WorkoutSessionDraftFileStore(url: directory.appendingPathComponent("unsaved.json")); try unsavedStore.save(unsaved)
        let original = try Data(contentsOf: unsavedStore.url)
        await WorkoutSessionDraftController.resumePendingWorkouts(frontend: frontend, directory: directory, read: { draft in
            .init(session: draft.baseline, revision: draft.revision)
        })
        let after = try XCTUnwrap(savedStore.load())
        XCTAssertEqual(posts, 1); XCTAssertNil(after.pending); XCTAssertFalse(after.hasChanges)
        XCTAssertEqual(after.row(1)?.actualReps, 8)
        XCTAssertEqual(frontend.state.operations.first?.id, pendingID)
        XCTAssertEqual(try Data(contentsOf: unsavedStore.url), original)
    }
    func testAcknowledgementCannotClaimNewerEditsWereSyncedWhenRefreshFails() async throws {
        var release: CheckedContinuation<Void, Never>?
        let frontend = WorkoutFrontendClient(store: .init(url: file("commands.json")), send: { endpoint, body, _ in
            if endpoint == .frontendCapabilities { return try self.capabilities() }
            let intent = try JSONDecoder().decode(WorkoutFrontendIntent.self, from: XCTUnwrap(body))
            await withCheckedContinuation { release = $0 }
            return try self.receipt(intent)
        }, readCredential: { self.config }, saveCredential: { _ in })
        try await enable(frontend)
        let controller = WorkoutSessionDraftController(initial: initial(), store: .init(url: file("draft.json")), frontend: frontend)
        var edit = try XCTUnwrap(controller.state.entry(1)); edit.reps = "8"; edit.completed = true; controller.edit(edit)
        try controller.requestSave(finishing: false, refresh: { throw URLError(.notConnectedToInternet) })
        for _ in 0..<500 { if release != nil { break }; await Task.yield() }
        edit.reps = "9"; controller.edit(edit); release?.resume(); await controller.waitForDelivery()
        XCTAssertEqual(controller.state.row(1)?.actualReps, 8); XCTAssertEqual(controller.state.entry(1)?.reps, "9")
        XCTAssertTrue(controller.state.hasChanges)
        XCTAssertTrue(controller.message?.contains("newer edits") == true)
    }

}
