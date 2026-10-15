import Foundation
import XCTest
@testable import WhoopStore

final class LiftActivityLedgerTests: XCTestCase {
    let session = LiftActivityLedger.SessionBounds(id: "session", deviceId: "strap", startTs: 100, endTs: 300)
    let set = LiftActivityLedger.SetBounds(id: "set", sessionId: "session", deviceId: "strap", startTs: 110, endTs: 220)
    func phase(_ kind: LiftActivityInterval.Kind, _ start: Int, _ end: Int?, set: String? = "set") -> LiftActivityInterval {
        .init(sourceIntervalId: UUID().uuidString, kind: kind, sourceSetId: set, startedAt: start, endedAt: end)
    }
    func testBoundaryOracleDoesNotDrift() {
        let expected = [
            "BBBBBBBBBBBB....BB.B..BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
            "BBBBBB.....B.....B.B...B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.BBBBBBB",
            "BBBBBBBBBBBB....BB.B..BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
        ]
        let session = LiftActivityLedger.SessionBounds(id: "s", deviceId: "d", startTs: 100, endTs: 300)
        let set = LiftActivityLedger.SetBounds(id: "set", sessionId: "s", deviceId: "d", startTs: 110, endTs: 220)
        let actual = [LiftActivityInterval.Kind.work, .rest, .pause].map { kind -> String in
            var output = ""
            for start in stride(from: 90, through: 310, by: 10) {
                for end: Int? in [nil,110,120,220,300,310] {
                    let phase = LiftActivityInterval(sourceIntervalId: "00000000-0000-0000-0000-000000000001", kind: kind, sourceSetId: "set", startedAt: start, endedAt: end)
                    do { try LiftActivityLedger.validate([phase], session: session, sets: [set]); output += "." }
                    catch LiftActivityLedger.Invalid.bounds { output += "B" }
                    catch { output += "X" }
                }
            }
            return output
        }
        XCTAssertEqual(actual, expected)
    }

    func testLongPauseRestAndUnknownWindowsRemainHonest() throws {
        let phases = [phase(.work,110,120), phase(.pause,120,200), phase(.work,200,220),
            phase(.rest,220,230), phase(.pause,230,270,set:nil), phase(.rest,270,nil)]
        try LiftActivityLedger.validate(phases, session: session, sets: [set])
        XCTAssertEqual(LiftActivityLedger.workWindows(phases, setID: "set"), [110..<120,200..<220])
        XCTAssertEqual(try LiftActivityLedger.decode(LiftActivityLedger.encode(phases)), phases)
        XCTAssertEqual(LiftActivityLedger.workWindows([phase(.work,110,nil)], setID: "set"), [])
    }
    func testRejectsOverlapBoundsForeignAndDanglingReferences() {
        for phases in [[phase(.work,110,150),phase(.pause,140,160)], [phase(.work,99,120)],
                       [phase(.work,110,301)], [phase(.work,110,120,set:nil)],
                       [phase(.work,110,120,set:"foreign")], [phase(.pause,221,240)]] {
            XCTAssertThrowsError(try LiftActivityLedger.validate(phases, session: session, sets: [set]))
        }
        let foreign = LiftActivityLedger.SetBounds(id: "set", sessionId: "other", deviceId: "strap", startTs: 110, endTs: 220)
        XCTAssertThrowsError(try LiftActivityLedger.validate([phase(.work,110,120)], session: session, sets: [foreign]))
    }
    func testDeletedSetLineageIsRetainedButNotAnActiveAggregate() throws {
        let phases = [phase(.work,110,120)]
        try LiftActivityLedger.validate(phases, session: session, sets: [], retainedSetIDs: ["set"])
        XCTAssertEqual(LiftActivityLedger.workWindows(phases,setID:"remaining"), [])
        XCTAssertThrowsError(try LiftActivityLedger.validate(phases, session: session, sets: []))
    }
    func testInvalidLedgerRollsBackAndDeletedTimingSurvivesLaterCorrection() async throws {
        let store = try await WhoopStore.inMemory()
        var record = LiftSessionRow(id: "session", deviceId: "strap", startTs: 100, endTs: 300,
            sport: "Strength Training", programId: nil, programName: nil, sessionRpe: nil, note: nil)
        let row = LiftSetRow(id: "set", deviceId: "strap", sessionId: "session", ord: 0,
            exercise: "Press", primaryMuscle: nil, setIndex: 1, weightKg: 20, reps: 8, rpe: nil,
            isWarmup: false, startTs: 110, endTs: 220, restSec: nil, note: nil)
        let workout = WorkoutRow(startTs: 100, endTs: 300, sport: record.sport, source: "manual",
            durationS: 200, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
            zonesJSON: nil, notes: nil, steps: nil)
        record.activityIntervalsJSON = try LiftActivityLedger.encode([phase(.work,110,120,set:"foreign")])
        do { try await store.saveLiftRecording(session: record, sets: [row], workout: workout); XCTFail("Dangling source must reject atomically") } catch { }
        let rejected = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 400)
        XCTAssertTrue(rejected.isEmpty)
        record.activityIntervalsJSON = try LiftActivityLedger.encode([phase(.work,110,120)])
        try await store.saveLiftRecording(session: record, sets: [row], workout: workout)
        try await store.editLiftRecording(session: record, upserts: [], deletedSetIDs: [row.id])
        record.note = "Corrected note"
        try await store.editLiftRecording(session: record, upserts: [], deletedSetIDs: [])
        let retained = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 400)
        let sets = try await store.liftSets(sessionId: record.id)
        XCTAssertEqual(retained.first?.activityIntervalsJSON, record.activityIntervalsJSON)
        XCTAssertTrue(sets.isEmpty)
    }

    func testUnionQueryExcludesPauseAndDeduplicatesBoundaries() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            for (ts,bpm) in [(110,100),(119,120),(120,200),(199,200),(200,140),(219,160),(220,200)] {
                try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',?,?)", arguments: [ts,bpm])
            }
        }
        let stats = try await store.measuredHeartRateStats(deviceId: "strap", windows: [110..<120,200..<220,200..<210])
        XCTAssertEqual(stats, HRWindowStats(n: 4,avg:130,max:160))
        let unknown = try await store.measuredHeartRateStats(deviceId: "strap", windows: [])
        XCTAssertEqual(unknown, HRWindowStats(n:0,avg:nil,max:nil))
    }
    func testDuplicateIdentitiesAndOverLimitAreRejectedWithoutTruncation() throws {
        let same = phase(.work,110,110)
        XCTAssertThrowsError(try LiftActivityLedger.validate([same,same],session:session,sets:[set]))
        let many = (0...512).map { _ in phase(.work,110,110) }
        XCTAssertThrowsError(try LiftActivityLedger.encode(many))
    }
}
