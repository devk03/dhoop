import Foundation

/// An omitted patch preserves an existing observation; null deliberately clears an import-owned field.
enum WorkoutObservationPatch<Value: Equatable>: Equatable {
    case unchanged, clear, value(Value)
}

enum WorkoutObservationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let field) = self { return "Workout sync cannot accept \(field). Local entries are kept." }
        return nil
    }
}

struct WorkoutEnteredLoad: Codable, Equatable {
    enum Unit: String, Codable { case kg, lb }
    var value: String
    var unit: Unit
}

struct WorkoutObservedHeartRate: Codable, Equatable {
    var sampleCount: Int
    var coverageFraction: Double?
    var averageBpm: Double?
    var maximumBpm: Double?

    enum CodingKeys: String, CodingKey { case sampleCount, coverageFraction, averageBpm, maximumBpm }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sampleCount, forKey: .sampleCount)
        // These nullable fields are required by the receiver; they are not optional patch keys.
        try c.encode(coverageFraction, forKey: .coverageFraction)
        try c.encode(averageBpm, forKey: .averageBpm)
        try c.encode(maximumBpm, forKey: .maximumBpm)
    }
    func validate() throws {
        guard sampleCount >= 0,
              coverageFraction.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              averageBpm.map({ $0.isFinite && (0...300).contains($0) }) ?? true,
              maximumBpm.map({ $0.isFinite && (0...300).contains($0) }) ?? true,
              sampleCount > 0 || (averageBpm == nil && maximumBpm == nil) else {
            throw WorkoutObservationError.invalid("heart-rate evidence")
        }
    }
}

/// Only explicit observations are encoded. Constructing a set never fills it from a prescription.
struct WorkoutSetObservation: Encodable, Equatable {
    enum SetType: String, Encodable { case warmup, work }
    enum LoadBasis: String, Encodable { case total, perHand = "per_hand", added, none }
    var sourceSetId: UUID
    var setType: SetType
    var loadBasis: LoadBasis
    var lifeSetId: WorkoutObservationPatch<Int> = .unchanged
    var completed: Bool?
    var loadKg: WorkoutObservationPatch<Double> = .unchanged
    var reps: WorkoutObservationPatch<Int> = .unchanged
    var enteredLoad: WorkoutObservationPatch<WorkoutEnteredLoad> = .unchanged
    var rpe: WorkoutObservationPatch<Double> = .unchanged
    var notes: WorkoutObservationPatch<String> = .unchanged
    var rir: WorkoutObservationPatch<Int> = .unchanged
    var startedAt: WorkoutObservationPatch<String> = .unchanged
    var endedAt: WorkoutObservationPatch<String> = .unchanged
    var measuredActiveSeconds: WorkoutObservationPatch<Double> = .unchanged
    var heartRateSummary: WorkoutObservationPatch<WorkoutObservedHeartRate> = .unchanged
    var supersetGroupId: WorkoutObservationPatch<UUID> = .unchanged
    var roundIndex: WorkoutObservationPatch<Int> = .unchanged
    var executionOrder: Int?

    enum CodingKeys: String, CodingKey {
        case sourceSetId, lifeSetId, setType, completed, loadKg, loadBasis, reps, enteredLoad
        case rpe, notes, rir, startedAt, endedAt, measuredActiveSeconds, heartRateSummary
        case supersetGroupId, roundIndex, executionOrder
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceSetId.uuidString.lowercased(), forKey: .sourceSetId)
        try c.encode(setType, forKey: .setType)
        try c.encode(loadBasis, forKey: .loadBasis)
        try c.encodeIfPresent(completed, forKey: .completed)
        try c.encodePatch(lifeSetId, forKey: .lifeSetId)
        try c.encodePatch(loadKg, forKey: .loadKg)
        try c.encodePatch(reps, forKey: .reps)
        try c.encodePatch(enteredLoad, forKey: .enteredLoad)
        try c.encodePatch(rpe, forKey: .rpe)
        try c.encodePatch(notes, forKey: .notes)
        try c.encodePatch(rir, forKey: .rir)
        try c.encodePatch(startedAt, forKey: .startedAt)
        try c.encodePatch(endedAt, forKey: .endedAt)
        try c.encodePatch(measuredActiveSeconds, forKey: .measuredActiveSeconds)
        try c.encodePatch(heartRateSummary, forKey: .heartRateSummary)
        switch supersetGroupId {
        case .unchanged: break
        case .clear: try c.encodeNil(forKey: .supersetGroupId)
        case .value(let id): try c.encode(id.uuidString.lowercased(), forKey: .supersetGroupId)
        }
        try c.encodePatch(roundIndex, forKey: .roundIndex)
        try c.encodeIfPresent(executionOrder, forKey: .executionOrder)
    }

    func validate() throws {
        if case .value(let id) = lifeSetId, id <= 0 || id > 9_007_199_254_740_991 { throw WorkoutObservationError.invalid("set binding") }
        if case .value(let kg) = loadKg, !kg.isFinite || !(0...2267).contains(kg) || loadBasis == .none {
            throw WorkoutObservationError.invalid("load")
        }
        if case .value(let count) = reps, !(0...100).contains(count) { throw WorkoutObservationError.invalid("rep count") }
        if case .value(let rating) = rpe, !rating.isFinite || !(0...10).contains(rating) { throw WorkoutObservationError.invalid("RPE") }
        if case .value(let notes) = notes, notes.utf16.count > 2000 { throw WorkoutObservationError.invalid("set notes") }
        if case .value(let rating) = rir, !(0...5).contains(rating) { throw WorkoutObservationError.invalid("RIR") }
        if case .value(let round) = roundIndex, !(0...199).contains(round) { throw WorkoutObservationError.invalid("superset round") }
        if let executionOrder, !(0...1000).contains(executionOrder) { throw WorkoutObservationError.invalid("set execution order") }
        if case .value(let duration) = measuredActiveSeconds, !duration.isFinite || !(0...86400).contains(duration) {
            throw WorkoutObservationError.invalid("active duration")
        }
        let start = try timestamp(startedAt), end = try timestamp(endedAt)
        if let start, let end {
            guard end >= start else { throw WorkoutObservationError.invalid("set timestamps") }
            if case .value(let duration) = measuredActiveSeconds, duration > end.timeIntervalSince(start) {
                throw WorkoutObservationError.invalid("active duration")
            }
        }
        if case .value(let summary) = heartRateSummary { try summary.validate() }
        if case .value(let entered) = enteredLoad {
            guard loadBasis != .none,
                  entered.value.range(of: #"^\d+(\.\d{1,12})?$"#, options: .regularExpression) != nil,
                  let numeric = Double(entered.value), numeric.isFinite else { throw WorkoutObservationError.invalid("entered load") }
            if case .value(let kg) = loadKg {
                let converted = entered.unit == .lb ? numeric * 0.45359237 : numeric
                guard abs(converted - kg) <= 1e-8 else { throw WorkoutObservationError.invalid("load units") }
            }
        }
    }

    private func timestamp(_ patch: WorkoutObservationPatch<String>) throws -> Date? {
        guard case .value(let value) = patch else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw WorkoutObservationError.invalid("set timestamp") }
        return date
    }
}

private extension KeyedEncodingContainer {
    mutating func encodePatch<Value: Encodable & Equatable>(_ patch: WorkoutObservationPatch<Value>, forKey key: Key) throws {
        switch patch {
        case .unchanged: break
        case .clear: try encodeNil(forKey: key)
        case .value(let value): try encode(value, forKey: key)
        }
    }
}
