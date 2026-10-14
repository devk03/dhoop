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
            let existing = try Row.fetchOne(db, sql: "SELECT id FROM liftSession WHERE deviceId = ? AND startTs = ? AND sport = ?",
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
            _ = try Self.writeLiftSessions([session], db: db)
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
