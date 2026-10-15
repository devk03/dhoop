import Foundation
import GRDB

public enum LiftRecordingError: LocalizedError {
    case inconsistentRecording
    public var errorDescription: String? { "The workout and sets do not belong to the same strength session." }
}

extension WhoopStore {
    /// One transaction owns the session, its exact set list and its paired manual workout.
    /// Existing natural-key and set identities survive a retry. No schema or stored formula changes.
    public func saveLiftRecording(session: LiftSessionRow, sets: [LiftSetRow], workout: WorkoutRow,
                                  updatedProgramItems: [LiftProgramItemRow]? = nil) async throws {
        guard workout.startTs == session.startTs, workout.sport == session.sport,
              workout.source == "manual", Set(sets.map(\.id)).count == sets.count,
              sets.allSatisfy({ $0.deviceId == session.deviceId && $0.sessionId == session.id })
        else { throw LiftRecordingError.inconsistentRecording }
        if let updatedProgramItems {
            guard let programID = session.programId,
                  updatedProgramItems.allSatisfy({ $0.programId == programID && $0.deviceId == session.deviceId })
            else { throw LiftRecordingError.inconsistentRecording }
        }
        try syncWrite { db in
            let existing = try Row.fetchOne(db, sql: "SELECT * FROM liftSession WHERE deviceId = ? AND startTs = ? AND sport = ?",
                arguments: [session.deviceId, session.startTs, session.sport])
            let canonicalID: String = existing?["id"] ?? session.id
            let previous = try Row.fetchAll(db, sql: "SELECT * FROM liftSet WHERE sessionId = ?", arguments: [canonicalID])
                .map(LiftSetRow.decode)
            let canonicalSets = sets.map { row -> LiftSetRow in
                var row = row
                row.sessionId = canonicalID
                if let old = previous.first(where: { $0.ord == row.ord && $0.exercise == row.exercise && $0.setIndex == row.setIndex }) {
                    row.id = old.id
                }
                return row
            }
            for row in canonicalSets {
                if let owner = try String.fetchOne(db, sql: "SELECT sessionId FROM liftSet WHERE id = ?", arguments: [row.id]), owner != canonicalID {
                    throw LiftRecordingError.inconsistentRecording
                }
            }
            var canonicalSession = session
            canonicalSession.id = canonicalID
            if let json = session.activityIntervalsJSON {
                var phases = try LiftActivityLedger.decode(json)
                let mapping = Dictionary(uniqueKeysWithValues: zip(sets, canonicalSets).map { ($0.id, $1.id) })
                for index in phases.indices {
                    if let id = phases[index].sourceSetId { phases[index].sourceSetId = mapping[id] ?? id }
                }
                let priorJSON: String? = existing?["activityIntervalsJSON"]
                let retained = try priorJSON.map(LiftActivityLedger.decode)?.compactMap(\.sourceSetId) ?? []
                try LiftActivityLedger.validate(phases, session: canonicalSession, sets: canonicalSets + previous,
                    retainedSetIDs: Set(retained))
                canonicalSession.activityIntervalsJSON = try LiftActivityLedger.encode(phases)
            }
            _ = try Self.writeLiftSessions([canonicalSession], db: db)
            try db.execute(sql: "DELETE FROM liftSet WHERE sessionId = ?", arguments: [canonicalID])
            _ = try Self.writeLiftSets(canonicalSets, db: db)
            _ = try Self.writeWorkouts([workout], deviceId: session.deviceId, db: db)
            if let updatedProgramItems, let programID = session.programId {
                _ = try Self.writeLiftProgramItems(programId: programID, items: updatedProgramItems, db: db)
            }
        }
    }

