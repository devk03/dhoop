import XCTest
@testable import StrandDesign

final class ChartScrubIndexTests: XCTestCase {
    private func point(_ x: Double, _ y: Double, series: String = "hr", segment: String = "a") -> ChartScrubDatum {
        ChartScrubDatum(id: "\(series)-\(x)", x: x, y: y, value: String(y), context: "Recorded at \(x)", series: series, segment: segment)
    }

    func testIrregularTimesSnapToActualMeasurementWithoutInterpolating() {
        let index = ChartScrubIndex([point(100, 61), point(101, 84), point(1000, 55)])
        XCTAssertEqual(index.selection(at: 102)?.data.first?.y, 84)
        XCTAssertEqual(index.selection(at: 900)?.x, 1000)
        XCTAssertEqual(index.selection(at: 100.5)?.x, 100)
        XCTAssertEqual(index.selection(at: -20)?.x, 100)
        XCTAssertEqual(index.selection(at: 2000)?.x, 1000)
        XCTAssertFalse(index.selection(at: 1000)?.isGap ?? true)
    }

    func testGapReadoutReturnsDatedEndpointInsteadOfInventingValue() {
        let index = ChartScrubIndex([point(0, 65), point(1, 66), point(100, 90, segment: "b")])
        let gap = index.selection(at: 40)
        XCTAssertTrue(gap?.isGap ?? false)
        XCTAssertEqual(gap?.x, 1)
        XCTAssertEqual(gap?.data.first?.context, "Recorded at 1.0")
        XCTAssertFalse(index.selection(at: 0.5)?.isGap ?? true)
    }

    func testInterleavedSourceDoesNotHideGapAndAbsentSourceIsNotInterpolated() {
        let index = ChartScrubIndex([
            point(0, 70, series: "whoop", segment: "a"),
            point(9, 8, series: "apple"),
            point(10, 72, series: "whoop", segment: "b"),
            point(10, 9, series: "apple")
        ])
        let selection = index.selection(at: 9.8)
        XCTAssertTrue(selection?.isGap ?? false)
        XCTAssertEqual(selection?.data.map(\.y), [72, 9])
        XCTAssertEqual(index.selection(at: 9)?.data.map(\.series), ["apple"])
    }

    func testDailyBarsDistinguishMissingDayFromRecordedZero() {
        let index = ChartScrubIndex([point(0, 0), point(2, 500)])
        XCTAssertEqual(index.selection(at: 0, exact: true)?.data.first?.y, 0)
        let missing = index.selection(at: 1, exact: true)
        XCTAssertEqual(missing?.x, 1)
        XCTAssertTrue(missing?.data.isEmpty ?? false)
        XCTAssertTrue(missing?.isGap ?? false)
    }

    func testNonfiniteReadingsAndEmptyInputCannotCreateSelection() {
        let index = ChartScrubIndex([point(.nan, 60), point(1, .infinity), point(3, 73)])
        XCTAssertEqual(index.positions, [3])
        XCTAssertNil(index.selection(at: .nan))
        XCTAssertNil(ChartScrubIndex([]).selection(at: 0))
        XCTAssertNil(ChartScrubIndex([]).adjacent(to: nil, forward: true))
    }

    func testAccessibilityStepsDistinctPositionsInChronologicalOrder() {
        let index = ChartScrubIndex([point(30, 3), point(10, 1), point(20, 2), point(20, 6, series: "other")])
        XCTAssertEqual(index.adjacent(to: nil, forward: true), 10)
        XCTAssertEqual(index.adjacent(to: nil, forward: false), 30)
        XCTAssertEqual(index.adjacent(to: 10, forward: true), 20)
        XCTAssertEqual(index.adjacent(to: 20, forward: true), 30)
        XCTAssertEqual(index.adjacent(to: 10, forward: false), 10)
        XCTAssertEqual(index.adjacent(to: 30, forward: true), 30)
    }

    func testInspectionRetainsPointNotDrawnByRenderingReduction() {
        let full = (0..<1000).map { point(Double($0), 70 + Double($0 % 3)) }
        let drawn = DashboardTraceSampling.reduce(full.map { TrendPoint(date: Date(timeIntervalSince1970: $0.x), value: $0.y) }, targetCount: 40)
        let omitted = full.first { original in !drawn.contains { $0.date.timeIntervalSince1970 == original.x } }!
        XCTAssertEqual(ChartScrubIndex(full).selection(at: omitted.x)?.data.first?.id, omitted.id)
    }
}
