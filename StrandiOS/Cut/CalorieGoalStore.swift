import Foundation
import Combine

/// Strict locale-aware entry parsing; pasted thousands separators must not become decimals.
enum NutritionInputNumber {
    static func parse(_ input: String, locale: Locale = .current) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal
        let decimal = formatter.decimalSeparator ?? ".", separator = formatter.groupingSeparator ?? ","
        let parts = text.components(separatedBy: decimal)
        guard parts.count <= 2 else { return nil }
        func digits(_ value: String) -> String? {
            var result = ""
            for character in value {
                guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
                result += String(digit)
            }
            return result
        }
        let groups = parts[0].components(separatedBy: separator)
        let primary = max(1, formatter.groupingSize), secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
        if groups.count > 1 {
            guard let first = groups.first, (1...secondary).contains(first.count), groups.last?.count == primary,
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == secondary }) else { return nil }
        }
        guard let whole = digits(groups.joined()), let fraction = digits(parts.count == 2 ? parts[1] : ""),
              !whole.isEmpty || !fraction.isEmpty else { return nil }
        let normalized = (whole.isEmpty ? "0" : whole) + (parts.count == 2 ? "." + fraction : "")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }; return value
    }
}

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

