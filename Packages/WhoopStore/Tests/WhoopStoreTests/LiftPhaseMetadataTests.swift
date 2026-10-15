import Foundation
import GRDB
import XCTest
@testable import WhoopStore

final class LiftPhaseMetadataTests: XCTestCase {
    func testUpgradePreservesLegacyRowsAndLeavesMetadataUnknown() throws {
        let database = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(database, upTo: "v46-lift-log")
        try database.write { db in
            try db.execute(sql: "INSERT INTO liftExercise (id,deviceId,name,createdAt) VALUES ('exercise','strap','Press',100)")
            try db.execute(sql: "INSERT INTO liftProgramItem (id,deviceId,programId,ord,exercise,targetSets) VALUES ('item','strap','routine',0,'Press',3)")
            try db.execute(sql: "INSERT INTO liftSession (id,deviceId,startTs,sport,note) VALUES ('session','strap',100,'Strength Training','Keep this')")
            try db.execute(sql: "INSERT INTO liftSet (id,deviceId,sessionId,ord,exercise,setIndex,weightKg,reps) VALUES ('set','strap','session',0,'Press',1,20,8)")
            try db.execute(sql: "INSERT INTO hrSample (deviceId,ts,bpm) VALUES ('strap',120,90)")
        }
        try migrator.migrate(database)
        // Reopening an already migrated backup must be idempotent too.
        try migrator.migrate(database)
        try database.read { db in
            let exercise = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM liftExercise"))
            XCTAssertEqual(exercise["name"] as String, "Press")
            XCTAssertNil(exercise["parentExerciseId"] as String?)
            let item = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM liftProgramItem"))
            XCTAssertEqual(item["targetSets"] as Int, 3)
            XCTAssertNil(item["supersetGroupId"] as String?)
            let session = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM liftSession"))
            XCTAssertEqual(session["note"] as String, "Keep this")
            XCTAssertNil(session["activityIntervalsJSON"] as String?)
            let set = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM liftSet"))
            XCTAssertEqual(set["weightKg"] as Double, 20)
            XCTAssertEqual(set["reps"] as Int, 8)
            XCTAssertNil(set["supersetGroupId"] as String?)
            XCTAssertNil(set["roundIndex"] as Int?)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT bpm FROM hrSample"), 90)
        }
    }

    func testMetadataSurvivesWritersCodableAndIndependentHistory() async throws {
        let store = try await WhoopStore.inMemory()
        let parent = LiftExerciseRow(id: "parent", deviceId: "strap", name: "Press",
            primaryMuscle: .chest, createdAt: 100, lastUsedTs: nil)
        let variation = LiftExerciseRow(id: "child", deviceId: "strap", name: "Incline press",
            primaryMuscle: .chest, createdAt: 100, lastUsedTs: nil, parentExerciseId: parent.id)
        _ = try await store.upsertLiftExercises([parent, variation])
        // Recency/classification updates from old callers must not erase ancestry.
        _ = try await store.upsertLiftExercises([.init(id: "ignored", deviceId: "strap", name: variation.name,
            primaryMuscle: nil, createdAt: 101, lastUsedTs: 200)])
        let exercises = try await store.liftExercises(deviceId: "strap")
        XCTAssertEqual(exercises.first(where: { $0.id == "child" })?.parentExerciseId, "parent")
        let item = LiftProgramItemRow(id: "item", deviceId: "strap", programId: "routine", ord: 0,
            exercise: variation.name, targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10,
            targetRpe: nil, targetWeightKg: 20, restSec: 60, note: nil, supersetGroupId: "group")
        _ = try await store.replaceLiftProgramItems(programId: "routine", items: [item])
        let items = try await store.liftProgramItems(programId: "routine")
        XCTAssertEqual(items, [item])
        let session = LiftSessionRow(id: "session", deviceId: "strap", startTs: 100, endTs: 200,
            sport: "Strength Training", programId: nil, programName: nil, sessionRpe: nil,
            note: nil, activityIntervalsJSON: "[]")
        let set = LiftSetRow(id: "set", deviceId: "strap", sessionId: session.id, ord: 0,
            exercise: variation.name, primaryMuscle: .chest, setIndex: 1, weightKg: 20,
            reps: 8, rpe: nil, isWarmup: false, startTs: 110, endTs: 130, restSec: 60,
            note: nil, supersetGroupId: "group", roundIndex: 0)
        _ = try await store.upsertLiftSessions([session])
        _ = try await store.upsertLiftSets([set])
        let sessions = try await store.liftSessions(deviceId: "strap", fromTs: 0, toTs: 300)
        let sets = try await store.liftSets(sessionId: session.id)
        XCTAssertEqual(sessions, [session])
        XCTAssertEqual(sets, [set])
        XCTAssertEqual(try JSONDecoder().decode(LiftSessionRow.self, from: JSONEncoder().encode(session)), session)
        XCTAssertEqual(try JSONDecoder().decode(LiftSetRow.self, from: JSONEncoder().encode(set)), set)
        let parentHistory = try await store.lastLiftSets(deviceId: "strap", exercise: parent.name)
        let childHistory = try await store.lastLiftSets(deviceId: "strap", exercise: variation.name)
        XCTAssertTrue(parentHistory.isEmpty)
        XCTAssertEqual(childHistory, [set])
    }

    func testVariationParentMustBeLocalAndCannotReclassifyExistingHistory() async throws {
        let store = try await WhoopStore.inMemory()
        let parent = LiftExerciseRow(id: "parent", deviceId: "strap", name: "Press", primaryMuscle: nil, createdAt: 100, lastUsedTs: nil)
        _ = try await store.upsertLiftExercises([parent])
        for (id,device,name,parentID) in [("self","strap","Self","self"),("foreign","other","Foreign","parent"),("missing","strap","Missing","gone"),("parent","strap","Press","parent")] {
            do {
                _ = try await store.upsertLiftExercises([.init(id:id,deviceId:device,name:name,primaryMuscle:nil,createdAt:100,lastUsedTs:nil,parentExerciseId:parentID)])
                XCTFail("Invalid parent must not save")
            } catch { }
        }
        let local = try await store.liftExercises(deviceId: "strap")
        let other = try await store.liftExercises(deviceId: "other")
        XCTAssertEqual(local,[parent])
        XCTAssertTrue(other.isEmpty)
    }

    func testLegacyCodableRowsDoNotInventMetadata() throws {
        let session = try JSONDecoder().decode(LiftSessionRow.self, from: Data("""
            {"id":"s","deviceId":"d","startTs":100,"sport":"Strength Training"}
            """.utf8))
        XCTAssertNil(session.activityIntervalsJSON)
        let set = try JSONDecoder().decode(LiftSetRow.self, from: Data("""
            {"id":"set","deviceId":"d","sessionId":"s","ord":0,"exercise":"Press",
             "secondaryMuscles":[],"setIndex":1,"isWarmup":false}
            """.utf8))
        XCTAssertNil(set.roundIndex)
        XCTAssertNil(set.supersetGroupId)
    }
}
