import XCTest

final class MetricRangeProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }
    private var window: MetricDateWindow { MetricRangeSelection(now: date(10)).window(now: date(10), calendar: calendar) }
    private func reading(_ day: String, _ value: Double, source: String = "strap", key: String = "steps", method: String? = nil) -> DashboardDailyReading {
        DashboardDailyReading(day: day, value: value, source: source, key: key, method: method)
    }

    func testCalendarWindowIncludesSevenDatesAcrossDSTWithoutUsingSeven24HourPeriods() {
        XCTAssertEqual(window.fromDay, "2026-03-04")
        XCTAssertEqual(window.toDay, "2026-03-10")
        XCTAssertEqual(window.days, 7)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 6 * 86_400 - 3_600)
        XCTAssertEqual(window.through, date(10))
    }
    func testCustomRangeClampsFutureAndReversedDatesToToday() {
        var range = MetricRangeSelection(now: date(10)); range.preset = .custom
        range.customStart = date(12); range.customEnd = date(20)
        let result = range.window(now: date(10), calendar: calendar)
        XCTAssertEqual(result.fromDay, "2026-03-10")
        XCTAssertEqual(result.toDay, "2026-03-10")
        XCTAssertEqual(result.days, 1)
        XCTAssertEqual(result.through, date(10))
    }
    func testObservedZeroStepsCountsButMissingDaysAndInvalidOrFutureReadingsDoNot() {
        let groups = MetricRangeProjection.groups([
            reading("2026-03-04", 0), reading("2026-03-10", 1000),
            reading("2026-03-03", 999), reading("2026-03-11", 999),
            reading("2026-03-06", .nan), reading("2026-03-07", -1), reading("2026-03-08x", 999)
        ], window: window, separateMethods: false, allowZero: true)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].mean, 500)
        XCTAssertEqual(groups[0].readings.count, 2)
        XCTAssertEqual(window.coverage(groups[0].readings.count), "2 of 7 recorded days")
    }
    func testOneResolvedObservationPerDayPreservesFirstSourcePrecedence() {
        let groups = MetricRangeProjection.groups([
            reading("2026-03-04", 500, source: "strap"),
            reading("2026-03-04", 900, source: "apple-health"), reading("2026-03-05", 1000)
        ], window: window, separateMethods: false, allowZero: true)
        XCTAssertEqual(groups[0].mean, 750)
        XCTAssertEqual(groups[0].readings.count, 2)
    }
    func testHRVAndVO2MethodsHaveSeparateAverages() {
        let hrv = MetricRangeProjection.groups([
            reading("2026-03-04", 40, source: "strap", key: "hrv"),
            reading("2026-03-05", 60, source: "strap", key: "hrv"),
            reading("2026-03-06", 100, source: "apple-health", key: "hrv")
        ], window: window, separateMethods: true)
        XCTAssertEqual(Set(hrv.map(\.mean)), Set([50, 100]))
        let vo2 = MetricRangeProjection.groups([
            reading("2026-03-04", 40, key: "vo2max_est", method: "uth"),
            reading("2026-03-05", 50, key: "vo2max_est", method: "nes"),
            reading("2026-03-06", 60, source: "apple-health", key: "vo2max")
        ], window: window, separateMethods: true)
        XCTAssertEqual(vo2.count, 3)
        XCTAssertEqual(Set(vo2.map(\.mean)), Set([40, 50, 60]))
    }
    func testProteinAddsBothLogsOnceAndDoesNotInventProteinForCalorieOnlyDays() {
        let rows = MetricRangeProjection.loggedProtein(
            standalone: [("2026-03-04", 20), ("2026-03-04", 10), ("2026-03-05", 40)],
            food: [("2026-03-04", 30), ("2026-03-06", nil)])
        XCTAssertEqual(rows.map(\.day), ["2026-03-04", "2026-03-05"])
        let groups = MetricRangeProjection.groups(rows, window: window, separateMethods: false, allowZero: true)
        XCTAssertEqual(groups[0].mean, 50)
        XCTAssertEqual(groups[0].readings.map(\.value), [60, 40])
    }
    func testEmptyRangeHasNoFabricatedAverageAndAllHistoryHasNoInventedDayDenominator() {
        XCTAssertTrue(MetricRangeProjection.groups([], window: window, separateMethods: false).isEmpty)
        var range = MetricRangeSelection(now: date(10)); range.preset = .all
        let all = range.window(now: date(10), calendar: calendar)
        XCTAssertNil(all.days)
        XCTAssertEqual(all.coverage(2), "2 recorded days")
    }

    func testRecordedHRWeightsActualSampleCountsAcrossUnevenDays() {
        XCTAssertEqual(MetricRangeProjection.weightedMean([(120, 2), (100, 1)])!, 220.0 / 3.0, accuracy: 0.000001)
        XCTAssertNil(MetricRangeProjection.weightedMean([]))
    }
}
