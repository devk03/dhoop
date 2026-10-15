import Foundation

struct WorkoutFrontendIntent: Codable, Equatable {
    var schemaVersion = 1
    let operationId: UUID
    let expectedLifeRevision: Int
    let command: [String: WorkoutTrackerValue]
    private enum CodingKeys: String,CodingKey { case schemaVersion,operationId,expectedLifeRevision,command }
    func encode(to encoder:Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(schemaVersion,forKey:.schemaVersion)
        try c.encode(operationId.uuidString.lowercased(),forKey:.operationId)
        try c.encode(expectedLifeRevision,forKey:.expectedLifeRevision)
        try c.encode(command,forKey:.command)
    }
}

struct WorkoutFrontendReceipt: Codable, Equatable {
    enum State: String, Codable { case running, committed, rejected, uncertain, notObserved = "not_observed" }
    struct Result: Codable, Equatable {
        let mesocycleId: Int?
        let sessionId: Int?
        let setId: Int?
        let invalidate: String
    }
    let schemaVersion: Int
    let operationId: UUID
    let requestHash: String?
    let request: WorkoutFrontendIntent?
    let state: State
    let result: Result?
    let receiptLifeRevision: Int?
    let lifeRevision: Int

    func validate(for intent: WorkoutFrontendIntent, prior: WorkoutFrontendReceipt?) throws {
        guard schemaVersion == 1, operationId == intent.operationId, lifeRevision >= 0 else { throw WorkoutTrackerContractError.invalidSnapshot }
        if state == .notObserved {
            guard request == nil, requestHash == nil, result == nil else { throw WorkoutTrackerContractError.invalidSnapshot }
            return
        }
        guard request == intent, let hash = requestHash, hash.count == 64,
              hash.allSatisfy({ $0.isHexDigit }), receiptLifeRevision.map({ $0 >= intent.expectedLifeRevision }) ?? false,
              prior?.requestHash == nil || prior?.requestHash == hash,
              state != .committed || (result?.invalidate == "workout_tracker") else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}

struct WorkoutFrontendCapabilities: Codable, Equatable {
    let schemaVersion: Int
    let manualCommands: Bool
    let frontendStart: Bool
    let actions: [String]
    let lifeRevision: Int
    func validate() throws {
        guard schemaVersion == 1, lifeRevision >= 0, actions.count <= 30,
              Set(actions).count == actions.count, Set(actions).isSubset(of: Self.supportedActions)
        else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
    static let supportedActions: Set<String> = ["create_mesocycle", "restart_half_marathon_program", "create_four_lift_program",
        "update_athlete_profile", "recalculate_half_marathon_weights", "substitute_exercise", "update_set", "reset_mesocycle",
        "start_session", "update_session", "update_benchmarks", "tune_exercise"]
}

struct WorkoutFrontendOperation: Codable, Equatable, Identifiable {
    enum State: String, Codable { case prepared, sending, committed, rejected, uncertain, notObserved, cancelled }
    var id: UUID { intent.operationId }
    let intent: WorkoutFrontendIntent
    let bytes: Data
    let origin: String
    let installationId: UUID
    let createdAt: Date
    var state: State
    var receipt: WorkoutFrontendReceipt?
    var attemptedAt: Date?
    var unresolved: Bool { [.prepared,.sending,.uncertain,.notObserved].contains(state) }
}

struct WorkoutFrontendState: Codable {
    var version = 1
    var enabled = false
    var origin: String?
    var installationId: UUID?
    var capabilities: WorkoutFrontendCapabilities?
    var checkedAt: Date?
    var operations: [WorkoutFrontendOperation] = []
    func validate() throws {
        guard version == 1, operations.count <= 10000, Set(operations.map(\.id)).count == operations.count,
              operations.filter(\.unresolved).count <= 1,
              !enabled || (origin != nil && installationId != nil) else { throw WorkoutTrackerContractError.invalidSnapshot }
        try capabilities?.validate()
        for item in operations {
            guard item.bytes.count <= WorkoutSyncTransport.bodyLimit,
                  item.intent.schemaVersion == 1, item.intent.expectedLifeRevision >= 0,
                  item.intent.command["action"].flatMap({ if case .string(let value) = $0 { return value }; return nil }).map(WorkoutFrontendCapabilities.supportedActions.contains) == true,
                  try JSONDecoder().decode(WorkoutFrontendIntent.self, from: item.bytes) == item.intent
            else { throw WorkoutTrackerContractError.invalidSnapshot }
            _ = try WorkoutSyncEndpoint.frontendCommand.url(origin:item.origin)
            try item.receipt?.validate(for:item.intent,prior:nil)
            switch item.state {
            case .prepared, .cancelled:
                guard item.attemptedAt == nil, item.receipt == nil else { throw WorkoutTrackerContractError.invalidSnapshot }
            case .sending, .uncertain:
                guard item.attemptedAt != nil else { throw WorkoutTrackerContractError.invalidSnapshot }
            case .committed:
                guard item.attemptedAt != nil, item.receipt?.state == .committed else { throw WorkoutTrackerContractError.invalidSnapshot }
            case .rejected:
                guard item.attemptedAt != nil, item.receipt?.state == .rejected else { throw WorkoutTrackerContractError.invalidSnapshot }
            case .notObserved:
                guard item.attemptedAt != nil, item.receipt?.state == .notObserved else { throw WorkoutTrackerContractError.invalidSnapshot }
            }
        }
    }
}

struct WorkoutFrontendFileStore {
    let url: URL
    func load() throws -> WorkoutFrontendState {
        guard FileManager.default.fileExists(atPath:url.path) else { return WorkoutFrontendState() }
        let data = try Data(contentsOf:url)
        guard data.count <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let state = try JSONDecoder().decode(WorkoutFrontendState.self,from:data)
        try state.validate();return state
    }
    func save(_ state: WorkoutFrontendState) throws {
        try state.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(state)
        guard data.count <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
    }
}
