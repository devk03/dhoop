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
}
