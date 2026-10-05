import XCTest

final class RunningZoneSessionTests: XCTestCase {
    private let target = RunningZoneTarget(name: "Zone 2", lowerBPM: 120, upperBPM: 141, method: "Manual fixture")
    private func makeSession(goal: TimeInterval = 60) -> RunningZoneSession {
        RunningZoneSession(deviceId: "strap-a", target: target, goalSeconds: goal,
                           startedAt: Date(timeIntervalSince1970: 100))!
    }
    @discardableResult private func sample(_ run: inout RunningZoneSession, _ time: TimeInterval, _ bpm: Int,
                                           now: TimeInterval? = nil, device: String = "strap-a", connected: Bool = true,
                                           enabled: Bool = true, bonded: Bool = true) -> RunningZoneSession.Observation {
        run.observe(RunningHeartRateSample(deviceId: device, bpm: bpm, receivedAt: time), now: now ?? time,
                    connected: connected, alertsEnabled: enabled, mayBuzz: bonded)
    }

    func testGoalCountsOnlyIntervalsWhoseTwoFreshEndpointsAreInZone() {
        var session = makeSession()
        sample(&session, 100, 110) // Warm-up is not goal time.
        sample(&session, 101, 130) // Crossing into the zone is not inferred.
        sample(&session, 102, 130)
        sample(&session, 103, 130)
        sample(&session, 104, 150) // Crossing out is not inferred.
        sample(&session, 105, 150)
        XCTAssertEqual(session.inZoneSeconds, 2)
        XCTAssertEqual(session.observedSeconds, 5)
        // Five observed interval means: 120, 130, 130, 140, 150 bpm.
        XCTAssertEqual(session.averageBPM!, 134, accuracy: 0.0001)
    }

    func testRepeatedBPMIsCountedButDuplicateTimestampsCannotCreateTime() {
        var session = makeSession()
        sample(&session, 100, 130)
        sample(&session, 101, 130)
        sample(&session, 101, 130)
        sample(&session, 102, 130)
        XCTAssertEqual(session.inZoneSeconds, 2)
        XCTAssertEqual(session.readableSamples, 3)
    }

    func testMissingIntervalsStalePacketsAndOtherSourcesNeverBridgeTheGoal() {
        var session = makeSession()
        sample(&session, 100, 130)
        sample(&session, 101, 130)
        sample(&session, 120, 130) // Gap has no synthetic hold time.
        sample(&session, 121, 130)
        XCTAssertEqual(session.inZoneSeconds, 2)
        XCTAssertFalse(sample(&session, 122, 130, now: 125).accepted)
        XCTAssertFalse(sample(&session, 126, 130, device: "strap-b").accepted)
        sample(&session, 127, 130)
        sample(&session, 128, 130)
        XCTAssertEqual(session.inZoneSeconds, 3)
        XCTAssertEqual(session.observedSeconds, 3)
    }

    func testPreStartFutureDisconnectedAndInvalidReadingsAreNotEvidence() {
        var session = makeSession()
        for (time, bpm, now, connected) in [(99.0, 130, 100.0, true), (101, 130, 100, true),
                                          (102, 130, 102, false), (103, 0, 103, true), (104, 221, 104, true)] {
            let result = sample(&session, time, bpm, now: now, connected: connected)
            XCTAssertFalse(result.accepted); XCTAssertNil(result.alert)
        }
        XCTAssertEqual(session.readableSamples, 0)
        XCTAssertEqual(session.inZoneSeconds, 0)
    }

    func testMaximumOnlyUsesFreshSameDeviceReadings() {
        var session = makeSession()
        sample(&session, 100, 130); sample(&session, 101, 150)
        sample(&session, 102, 210, now: 110)
        sample(&session, 111, 200, device: "strap-b")
        XCTAssertEqual(session.maximumBPM, 150)
    }

    func testPauseAndResumePreserveProgressWithoutCreditingThePause() {
        var session = makeSession()
        sample(&session, 100, 130); sample(&session, 101, 130)
        session.pause()
        XCTAssertFalse(sample(&session, 102, 130).accepted)
        session.resume()
        sample(&session, 110, 130); sample(&session, 111, 130)
        XCTAssertEqual(session.inZoneSeconds, 2)
        XCTAssertEqual(session.observedSeconds, 2)
    }

