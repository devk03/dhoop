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

    func discardDraft(id: UUID) throws {
        let url = directory.appendingPathComponent("active.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        if try JSONDecoder().decode(HIITSession?.self, from: data) == nil { return }
        let draft = try JSONDecoder().decode(HIITSession.self, from: data)
        guard draft.id == id else { throw CocoaError(.fileWriteFileExists) }
        try Data("null".utf8).write(to: url, options: .atomic)
    }

    /// Retire exactly one archive. A matching stale draft must not resurrect it on next launch.
    func deleteWorkout(at url: URL, id: UUID) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              url.lastPathComponent.hasPrefix("workout-"), url.pathExtension == "json" else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let run = try JSONDecoder().decode(HIITSession.self, from: Data(contentsOf: url))
        guard run.id == id else { throw CocoaError(.fileReadCorruptFile) }
        let draftURL = directory.appendingPathComponent("active.json")
        if FileManager.default.fileExists(atPath: draftURL.path) {
            let draft = try JSONDecoder().decode(HIITSession?.self, from: Data(contentsOf: draftURL))
            if draft?.id == id { try discardDraft(id: id) }
        }
        // Retain the original bytes outside the browsable archive, without deleting sensor history.
        let retired = directory.appendingPathComponent("Deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: retired.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
    }
}
