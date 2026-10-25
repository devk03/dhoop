import Foundation
import Combine

struct CalorieGoalPeriod: Codable, Identifiable, Equatable {
    let id: String
    let startDate: String
    let endDate: String
    let minCalories: Double
    let maxCalories: Double
    var valid: Bool {
        UUID(uuidString: id) != nil && Self.date(startDate) != nil && Self.date(endDate) != nil && startDate <= endDate
            && minCalories.isFinite && maxCalories.isFinite && minCalories >= 0 && maxCalories > 0 && maxCalories >= minCalories && maxCalories <= 20000
    }
    func contains(_ day: String) -> Bool { valid && Self.date(day) != nil && startDate <= day && day <= endDate }
    static func date(_ key: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard key.count == 10, let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return date
    }
}

/// An estimated subtotal never implies that every food or the entire day was logged.
struct NutritionCalorieSummary: Equatable {
    let calories: Double?
    let entryCount: Int
    let estimatedEntryCount: Int
    init(estimates: [Double?]) {
        let known = estimates.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        entryCount = estimates.count; estimatedEntryCount = known.count
        calories = known.isEmpty ? nil : known.reduce(0, +)
    }
}

