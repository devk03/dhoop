import XCTest

final class SleepRangeProjectionTests: XCTestCase {
    private var window: MetricDateWindow {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
        return MetricRangeSelection(now: now).window(now: now, calendar: calendar)
    }
    private func row(_ day: String, _ value: Double, source: String = "strap", key: String = "sleep_total_min") -> DashboardDailyReading {
        DashboardDailyReading(day: day, value: value, source: source, key: key)
    }
    func testHistoricalWindowExcludesResolverBufferDayAndMissingNights() {
        let rows = SleepRangeProjection.readings(totals: [row("2026-09-28", 360), row("2026-10-04", 480), row("2026-10-05", 600), row("2026-09-27", 600)], deep: [], rem: [], light: [], window: window)
        XCTAssertEqual(rows.map(\.total.day), ["2026-09-28", "2026-10-04"])
        XCTAssertEqual(SleepRangeProjection.mean(rows.map { $0.total.value }), 420)
        XCTAssertEqual(window.coverage(rows.count), "2 of 7 recorded days")
    }
    func testStagesCannotBorrowAnotherSourcesMeasurementsForTheSameDay() {
        let rows = SleepRangeProjection.readings(totals: [row("2026-10-04", 480)],
            deep: [row("2026-10-04", 90, source: "apple-health", key: "deep_min")],
            rem: [row("2026-10-04", 100, key: "sleep_rem_min")], light: [], window: window)
        XCTAssertNil(rows[0].deep)
        XCTAssertEqual(rows[0].rem, 100)
        XCTAssertNil(rows[0].light)
    }
    func testRecordedZeroStageIsPreservedWhileNilIsExcludedFromMean() {
        XCTAssertEqual(SleepRangeProjection.mean([0, nil, 60]), 30)
        XCTAssertNil(SleepRangeProjection.mean([nil, .nan, -1]))
    }
    func testCircularClockMeanCrossesMidnightAndRejectsOppositeTimings() {
        XCTAssertEqual(SleepRangeProjection.clockMeanMinutes([23 * 60 + 30, 30]), 0)
        XCTAssertNil(SleepRangeProjection.clockMeanMinutes([0, 720]))
        XCTAssertNil(SleepRangeProjection.clockMeanMinutes([]))
    }
    func testDurationGoalRetainsOverGoalAmountWithoutInventingMissingSleep() {
        XCTAssertEqual(SleepDurationGoal(recordedMinutes: 495).percentage, 100)
        XCTAssertEqual(SleepDurationGoal(recordedMinutes: 396).percentage, 80)
        let longNight = SleepDurationGoal(recordedMinutes: 594)
        XCTAssertEqual(longNight.percentage, 120)
        XCTAssertEqual(longNight.ringFraction, 1)
        XCTAssertNil(SleepDurationGoal(recordedMinutes: nil).percentage)
        XCTAssertNil(SleepDurationGoal(recordedMinutes: .nan).recordedMinutes)
        XCTAssertNil(SleepDurationGoal(recordedMinutes: -1).recordedMinutes)
        XCTAssertEqual(SleepDurationGoal(recordedMinutes: 0).percentage, 0)
    }

}
