import XCTest
import Foundation
import GRDB
import WhoopProtocol
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntelligencePersistenceRetryTests: XCTestCase {
    func testComputedScoreFailurePreservesRowsAndRetries() async throws {
        try await verifyRetry(rejecting: "INSERT ON dailyMetric", operation: "computed scores")
    }

    func testSleepSessionFailurePreservesRowsAndRetries() async throws {
        try await verifyRetry(rejecting: "INSERT ON sleepSession", operation: "sleep sessions")
    }

    func testMotionFailureLeavesRescoreOwedAndRetries() async throws {
        try await verifyRetry(rejecting: "UPDATE OF motionJSON ON sleepSession", operation: "sleep sessions")
    }

    func testBandStateFailureLeavesRescoreOwedAndRetries() async throws {
        try await verifyRetry(rejecting: "UPDATE OF sleepStateJSON ON sleepSession", operation: "sleep sessions")
    }

    private func verifyRetry(rejecting statement: String, operation: String) async throws {
        let defaults = UserDefaults.standard
        let keys = [
            "profile.dateOfBirth", "profile.age", "profile.sex", "profile.weightKg",
            "profile.heightCm", "profile.waistCm", "profile.hrMaxOverride", "profile.stepTicksPerStep",
            "profile.stepsCalibrationCoefficient", "profile.stepsCalibrationSampleDays",
            "profile.stepsCalibrationConfidence", "profile.stepsCalibrationManual",
            "profile.stepsManualCoefficient", "profile.stepsHasBankedMotion",
            "noop.analyzeWatermark", "analyzeRecent.stepsMotionCache.v1",
            "noop.hrvBaselineEpoch", "noop.recoveryBaselineEpoch", UnitPrefs.hrvWindowKey,
            RescoreBackgroundScheduler.owedKey, RescoreBackgroundScheduler.owedTokenKey,
            RescoreBackgroundScheduler.lastPassSecondsKey,
            RescoreBackgroundScheduler.owedAfterCompletedPassKey,
            RescoreBackgroundScheduler.lastAttemptStartedAtKey,
            DayCycleMode.storageKey, PuffinExperiment.experimentalSleepV2Key,
            PuffinExperiment.motionAwareWakeKey,
        ]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set(DayCycleMode.midnight.rawValue, forKey: DayCycleMode.storageKey)
        defaults.set(true, forKey: PuffinExperiment.experimentalSleepV2Key)
        defaults.set(false, forKey: PuffinExperiment.motionAwareWakeKey)
        defaults.set("previous-completed-pass", forKey: "noop.analyzeWatermark")
        defaults.set(42.0, forKey: RescoreBackgroundScheduler.lastPassSecondsKey)

        let store = try await WhoopStore.inMemory()
        let device = "my-whoop"
        let computed = device + "-noop"
        let midnight = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let wakeDay = midnight - 86_400
        let start = wakeDay - 16 * 3_600
        let hr = (0..<(24 * 3_600)).map { i in
            let asleep = i >= 16 * 3_600
            let phase = asleep ? i - 16 * 3_600 : i
            let bpm = asleep ? 64 + Int(sin(Double(phase) / 900) * 5)
                             : 74 + Int(sin(Double(phase) / 500) * 11)
            return HRSample(ts: start + i, bpm: bpm)
        }
        let gravity = (0..<(8 * 3_600)).map { GravitySample(ts: wakeDay + $0, x: 0, y: 0, z: 1) }
        let band = stride(from: wakeDay, to: wakeDay + 8 * 3_600, by: 30).map {
            SleepStateSample(ts: $0, state: 1)
        }
        _ = try await store.insert(Streams(hr: hr, gravity: gravity, sleepState: band), deviceId: device)
        let originalFingerprint = try await store.analysisFingerprint()
        let staleDay = Repository.localDayKey(Date(timeIntervalSince1970: Double(midnight - 3 * 86_400)))
        let stale = DailyMetric(day: staleDay, totalSleepMin: 123, efficiency: 0.8,
            deepMin: 30, remMin: 30, lightMin: 63, disturbances: 1, restingHr: 70,
            avgHrv: 25, recovery: 40, strain: 20, exerciseCount: 0)
        _ = try await store.upsertDailyMetrics([stale], deviceId: computed)
        let originalSleep = CachedSleepSession(startTs: midnight - 3 * 86_400,
            endTs: midnight - 3 * 86_400 + 3_600, efficiency: 0.8, restingHr: 70,
            avgHrv: 25, stagesJSON: nil, userEdited: true, deviceId: computed)
        _ = try await store.upsertSleepSessions([originalSleep], deviceId: computed)

        // Reject a real SQLite write. Toggling a fixture flag restores storage without changing
        // raw inputs, so the second invocation must retry rather than pass the unchanged-input gate.
        try await store.registryWriter.write { db in
            try db.execute(sql: "CREATE TABLE retryFailure(enabled INTEGER NOT NULL)")
            try db.execute(sql: "INSERT INTO retryFailure VALUES (1)")
            try db.execute(sql: """
                CREATE TRIGGER rejectRescore BEFORE \(statement)
                WHEN (SELECT enabled FROM retryFailure) = 1
                BEGIN SELECT RAISE(ABORT, 'fixture persistence failure'); END
                """)
        }
        let repo = Repository(deviceId: device)
        repo.setStoreForTesting(store)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: device)
        var diagnostics: [String] = []
        engine.diagnosticSink = { line, _ in diagnostics.append(line) }

        await engine.analyzeRecent(maxDays: 4, force: true)

        XCTAssertFalse(engine.computing)
        XCTAssertNotNil(engine.note)
        XCTAssertTrue(engine.results.isEmpty, "failed persistence must not publish a completed result")
        XCTAssertEqual(defaults.string(forKey: "noop.analyzeWatermark"), "previous-completed-pass")
        XCTAssertTrue(RescoreBackgroundScheduler.isRescoreOwed)
        XCTAssertEqual(RescoreBackgroundScheduler.lastCompletedPassSeconds, 42)
        XCTAssertTrue(diagnostics.contains { $0.contains("persistence failed operation=\(operation)") },
                      "the injected required write must have been reached: \(diagnostics)")
        XCTAssertFalse(diagnostics.contains { $0.contains("re-score: done") })
        let failedDaily = try await store.dailyMetrics(deviceId: computed, from: staleDay, to: staleDay)
        XCTAssertEqual(failedDaily, [stale], "no stale reconciliation may follow a required write failure")
        let failedSleep = try await store.sleepSessions(deviceId: computed,
            from: originalSleep.startTs, to: originalSleep.endTs, limit: 10)
        XCTAssertEqual(failedSleep, [originalSleep])
        let rawAfterFailure = try await store.hrSamples(deviceId: device, from: start,
            to: start + 24 * 3_600, limit: 100_000)
        XCTAssertEqual(rawAfterFailure, hr)

        try await store.registryWriter.write { db in
            try db.execute(sql: "UPDATE retryFailure SET enabled = 0")
        }
        diagnostics.removeAll()
        await engine.analyzeRecent(maxDays: 4, force: false)

        XCTAssertFalse(engine.computing)
        XCTAssertNil(engine.note)
        XCTAssertFalse(engine.results.isEmpty)
        XCTAssertFalse(RescoreBackgroundScheduler.isRescoreOwed)
        XCTAssertEqual(defaults.string(forKey: "noop.analyzeWatermark"), originalFingerprint)
        XCTAssertTrue(diagnostics.contains { $0.contains("re-score: done") })
        let sleeps = try await store.sleepSessions(deviceId: computed, from: wakeDay,
            to: midnight, limit: 100)
        XCTAssertFalse(sleeps.isEmpty, "the retry must bank the detected night")
        let finalFingerprint = try await store.analysisFingerprint()
        XCTAssertEqual(finalFingerprint, originalFingerprint, "rescoring must not change raw streams")
    }
}