    func testGoalCompletionCapsProgressAndRejectsFurtherObservations() {
        var session = makeSession(goal: 2.5)
        for t in 100...103 { sample(&session, Double(t), 130) }
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.inZoneSeconds, 2.5)
        XCTAssertEqual(session.remainingSeconds, 0)
        XCTAssertFalse(sample(&session, 104, 130).accepted)
        session.resume()
        XCTAssertEqual(session.phase, .completed)
    }

    func testZoneExitRequiresEntryAndThreeContinuousSecondsOutside() {
        var session = makeSession()
        for t in 100...105 { XCTAssertNil(sample(&session, Double(t), 110).alert) }
        sample(&session, 106, 130)
        XCTAssertNil(sample(&session, 107, 110).alert)
        XCTAssertNil(sample(&session, 108, 110).alert)
        XCTAssertNil(sample(&session, 109, 110).alert)
        XCTAssertEqual(sample(&session, 110, 110).alert, .below)
    }

    func testBuzzCooldownAppliesAcrossReentryAndDirectionChanges() {
        var session = makeSession()
        sample(&session, 100, 130)
        for t in 101...103 { XCTAssertNil(sample(&session, Double(t), 150).alert) }
        XCTAssertEqual(sample(&session, 104, 150).alert, .above)
        sample(&session, 105, 130)
        for t in 106...133 { XCTAssertNil(sample(&session, Double(t), 110).alert) }
        XCTAssertEqual(sample(&session, 134, 110).alert, .below)
        XCTAssertNil(sample(&session, 135, 110).alert)
    }

    func testNoBuzzFromGapsStaleReadingsOrDisabledHaptics() {
        var session = makeSession()
        sample(&session, 100, 130); sample(&session, 101, 110); sample(&session, 102, 110)
        XCTAssertNil(sample(&session, 105, 110).alert) // Restart the dwell after gap.
        XCTAssertNil(sample(&session, 106, 110).alert)
        XCTAssertNil(sample(&session, 107, 110).alert)
        XCTAssertNil(sample(&session, 108, 110, now: 111).alert) // Stale breaks dwell.
        for t in 112...116 { XCTAssertNil(sample(&session, Double(t), 110, enabled: false).alert) }
        XCTAssertNil(sample(&session, 117, 110, bonded: false).alert)
        XCTAssertEqual(sample(&session, 118, 110).alert, .below)
    }

    func testReserveZoneBoundariesUseHRRAndPreserveConfiguredCustomBounds() {
        let estimate = RunningZoneTarget.reserveZones(maxHR: 200, restingHR: 60, method: "HRR estimate")
        XCTAssertEqual(estimate.map(\.lowerBPM), [116, 144, 158, 172, 186])
        XCTAssertEqual(estimate[1].upperBPM, 158)
        XCTAssertTrue(estimate[1].contains(144)); XCTAssertTrue(estimate[1].contains(157))
        XCTAssertFalse(estimate[1].contains(158)); XCTAssertTrue(estimate[4].contains(210))
        let custom = RunningZoneTarget.customZones(lowerBounds: [90, 110, 130, 150, 170])
        XCTAssertEqual(custom[1].rangeLabel, "110–129 bpm")
        XCTAssertEqual(custom[1].method, "Configured custom BPM zones")
        XCTAssertTrue(RunningZoneTarget.reserveZones(maxHR: 60, restingHR: 60, method: "Invalid").isEmpty)
        XCTAssertTrue(RunningZoneTarget.reserveZones(maxHR: .nan, restingHR: 60, method: "Invalid").isEmpty)
    }

    func testDecodedActiveSessionCanRestorePausedWithoutBridgingPreviousReading() throws {
        var original = makeSession()
        sample(&original, 100, 130); sample(&original, 101, 130)
        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(RunningZoneSession.self, from: data)
        restored.pause()
        XCTAssertEqual(restored.phase, .paused)
        XCTAssertFalse(sample(&restored, 200, 130).accepted)
        restored.resume()
        sample(&restored, 201, 130); sample(&restored, 202, 130)
        XCTAssertEqual(restored.inZoneSeconds, 2)
    }
}
