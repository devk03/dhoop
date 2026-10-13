import Foundation
import StrandAnalytics
import WhoopProtocol

struct DhoopAlarmDefinition: Codable, Equatable, Identifiable {
    var id = UUID().uuidString.lowercased()
    var label = "Wake up"
    var enabled = true
    var rule = AlarmScheduleRule(minute: 7 * 60)
    var revision = 1
    var deleted = false
    var phoneBackup = false
    var valid: Bool {
        UUID(uuidString: id) != nil && !label.isEmpty && label.count <= 100 && rule.valid && revision > 0
    }
}

struct DhoopAlarmSlot: Codable, Equatable, Identifiable {
    var id: String { "\(deviceID)|\(slot)" }
    let deviceID: String
    let slot: Int
    /// Last exact record the owner approved, or Dhoop verified after its write.
    var expected: Whoop5AlarmRecord
    var originalRecord: Whoop5AlarmRecord?
    var definitionIDs: [String] = []
    var verifiedAt: Date?
    /// Committed before a SET. A later read resolves partial writes/crashes, never a blind resend.
    var pendingRecord: Whoop5AlarmRecord?
    var pendingDefinitionIDs: [String] = []
    var removalRequested = false
    var detail = "Slot use approved; no alarm scheduled"
}

struct DhoopAlarmHistory: Codable, Equatable, Identifiable {
    var id = UUID().uuidString.lowercased()
    let at: Date
    let deviceID: String
    let slot: Int?
    let epoch: Int?
    let message: String
}

struct DhoopAlarmState: Codable, Equatable {
    var version = 1
    var legacyImported = false
    var definitions: [DhoopAlarmDefinition] = []
    var slots: [DhoopAlarmSlot] = []
    var history: [DhoopAlarmHistory] = []
    var valid: Bool {
        version == 1 && definitions.count <= 100 && definitions.allSatisfy(\.valid)
            && Set(definitions.map(\.id)).count == definitions.count
            && Set(slots.map(\.id)).count == slots.count
            && slots.allSatisfy { !$0.deviceID.isEmpty && (1...6).contains($0.slot)
                && $0.expected.slot == $0.slot && Whoop5AlarmRecord(payload: $0.expected.bytes, slot: $0.slot) != nil
                && ($0.pendingRecord == nil || ($0.pendingRecord?.slot == $0.slot
                    && Whoop5AlarmRecord(payload: $0.pendingRecord!.bytes, slot: $0.slot) != nil)) }
            && history.count <= 512
    }
}

/// Personal Apple alarm state, independent of the health DB and .noopbak schema.
/// Android shares protocol/planner contracts; this new device-ownership file is Apple-only.
struct DhoopAlarmFile {
    let url: URL
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dhoop/Alarms/state-v1.json")) { self.url = url }
    func read() throws -> DhoopAlarmState {
        do {
            let state = try JSONDecoder().decode(DhoopAlarmState.self, from: Data(contentsOf: url))
            guard state.valid else { throw CocoaError(.fileReadCorruptFile) }
            return state
        } catch CocoaError.fileReadNoSuchFile { return DhoopAlarmState() }
    }
    func save(_ state: DhoopAlarmState) throws {
        guard state.valid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(state)
        #if os(iOS)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
    }
}
