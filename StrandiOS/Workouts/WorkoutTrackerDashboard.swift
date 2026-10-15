import Foundation

/// Canonical website state. This is a dated cache, not a second workout database.
struct WorkoutTrackerDashboard: Codable, Equatable {
    struct Pagination: Codable, Equatable {
        let cursor: Int
        let limit: Int
        let totalSessions: Int
        let nextCursor: Int?
    }
    struct Capabilities: Codable, Equatable {
        let manualCommands: Bool
        let frontendStart: Bool
    }
    struct Cycle: Codable, Equatable, Identifiable {
        let id: Int
        let name: String
        let startDate: String
        let durationWeeks: Int
        let status: String
        let goals: [String: WorkoutTrackerValue]
        let config: [String: WorkoutTrackerValue]
        let createdAt: String
        let updatedAt: String
    }
    struct SetLog: Codable, Equatable, Identifiable {
        let id: Int
        let setNumber: Int
        let setType: String
        let plannedLoad: Double
        let plannedReps: Int
        let actualLoad: Double?
        let actualReps: Int?
        let rir: Double?
        let completed: Bool
    }
    struct Exercise: Codable, Equatable, Identifiable {
        let id: Int
        let exerciseKey: String
        let name: String
        let orderIndex: Int
        let loadMode: String
        let progressionType: String
        let plannedSets: Int
        let plannedReps: Int
        let plannedLoad: Double
        let targetRir: Double
        let notes: String
        let slotKey: String
        let movementPattern: String
        let originalExerciseKey: String
        let originalExerciseName: String
        let isPriming: Bool
        let sets: [SetLog]
    }
    struct Finisher: Codable, Equatable {
        let id: Int
        let title: String
        let kind: String
        let status: String
        let metrics: [String: WorkoutTrackerValue]
    }
    struct Session: Codable, Equatable, Identifiable {
        let id: Int
        let mesocycleId: Int
        let weekNumber: Int
        let sessionKey: String
        let kind: String
        let title: String
        let scheduledDate: String
        let orderIndex: Int
        let status: String
        let readiness: String
        let rating: String
        let notes: String
        let metrics: [String: WorkoutTrackerValue]
        let sheetItemId: String
        let linkedSessionId: Int?
        let completedAt: String
        let exercises: [Exercise]
        let finisher: Finisher?
    }
    struct Benchmark: Codable, Equatable, Identifiable {
        let id: Int
        let mesocycleId: Int
        let exerciseKey: String
        let name: String
        let loadMode: String
        let unit: String
        let increment: Double
        let seedLoad: Double
        let seedReps: Int
        let seedRir: Double
        let estimatedMax: Double
        let effectiveMax: Double
        let isPrimary: Bool
        let config: [String: WorkoutTrackerValue]
    }
    struct LibraryItem: Codable, Equatable, Identifiable {
        var id: String { exerciseKey }
        let exerciseKey: String
        let name: String
        let movementPattern: String
        let loadMode: String
        let unit: String
        let increment: Double
        let repMin: Int
        let repMax: Int
        let notes: String
    }
    struct Season: Codable, Equatable, Identifiable {
        let id: Int
        let mesocycleId: Int
        let sportKey: String
        let name: String
        let startsOn: String
        let plannedEvents: Int
        let completedEvents: Int
        let status: String
        let config: [String: WorkoutTrackerValue]
    }
    struct Dashboard: Codable, Equatable {
        let lifeRevision: Int?
        let mesocycles: [Cycle]
        let activeMesocycle: Cycle?
        let benchmarks: [Benchmark]
        var sessions: [Session]
        let exerciseLibrary: [LibraryItem]
        let sportSeasons: [Season]
    }
    let schemaVersion: Int
    let lifeRevision: Int
    var dashboard: Dashboard
    var pagination: Pagination
    let capabilities: Capabilities

    func validate() throws {
        guard schemaVersion == 1, lifeRevision >= 0,
              dashboard.lifeRevision == nil || dashboard.lifeRevision == lifeRevision,
              pagination.cursor >= 0, (1...25).contains(pagination.limit), pagination.totalSessions >= 0,
              dashboard.sessions.count <= pagination.limit,
              pagination.cursor <= pagination.totalSessions,
              dashboard.sessions.count <= pagination.totalSessions - pagination.cursor,
              pagination.nextCursor.map({ $0 > pagination.cursor && $0 == pagination.cursor + dashboard.sessions.count && $0 < pagination.totalSessions }) ?? true,
              (pagination.cursor + dashboard.sessions.count < pagination.totalSessions) == (pagination.nextCursor != nil),
              dashboard.mesocycles.count <= 1000, dashboard.exerciseLibrary.count <= 2000,
              dashboard.benchmarks.count <= 1000, dashboard.sportSeasons.count <= 1000,
              Set(dashboard.sessions.map(\.id)).count == dashboard.sessions.count,
              Set(dashboard.mesocycles.map(\.id)).count == dashboard.mesocycles.count,
              Set(dashboard.exerciseLibrary.map(\.exerciseKey)).count == dashboard.exerciseLibrary.count,
              dashboard.mesocycles.allSatisfy({ $0.id > 0 }),
              dashboard.activeMesocycle.map({ cycle in dashboard.mesocycles.contains { $0.id == cycle.id } }) ?? dashboard.sessions.isEmpty
        else { throw WorkoutTrackerContractError.invalidSnapshot }
        for session in dashboard.sessions {
            guard session.id > 0, session.mesocycleId == dashboard.activeMesocycle?.id,
                  session.exercises.count <= 200, Set(session.exercises.map(\.id)).count == session.exercises.count,
                  session.exercises.allSatisfy({ exercise in exercise.id > 0 && exercise.sets.count <= 200 &&
                      Set(exercise.sets.map(\.id)).count == exercise.sets.count && exercise.sets.allSatisfy { $0.id > 0 && $0.setNumber > 0 } })
            else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
    }
}

/// Unknown server config/metric keys are retained without making native copies of website policy.
indirect enum WorkoutTrackerValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([Self]), object([String: Self])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([Self].self) { self = .array(value) }
        else { self = .object(try c.decode([String:Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
