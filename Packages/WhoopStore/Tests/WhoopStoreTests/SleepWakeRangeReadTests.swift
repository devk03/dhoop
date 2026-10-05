import XCTest
import GRDB
@testable import WhoopStore

final class SleepWakeRangeReadTests: XCTestCase {
    private func fixture() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE sleepSession(deviceId TEXT, startTs INTEGER, endTs INTEGER,
                    efficiency REAL, restingHr INTEGER, avgHrv REAL, stagesJSON TEXT,
                    userEdited INTEGER, startTsAdjusted INTEGER, stagingSparse INTEGER);
                INSERT INTO sleepSession VALUES ('strap', 10, 100, NULL, NULL, NULL, NULL, 1, 20, NULL);
                INSERT INTO sleepSession VALUES ('strap', 200, 300, NULL, NULL, NULL, NULL, 0, NULL, NULL);
                INSERT INTO sleepSession VALUES ('other', 10, 100, NULL, NULL, NULL, NULL, 0, NULL, NULL);
                """)
        }
        return queue
    }
    func testWakeBoundsIncludeOvernightStartsAndPreserveEditedOnsetAndSource() throws {
        let queue = try fixture()
        try queue.read { db in
            let rows = try WhoopStore.readSleepSessionsByWake(db: db, deviceId: "strap", from: 100, to: 200)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].effectiveStartTs, 20)
            XCTAssertEqual(rows[0].endTs, 100)
            XCTAssertEqual(rows[0].deviceId, "strap")
        }
    }
    func testAllHistoryDoesNotTruncateAtFourThousandSessions() throws {
        let queue = try fixture()
        try queue.write { db in
            try db.execute(sql: """
                WITH RECURSIVE nights(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM nights WHERE x < 4001)
                INSERT INTO sleepSession SELECT 'long', x*1000, x*1000+500, NULL, NULL, NULL, NULL, 0, NULL, NULL FROM nights;
                """)
        }
        try queue.read { db in
            let rows = try WhoopStore.readSleepSessionsByWake(db: db, deviceId: "long", from: 0, to: 5000000)
            XCTAssertEqual(rows.count, 4001)
            XCTAssertTrue(try WhoopStore.readSleepSessionsByWake(db: db, deviceId: "strap", from: 400, to: 500).isEmpty)
        }
    }
}
