import Foundation

/// A navigation bookmark, scoped to the Life connection. It never stores workout results or status.
struct WorkoutLastOpened: Codable, Equatable, Identifiable {
    static let storageKey = "dhoop.workout.lastOpened.v1"
    let origin: String
    let installationId: UUID
    let mesocycleId: Int
    let sessionId: Int
    var id: String { "\(installationId.uuidString)-\(mesocycleId)-\(sessionId)" }

    var storageValue: String? {
        guard valid, let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func resolve(_ value: String, origin: String?, installationId: UUID?, enabled: Bool) -> Self? {
        guard enabled, value.utf8.count <= 2048, let data = value.data(using: .utf8),
              let record = try? JSONDecoder().decode(Self.self, from: data), record.valid,
              record.origin == origin, record.installationId == installationId else { return nil }
        return record
    }
    private var valid: Bool { !origin.isEmpty && origin.utf8.count <= 512 && mesocycleId > 0 && sessionId > 0 }
}
