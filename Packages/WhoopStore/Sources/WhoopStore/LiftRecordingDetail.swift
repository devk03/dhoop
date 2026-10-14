import Foundation
import GRDB

/// Raw rows from one read transaction. No metric or persisted value is changed.
public struct LiftRecordingDetail: Equatable {
    public let session: LiftSessionRow
    public let sets: [LiftSetRow]
    public let workout: WorkoutRow?
    public let previousSets: [String: [LiftSetRow]]

    public init(session: LiftSessionRow, sets: [LiftSetRow], workout: WorkoutRow?, previousSets: [String: [LiftSetRow]]) {
        self.session = session; self.sets = sets; self.workout = workout; self.previousSets = previousSets
    }
}

extension WhoopStore {
    /// Missing means no row under the recorded identity; a failed read always throws.
    public func liftRecordingDetail(deviceId: String, sessionId: String) async throws -> LiftRecordingDetail? {
        try syncRead { db in
            guard let raw = try Row.fetchOne(db, sql: "SELECT * FROM liftSession WHERE id = ? AND deviceId = ?",
                                            arguments: [sessionId, deviceId]) else { return nil }
            let session = LiftSessionRow.decode(raw)
            let sets = try Row.fetchAll(db, sql: "SELECT * FROM liftSet WHERE sessionId = ? ORDER BY ord ASC",
                                       arguments: [sessionId]).map(LiftSetRow.decode)
            guard sets.allSatisfy({ $0.deviceId == deviceId }) else { throw LiftRecordingError.inconsistentRecording }
            let workout = try Row.fetchOne(db, sql: "SELECT * FROM workout WHERE deviceId = ? AND startTs = ? AND sport = ?",
                                          arguments: [deviceId, session.startTs, session.sport]).map(Self.decodeWorkout)
            var previous: [String: [LiftSetRow]] = [:]
            for name in Set(sets.filter { $0.reps != 0 }.map(\.exercise)) {
                let priorId = try String.fetchOne(db, sql: """
                    SELECT s.sessionId FROM liftSet s JOIN liftSession sess ON sess.id = s.sessionId
                    WHERE s.deviceId = ? AND sess.deviceId = ? AND s.exercise = ? AND sess.startTs < ?
                      AND (s.reps IS NULL OR s.reps <> 0)
                    ORDER BY sess.startTs DESC LIMIT 1
                    """, arguments: [deviceId, deviceId, name, session.startTs])
                if let priorId {
                    previous[name] = try Row.fetchAll(db, sql: """
                        SELECT * FROM liftSet WHERE sessionId = ? AND deviceId = ? AND exercise = ?
                          AND (reps IS NULL OR reps <> 0) ORDER BY ord ASC
                        """, arguments: [priorId, deviceId, name]).map(LiftSetRow.decode)
                } else { previous[name] = [] }
            }
            return LiftRecordingDetail(session: session, sets: sets, workout: workout, previousSets: previous)
        }
    }
}
