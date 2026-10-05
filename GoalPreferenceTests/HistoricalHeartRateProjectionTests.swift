import XCTest

final class HistoricalHeartRateProjectionTests: XCTestCase {
    func testAverageUsesActualSavedSamplesWithoutFillingMissingTime() {
        let result = HistoricalHeartRateProjection.summarize([
            DashboardTraceSample(time: 120, value: 60), DashboardTraceSample(time: 121, value: 80),
            DashboardTraceSample(time: 180, value: 100)
        ], from: 120, through: 180)
        XCTAssertEqual(result.averageBPM, 80)
        XCTAssertEqual(result.sampleCount, 3)
        XCTAssertEqual(result.readings.map(\.averageBPM), [70, 100])
        XCTAssertEqual(result.readings.map(\.count), [2, 1])
        XCTAssertEqual(result.readings.map(\.time), [121, 180])
        XCTAssertNotEqual(result.readings[0].segment, result.readings[1].segment)
    }

    func testGapWithinTheSameMinuteStillProducesSeparateRuns() {
        let result = HistoricalHeartRateProjection.summarize([
            DashboardTraceSample(time: 120, value: 60), DashboardTraceSample(time: 121, value: 60),
            DashboardTraceSample(time: 140, value: 100)
        ], from: 120, through: 180)
        XCTAssertEqual(result.readings.map(\.averageBPM), [60, 100])
        XCTAssertNotEqual(result.readings[0].segment, result.readings[1].segment)
    }

    func testBoundsAndEmptyWindowsDoNotBorrowFutureOrAnotherDay() {
        let samples = [DashboardTraceSample(time: 119, value: 50), DashboardTraceSample(time: 120, value: 70),
                       DashboardTraceSample(time: 181, value: 90), DashboardTraceSample(time: 150, value: .nan)]
        let result = HistoricalHeartRateProjection.summarize(samples, from: 120, through: 180)
        XCTAssertEqual(result.averageBPM, 70)
        XCTAssertEqual(result.sampleCount, 1)
        XCTAssertNil(HistoricalHeartRateProjection.summarize(samples, from: 200, through: 300).averageBPM)
    }
}
