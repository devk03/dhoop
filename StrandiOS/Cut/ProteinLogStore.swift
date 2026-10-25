import Foundation
import Combine

/// Optional food estimates share the protein log without creating a deficit-log day.
@MainActor
final class ProteinLogStore: ObservableObject {
    enum Failure: LocalizedError {
        case unreadable, invalidEntry, invalidTarget, encoding
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The saved protein log could not be read. Existing data is preserved; retry after restoring or repairing it."
            case .invalidEntry: return "Enter protein above zero or a calorie estimate. Your input is kept."
            case .invalidTarget: return "Enter a valid positive target or leave it blank. Your input is kept."
            case .encoding: return "Protein could not be saved. Existing entries and your input are kept."
            }
        }
    }
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        let day: String
        let name: String
        let grams: Double
        var loggedAt: Date? = nil
        var calories: Double? = nil
    }

    static let entriesKey = "dhoop.protein.entries"
    static let targetKey = "dhoop.protein.targetGrams"
    private let defaults: UserDefaults
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var targetGrams: Double?
    @Published private(set) var storageError: String?
    var storageUnavailable: Bool { storageError != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let target = defaults.double(forKey: Self.targetKey)
        targetGrams = target.isFinite && target > 0 ? target : nil
        do { entries = try readEntries() }
        catch { storageError = Failure.unreadable.localizedDescription }
    }

    private func readEntries() throws -> [Entry] {
        guard let raw = defaults.object(forKey: Self.entriesKey) else { return [] }
        guard let data = raw as? Data, let decoded = try? JSONDecoder().decode([Entry].self, from: data),
              Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy({ $0.grams.isFinite && $0.grams >= 0
                  && ($0.calories.map { $0.isFinite && $0 >= 0 && $0 <= 20000 } ?? true)
                  && $0.day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }) else { throw Failure.unreadable }
        return decoded
    }

    func reload() throws {
        do {
            entries = try readEntries(); storageError = nil
            let target = defaults.double(forKey: Self.targetKey)
            targetGrams = target.isFinite && target > 0 ? target : nil
        }
        catch { storageError = Failure.unreadable.localizedDescription; throw Failure.unreadable }
    }

    private func commit(_ next: [Entry]) throws {
        guard let data = try? JSONEncoder().encode(next) else { throw Failure.encoding }
        defaults.set(data, forKey: Self.entriesKey)
        entries = next
    }

    func add(grams: Double, name: String, day: String, now: Date = Date(), calories: Double? = nil) throws {
        guard grams.isFinite, grams >= 0, grams > 0 || calories != nil,
              calories.map({ $0.isFinite && $0 >= 0 && $0 <= 20000 }) ?? true,
              day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { throw Failure.invalidEntry }
        try reload()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try commit(entries + [Entry(day: day, name: name.isEmpty ? (calories == nil ? "Protein" : "Food") : name,
            grams: grams, loggedAt: now, calories: calories)])
    }

    func remove(_ id: UUID) throws {
        try reload()
        try commit(entries.filter { $0.id != id })
    }

    func setTarget(_ value: Double?) throws {
        guard value.map({ $0.isFinite && $0 > 0 }) ?? true else { throw Failure.invalidTarget }
        if let value { defaults.set(value, forKey: Self.targetKey) }
        else { defaults.removeObject(forKey: Self.targetKey) }
        targetGrams = value
    }

    func total(day: String, foodProtein: Double = 0) -> Double {
        entries.filter { $0.day == day }.reduce(max(0, foodProtein)) { $0 + $1.grams }
    }
}