    /// Routine metadata and ordered targets succeed or fail together.
    public func saveLiftProgram(_ program: LiftProgramRow, items: [LiftProgramItemRow]) async throws {
        guard items.allSatisfy({ $0.programId == program.id && $0.deviceId == program.deviceId }) else {
            throw LiftRecordingError.inconsistentRecording
        }
        try syncWrite { db in
            _ = try Self.writeLiftPrograms([program], db: db)
            _ = try Self.writeLiftProgramItems(programId: program.id, items: items, db: db)
        }
    }

    /// Corrections retain recorded timings and mutate only explicitly selected rows in one session.
    public func editLiftRecording(session: LiftSessionRow, upserts: [LiftSetRow], deletedSetIDs: [String]) async throws {
        guard upserts.allSatisfy({ $0.sessionId == session.id && $0.deviceId == session.deviceId }) else {
            throw LiftRecordingError.inconsistentRecording
        }
        try syncWrite { db in
            guard try String.fetchOne(db, sql: "SELECT id FROM liftSession WHERE deviceId = ? AND startTs = ? AND sport = ?",
                arguments: [session.deviceId, session.startTs, session.sport]) == session.id else {
                throw LiftRecordingError.inconsistentRecording
            }
            for id in deletedSetIDs + upserts.map(\.id) {
                if let owner = try String.fetchOne(db, sql: "SELECT sessionId FROM liftSet WHERE id = ?", arguments: [id]), owner != session.id {
                    throw LiftRecordingError.inconsistentRecording
                }
            }
            if let json = session.activityIntervalsJSON {
                let previous = try Row.fetchAll(db, sql: "SELECT * FROM liftSet WHERE sessionId = ?", arguments: [session.id]).map(LiftSetRow.decode)
                let retainedJSON = try String.fetchOne(db, sql: "SELECT activityIntervalsJSON FROM liftSession WHERE id = ?", arguments: [session.id])
                let retained = try retainedJSON.map(LiftActivityLedger.decode)?.compactMap(\.sourceSetId) ?? []
                // New corrections own current bounds; deleted rows retain their historical lineage.
                let merged = upserts + previous.filter { old in !upserts.contains { $0.id == old.id } }
                try LiftActivityLedger.validate(LiftActivityLedger.decode(json), session: session, sets: merged,
                    retainedSetIDs: Set(retained))
            }
            _ = try Self.writeLiftSessions([session], db: db)
            _ = try Self.writeLiftSets(upserts, db: db)
            for id in deletedSetIDs {
                try db.execute(sql: "DELETE FROM liftSet WHERE id = ? AND sessionId = ?", arguments: [id, session.id])
            }
        }
    }

    /// Delete only the explicitly selected strength recording, never HR samples or another session.
    @discardableResult
    public func deleteLiftRecording(_ session: LiftSessionRow) async throws -> Bool {
        try syncWrite { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM liftSession WHERE id = ? AND deviceId = ? AND startTs = ? AND sport = ?",
                arguments: [session.id, session.deviceId, session.startTs, session.sport]) == 1 else { return false }
            try db.execute(sql: "DELETE FROM liftSet WHERE sessionId = ?", arguments: [session.id])
            try db.execute(sql: "DELETE FROM liftSession WHERE id = ?", arguments: [session.id])
            try db.execute(sql: "DELETE FROM workout WHERE deviceId = ? AND startTs = ? AND sport = ? AND source = 'manual'",
                arguments: [session.deviceId, session.startTs, session.sport])
            return true
        }
    }
}

// Typed storage adapters keep the validation helper independent of GRDB and app frameworks.
extension LiftActivityLedger {
    static func validate(_ intervals: [LiftActivityInterval], session: LiftSessionRow,
                         sets: [LiftSetRow], retainedSetIDs: Set<String> = []) throws {
        try validate(intervals,
            session: .init(id: session.id, deviceId: session.deviceId, startTs: session.startTs, endTs: session.endTs),
            sets: sets.map { .init(id: $0.id, sessionId: $0.sessionId, deviceId: $0.deviceId, startTs: $0.startTs, endTs: $0.endTs) },
            retainedSetIDs: retainedSetIDs)
    }
}
