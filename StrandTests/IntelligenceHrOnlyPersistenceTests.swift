import XCTest
import WhoopProtocol
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntelligenceHrOnlyPersistenceTests: XCTestCase {
    func testStandardHRNightWithoutHistoryReachesSavedSleepAndRepository() async throws {
        let defaults = UserDefaults.standard
        let keys = ["noop.analyzeWatermark", "analyzeRecent.stepsMotionCache.v1",
                    DayCycleMode.storageKey, UnitPrefs.hrvWindowKey, RescoreBackgroundScheduler.owedKey,
                    RescoreBackgroundScheduler.owedTokenKey,
                    RescoreBackgroundScheduler.lastPassSecondsKey,
                    RescoreBackgroundScheduler.owedAfterCompletedPassKey,
                    RescoreBackgroundScheduler.lastAttemptStartedAtKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(DayCycleMode.midnight.rawValue, forKey: DayCycleMode.storageKey)
        defaults.set(HrvWindow.whole.rawValue, forKey: UnitPrefs.hrvWindowKey)
        let store = try await WhoopStore.inMemory()
        try DeviceRegistryStore(dbQueue: store.registryWriter).setModel("my-whoop", model: "WHOOP 5.0")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "my-whoop")
        let wake = Calendar.current.date(byAdding: .day, value: -1,
                                        to: Calendar.current.startOfDay(for: Date()))!
        let day = Repository.localDayKey(wake)
        let start = Int(wake.timeIntervalSince1970) - 16 * 3_600
        let hr = (0..<(24 * 3_600)).map { second -> HRSample in
            let asleep = second >= 16 * 3_600
            let phase = asleep ? second - 16 * 3_600 : second
            let bpm = asleep ? 54 + Int(sin(Double(phase) / 900) * 2)
                             : 80 + Int(sin(Double(phase) / 500) * 8)
            return HRSample(ts: start + second, bpm: bpm)
        }
        // Beat timestamps must follow the intervals: emitting one 1,111 ms beat every second
        // would over-count elapsed time and correctly fail the production HRV integrity gate.
        var rr: [RRInterval] = []
        var elapsedMs = 0
        while elapsedMs < hr.count * 1_000 {
            let bpm = hr[elapsedMs / 1_000].bpm
            let interval = 60_000 / bpm + (rr.count.isMultiple(of: 2) ? -30 : 30)
            elapsedMs += interval
            if elapsedMs >= hr.count * 1_000 { break }
            rr.append(RRInterval(ts: start + elapsedMs / 1_000, rrMs: interval,
                                 srcChannel: .whoop5Standard))
        }
        // Standard BLE can deliver HR/R-R while WHOOP history delivers no motion or band sleep state.
        _ = try await store.insert(Streams(hr: hr, rr: rr), deviceId: "my-whoop")
        await engine.analyzeRecent(maxDays: 3, force: true)

        let daily = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: day, to: day)
        let night = try XCTUnwrap(daily.first)
        XCTAssertGreaterThan(night.totalSleepMin ?? 0, 120)
        XCTAssertEqual(night.sleepHrOnly, true, "The fallback must retain its estimate label")
        XCTAssertNotNil(night.restingHr)
        XCTAssertNotNil(night.avgHrv)
        let sessions = try await store.sleepSessions(deviceId: "my-whoop-noop", from: start,
                                                     to: start + 24 * 3_600, limit: 100)
        XCTAssertFalse(sessions.isEmpty, "A scored night must persist beyond the running engine")
        let shown = await repo.allSleepSessions(days: 3)
        XCTAssertFalse(shown.isEmpty, "The sleep screen's repository must expose the persisted night")
    }
}
