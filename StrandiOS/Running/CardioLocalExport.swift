import Foundation

/// Portable copy of local Cardio records omitted by the cross-platform database backup.
struct CardioLocalExport: Codable, Sendable {
    let formatVersion: Int
    let createdAt: Date
    let runningSummaries: Data?
    let runningDraft: Data?
    let intervalFiles: [String: Data]

    static func capture(defaults: UserDefaults = .standard, directory: URL, now: Date = Date()) throws -> Self {
        var files: [String: Data] = [:]
        if FileManager.default.fileExists(atPath: directory.path) {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.lastPathComponent == "active.json" || (url.lastPathComponent.hasPrefix("workout-") && url.pathExtension == "json") {
                // Preserve the original bytes, including a damaged record, rather than silently skipping it.
                files[url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return Self(formatVersion: 1, createdAt: now,
            runningSummaries: defaults.data(forKey: "dhoop.running.summaries.v1"),
            runningDraft: defaults.data(forKey: "dhoop.running.activeDraft.v1"), intervalFiles: files)
    }

    @MainActor static func writeCopy() async throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DhoopHIIT", isDirectory: true)
        let archive = try capture(directory: directory)
        // Controllers commit on MainActor. Capture every input before yielding, so finishing a
        // session cannot clear a draft between enumeration and capture of its completed record.
        return try await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dhoop-Cardio-\(UUID().uuidString).json")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(archive).write(to: url, options: .atomic)
            return url
        }.value
    }
}
