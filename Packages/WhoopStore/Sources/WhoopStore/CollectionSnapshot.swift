import Foundation
import GRDB

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
    public let opticalEstimates: CollectionStreamSnapshot
    public let steps: CollectionStreamSnapshot
}

extension WhoopStore {
    /// One consistent read transaction, bound to the active registry id rather than merged/imported data.
    public func collectionSnapshot(deviceId: String, from: Int, to: Int) async throws -> WhoopCollectionSnapshot {
        try syncRead { db in
            func stream(_ table: String) throws -> CollectionStreamSnapshot {
                // Table names are the fixed literals below; device/time values are always bound.
                let row = try Row.fetchOne(db, sql:
                    "SELECT COUNT(*) AS n, MAX(ts) AS latest FROM \(table) WHERE deviceId = ? AND ts >= ? AND ts <= ?",
                    arguments: [deviceId, from, to])!
                return CollectionStreamSnapshot(count: row["n"], latestTs: row["latest"])
            }
            return try WhoopCollectionSnapshot(deviceId: deviceId, fromTs: from, toTs: to,
                heartRate: stream("hrSample"), rr: stream("rrInterval"),
                opticalEstimates: stream("ppgHrSample"), steps: stream("stepSample"))
        }
    }
}
