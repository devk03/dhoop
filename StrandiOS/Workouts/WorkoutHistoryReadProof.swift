import Foundation

/// Explicit local read-only verification for developer-assisted installation; no credential export.
@MainActor
enum WorkoutHistoryReadProof {
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--workout-history-proof") else { return }
        var result: [String: Any] = ["schemaVersion": 1, "status": "not_verified"]
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
            let strength = try await client.readStrength()
            try strength.validate()
            if let row = strength.nextUp { _ = try await client.readHistorySession(row) }
            result = ["schemaVersion": 1, "status": "authenticated_history_reads_verified",
                "pages": pages, "rows": chain.sessions.count, "revision": first.lifeRevision,
                "detailVerified": !chain.sessions.isEmpty, "filteredReadVerified": true, "filteredRows": filteredPage.sessions.count,
                "strengthReadVerified": true, "liftingProgramCount": strength.programs.count,
                "pendingLiftingWorkouts": strength.counts.pending, "writesAttempted": false]
        } catch {
            if case WorkoutSyncTransportError.http(let code) = error { result["httpStatus"] = code }
            result["errorType"] = String(describing: type(of: error))
        }
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("workout-history-proof.json"), options: .atomic)
        }
    }
}
