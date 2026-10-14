import Foundation

struct WorkoutTrackerBackupManifest: Codable {
    var version = 1
    let createdAt: Date
    var state: WorkoutTrackerState
    let archiveFiles: [UUID]
    func validate() throws {
        guard version == 1, archiveFiles.count <= 50000, Set(archiveFiles).count == archiveFiles.count,
              Set(state.archives.values.map(\.fileId)).isSubset(of: Set(archiveFiles)) else { throw WorkoutTrackerContractError.invalidSnapshot }
        try state.validate()
    }
}

extension WorkoutTrackerFileStore {
    func backupManifest(at package: URL) throws -> WorkoutTrackerBackupManifest {
        let file = package.appendingPathComponent("manifest.json")
        let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true, (metadata.fileSize ?? Int.max) <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let manifest = try JSONDecoder().decode(WorkoutTrackerBackupManifest.self, from: Data(contentsOf: file))
        try manifest.validate(); return manifest
    }
    private func snapshot(fileId: UUID, directory: URL) throws -> WorkoutTrackerDelivery {
        let file = directory.appendingPathComponent(fileId.uuidString.lowercased() + ".json")
        let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true, (metadata.fileSize ?? Int.max) <= 8 * 1024 * 1024 else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        let value = try JSONDecoder().decode(WorkoutTrackerDelivery.self, from: Data(contentsOf: file))
        guard value.valid else { throw WorkoutTrackerContractError.invalidSnapshot }
        if value.bytes != nil { try value.validateBody() }
        return value
    }

    /// File copies keep package preparation bounded in memory. The source folder is never modified.
    func prepareBackup(state: WorkoutTrackerState, destination: URL) throws {
        try state.validate()
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw WorkoutTrackerContractError.backupConflict }
        var safe = state; safe.enabled = false
        safe.message = "Restored metadata stays offline until explicitly configured and enabled."
        var files: [UUID] = []
        if FileManager.default.fileExists(atPath: archiveDirectory.path) {
            guard try archiveDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw WorkoutTrackerContractError.invalidSnapshot }
            for file in try FileManager.default.contentsOfDirectory(at: archiveDirectory, includingPropertiesForKeys: nil) where !file.lastPathComponent.hasPrefix(".") {
                guard file.pathExtension == "json", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { throw WorkoutTrackerContractError.invalidSnapshot }
                _ = try snapshot(fileId: id, directory: archiveDirectory)
                files.append(id)
            }
        }
        let manifest = WorkoutTrackerBackupManifest(createdAt: Date(), state: safe, archiveFiles: files.sorted { $0.uuidString < $1.uuidString })
        try manifest.validate()
        for reference in state.archives.values { _ = try archived(reference) }
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("archive", isDirectory: true), withIntermediateDirectories: true)
        for id in files { try FileManager.default.copyItem(at: archiveURL(id), to: destination.appendingPathComponent("archive/" + id.uuidString.lowercased() + ".json")) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// All identifiers/conflicts are checked before copying or changing the current manifest.
    func mergedBackup(from package: URL, current: WorkoutTrackerState) throws -> WorkoutTrackerState {
        guard try package.appendingPathComponent("archive").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw WorkoutTrackerContractError.invalidSnapshot }
        let manifest = try backupManifest(at: package)
        try current.validate()
        let incomingDirectory = package.appendingPathComponent("archive", isDirectory: true)
        func incoming(_ reference: WorkoutTrackerArchiveReference) throws -> WorkoutTrackerDelivery {
            let value = try snapshot(fileId: reference.fileId, directory: incomingDirectory)
            guard WorkoutTrackerArchiveReference(delivery: value, fileId: reference.fileId) == reference else { throw WorkoutTrackerContractError.invalidSnapshot }
            return value
        }
        // Validate every included snapshot, including older versions retained as provenance.
        for id in manifest.archiveFiles {
            let value = try snapshot(fileId: id, directory: incomingDirectory)
            if FileManager.default.fileExists(atPath: archiveURL(id).path), try snapshot(fileId: id, directory: archiveDirectory) != value {
                throw WorkoutTrackerContractError.backupConflict
            }
        }
        for reference in manifest.state.archives.values { _ = try incoming(reference) }
        let activeByID = Dictionary(uniqueKeysWithValues: current.deliveries.map { ($0.id, $0) })
        func local(_ id: UUID) throws -> WorkoutTrackerDelivery? {
            if let value = activeByID[id] { return value }
            if let reference = current.archives[id.uuidString.lowercased()] { return try archived(reference) }
            return nil
        }
        for value in manifest.state.deliveries {
            if let existing = try local(value.id), !existing.sameIntent(as: value) { throw WorkoutTrackerContractError.backupConflict }
        }
        for reference in manifest.state.archives.values {
            if let existing = try local(reference.id), !existing.sameIntent(as: try incoming(reference)) { throw WorkoutTrackerContractError.backupConflict }
        }
        var next = current
        for (key, value) in manifest.state.legacyExerciseIdentities {
            if let existing = next.legacyExerciseIdentities[key], existing != value { throw WorkoutTrackerContractError.backupConflict }
            next.legacyExerciseIdentities[key] = value
        }
        // A backup's "not attempted" fact only describes its creation time. The original app
        // may have submitted later. Restored unaccepted intents must recover their receipt first.
        func restored(_ value: WorkoutTrackerDelivery) -> WorkoutTrackerDelivery {
            var copy = value
            if copy.status != .accepted, copy.submissionAttempted == false { copy.submissionAttempted = nil }
            return copy
        }
        var restoredArchives: [(UUID, WorkoutTrackerDelivery)] = []
        for value in manifest.state.deliveries where try local(value.id) == nil { next.deliveries.append(restored(value)) }
        for (key, reference) in manifest.state.archives where try local(reference.id) == nil {
            let original = try incoming(reference), copy = restored(original)
            if copy != original {
                let fileId = UUID()
                next.archives[key] = WorkoutTrackerArchiveReference(delivery: copy, fileId: fileId)
                restoredArchives.append((fileId, copy))
            } else { next.archives[key] = reference }
        }
        next.locallyKeptSources.formUnion(manifest.state.locallyKeptSources)
        next.locallyKeptSources.formUnion(manifest.state.deliveries.filter { $0.paused == true }.map(\.sourceWorkoutId))
        next.locallyKeptSources.formUnion(manifest.state.archives.values.filter { $0.paused == true }.map(\.sourceWorkoutId))
        if next.origin == nil && next.installationId == nil {
            next.origin = manifest.state.origin; next.installationId = manifest.state.installationId
        }
        // Cached plans are only reused within the same reviewed connection; existing snapshots win.
        if next.origin == manifest.state.origin && next.installationId == manifest.state.installationId {
            for (key, value) in manifest.state.manifests where next.manifests[key] == nil {
                next.manifests[key] = value
                next.manifestReadAt[key] = manifest.state.manifestReadAt[key]
                next.cachedPlanBlocks[key] = manifest.state.cachedPlanBlocks[key]
            }
        }
        next.enabled = false
        next.message = "Metadata merged. Tracker remains off; SQLite workouts and credentials were not changed."
        try next.validate(maxDeliveries: 1000)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        for id in manifest.archiveFiles where !FileManager.default.fileExists(atPath: archiveURL(id).path) {
            try FileManager.default.copyItem(at: incomingDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json"), to: archiveURL(id))
        }
        for (id, value) in restoredArchives {
            try JSONEncoder().encode(value).write(to: archiveURL(id), options: .atomic)
            guard try archived(WorkoutTrackerArchiveReference(delivery: value, fileId: id)) == value else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
        return next
    }
}
