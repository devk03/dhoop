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

    func deleteSummary(id: UUID) throws -> [RunningSessionSummary] {
        let current = try defaults.data(forKey: Self.summariesKey)
            .map { try JSONDecoder().decode([RunningSessionSummary].self, from: $0) } ?? []
        let remaining = current.filter { $0.id != id }
        let data = try JSONEncoder().encode(remaining)
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
