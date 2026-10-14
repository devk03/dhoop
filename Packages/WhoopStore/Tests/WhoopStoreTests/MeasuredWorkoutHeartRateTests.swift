import XCTest
import GRDB
import WhoopProtocol
@testable import WhoopStore

final class MeasuredWorkoutHeartRateTests: XCTestCase {
    func testSetBoundaryBelongsToOnlyOneWindowAndAnotherDeviceIsExcluded() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId,ts,bpm) VALUES ('a',1000,60),('a',1001,120),('a',1002,150),('b',1000,200),('a',1003,0)")
        }
        let first = try await store.measuredHeartRateStats(deviceId: "a", from: 1000, toExclusive: 1002)
        let second = try await store.measuredHeartRateStats(deviceId: "a", from: 1002, toExclusive: 1004)
        XCTAssertEqual(first, HRWindowStats(n: 2, avg: 90, max: 120))
        XCTAssertEqual(second, HRWindowStats(n: 1, avg: 150, max: 150))
        // Captured verbatim by the Kotlin production-query oracle test.
        let oracle = [first, second].map {
            "\($0.n)|\($0.avg.map { String($0) } ?? "null")|\($0.max.map { String($0) } ?? "null")"
        }.joined(separator: " ; ")
        print("MeasuredWorkoutHR oracle: \(oracle)")
        let rows = try await store.measuredHeartRateSamples(deviceId: "a", from: 1000, toExclusive: 1002, limit: 10)
        XCTAssertEqual(rows.map(\.ts), [1000, 1001])
        XCTAssertEqual(rows.map(\.bpm), [60, 120])
        let negativeLimit = try await store.measuredHeartRateSamples(deviceId: "a", from: 1000, toExclusive: 1004, limit: -1)
        XCTAssertTrue(negativeLimit.isEmpty, "A negative cap must not silently become unlimited on either platform")
    }

    func testEmptyOrReversedWindowIsUnavailableRatherThanAZeroAverage() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.insert(Streams(ppgHr: [PpgHrSample(ts: 1001, bpm: 70, conf: 0.9)]), deviceId: "a")
        let absent = try await store.measuredHeartRateStats(deviceId: "a", from: 1000, toExclusive: 1002)
        let reversed = try await store.measuredHeartRateStats(deviceId: "a", from: 1002, toExclusive: 1000)
        XCTAssertEqual(absent, HRWindowStats(n: 0, avg: nil, max: nil))
        XCTAssertEqual(reversed, absent)
    }
}
