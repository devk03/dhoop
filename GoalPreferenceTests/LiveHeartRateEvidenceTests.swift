import XCTest

final class LiveHeartRateEvidenceTests: XCTestCase {
    func testEveryReceiptAdvancesEvidenceEvenAtUnchangedHeartRate() {
        var evidence = LiveHeartRateEvidence()
        XCTAssertFalse(evidence.isFresh(at: 100, silenceSeconds: 10))
        evidence.record(at: 100)
        evidence.record(at: 101)
        XCTAssertEqual(evidence.packets, 2)
        XCTAssertEqual(evidence.lastReceivedAt, 101)
        XCTAssertTrue(evidence.isFresh(at: 109, silenceSeconds: 10))
        XCTAssertFalse(evidence.isFresh(at: 111, silenceSeconds: 10))
        XCTAssertFalse(evidence.isFresh(at: 99, silenceSeconds: 10), "A future timestamp cannot prove receipt now")
    }

    func testNewConnectionHasNoStaleReceiptEvidence() {
        var evidence = LiveHeartRateEvidence()
        evidence.record(at: 100)
        evidence = LiveHeartRateEvidence()
        XCTAssertEqual(evidence.packets, 0)
        XCTAssertNil(evidence.lastReceivedAt)
    }

    func testLiveTraceRecordsUnchangedBPMAndIsBoundedByActualTime() {
        var evidence = LiveHeartRateEvidence()
        for time in 0...1000 { evidence.record(bpm: 72, at: Double(time)) }
        XCTAssertEqual(evidence.packets, 1001)
        XCTAssertEqual(evidence.samples.first?.receivedAt, 700)
        XCTAssertEqual(evidence.samples.last?.receivedAt, 1000)
        XCTAssertLessThanOrEqual(evidence.samples.count, LiveHeartRateEvidence.sampleCapacity)
        evidence.record(bpm: 73, at: 1000.5)
        XCTAssertEqual(evidence.samples.last?.bpm, 73)
        XCTAssertEqual(evidence.samples.filter { Int($0.receivedAt) == 1000 }.count, 1)
    }

    func testConnectedAndRecentReceiptStillNeedCurrentReadableWHOOPHR() {
        var evidence = LiveHeartRateEvidence()
        evidence.record(bpm: 72, at: 100)
        XCTAssertTrue(evidence.status(connected: true, isWhoop: true, heartRate: 72, at: 101, silenceSeconds: 10).isReceiving)
        for (connected, whoop, hr, now) in [(false, true, 72 as Int?, 101.0), (true, false, 72, 101),
                                           (true, true, nil, 101), (true, true, 72, 111)] {
            XCTAssertNil(evidence.status(connected: connected, isWhoop: whoop, heartRate: hr, at: now, silenceSeconds: 10).bpm)
        }
    }

    func testAnotherDeviceCannotBorrowFreshReceiptsOrPacketCounts() {
        var evidence = LiveHeartRateEvidence()
        evidence.record(bpm: 72, deviceId: "strap-a", at: 100)
        let other = evidence.status(connected: true, isWhoop: true, heartRate: 72, at: 101,
                                    silenceSeconds: 10, expectedDeviceId: "strap-b")
        XCTAssertNil(other.bpm)
        XCTAssertNil(other.sampleAge)
        XCTAssertEqual(other.packets, 0)
        let watch = evidence.status(connected: true, isWhoop: false, heartRate: 72, at: 101, silenceSeconds: 10)
        XCTAssertNil(watch.bpm)
        XCTAssertEqual(watch.packets, 0)
        XCTAssertFalse(watch.connected)
    }

    func testNewAttributedSourceStartsItsOwnTraceAndCount() {
        var evidence = LiveHeartRateEvidence()
        evidence.record(bpm: 72, deviceId: "strap-a", at: 100)
        evidence.record(bpm: 80, deviceId: "strap-b", at: 101)
        XCTAssertEqual(evidence.sourceDeviceId, "strap-b")
        XCTAssertEqual(evidence.packets, 1)
        XCTAssertEqual(evidence.samples.map(\.bpm), [80])
    }

    func testConnectionIsAttributedEvenBeforeAnyReadablePacket() {
        let evidence = LiveHeartRateEvidence()
        let linked = evidence.status(connected: true, isWhoop: true, heartRate: nil, at: 100,
                                     silenceSeconds: 10, expectedDeviceId: "strap-a", connectionDeviceId: "strap-a")
        XCTAssertTrue(linked.connected)
        XCTAssertFalse(linked.isReceiving)
        let other = evidence.status(connected: true, isWhoop: true, heartRate: nil, at: 100,
                                    silenceSeconds: 10, expectedDeviceId: "strap-b", connectionDeviceId: "strap-a")
        XCTAssertFalse(other.connected)
    }
}
