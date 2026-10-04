import Foundation
import GRDB
import WhoopProtocol

/// Exact-device transport evidence. Counts do not assert physiological validity or score eligibility.
public struct CollectionStreamSnapshot: Sendable, Equatable {
    public let count: Int
    public let latestTs: Int?
}

public struct WhoopCollectionSnapshot: Sendable, Equatable {
    public let deviceId: String
    public let fromTs: Int
    public let toTs: Int
    public let heartRate: CollectionStreamSnapshot
    public let rr: CollectionStreamSnapshot
    /// Records accepted by the existing transport/time policy; physiological filtering still follows.
    public let scorableRR: CollectionStreamSnapshot
    public let opticalEstimates: CollectionStreamSnapshot
    public let steps: CollectionStreamSnapshot
}

extension WhoopStore {
    /// One consistent read transaction, bound to the active registry id rather than merged/imported data.
    public func collectionSnapshot(deviceId: String, from: Int, to: Int) async throws -> WhoopCollectionSnapshot {
        try syncRead { try Self.readCollectionSnapshot(db: $0, deviceId: deviceId, from: from, to: to) }
    }

    static func readCollectionSnapshot(db: Database, deviceId: String, from: Int, to: Int) throws -> WhoopCollectionSnapshot {
            func stream(_ table: String) throws -> CollectionStreamSnapshot {
                // Table names are the fixed literals below; device/time values are always bound.
                let row = try Row.fetchOne(db, sql:
                    "SELECT COUNT(*) AS n, MAX(ts) AS latest FROM \(table) WHERE deviceId = ? AND ts >= ? AND ts <= ?",
                    arguments: [deviceId, from, to])!
                return CollectionStreamSnapshot(count: row["n"], latestTs: row["latest"])
            }
            let predicate = rrWindowSourcePredicate(strictWhoop5: try isWhoop5RRSource(db: db, deviceId: deviceId))
            let usable = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS n, MAX(ts) AS latest FROM rrInterval
                WHERE deviceId = :d AND ts >= :f AND ts <= :t
                  AND (srcChannel IS NULL OR srcChannel <> :rrx)
                  AND \(predicate) AND (tsSuspect IS NULL OR tsSuspect <> 1)
                """, arguments: ["d": deviceId, "f": from, "t": to, "rrx": RRSourceChannel.spo2Ibi.rawValue])!
            return try WhoopCollectionSnapshot(deviceId: deviceId, fromTs: from, toTs: to,
                heartRate: stream("hrSample"), rr: stream("rrInterval"),
                scorableRR: CollectionStreamSnapshot(count: usable["n"], latestTs: usable["latest"]),
                opticalEstimates: stream("ppgHrSample"), steps: stream("stepSample"))
    }

    /// The Today chart uses measured rows only, so optical estimates never acquire a measured label.
    public func measuredHeartRateSamples(deviceId: String, from: Int, to: Int, limit: Int = 200_000) async throws -> [HRSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT ts, bpm FROM hrSample WHERE deviceId = ? AND ts >= ? AND ts <= ? ORDER BY ts ASC LIMIT ?",
                            arguments: [deviceId, from, to, limit])
                .map { HRSample(ts: $0["ts"], bpm: $0["bpm"]) }
        }
    }
}
