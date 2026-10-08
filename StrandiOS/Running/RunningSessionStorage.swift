import Foundation

/// Preference-backed zone records. Mutations decode the current value before replacing it.
struct RunningSessionStorage {
    static let summariesKey = "dhoop.running.summaries.v1"
    static let draftKey = "dhoop.running.activeDraft.v1"
    struct Draft: Codable {
        var session: RunningZoneSession
        let elapsedSeconds: TimeInterval
    }
    let defaults: UserDefaults
    var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DhoopZoneRuns", isDirectory: true)

    func loadSummaries() throws -> [RunningSessionSummary] {
        var rows = try defaults.data(forKey: Self.summariesKey)
            .map { try JSONDecoder().decode([RunningSessionSummary].self, from: $0) } ?? []
        guard FileManager.default.fileExists(atPath: directory.path) else { return rows }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var retired = Set<UUID>()
        for file in files where file.lastPathComponent.hasPrefix("retired-") && file.pathExtension == "json" {
            let id = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file))
            guard file.lastPathComponent == "retired-\(id.uuidString).json" else { throw CocoaError(.fileReadCorruptFile) }
            retired.insert(id)
        }
        for file in files where file.lastPathComponent.hasPrefix("workout-") && file.pathExtension == "json" {
            let summary = try JSONDecoder().decode(RunningSessionSummary.self, from: Data(contentsOf: file))
            guard file.lastPathComponent == "workout-\(summary.id.uuidString).json" else { throw CocoaError(.fileReadCorruptFile) }
            if !retired.contains(summary.id), !rows.contains(where: { $0.id == summary.id }) { rows.append(summary) }
        }
        return rows.filter { !retired.contains($0.id) }.sorted { $0.startedAt > $1.startedAt }
    }

    func saveSummary(_ summary: RunningSessionSummary) throws -> [RunningSessionSummary] {
        var current = try loadSummaries()
        if current.contains(where: { $0.id == summary.id }) { return current }
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("retired-\(summary.id.uuidString).json").path)
        else { throw CocoaError(.fileWriteFileExists) }
        current.insert(summary, at: 0)
        // Validate/encode before changing either the history or its recoverable active draft.
        let data = try JSONEncoder().encode(current)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // UserDefaults is buffered. Retain a durable completed snapshot before clearing any draft.
        try JSONEncoder().encode(summary).write(to: directory.appendingPathComponent("workout-\(summary.id.uuidString).json"), options: .atomic)
        defaults.set(data, forKey: Self.summariesKey)
        return current
    }

    func deleteSummary(id: UUID) throws -> [RunningSessionSummary] {
        let current = try loadSummaries()
        let remaining = current.filter { $0.id != id }
        let data = try JSONEncoder().encode(remaining)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let original = current.first(where: { $0.id == id }) {
            let archive = directory.appendingPathComponent("workout-\(id.uuidString).json")
            if !FileManager.default.fileExists(atPath: archive.path) {
                try JSONEncoder().encode(original).write(to: archive, options: .atomic)
            }
        }
        // Retain the archive; this tombstone prevents a completed/deleted recording resurrecting.
        try JSONEncoder().encode(id).write(to: directory.appendingPathComponent("retired-\(id.uuidString).json"), options: .atomic)
        defaults.set(data, forKey: Self.summariesKey)
        return remaining
    }

    func discardDraft(id: UUID) throws {
        guard let data = defaults.data(forKey: Self.draftKey) else { return }
        let draft = try JSONDecoder().decode(Draft.self, from: data)
        guard draft.session.id == id else { throw CocoaError(.fileWriteFileExists) }
        defaults.removeObject(forKey: Self.draftKey)
    }
}
