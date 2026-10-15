import Foundation

/// Observed phases only. An absent end remains unresolved, including after relaunch.
public struct LiftActivityInterval: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case work, rest, pause }
    public var sourceIntervalId: String
    public var kind: Kind
    public var sourceSetId: String?
    public var startedAt: Int
    public var endedAt: Int?

    public init(sourceIntervalId: String, kind: Kind, sourceSetId: String?, startedAt: Int, endedAt: Int?) {
        self.sourceIntervalId = sourceIntervalId
        self.kind = kind
        self.sourceSetId = sourceSetId
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum LiftActivityLedger {
    public enum Invalid: Error { case malformed, bounds, reference, overlap }
    public struct SessionBounds: Sendable {
        public var id: String
        public var deviceId: String
        public var startTs: Int
        public var endTs: Int?
        public init(id: String, deviceId: String, startTs: Int, endTs: Int?) {
            self.id = id; self.deviceId = deviceId; self.startTs = startTs; self.endTs = endTs
        }
    }
    public struct SetBounds: Sendable {
        public var id: String
        public var sessionId: String
        public var deviceId: String
        public var startTs: Int?
        public var endTs: Int?
        public init(id: String, sessionId: String, deviceId: String, startTs: Int?, endTs: Int?) {
            self.id = id; self.sessionId = sessionId; self.deviceId = deviceId; self.startTs = startTs; self.endTs = endTs
        }
    }
    public static let maximumIntervals = 512

    public static func decode(_ json: String) throws -> [LiftActivityInterval] {
        try JSONDecoder().decode([LiftActivityInterval].self, from: Data(json.utf8))
    }

    public static func encode(_ intervals: [LiftActivityInterval]) throws -> String {
        guard intervals.count <= maximumIntervals else { throw Invalid.malformed }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(intervals), as: UTF8.self)
    }

    /// Prior validated references survive set deletion, without contributing to current aggregates.
    public static func validate(_ intervals: [LiftActivityInterval], session: SessionBounds,
                                sets: [SetBounds], retainedSetIDs: Set<String> = []) throws {
        guard intervals.count <= maximumIntervals,
              Set(intervals.map(\.sourceIntervalId)).count == intervals.count,
              intervals.allSatisfy({ UUID(uuidString: $0.sourceIntervalId) != nil }) else { throw Invalid.malformed }
        let known = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for interval in intervals {
            guard interval.startedAt >= session.startTs,
                  session.endTs.map({ interval.startedAt <= $0 }) ?? true,
                  interval.endedAt.map({ $0 >= interval.startedAt }) ?? true
            else { throw Invalid.bounds }
            if let end = interval.endedAt, let sessionEnd = session.endTs, end > sessionEnd { throw Invalid.bounds }
            if interval.kind == .work && interval.sourceSetId == nil { throw Invalid.reference }
            if let id = interval.sourceSetId {
                guard let set = known[id] else {
                    if retainedSetIDs.contains(id) { continue }
                    throw Invalid.reference
                }
                guard set.sessionId == session.id, set.deviceId == session.deviceId else { throw Invalid.reference }
                if interval.kind != .rest {
                    guard set.startTs.map({ interval.startedAt >= $0 }) ?? true,
                          set.endTs.map({ interval.startedAt <= $0 }) ?? true else { throw Invalid.bounds }
                    if let end = interval.endedAt, let setEnd = set.endTs, end > setEnd { throw Invalid.bounds }
                }
            }
        }
        let closed = intervals.filter { ($0.endedAt ?? $0.startedAt) > $0.startedAt }.sorted { $0.startedAt < $1.startedAt }
        for pair in zip(closed, closed.dropFirst()) {
            if pair.0.endedAt! > pair.1.startedAt { throw Invalid.overlap }
        }
    }

    /// Half-open confirmed work ranges. Missing ends and deleted sets cannot manufacture work time.
    public static func workWindows(_ intervals: [LiftActivityInterval], setID: String) -> [Range<Int>] {
        intervals.compactMap {
            guard $0.kind == .work, $0.sourceSetId == setID, let end = $0.endedAt, end > $0.startedAt else { return nil }
            return $0.startedAt..<end
        }.sorted { $0.lowerBound < $1.lowerBound }
    }
}
