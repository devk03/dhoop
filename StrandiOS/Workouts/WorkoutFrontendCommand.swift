import Foundation

/// The canonical connection an editor was opened against; credentials never enter view state.
struct WorkoutFrontendScope: Equatable {
    let origin: String
    let installationId: UUID
}

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
    var sessionCompletion: Bool? = nil
    var sessionDateScheduling: Bool? = nil
    var sessionBatchSave: Bool? = nil
    var historicalSessionEditing: Bool? = nil
    var progressionPreferences: Bool? = nil
    var customExerciseSubstitution: Bool? = nil
    func validate() throws {
        guard schemaVersion == 1, lifeRevision >= 0, actions.count <= 30,
              Set(actions).count == actions.count, Set(actions).isSubset(of: Self.supportedActions)
        else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
    static let supportedActions: Set<String> = ["create_mesocycle", "restart_half_marathon_program", "create_four_lift_program",
        "update_athlete_profile", "recalculate_half_marathon_weights", "substitute_exercise", "update_set", "reset_mesocycle",
        "start_session", "update_session", "update_benchmarks", "tune_exercise", "update_progression_preferences"]
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

/// Reusable exercises share Life's catalog. Definitions are explicit and frozen with the command.
struct WorkoutCustomExerciseDefinition: Codable, Equatable {
    var name: String
    let movementPattern: String
    let loadMode: String
    let unit: String
    let increment: Double
    let repMin: Int
    let repMax: Int
    let notes: String
    static let loadModes = ["barbell", "machine", "dumbbell_each", "bodyweight_added", "bodyweight", "duration"]
    func normalized() throws -> Self {
        var value = self; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(value.name.utf16.count), (1...100).contains(movementPattern.utf16.count),
              Self.loadModes.contains(loadMode), unit == "lb", increment.isFinite, increment > 0, increment <= 500,
              (1...100).contains(repMin), (repMin...100).contains(repMax), notes.utf16.count <= 2000 else { throw Invalid() }
        return value
    }
    var value: WorkoutTrackerValue {
        .object(["name": .string(name), "movementPattern": .string(movementPattern), "loadMode": .string(loadMode),
                 "unit": .string(unit), "increment": .number(increment), "repMin": .number(Double(repMin)),
                 "repMax": .number(Double(repMax)), "notes": .string(notes)])
    }
    struct Invalid: LocalizedError {
        var errorDescription: String? { "Review the exercise name, load type, increment and rep range before saving." }
    }
    static func normalize(command: [String: WorkoutTrackerValue]) throws -> [String: WorkoutTrackerValue] {
        guard let value = command["replacementExercise"] else { return command }
        guard command["action"] == .string("substitute_exercise"),
              case .string(let key) = command["replacementExerciseKey"], key.hasPrefix("custom:"),
              let id = UUID(uuidString: String(key.dropFirst(7))), key == "custom:" + id.uuidString.lowercased() else { throw Invalid() }
        let data = try JSONEncoder().encode(value)
        let definition = try JSONDecoder().decode(Self.self, from: data).normalized()
        var result = command; result["replacementExercise"] = definition.value; return result
    }
}

/// An editable local form is separate from immutable submitted operations and canonical Life data.
struct WorkoutReplacementDraft: Codable, Equatable {
    let scope: WorkoutReplacementDraftScope
    var customKey = "custom:" + UUID().uuidString.lowercased()
    var custom = false
    var replacement = ""
    var name = ""
    var loadMode: String
    var increment: String
    var repMin: String
    var repMax: String
    var notes = ""
    var applied = false
    init(scope: WorkoutReplacementDraftScope, exercise: WorkoutTrackerDashboard.Exercise, library: [WorkoutTrackerDashboard.LibraryItem]) {
        self.scope = scope; loadMode = exercise.loadMode
        let original = library.first { $0.exerciseKey == exercise.exerciseKey }
        increment = (original?.increment ?? 5).formatted(.number.grouping(.never))
        repMin = String(original?.repMin ?? exercise.plannedReps)
        repMax = String(original?.repMax ?? max(exercise.plannedReps, 12))
    }
    func command(exercise: WorkoutTrackerDashboard.Exercise, library: [WorkoutTrackerDashboard.LibraryItem], locale: Locale = .current) throws -> [String: WorkoutTrackerValue] {
        var result: [String: WorkoutTrackerValue] = ["action": .string("substitute_exercise"),
            "mesocycleId": .number(Double(scope.programID)), "sessionId": .number(Double(scope.sessionID)),
            "sessionExerciseId": .number(Double(scope.exerciseID))]
        if custom {
            guard let step = try? Double(increment, format: .number.locale(locale)),
                  let low = Int(repMin), let high = Int(repMax) else { throw WorkoutCustomExerciseDefinition.Invalid() }
            result["replacementExerciseKey"] = .string(customKey)
            result["replacementExercise"] = try WorkoutCustomExerciseDefinition(name: name, movementPattern: exercise.movementPattern,
                loadMode: loadMode, unit: "lb", increment: step, repMin: low, repMax: high, notes: notes).normalized().value
        } else {
            guard library.contains(where: { $0.exerciseKey == replacement && $0.movementPattern == exercise.movementPattern && $0.exerciseKey != exercise.exerciseKey }) else { throw WorkoutCustomExerciseDefinition.Invalid() }
            result["replacementExerciseKey"] = .string(replacement)
        }
        return try WorkoutCustomExerciseDefinition.normalize(command: result)
    }
}
struct WorkoutReplacementDraftScope: Codable, Equatable {
    let origin: String
    let installationID: UUID
    let programID: Int
    let sessionID: Int
    let exerciseID: Int
}
struct WorkoutReplacementDraftStore {
    let url: URL
    func load(scope: WorkoutReplacementDraftScope) throws -> WorkoutReplacementDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 32768 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let result = try JSONDecoder().decode(WorkoutReplacementDraft.self, from: data)
        guard result.scope == scope else { throw WorkoutTrackerContractError.invalidSnapshot }
        return result
    }
    func save(_ draft: WorkoutReplacementDraft) throws {
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 32768 else { throw WorkoutTrackerContractError.invalidSnapshot }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
