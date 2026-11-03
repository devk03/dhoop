import Foundation

/// Explicit local read-only verification for developer-assisted installation; no credential export.
@MainActor
enum WorkoutHistoryReadProof {
    /// Three reads at most, with a run identity and timings but no workout values or credentials.
    private static func frontendReadProof() async {
        let prefix = "--workout-read-run="
        let run = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
            .flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }?.uuidString ?? "manual"
        var result: [String: Any] = ["runId": run, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "capturedAt": ISO8601DateFormatter().string(from: Date()), "proofWritesAttempted": false, "status": "not_verified"]
        var stage = "capabilities"
        func milliseconds(_ start: ContinuousClock.Instant) -> Double {
            let d = start.duration(to: .now).components
            return Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
        }
        do {
            let frontend = WorkoutFrontendClient.shared, tracker = WorkoutTrackerClient.shared
            var start = ContinuousClock.now
            try await frontend.checkCapabilities()
            result["capabilityReadMilliseconds"] = milliseconds(start)
            result["manualCommands"] = frontend.state.capabilities?.manualCommands == true
            result["sessionBatchSave"] = frontend.state.capabilities?.sessionBatchSave == true
            result["customExerciseSubstitution"] = frontend.state.capabilities?.customExerciseSubstitution == true
            result["frontendStart"] = frontend.state.capabilities?.frontendStart == true
            result["revision"] = frontend.state.capabilities?.lifeRevision
            stage = "strength"; start = .now
            let strength = try await tracker.readStrength()
            result["strengthReadMilliseconds"] = milliseconds(start)
            if let row = strength.nextUp {
                stage = "exact_session"; start = .now
                let page = try await tracker.readHistorySession(row)
                result["exactSessionReadMilliseconds"] = milliseconds(start)
                result["exactSessionVerified"] = page.dashboard.sessions.count == 1 && page.dashboard.sessions.first?.id == row.id
            } else { result["exactSessionVerified"] = false; result["noNextWorkout"] = true }
            result["status"] = "authenticated_reads_verified"
        } catch {
            result["stage"] = stage; result["errorType"] = String(describing: type(of: error))
            if case WorkoutSyncTransportError.http(let code) = error { result["httpStatus"] = code }
        }
        result["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("workout-frontend-read-" + run + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    static func runIfRequested() async {
        if ProcessInfo.processInfo.arguments.contains("--workout-frontend-read-proof") {
            await frontendReadProof(); return
        }
        guard ProcessInfo.processInfo.arguments.contains("--workout-history-proof") else { return }
        var result: [String: Any] = ["schemaVersion": 1, "status": "not_verified"]
        var stage = "history"
        do {
            let client = WorkoutTrackerClient.shared, filters = WorkoutHistoryFilters()
            let first = try await client.readHistory(filters: filters, cursor: nil)
            var chain = WorkoutHistoryPageChain()
            try chain.accept(first, requestedFilters: filters, cursor: nil)
            var pages = 1
            if let cursor = chain.nextCursor {
                let next = try await client.readHistory(filters: filters, cursor: cursor)
                try chain.accept(next, requestedFilters: filters, cursor: cursor); pages += 1
            }
            if let row = chain.sessions.first { _ = try await client.readHistorySession(row) }
            var filtered = filters; filtered.kind = "strength"
            let filteredPage = try await client.readHistory(filters: filtered, cursor: nil)
            guard filteredPage.filters == filtered else { throw WorkoutTrackerContractError.invalidSnapshot }
            stage = "strength"
            let strength = try await client.readStrength()
            try strength.validate()
            var previousSetVerified = false
            var previousSetAvailability = "not_checked"
            var previousSetReason: String?
            if let row = strength.nextUp {
                let detail = try await client.readHistorySession(row)
                if let session = detail.dashboard.sessions.first,
                   let exercise = session.exercises.first(where: { !$0.sets.isEmpty }),
                   let set = exercise.sets.first(where: { $0.setType == "work" }) ?? exercise.sets.first {
                    stage = "previous_set"
                    let previous = try await client.readPreviousSet(session: session, exercise: exercise, set: set, minimumRevision: detail.lifeRevision)
                    previousSetVerified = true; previousSetAvailability = previous.availability
                    previousSetReason = previous.unavailableReason
                }
            }
            stage = "capabilities"
            let frontend = WorkoutFrontendClient.shared
            try await frontend.checkCapabilities()
            guard frontend.state.capabilities?.sessionDateScheduling == true,
                  frontend.state.capabilities?.frontendStart == false else { throw WorkoutTrackerContractError.invalidSnapshot }
            result = ["schemaVersion": 1, "status": "authenticated_history_reads_verified",
                "pages": pages, "rows": chain.sessions.count, "revision": first.lifeRevision,
                "detailVerified": !chain.sessions.isEmpty, "filteredReadVerified": true, "filteredRows": filteredPage.sessions.count,
                "strengthReadVerified": true, "liftingProgramCount": strength.programs.count,
                "pendingLiftingWorkouts": strength.counts.pending, "schedulingEnabled": true,
                "manualCompletionEnabled": frontend.state.capabilities?.sessionCompletion == true,
                "previousSetReadVerified": previousSetVerified, "previousSetAvailability": previousSetAvailability,
                "lifecycleEnabled": false, "writesAttempted": false]
            if let previousSetReason { result["previousSetReason"] = previousSetReason }
        } catch {
            result["stage"] = stage
            if case WorkoutSyncTransportError.http(let code) = error { result["httpStatus"] = code }
            result["errorType"] = String(describing: type(of: error))
        }
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("workout-history-proof.json"), options: .atomic)
        }
    }
}
