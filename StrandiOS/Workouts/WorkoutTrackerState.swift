import Foundation

struct WorkoutTrackerState: Codable, Equatable {
    enum CachedPlanBlock: String, Codable {
        case inconsistent, unavailable, invalid
        var message: String {
            switch self {
            case .inconsistent: return "Life reported an inconsistent prescription. Review it there and read it again before starting."
            case .unavailable: return "The original tracker target is unavailable. Its cached plan cannot start another capture."
            case .invalid: return "The latest plan could not be validated. Read a valid plan before starting this cached routine."
            }
        }
    }
    var version = 1
    var enabled = false
    var origin: String?
    var installationId: UUID?
    var index: WorkoutTrackerIndex?
    var manifests: [String: WorkoutTrackerManifest] = [:]
    var manifestReadAt: [String: Date] = [:]
    var cachedPlanBlocks: [String: CachedPlanBlock] = [:]
    var deliveries: [WorkoutTrackerDelivery] = []
    var legacyExerciseIdentities: [String: UUID] = [:]
    var archives: [String: WorkoutTrackerArchiveReference] = [:]
    var locallyKeptSources: Set<UUID> = []
    var capturedAt: Date?
    var message = "Workout tracker is off. Local strength tracking works without it."

    init() {}
    enum CodingKeys: String, CodingKey { case version, enabled, origin, installationId, index, manifests, manifestReadAt, cachedPlanBlocks, deliveries, legacyExerciseIdentities, archives, locallyKeptSources, capturedAt, message }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        installationId = try c.decodeIfPresent(UUID.self, forKey: .installationId)
        index = try c.decodeIfPresent(WorkoutTrackerIndex.self, forKey: .index)
        manifests = try c.decodeIfPresent([String: WorkoutTrackerManifest].self, forKey: .manifests) ?? [:]
        manifestReadAt = try c.decodeIfPresent([String: Date].self, forKey: .manifestReadAt) ?? [:]
        cachedPlanBlocks = try c.decodeIfPresent([String: CachedPlanBlock].self, forKey: .cachedPlanBlocks) ?? [:]
        deliveries = try c.decodeIfPresent([WorkoutTrackerDelivery].self, forKey: .deliveries) ?? []
        legacyExerciseIdentities = try c.decodeIfPresent([String: UUID].self, forKey: .legacyExerciseIdentities) ?? [:]
        archives = try c.decodeIfPresent([String: WorkoutTrackerArchiveReference].self, forKey: .archives) ?? [:]
        locallyKeptSources = try c.decodeIfPresent(Set<UUID>.self, forKey: .locallyKeptSources) ?? []
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? "Tracker state loaded"
    }

    func validate(maxDeliveries: Int = 200) throws {
        guard version == 1, manifests.count <= 1000, deliveries.count <= maxDeliveries, deliveries.allSatisfy(\.valid),
              manifestReadAt.count <= 1000, Set(manifestReadAt.keys).isSubset(of: Set(manifests.keys)),
              manifestReadAt.values.allSatisfy({ $0.timeIntervalSince1970.isFinite && (0...253402300799).contains($0.timeIntervalSince1970) }),
              cachedPlanBlocks.count <= 1000, cachedPlanBlocks.keys.allSatisfy({ Int($0).map({ $0 > 0 }) ?? false }),
              archives.count <= 20000, archives.allSatisfy({ $0.key == $0.value.id.uuidString.lowercased() && $0.value.valid }),
              locallyKeptSources.count <= 20000,
              legacyExerciseIdentities.count <= 2000, legacyExerciseIdentities.keys.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 1000 }),
              Set(deliveries.map(\.id)).count == deliveries.count,
              !enabled || (origin != nil && installationId != nil),
              origin == nil || installationId != nil else {
            throw WorkoutTrackerContractError.invalidSnapshot
        }
        if let origin { _ = try WorkoutSyncEndpoint.catalog.url(origin: origin) }
        try index?.validate()
        for (key, manifest) in manifests {
            try manifest.validate()
            guard key == String(manifest.sessionId) else { throw WorkoutTrackerContractError.invalidSnapshot }
        }
        for delivery in deliveries where delivery.bytes != nil { try delivery.validateBody() }
    }
}

/// Corrupt state is left in place. No reset silently loses bindings or implies successful delivery.
struct WorkoutTrackerFileStore {
    let url: URL
    func load() throws -> WorkoutTrackerState {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkoutTrackerState() }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        let state = try JSONDecoder().decode(WorkoutTrackerState.self, from: bytes)
        try state.validate()
        return state
    }
    func save(_ state: WorkoutTrackerState) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        guard data.count <= 8 * 1024 * 1024 else { throw WorkoutTrackerContractError.invalidSnapshot }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
