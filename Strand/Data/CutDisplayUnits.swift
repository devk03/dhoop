import Foundation
import SwiftUI

/// Display and input adapters for the iPhone weight-loss screens. Stored values remain kg and cm.
struct CutDisplayUnits {
    let system: UnitSystem

    init(rawValue: String) {
        system = UnitSystem(rawValue: rawValue) ?? .metric
    }

    var massUnit: String { UnitFormatter.massUnit(system) }
    var massStep: Double { system == .imperial ? 1 : 0.1 }

    func massValue(_ kilograms: Double) -> Double {
        system == .imperial ? UnitFormatter.kgToPounds(kilograms) : kilograms
    }

    func kilograms(_ displayed: Double) -> Double {
        system == .imperial ? displayed / UnitFormatter.poundsPerKilogram : displayed
    }

    func mass(_ kilograms: Double, decimals: Int = 1) -> String {
        String(format: "%.*f %@", decimals, massValue(kilograms), massUnit)
    }

    func massInput(_ kilograms: Double) -> String {
        String(format: "%.1f", massValue(kilograms))
    }

    func parsedWeight(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        let kg = kilograms(value)
        return kg > 20 && kg < 400 ? kg : nil
    }

    func massBinding(_ kilograms: Binding<Double>) -> Binding<Double> {
        Binding(get: { massValue(kilograms.wrappedValue) },
                set: { kilograms.wrappedValue = self.kilograms($0) })
    }

    func massRange(_ kilograms: ClosedRange<Double>) -> ClosedRange<Double> {
        massValue(kilograms.lowerBound)...massValue(kilograms.upperBound)
    }

    func heightValue(_ centimeters: Double) -> Double {
        system == .imperial ? UnitFormatter.cmToInches(centimeters) : centimeters
    }

    func height(_ centimeters: Double) -> String {
        UnitFormatter.heightFromCentimeters(centimeters, system: system)
    }

    func heightBinding(_ centimeters: Binding<Double>) -> Binding<Double> {
        Binding(get: { heightValue(centimeters.wrappedValue) },
                set: { centimeters.wrappedValue = system == .imperial
                    ? $0 * UnitFormatter.centimetersPerInch : $0 })
    }

    var heightRange: ClosedRange<Double> { heightValue(120)...heightValue(230) }

    /// Existing targets remain editable after the user reaches them; only an unset goal gets a preview default.
    static func goalEditor(currentKg: Double, savedGoalKg: Double, isUnset: Bool)
        -> (valueKg: Double, rangeKg: ClosedRange<Double>) {
        let proposedMaximum = max(40, currentKg - 0.5)
        let minimum = isUnset ? 40 : min(40, savedGoalKg)
        let maximum = isUnset ? proposedMaximum : max(proposedMaximum, savedGoalKg)
        return (isUnset ? proposedMaximum : savedGoalKg, minimum...maximum)
    }

    func proteinRatio(_ gramsPerKilogram: Double) -> String {
        let ratio = system == .imperial ? gramsPerKilogram / UnitFormatter.poundsPerKilogram : gramsPerKilogram
        return String(format: "%.1f g/%@", ratio, massUnit)
    }

    func fatMass(_ kilograms: Double) -> String {
        if system == .imperial { return mass(kilograms, decimals: 2) }
        return kilograms < 1 ? "\(Int((kilograms * 1000).rounded())) g" : mass(kilograms, decimals: 2)
    }
}
