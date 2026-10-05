import XCTest
import SwiftUI

final class CutDisplayUnitsTests: XCTestCase {
    private let imperial = CutDisplayUnits(rawValue: "imperial")
    private let metric = CutDisplayUnits(rawValue: "metric")

    func testImperialWeightEntrySavesKilogramsAndValidatesAfterConversion() throws {
        XCTAssertEqual(try XCTUnwrap(imperial.parsedWeight("220.462")), 100, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(imperial.parsedWeight("500")), 226.796, accuracy: 0.001)
        XCTAssertNil(metric.parsedWeight("500"))
        for text in ["", "nan", "inf", "-10", "1000"] {
            XCTAssertNil(imperial.parsedWeight(text), text)
        }
        XCTAssertEqual(try XCTUnwrap(metric.parsedWeight("75,5")), 75.5, accuracy: 0.001)
    }

    func testUnitChangesAndStepperBindingsPreserveStoredMeasurements() {
        var kg = 100.0
        let weight = Binding(get: { kg }, set: { kg = $0 })
        XCTAssertEqual(imperial.massBinding(weight).wrappedValue, 220.462, accuracy: 0.000001)
        XCTAssertEqual(metric.massBinding(weight).wrappedValue, 100)
        XCTAssertEqual(kg, 100, "Reading a different display unit must not rewrite stored weight")
        imperial.massBinding(weight).wrappedValue = 200
        XCTAssertEqual(kg, 90.71858, accuracy: 0.00001)
        XCTAssertEqual(metric.massBinding(weight).wrappedValue, 90.71858, accuracy: 0.00001)

        var cm = 177.8
        let height = Binding(get: { cm }, set: { cm = $0 })
        XCTAssertEqual(imperial.heightBinding(height).wrappedValue, 70, accuracy: 0.000001)
        imperial.heightBinding(height).wrappedValue = 71
        XCTAssertEqual(cm, 180.34, accuracy: 0.000001)
        XCTAssertEqual(imperial.height(cm), "5′ 11″")
    }

    func testGoalProgressPaceAndProteinFollowSelectedUnits() {
        XCTAssertEqual(imperial.mass(100), "220.5 lb")
        XCTAssertEqual(metric.mass(100), "100.0 kg")
        XCTAssertEqual(imperial.mass(0.5, decimals: 2), "1.10 lb")
        XCTAssertEqual(imperial.fatMass(0.1), "0.22 lb")
        XCTAssertEqual(metric.fatMass(0.1), "100 g")
        XCTAssertEqual(imperial.proteinRatio(2), "0.9 g/lb")
        XCTAssertEqual(metric.proteinRatio(2), "2.0 g/kg")
        XCTAssertEqual(imperial.massRange(40...250).upperBound, 551.155, accuracy: 0.000001)
    }

    func testEditingAchievedGoalPreservesTheSavedTarget() {
        let existing = CutDisplayUnits.goalEditor(currentKg: 74, savedGoalKg: 75, isUnset: false)
        XCTAssertEqual(existing.valueKg, 75)
        XCTAssertTrue(existing.rangeKg.contains(75), "Editing the date must not silently lower a reached weight goal")
        let unset = CutDisplayUnits.goalEditor(currentKg: 60, savedGoalKg: 60, isUnset: true)
        XCTAssertEqual(unset.valueKg, 59.5)
        XCTAssertTrue(unset.rangeKg.contains(unset.valueKg))
    }
}
