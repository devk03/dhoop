import Foundation

/// A completed workout becomes durable before its redundant active draft is cleared.
struct HIITWorkoutFiles {
    let directory: URL

    func save(_ workout: HIITSession) throws -> String? {
        let data = try JSONEncoder().encode(workout)
        let name = "workout-\(Int(workout.startedAt.timeIntervalSince1970))-\(workout.id.uuidString).json"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        do {
            try Data("null".utf8).write(to: directory.appendingPathComponent("active.json"), options: .atomic)
            return nil
        } catch {
            // Restoration ignores a draft whose UUID is already in the completed archive.
            // Cleanup failure must not leave that completed session resumable in memory.
            return error.localizedDescription
        }
    }
}
