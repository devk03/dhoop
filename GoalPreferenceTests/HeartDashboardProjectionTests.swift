import XCTest

final class HeartDashboardProjectionTests: XCTestCase {
    func testTodayNeverUsesBufferedTomorrowOrInventsMissingDays() {
        let readings = [
            DashboardDailyReading(day: "2026-10-03", value: 1000, source: "whoop", key: "steps"),
            DashboardDailyReading(day: "2026-10-05", value: 9000, source: "whoop", key: "steps"),
            DashboardDailyReading(day: "2026-10-04", value: .nan, source: "whoop", key: "steps")
        ]
        XCTAssertTrue(HeartDashboardProjection.bounded(readings, from: "2026-10-04", through: "2026-10-04").isEmpty)
        XCTAssertEqual(HeartDashboardProjection.latest(readings, through: "2026-10-04")?.day, "2026-10-03")
    }

    func testHRGapAndSingletonKeepActualValuesAndTimestamps() {
        let samples = [DashboardTraceSample(time: 100, value: 72), DashboardTraceSample(time: 101, value: 72),
                       DashboardTraceSample(time: 130, value: 90), DashboardTraceSample(time: 200, value: 65)]
        let trace = HeartDashboardProjection.trace(samples, from: 100, through: 200, gapSeconds: 1)
        XCTAssertEqual(trace.map(\.time), [100, 101, 130, 200])
        XCTAssertEqual(trace.map(\.value), [72, 72, 90, 65])
        XCTAssertEqual(trace.map(\.segment), ["0", "0", "1", "2"])
    }

    func testSourceAndEstimatorChangesBreakEvenWhenAFormerMethodReturns() {
        let samples = [DashboardTraceSample(time: 100, value: 40, provenance: "nes"),
                       DashboardTraceSample(time: 101, value: 41, provenance: "uth"),
                       DashboardTraceSample(time: 102, value: 42, provenance: "nes"),
                       DashboardTraceSample(time: 103, value: 43, provenance: "apple")]
        XCTAssertEqual(HeartDashboardProjection.trace(samples, from: 100, through: 103, gapSeconds: 10).map(\.segment), ["0", "1", "2", "3"])
    }

    func testFutureReceiptsAndInvalidValuesAreExcluded() {
        let samples = [DashboardTraceSample(time: 99, value: 60), DashboardTraceSample(time: 100, value: 72),
                       DashboardTraceSample(time: 101, value: .infinity), DashboardTraceSample(time: 102, value: 90)]
        XCTAssertEqual(HeartDashboardProjection.trace(samples, from: 100, through: 101, gapSeconds: 1).map(\.value), [72])
    }

    func testCalendarDatesRejectNormalizationAndRespectTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertNil(HeartDashboardProjection.date("2026-02-30", calendar: calendar))
        let date = HeartDashboardProjection.date("2026-10-04", calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: date), 4)
        XCTAssertEqual(calendar.component(.hour, from: date), 0)
    }
}
