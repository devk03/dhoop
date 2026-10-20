#if DEBUG
import XCTest
import GRDB

final class OwnerDataReviewSliceTests: XCTestCase {
    func testSlicePreservesGapsSavedStagesAndSourceWithoutCopyingUnrelatedStreams() throws {
        let source = try DatabaseQueue()
        let latest = 1_800_000_000
        try source.write { db in
            try db.execute(sql: "CREATE TABLE hrSample(ts INTEGER PRIMARY KEY, bpm INTEGER); CREATE INDEX hr_value ON hrSample(bpm); CREATE TABLE rrInterval(ts INTEGER, rrMs INTEGER, ord INTEGER); CREATE TABLE sleepSession(startTs INTEGER, endTs INTEGER, stagesJSON TEXT); CREATE TABLE dailyMetric(day TEXT, avgHrv REAL); CREATE TABLE rawBatch(payload BLOB)")
            try db.execute(sql: "INSERT INTO hrSample VALUES (?, 65), (?, 70), (?, 71)", arguments: [latest - 10 * 86400, latest - 3600, latest])
            try db.execute(sql: "INSERT INTO rrInterval VALUES (?, 900, 2), (?, 850, 1)", arguments: [latest, latest])
            try db.execute(sql: "INSERT INTO sleepSession VALUES (?, ?, ?)", arguments: [latest - 10 * 86400, latest - 9 * 86400, "[{\"stage\":\"deep\",\"gap\":true}]"])
            try db.execute(sql: "INSERT INTO dailyMetric VALUES ('2027-01-01', 96.6); INSERT INTO rawBatch VALUES (X'112233')")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("owner-review-test-\(UUID()).sqlite")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let result = try OwnerDataReviewSlice.create(from: source, at: url, calendar: calendar)
        XCTAssertEqual(result.counts["hrSample"], 2)
        XCTAssertEqual(result.counts["rrInterval"], 2)
        XCTAssertEqual(result.counts["sleepSession"], 1)
        XCTAssertEqual(result.rawThrough, latest)
        let slice = try DatabaseQueue(path: url.path)
        try slice.read { db in
            XCTAssertEqual(try Int.fetchAll(db, sql: "SELECT ts FROM hrSample ORDER BY ts"), [latest - 3600, latest])
            XCTAssertEqual(try Int.fetchAll(db, sql: "SELECT ord FROM rrInterval ORDER BY ord"), [1, 2])
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT avgHrv FROM dailyMetric"), 96.6)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT stagesJSON FROM sleepSession"), "[{\"stage\":\"deep\",\"gap\":true}]")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rawBatch"), 0)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA quick_check"), "ok")
            XCTAssertTrue(try db.indexes(on: "hrSample").contains { $0.name == "hr_value" })
        }
        try source.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rawBatch"), 1)
        }
        // A second run cannot replace the first copy, or accidentally target the owner's database.
        XCTAssertThrowsError(try OwnerDataReviewSlice.create(from: source, at: url, calendar: calendar))
        try slice.read { db in XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample"), 2) }
    }
}
#endif
