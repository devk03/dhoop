import XCTest
import WhoopProtocol
@testable import WhoopStore

final class RawSensorCSVExportTests: XCTestCase {
    func testSuccessiveExportsKeepEachPreparedFileAndItsOriginalRecordedSource() async throws {
        let store = try await WhoopStore.inMemory()
        var exports: [(URL, Int)] = []
        for index in 0..<8 {
            let source = "source-\(index)", bpm = 60 + index
            _ = try await store.insert(Streams(hr: [HRSample(ts: 1000, bpm: bpm)]), deviceId: source)
            exports.append((try await store.exportRawCSV(deviceId: source, since: 900), bpm))
        }
        XCTAssertEqual(Set(exports.map(\.0)).count, exports.count, "One pending share must not overwrite another export")
        for (url, bpm) in exports {
            let csv = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(csv.contains(",hr,\(bpm),"), "Each original URL must still contain its own recorded source's values")
            XCTAssertEqual(csv.split(separator: "\n").count, 2, "Header plus one actual reading; other devices must not leak into the export")
        }
    }
}
