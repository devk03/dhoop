import XCTest
@testable import WhoopProtocol

final class Whoop5AlarmRecordTests: XCTestCase {
    func testExactRecordPaddingAndTargetedClear() throws {
        let record = try XCTUnwrap(Whoop5AlarmRecord.standard(slot: 6, epoch: 1791871200))
        // Independent little-endian timestamp and existing waveform oracle.
        XCTAssertEqual(record.bytes, [4, 6, 224, 200, 205, 106, 0, 0, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 7, 30, 0])
        XCTAssertEqual(record.epoch, 1791871200)
        XCTAssertEqual(Whoop5AlarmRecord(payload: record.bytes + [0, 0], slot: 6), record)
        XCTAssertNil(Whoop5AlarmRecord(payload: record.bytes + [1], slot: 6))
        XCTAssertNil(Whoop5AlarmRecord(payload: record.bytes, slot: 1))
        XCTAssertEqual(Whoop5AlarmRecord.clearPayload(slot: 6), [2, 6])
        XCTAssertNil(Whoop5AlarmRecord.clearPayload(slot: 255))
    }
    func testAmbiguousZerosAndMalformedData() throws {
        let zero = try XCTUnwrap(Whoop5AlarmRecord(payload: [4, 1] + Array(repeating: 0, count: 19), slot: 1))
        XCTAssertTrue(zero.isClearedCandidate)
        XCTAssertTrue(zero.isZeroTime)
        XCTAssertNil(Whoop5AlarmRecord(payload: Array(repeating: 0, count: 21), slot: 1))
        XCTAssertNil(Whoop5AlarmRecord(payload: Array(zero.bytes.prefix(20)), slot: 1))
        var bad = try XCTUnwrap(Whoop5AlarmRecord.standard(slot: 1, epoch: 1791871200)).bytes
        bad[18] = 8
        XCTAssertNil(Whoop5AlarmRecord(payload: bad, slot: 1))
        bad[18] = 7; bad[19] = 29
        XCTAssertNil(Whoop5AlarmRecord(payload: bad, slot: 1))
    }
}
