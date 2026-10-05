import XCTest
import GRDB
import WhoopProtocol
@testable import WhoopStore

/// Minimal in-memory fixtures exercise the production read without opening a user store or migrator.
final class CollectionSnapshotTests: XCTestCase {
    private func fixture(model: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE pairedDevice(id TEXT, model TEXT, brand TEXT);
                CREATE TABLE hrSample(deviceId TEXT, ts INTEGER, bpm INTEGER);
                CREATE TABLE rrInterval(deviceId TEXT, ts INTEGER, rrMs INTEGER, srcChannel INTEGER, tsSuspect INTEGER);
                CREATE TABLE ppgHrSample(deviceId TEXT, ts INTEGER);
                CREATE TABLE stepSample(deviceId TEXT, ts INTEGER);
                """)
            try db.execute(sql: "INSERT INTO pairedDevice VALUES ('strap', ?, 'WHOOP')", arguments: [model])
            try db.execute(sql: "INSERT INTO hrSample VALUES ('strap',100,72),('strap',101,73),('other',102,80),('strap',200,90)")
            try db.execute(sql: "INSERT INTO rrInterval VALUES ('strap',100,800,5,NULL),('strap',101,810,7,NULL),('strap',102,820,6,NULL),('strap',103,830,NULL,NULL),('strap',104,840,5,1)")
            try db.execute(sql: "INSERT INTO rrInterval VALUES ('strap',105,850,?,NULL)", arguments: [RRSourceChannel.spo2Ibi.rawValue])
        }
        return queue
    }

    func testWHOOP5UsesOneValidTransportAndExactDeviceWindow() throws {
        let queue = try fixture(model: "WHOOP 5.0 / MG")
        try queue.read { db in
            let snapshot = try WhoopStore.readCollectionSnapshot(db: db, deviceId: "strap", from: 100, to: 110)
            XCTAssertEqual(snapshot.heartRate.count, 2)
            XCTAssertEqual(snapshot.heartRate.latestTs, 101)
            XCTAssertEqual(snapshot.rr.count, 6)
            XCTAssertEqual(snapshot.scorableRR.count, 1)
            XCTAssertEqual(snapshot.scorableRR.latestTs, 100)
        }
    }

    func testStandardTransportFillsAWindowWithoutHistoricalRR() throws {
        let queue = try fixture(model: "WHOOP 5.0 / MG")
        try queue.read { db in
            let snapshot = try WhoopStore.readCollectionSnapshot(db: db, deviceId: "strap", from: 101, to: 110)
            XCTAssertEqual(snapshot.scorableRR.count, 1)
            XCTAssertEqual(snapshot.scorableRR.latestTs, 101)
        }
    }

    func testWHOOP4DoesNotInheritWHOOP5TransportRestriction() throws {
        let queue = try fixture(model: "WHOOP 4.0")
        try queue.read { db in
            let snapshot = try WhoopStore.readCollectionSnapshot(db: db, deviceId: "strap", from: 100, to: 110)
            XCTAssertEqual(snapshot.scorableRR.count, 4)
            XCTAssertEqual(snapshot.scorableRR.latestTs, 103)
        }
    }

    func testEmptyWindowIsZeroWithNoInventedTimestamp() throws {
        let queue = try fixture(model: "WHOOP 5.0 / MG")
        try queue.read { db in
            let snapshot = try WhoopStore.readCollectionSnapshot(db: db, deviceId: "strap", from: 300, to: 310)
            XCTAssertEqual(snapshot.heartRate.count, 0)
            XCTAssertNil(snapshot.heartRate.latestTs)
            XCTAssertEqual(snapshot.scorableRR.count, 0)
            XCTAssertNil(snapshot.scorableRR.latestTs)
        }
    }
    func testLongHRRangeIsUncappedAndSampleWeightedRatherThanMeanOfDailyMeans() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE hrSample(deviceId TEXT, ts INTEGER, bpm INTEGER)")
            try db.execute(sql: """
                WITH RECURSIVE readings(x) AS (SELECT 0 UNION ALL SELECT x+1 FROM readings WHERE x < 200000)
                INSERT INTO hrSample SELECT 'strap', 1700000000+x, 60 FROM readings;
                INSERT INTO hrSample VALUES ('strap', 1700300000, 100), ('other', 1700000001, 220);
                """)
        }
        try queue.read { db in
            let days = try WhoopStore.readMeasuredHeartRateDays(db: db, deviceId: "strap", from: 1700000000, to: 1700300000)
            let count = days.reduce(0) { $0 + $1.count }
            let total = days.reduce(0) { $0 + $1.sumBPM }
            XCTAssertEqual(count, 200002)
            XCTAssertEqual(total, 200001 * 60 + 100)
            XCTAssertEqual(total / Double(count), 60 + 40 / 200002.0, accuracy: 0.000001)
        }
    }

    func testHRRangeBoundsInvalidValuesAndEmptyWindow() throws {
        let queue = try fixture(model: "WHOOP 5.0")
        try queue.write { db in try db.execute(sql: "INSERT INTO hrSample VALUES ('strap',102,0),('strap',103,-1)") }
        try queue.read { db in
            let rows = try WhoopStore.readMeasuredHeartRateDays(db: db, deviceId: "strap", from: 100, to: 110)
            XCTAssertEqual(rows.reduce(0) { $0 + $1.count }, 2)
            XCTAssertEqual(rows.reduce(0) { $0 + $1.sumBPM }, 145)
            XCTAssertTrue(try WhoopStore.readMeasuredHeartRateDays(db: db, deviceId: "strap", from: 300, to: 400).isEmpty)
        }
    }

}
