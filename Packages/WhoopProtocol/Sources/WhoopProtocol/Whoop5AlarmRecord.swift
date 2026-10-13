import Foundation

/// Revision-4 alarm facts from docs/PROTOCOL_ALARMS.md. Zero time is an ambiguous read,
/// not proof of a free slot. Motor execution and persistence require device verification.
public struct Whoop5AlarmRecord: Equatable, Codable, Sendable {
    public let bytes: [UInt8]
    public var slot: Int { Int(bytes[1]) }
    public var epoch: Int64 {
        (0..<4).reduce(Int64(0)) { $0 | (Int64(bytes[2 + $1]) << ($1 * 8)) }
    }
    public var isZeroTime: Bool { epoch == 0 }
    public var isClearedCandidate: Bool { bytes.dropFirst(2).allSatisfy { $0 == 0 } }

    public init?(payload: [UInt8], slot: Int) {
        guard (1...6).contains(slot), (21...24).contains(payload.count),
              payload[0] == 4, Int(payload[1]) == slot,
              payload.dropFirst(21).allSatisfy({ $0 == 0 }) else { return nil }
        let body = Array(payload.prefix(21))
        let ticks = Int(body[6]) | (Int(body[7]) << 8)
        guard ticks < 32768, body[8..<16].allSatisfy({ $0 <= 251 }),
              body[18] < 8, body[20] <= 1,
              body[18] != 7 || (30...120).contains(body[19]) else { return nil }
        bytes = body
    }

    private enum CodingKeys: String, CodingKey { case bytes }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([UInt8].self, forKey: .bytes)
        guard raw.count >= 2, let record = Self(payload: raw, slot: Int(raw[1])) else {
            throw DecodingError.dataCorruptedError(forKey: .bytes, in: container, debugDescription: "Invalid alarm record")
        }
        self = record
    }

    public static func standard(slot: Int, epoch: Int64) -> Self? {
        guard (1...6).contains(slot), epoch > 0, epoch <= Int64(UInt32.max) else { return nil }
        // The existing 20-byte body receives a zero crescendo byte from frame padding.
        return Self(payload: AlarmPayload.setAlarmRev4(wakeEpochMs: epoch * 1000,
                                                       alarmId: UInt8(slot)) + [0], slot: slot)
    }

    /// Restricts the existing reversible DISABLE opcode to one slot; never ID 255.
    public static func clearPayload(slot: Int) -> [UInt8]? {
        guard (1...6).contains(slot) else { return nil }
        return [2, UInt8(slot)]
    }
}
