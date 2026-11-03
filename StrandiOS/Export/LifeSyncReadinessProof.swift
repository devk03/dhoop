#if os(iOS)
import Foundation

/// Explicit local support capture: dates/counts only, no measurements or credentials.
/// An optional manual sync uses the existing guarded user action; default capture is read-only.
@MainActor
enum LifeSyncReadinessProof {
    static func runIfRequested(model: AppModel) async {
        if ProcessInfo.processInfo.arguments.contains("--whoop-receipt-check") {
            await checkWhoopReceipt(model: model)
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("--life-sync-readiness") else { return }
        let arguments = ProcessInfo.processInfo.arguments
        let runPrefix = "--life-sync-readiness-run="
        let runId = arguments.first(where: { $0.hasPrefix(runPrefix) }).flatMap { UUID(uuidString: String($0.dropFirst(runPrefix.count))) }?.uuidString ?? "manual"
        let requestSync = arguments.contains("--life-sync-request-strap-sync")
        await capture(model: model, runId: runId, phase: "before", requestSync: requestSync)
        if requestSync {
            if !model.live.connected || !model.live.bonded { model.ble.armPendingManualSync() }
            model.ble.syncNow()
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            await capture(model: model, runId: runId, phase: "after", requestSync: true)
        }
    }
    /// Explicit support run using the existing live-HR request, with bounded waiting and
    /// private count/timestamp captures. Does not alter collection preferences or wake alarms.
    private static func checkWhoopReceipt(model: AppModel) async {
        let prefix = "--whoop-receipt-run="
        guard let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
              let run = UUID(uuidString: String(value.dropFirst(prefix.count))) else { return }
        ScreenIdle.hold(.supportCapture, true)
        defer { ScreenIdle.hold(.supportCapture, false) }
        let collection = WhoopCollectionModel()
        func capture(_ phase: String) async {
            await model.ble.flushStandardHRForLifecycle(reason: .explicit)
            await model.ble.flushPuffinCaptures()
            await collection.refresh(repo: model.repo, live: model.live)
            guard let data = try? JSONEncoder().encode(collection.proof(live: model.live, now: Date())) else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("whoop-receipt-" + run.uuidString + "-" + phase + ".json")
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        for _ in 0..<20 {
            if model.live.connected && model.live.historyReady { break }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        }
        await capture("before")
        guard model.live.connected, model.live.activeIsWhoop else { return }
        if ProcessInfo.processInfo.arguments.contains("--whoop-status-only") {
            model.ble.probeBodyLocationAndStatus()
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            await capture("statusAfter")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--whoop-collection-settings") {
            model.ble.probeDeviceConfigValues(collectionSettings: true)
            // The fixed read plan has ten steps with an eight-second per-step timeout.
            for _ in 0..<90 {
                if let report = model.live.deviceConfigProbe,
                   report != BLEManager.deviceConfigProbeWaiting {
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("whoop-settings-" + run.uuidString + ".txt")
                    try? Data(report.utf8).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    break
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
        do {
            model.startRealtimeHR()
            defer { model.stopRealtimeHR() }
            let started = Date()
            for (phase, offset) in [("midpoint", 30.0), ("after", 60.0)] {
                let remaining = max(0, started.addingTimeInterval(offset).timeIntervalSinceNow)
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
                await capture(phase)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--whoop-collection-settings") {
            if ProcessInfo.processInfo.arguments.contains("--whoop-raw-receipt-check"),
               !UserDefaults.standard.bool(forKey: "enableRawCapture") {
                model.ble.captureRawAccel(seconds: 10)
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                await capture("rawAfter")
            }
            model.ble.probeBodyLocationAndStatus()
            model.ble.send(.getDataRange, payload: [0x00])
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            // Explicit manual retry after live HR has been released, bypassing only the normal sync cooldown.
            model.ble.syncNow()
            do { try await Task.sleep(nanoseconds: 65_000_000_000) } catch { return }
            await capture("historyAfter")
        }
    }

    private static func capture(model: AppModel, runId: String, phase: String, requestSync: Bool) async {
        let client = SleepWebhookClient.shared
        let sourceId = model.repo.deviceId
        let checkpoint = client.checkpoint, delivery = checkpoint.delivery
        var result: [String: Any] = ["schemaVersion": 2, "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "runId": runId, "phase": phase, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "deviceTimeZone": TimeZone.current.identifier, "strapSyncRequested": requestSync,
            "connected": model.live.connected, "bonded": model.live.bonded, "encryptedBond": model.live.encryptedBond,
            "historyReady": model.live.historyIsReady(for: sourceId), "backfilling": model.live.backfilling,
            "historyPendingSync": model.live.historyPendingSync, "hasSyncError": model.live.lastSyncError != nil,
            "sleepEnabled": checkpoint.enabled, "proteinEnabled": checkpoint.proteinEnabled == true,
            "credentialsAvailable": client.hasCredentials, "proteinCredentialsAvailable": client.hasProteinCredentials,
            "storageUnavailable": client.storageUnavailable, "sending": client.isSending,
            "analysisComputing": model.intelligence.computing, "rescoreOwed": RescoreBackgroundScheduler.isRescoreOwed,
            "owedAfterCompletedPass": RescoreBackgroundScheduler.isOwedAfterCompletedPass,
            "revision": delivery.revision, "sleepPending": delivery.pending != nil, "proteinPending": delivery.proteinPending != nil,
            "sleepFailures": checkpoint.failures, "proteinFailures": checkpoint.proteinFailures ?? 0,
            "sleepMessage": checkpoint.message, "proteinMessage": checkpoint.proteinMessage ?? "Not enabled",
            "lifeSummaryDeliveryInvoked": false]
        if let synced = model.live.successfulSyncAt(for: sourceId) { result["lastSuccessfulStrapSyncAt"] = synced }
        if let error = model.live.lastSyncError { result["syncError"] = error }
        if let value = delivery.pending?.event { result["sleepPendingEventId"] = value.eventId; result["sleepPendingWakeDate"] = value.wakeDate; result["sleepPendingRevision"] = value.revision }
        if let value = delivery.proteinPending?.event { result["proteinPendingEventId"] = value.eventId; result["proteinPendingDay"] = value.day; result["proteinPendingRevision"] = value.revision }
        if let value = delivery.lastAcceptedEvent { result["sleepAcceptedEventId"] = value.eventId; result["sleepAcceptedWakeDate"] = value.wakeDate; result["sleepAcceptedRevision"] = value.revision }
        if let value = delivery.lastAcceptedProtein { result["proteinAcceptedEventId"] = value.eventId; result["proteinAcceptedDay"] = value.day; result["proteinAcceptedRevision"] = value.revision }
        if let value = delivery.lastOutcome { result["sleepOutcome"] = value }
        if let value = delivery.proteinOutcome { result["proteinOutcome"] = value }
        do {
            let now = Date(), days = SleepWebhookPolicy.completedDays(now: now)
            result["completedProteinThroughDay"] = days.through
            result["sleepWakeThroughDay"] = SleepWebhookPolicy.sleepWakeDays(now: now).through
            let entries = try ProteinWebhookProjection.savedEntries(includeCalories: checkpoint.caloriesEnabled == true)
            let candidates = try ProteinWebhookProjection.summaries(entries: entries, acknowledged: delivery.proteinAcknowledged ?? [:], from: days.from, to: days.through, includeCalories: checkpoint.caloriesEnabled == true)
            result["proteinSavedDays"] = Array(Set(entries.map(\.day))).sorted()
            result["proteinCandidateDays"] = candidates.filter { $0.day <= days.through && delivery.proteinAcknowledged?[$0.day] != $0 }.map(\.day)
            if let store = await model.repo.storeHandle() {
                let sleepDays = SleepWebhookPolicy.sleepWakeDays(now: now)
                let ids = await model.repo.sleepComparisonSourceIds().filter { !$0.hasSuffix("-noop") }
                result["resolvedWhoopSourceCount"] = ids.count
                if let latest = try await store.latestHRSampleTs(deviceId: sourceId) { result["latestStoredActiveSourceHRorOpticalAt"] = latest }
                var latestAcrossSources: Int?
                for id in ids {
                    if let latest = try await store.latestHRSampleTs(deviceId: id) { latestAcrossSources = max(latestAcrossSources ?? latest, latest) }
                }
                if let latestAcrossSources { result["latestStoredWhoopHRorOpticalAt"] = latestAcrossSources }
                let stats = try await store.collectionSnapshot(deviceId: sourceId,
                    from: Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970), to: Int(now.timeIntervalSince1970))
                result["activeSourceStoredHRToday"] = stats.heartRate.count
                result["activeSourceUsableRRToday"] = stats.scorableRR.count
                let before = SleepExportReadiness(computing: model.intelligence.computing,
                    rescoreOwed: RescoreBackgroundScheduler.isRescoreOwed, generation: RescoreBackgroundScheduler.currentOwedToken,
                    completedPass: RescoreBackgroundScheduler.isOwedAfterCompletedPass)
                let rows = try await store.verifiedWhoopSleepTotals(rawSourceIds: ids, from: sleepDays.from, to: sleepDays.through)
                let after = SleepExportReadiness(computing: model.intelligence.computing,
                    rescoreOwed: RescoreBackgroundScheduler.isRescoreOwed, generation: RescoreBackgroundScheduler.currentOwedToken,
                    completedPass: RescoreBackgroundScheduler.isOwedAfterCompletedPass)
                result["sleepReadinessBlockedDays"] = rows.filter { !before.allows(estimated: $0.estimated, after: after) }.map(\.day)
                result["verifiedSleepDays"] = rows.map { ["day": $0.day, "estimated": $0.estimated] as [String: Any] }
                result["sleepCandidateDays"] = rows.filter { before.allows(estimated: $0.estimated, after: after) }.filter {
                    delivery.acknowledged[$0.day] != SleepWebhookSummary(wakeDate: $0.day, sleepMinutes: $0.minutes, method: $0.estimated ? "dhoop_estimate" : "whoop_import", timeZone: "America/Los_Angeles")
                }.map(\.day)
            }
        } catch { result["readErrorType"] = String(describing: type(of: error)) }
        result["activeSourceChangedDuringRead"] = sourceId != model.repo.deviceId
        result["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        result["analysisComputingAfterRead"] = model.intelligence.computing
        result["rescoreOwedAfterRead"] = RescoreBackgroundScheduler.isRescoreOwed
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            let folder = FileManager.default.temporaryDirectory
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            try? data.write(to: folder.appendingPathComponent("life-sync-readiness-proof.json"), options: options)
            try? data.write(to: folder.appendingPathComponent("life-sync-readiness-" + runId + "-" + phase + ".json"), options: options)
        }
    }
}
#endif
