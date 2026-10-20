#if os(iOS) && DEBUG
import Foundation

/// Opt-in local diagnosis: identities, dates and counts only; no measurements or credentials.
@MainActor
enum LifeSyncReadinessProof {
    static func runIfRequested(model: AppModel) async {
        guard ProcessInfo.processInfo.arguments.contains("--life-sync-readiness") else { return }
        let client = SleepWebhookClient.shared
        let checkpoint = client.checkpoint, delivery = checkpoint.delivery
        var result: [String: Any] = ["schemaVersion": 1, "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "sleepEnabled": checkpoint.enabled, "proteinEnabled": checkpoint.proteinEnabled == true,
            "credentialsAvailable": client.hasCredentials, "proteinCredentialsAvailable": client.hasProteinCredentials,
            "storageUnavailable": client.storageUnavailable, "sending": client.isSending,
            "analysisComputing": model.intelligence.computing, "rescoreOwed": RescoreBackgroundScheduler.isRescoreOwed,
            "owedAfterCompletedPass": RescoreBackgroundScheduler.isOwedAfterCompletedPass,
            "revision": delivery.revision, "sleepPending": delivery.pending != nil, "proteinPending": delivery.proteinPending != nil,
            "sleepFailures": checkpoint.failures, "proteinFailures": checkpoint.proteinFailures ?? 0,
            "sleepMessage": checkpoint.message, "proteinMessage": checkpoint.proteinMessage ?? "Not enabled",
            "writesAttempted": false]
        if let value = delivery.pending?.event { result["sleepPendingEventId"] = value.eventId; result["sleepPendingWakeDate"] = value.wakeDate; result["sleepPendingRevision"] = value.revision }
        if let value = delivery.proteinPending?.event { result["proteinPendingEventId"] = value.eventId; result["proteinPendingDay"] = value.day; result["proteinPendingRevision"] = value.revision }
        if let value = delivery.lastAcceptedEvent { result["sleepAcceptedEventId"] = value.eventId; result["sleepAcceptedWakeDate"] = value.wakeDate; result["sleepAcceptedRevision"] = value.revision }
        if let value = delivery.lastAcceptedProtein { result["proteinAcceptedEventId"] = value.eventId; result["proteinAcceptedDay"] = value.day; result["proteinAcceptedRevision"] = value.revision }
        if let value = delivery.lastOutcome { result["sleepOutcome"] = value }
        if let value = delivery.proteinOutcome { result["proteinOutcome"] = value }
        do {
            let now = Date(), days = SleepWebhookPolicy.completedDays(now: now)
            let entries = try ProteinWebhookProjection.savedEntries()
            let candidates = try ProteinWebhookProjection.summaries(entries: entries, acknowledged: delivery.proteinAcknowledged ?? [:], from: days.from, to: days.through)
            result["proteinSavedDays"] = Array(Set(entries.map(\.day))).sorted()
            result["proteinCandidateDays"] = candidates.filter { $0.day <= days.through && delivery.proteinAcknowledged?[$0.day] != $0 }.map(\.day)
            if let store = await model.repo.storeHandle() {
                let sleepDays = SleepWebhookPolicy.sleepWakeDays(now: now)
                let ids = await model.repo.sleepComparisonSourceIds().filter { !$0.hasSuffix("-noop") }
                let rows = try await store.verifiedWhoopSleepTotals(rawSourceIds: ids, from: sleepDays.from, to: sleepDays.through)
                result["verifiedSleepDays"] = rows.map { ["day": $0.day, "estimated": $0.estimated] as [String: Any] }
                result["sleepCandidateDays"] = rows.filter {
                    delivery.acknowledged[$0.day] != SleepWebhookSummary(wakeDate: $0.day, sleepMinutes: $0.minutes, method: $0.estimated ? "dhoop_estimate" : "whoop_import", timeZone: "America/Los_Angeles")
                }.map(\.day)
            }
        } catch { result["readErrorType"] = String(describing: type(of: error)) }
        result["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        result["analysisComputingAfterRead"] = model.intelligence.computing
        result["rescoreOwedAfterRead"] = RescoreBackgroundScheduler.isRescoreOwed
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("life-sync-readiness-proof.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
#endif
