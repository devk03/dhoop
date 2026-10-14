import Foundation

struct WorkoutTrackerArchiveReference: Codable, Equatable, Identifiable {
    let id: UUID
    let fileId: UUID
    let sourceWorkoutId: UUID
    let revision: Int
    let startedAt: Int
    let title: String?
    let status: WorkoutTrackerDelivery.Status
    let paused: Bool?
    let createdAt: Date?
    var valid: Bool { revision > 0 && revision <= 9_007_199_254_740_991 }
    init(delivery: WorkoutTrackerDelivery, fileId: UUID) {
        id = delivery.id; self.fileId = fileId; sourceWorkoutId = delivery.sourceWorkoutId; revision = delivery.revision
        startedAt = delivery.record.startTs; title = delivery.record.programName; status = delivery.status; paused = delivery.paused; createdAt = delivery.createdAt
    }
}

extension WorkoutTrackerFileStore {
    var archiveDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("archive", isDirectory: true) }
    func archiveURL(_ fileId: UUID) -> URL { archiveDirectory.appendingPathComponent(fileId.uuidString.lowercased() + ".json") }
    func archived(_ reference: WorkoutTrackerArchiveReference) throws -> WorkoutTrackerDelivery {
        let file = archiveURL(reference.fileId)
        let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true,
              (metadata.fileSize ?? Int.max) <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let delivery = try JSONDecoder().decode(WorkoutTrackerDelivery.self, from: bytes)
        guard delivery.valid, WorkoutTrackerArchiveReference(delivery: delivery, fileId: reference.fileId) == reference else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        if delivery.bytes != nil { try delivery.validateBody() }
        return delivery
    }
    /// Copies completed intents before updating their index. Existing snapshots are never removed.
    func compact(_ input: WorkoutTrackerState, protecting sources: Set<UUID>) throws -> WorkoutTrackerState {
        try input.validate(maxDeliveries: 1000)
        var next = input
        let encoder = JSONEncoder()
        func needsCompaction() throws -> Bool {
            if next.deliveries.count > 80 { return true }
            return try encoder.encode(next).count > 4 * 1024 * 1024
        }
        while try needsCompaction() {
            guard let index = next.deliveries.indices.first(where: {
                next.deliveries[$0].canArchive && !sources.contains(next.deliveries[$0].sourceWorkoutId)
            }) else { break }
            let delivery = next.deliveries[index], fileId = UUID()
            let bytes = try encoder.encode(delivery)
            guard bytes.count <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            try bytes.write(to: archiveURL(fileId), options: .atomic)
            let reference = WorkoutTrackerArchiveReference(delivery: delivery, fileId: fileId)
            // Read back the full immutable intent before retiring its in-memory copy.
            guard try archived(reference) == delivery else { throw WorkoutTrackerContractError.invalidSnapshot }
            next.archives[delivery.id.uuidString.lowercased()] = reference
            next.deliveries.remove(at: index)
        }
        try next.validate()
        return next
    }
}
