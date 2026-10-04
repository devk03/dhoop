import Foundation
import Combine

/// Protein-only entries never create a calorie-log day or change a weight-loss plan.
@MainActor
final class ProteinLogStore: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        let day: String
        let name: String
        let grams: Double
    }

    static let entriesKey = "dhoop.protein.entries"
    static let targetKey = "dhoop.protein.targetGrams"
    private let defaults: UserDefaults
    @Published private(set) var entries: [Entry] {
        didSet {
            if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.entriesKey) }
        }
    }
    @Published var targetGrams: Double? {
        didSet {
            if let targetGrams, targetGrams.isFinite, targetGrams > 0 {
                defaults.set(targetGrams, forKey: Self.targetKey)
            } else {
                defaults.removeObject(forKey: Self.targetKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.entriesKey)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        let target = defaults.double(forKey: Self.targetKey)
        targetGrams = target.isFinite && target > 0 ? target : nil
    }

    func add(grams: Double, name: String, day: String) {
        guard grams.isFinite, grams > 0 else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.append(Entry(day: day, name: name.isEmpty ? "Protein" : name, grams: grams))
    }

    func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    func total(day: String, foodProtein: Double = 0) -> Double {
        entries.filter { $0.day == day }.reduce(max(0, foodProtein)) { $0 + $1.grams }
    }
}
