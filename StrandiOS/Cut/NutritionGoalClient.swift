import Foundation
import Combine

/// Read-backed Life goal state. Only explicit owner actions write; failed writes never queue.
@MainActor
final class NutritionGoalClient: ObservableObject {
    static let enabledKey = "dhoop.nutrition.sharedGoals.enabled"
    static let cacheKey = "dhoop.nutrition.goalCache.v1"
    static let shared = NutritionGoalClient()
    struct Cached: Codable { let endpoint: String; let document: NutritionGoalDocument; let readAt: Date }
    @Published private(set) var cached: Cached?
    @Published private(set) var busy = false
    @Published private(set) var requiresRefresh = true
    @Published private(set) var error: String?
    @Published private(set) var diagnostic: String?
    private let defaults: UserDefaults
    private let connection: () throws -> NutritionGoalConnection
    private let send: (NutritionGoalWrite?, NutritionGoalConnection) async throws -> Data
    var periods: [CalorieGoalPeriod] { cached?.document.periods ?? [] }
    var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    init(defaults: UserDefaults = .standard, connection: @escaping () throws -> NutritionGoalConnection = NutritionGoalClient.liveConnection,
         send: @escaping (NutritionGoalWrite?, NutritionGoalConnection) async throws -> Data = { try await NutritionGoalTransport().send($0, connection: $1) }) {
        self.defaults = defaults; self.connection = connection; self.send = send
        if let raw = defaults.object(forKey: Self.cacheKey) {
            do {
                guard let data = raw as? Data, data.count <= 131072 else { throw NutritionGoalFailure.storage }
                let value = try JSONDecoder().decode(Cached.self, from: data), active = try connection()
                try value.document.validate(installation: active.installationId)
                if active.credentials.endpoint == value.endpoint { cached = value }
            } catch { self.error = NutritionGoalFailure.storage.localizedDescription }
        }
    }
    static func liveConnection() throws -> NutritionGoalConnection {
        #if os(iOS)
        guard !SleepWebhookClient.shared.storageUnavailable,
              let bytes = try SleepWebhookKeychain.read("credentials") else { throw NutritionGoalFailure.unavailable }
        let credentials = try JSONDecoder().decode(SleepWebhookCredentials.self, from: bytes)
        guard credentials.endpoint == SleepWebhookClient.shared.checkpoint.delivery.endpoint else { throw NutritionGoalFailure.unavailable }
        let value = NutritionGoalConnection(credentials: credentials, installationId: SleepWebhookClient.shared.checkpoint.delivery.installationId)
        guard value.valid else { throw NutritionGoalFailure.unavailable }; return value
        #else
        throw NutritionGoalFailure.unavailable
        #endif
    }
    func goal(for day: String) -> CalorieGoalPeriod? { periods.first { $0.contains(day) } }
    func connectionDidChange() {
        guard let cached else { return }
        guard let active = try? connection(), active.installationId == cached.document.installationId,
              active.credentials.endpoint == cached.endpoint else {
            self.cached = nil; requiresRefresh = true; error = NutritionGoalFailure.unavailable.localizedDescription; return
        }
    }
    @discardableResult func refresh(activate: Bool = false) async -> Bool {
        connectionDidChange()
        guard !busy, enabled || activate else { error = NutritionGoalFailure.unavailable.localizedDescription; return false }
        busy = true; defer { busy = false }
        do {
            let active = try connection(), bytes = try await send(nil, active)
            try Task.checkCancellation(); guard try connection() == active else { throw NutritionGoalFailure.unconfirmed }
            try accept(bytes, active: active)
            if activate { defaults.set(true, forKey: Self.enabledKey) }; return true
        } catch { self.error = Self.message(error); diagnostic = (error as? NutritionGoalFailure)?.diagnosticCode ?? "connection_or_network_error"; requiresRefresh = true; return false }
    }
    func save(_ goal: CalorieGoalPeriod) async throws { try await write(action: "upsert", goal: goal, id: nil) }
    func remove(_ id: String) async throws { try await write(action: "remove", goal: nil, id: id) }
    private func write(action: String, goal: CalorieGoalPeriod?, id: String?) async throws {
        guard enabled, !busy, !requiresRefresh, let cached else { throw NutritionGoalFailure.unavailable }
        let active = try connection(); guard cached.document.installationId == active.installationId, cached.endpoint == active.credentials.endpoint else { throw NutritionGoalFailure.unavailable }
        let request = NutritionGoalWrite(installationId: active.installationId, expectedVersion: cached.document.version, action: action, goal: goal, id: id)
        _ = try JSONEncoder().encode(request); busy = true; defer { busy = false }
        do {
            let bytes = try await send(request, active); try Task.checkCancellation()
            guard try connection() == active else { throw NutritionGoalFailure.unconfirmed }
            let value = try JSONDecoder().decode(NutritionGoalDocument.self, from: bytes); try value.validate(installation: active.installationId)
            let alreadyMatched = action == "upsert" ? cached.document.periods.contains(goal!) : !cached.document.periods.contains(where: { $0.id == id })
            guard value.version > cached.document.version || (value.version == cached.document.version && alreadyMatched),
                  action == "upsert" ? value.periods.contains(goal!) : !value.periods.contains(where: { $0.id == id }) else { throw NutritionGoalFailure.unconfirmed }
            try accept(bytes, active: active)
        } catch { self.error = Self.message(error); requiresRefresh = true; throw error }
    }
    private func accept(_ bytes: Data, active: NutritionGoalConnection) throws {
        let value = try JSONDecoder().decode(NutritionGoalDocument.self, from: bytes); try value.validate(installation: active.installationId)
        let next = Cached(endpoint: active.credentials.endpoint, document: value, readAt: Date())
        let data = try JSONEncoder().encode(next); defaults.set(data, forKey: Self.cacheKey)
        cached = next; requiresRefresh = false; error = nil; diagnostic = nil
    }
    private static func message(_ error: Error) -> String { (error as? NutritionGoalFailure)?.localizedDescription ?? NutritionGoalFailure.unconfirmed.localizedDescription }
}
