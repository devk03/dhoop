import XCTest
@testable import StrandDesign

final class ChartSelectionReadoutTests: XCTestCase {
    func testSleepReadoutRemainsSafeAfterNightChangesToFewerIntervals() {
        let chart = Hypnogram(intervals: [SleepInterval(stage: .deep, start: 0, end: 3600)], smoothingSeconds: 0)
        XCTAssertTrue(chart.selectionDescription(at: 0).contains("Deep"))
        XCTAssertEqual(chart.selectionDescription(at: 12), "Adjust to inspect sleep intervals.")
        XCTAssertEqual(chart.selectionDescription(at: -1), "Adjust to inspect sleep intervals.")
        XCTAssertEqual(Hypnogram(intervals: []).selectionDescription(at: 0), "Adjust to inspect sleep intervals.")
    }
    func testCalendarReadoutRemainsSafeAfterAllHistoryShrinks() {
        let chart = YearHeatStrip(days: [RecoveryDay(date: Date(timeIntervalSince1970: 0), score: 72)])
        XCTAssertEqual(chart.selectionDescription(for: (week: 99, row: 6)), "Adjust to inspect dates.")
        XCTAssertEqual(chart.selectionDescription(for: (week: 0, row: 9)), "Adjust to inspect dates.")
        XCTAssertEqual(chart.selectionDescription(for: (week: -1, row: 0)), "Adjust to inspect dates.")
        XCTAssertEqual(YearHeatStrip(days: []).selectionDescription(for: (week: 0, row: 0)), "Adjust to inspect dates.")
    }
    func testGenericTimelinePreservesCallerUnitsAndMetricName() {
        let point = TrendPoint(date: Date(timeIntervalSince1970: 0), value: 35.1)
        let temperature = OverviewHRChart(points: [point], valueFormat: { "\($0) °C" }, inspectionLabel: "Skin temperature history")
        XCTAssertEqual(temperature.inspectionIndex.selection(at: 0)?.data.first?.value, "35.1 °C")
        XCTAssertEqual(temperature.inspectionLabel, "Skin temperature history")
        let heart = OverviewHRChart(points: [point], valueFormat: { "\(Int($0)) bpm" })
        XCTAssertEqual(heart.inspectionIndex.selection(at: 0)?.data.first?.value, "35 bpm")
    }
}
