import XCTest

final class SleepComparisonTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var window: MetricDateWindow {
        var s = MetricRangeSelection(now: date("2026-10-04T12:00:00Z")); s.preset = .today
        return s.window(now: date("2026-10-04T12:00:00Z"), calendar: utc)
    }
    private func sample(_ source: String = "eight.bundle", name: String = "Eight Sleep", start: String, end: String, stage: SleepComparisonSample.Stage) -> SleepComparisonSample {
        SleepComparisonSample(sourceID: source, sourceName: name, start: date(start).timeIntervalSince1970, end: date(end).timeIntervalSince1970, stage: stage)
    }
    func testProvidersWithSameNameRemainSeparateAndOvernightUsesWakeDate() {
        let samples = [
            sample(start: "2026-10-03T23:00:00Z", end: "2026-10-04T01:00:00Z", stage: .deep),
            sample(start: "2026-10-04T01:00:00Z", end: "2026-10-04T07:00:00Z", stage: .core),
            sample("other.bundle", start: "2026-10-04T00:00:00Z", end: "2026-10-04T06:00:00Z", stage: .unspecified)
        ]
        let providers = SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc)
        XCTAssertEqual(Set(providers.map(\.id)), ["eight.bundle", "other.bundle"])
        let eight = providers.first { $0.id == "eight.bundle" }!.days[0]
        XCTAssertEqual(eight.day, "2026-10-04"); XCTAssertEqual(eight.total, 480); XCTAssertEqual(eight.deep, 120)
        XCTAssertNil(providers.first { $0.id == "other.bundle" }!.days[0].deep)
    }
    func testDuplicatesAndCoarseOverlapNeverInflateDuration() {
        let precise = sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T02:00:00Z", stage: .deep)
        let broad = sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T08:00:00Z", stage: .unspecified)
        let row = SleepComparisonProjection.healthProviders([precise, precise, broad], window: window, calendar: utc)[0].days[0]
        XCTAssertEqual(row.total, 480); XCTAssertEqual(row.deep, 120); XCTAssertEqual(row.unspecified, 360)
    }
    func testConflictingStagesBecomeUnclassifiedAndAwakeGapIsNotFilled() {
        let samples = [
            sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T02:00:00Z", stage: .deep),
            sample(start: "2026-10-04T01:00:00Z", end: "2026-10-04T02:00:00Z", stage: .rem),
            sample(start: "2026-10-04T02:00:00Z", end: "2026-10-04T03:00:00Z", stage: .awake),
            sample(start: "2026-10-04T03:00:00Z", end: "2026-10-04T04:00:00Z", stage: .core)
        ]
        let row = SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc)[0].days[0]
        XCTAssertEqual(row.total, 180); XCTAssertEqual(row.deep, 60); XCTAssertEqual(row.rem, 0)
        XCTAssertEqual(row.light, 60); XCTAssertEqual(row.unspecified, 60)
    }
    func testSeparateNapAddsOnlyItsObservedDuration() {
        let samples = [sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T06:00:00Z", stage: .unspecified),
                       sample(start: "2026-10-04T10:00:00Z", end: "2026-10-04T10:30:00Z", stage: .unspecified)]
        let row = SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc)[0].days[0]
        XCTAssertEqual(row.total, 390); XCTAssertNil(row.rem)
    }
    func testOutsideRangeAndInvalidIntervalsDoNotLeakIntoToday() {
        let samples = [sample(start: "2026-10-03T01:00:00Z", end: "2026-10-03T07:00:00Z", stage: .core),
                       sample(start: "2026-10-04T10:00:00Z", end: "2026-10-04T09:00:00Z", stage: .core),
                       sample(start: "2026-10-04T11:00:00Z", end: "2026-10-04T13:00:00Z", stage: .core)]
        XCTAssertTrue(SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc).isEmpty)
    }
    func testDSTUsesActualElapsedTimeAndLocalWakeDate() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date("2026-11-01T20:00:00Z")
        var range = MetricRangeSelection(now: now); range.preset = .today
        let sample = sample(start: "2026-11-01T07:00:00Z", end: "2026-11-01T15:00:00Z", stage: .unspecified)
        let row = SleepComparisonProjection.healthProviders([sample], window: range.window(now: now, calendar: c), calendar: c)[0].days[0]
        XCTAssertEqual(row.total, 480); XCTAssertEqual(row.day, "2026-11-01")
    }
    func testMatchedAveragesUseIntersectionWithoutSourceFallback() {
        func row(_ day: String, _ value: Double, _ id: String) -> SleepComparisonDay {
            SleepComparisonDay(day: day, sourceID: id, method: "Recorded", total: value, deep: nil, rem: nil, light: nil, unspecified: nil)
        }
        let whoop = [row("2026-10-03", 400, "whoop"), row("2026-10-04", 420, "whoop")]
        let apple = [row("2026-10-02", 700, "apple"), row("2026-10-04", 450, "apple")]
        let pairs = SleepComparisonProjection.matched(whoop, apple)
        XCTAssertEqual(pairs.count, 1); XCTAssertEqual(pairs[0].apple.total - pairs[0].whoop.total, 30)
        XCTAssertTrue(SleepComparisonProjection.matched([], apple).isEmpty)
    }
    func testHistoricalEndDoesNotMisattributePartialOvernightFragments() {
        let now = date("2026-10-04T12:00:00Z")
        var range = MetricRangeSelection(now: now); range.preset = .custom
        range.customStart = date("2026-10-03T00:00:00Z"); range.customEnd = range.customStart
        let samples = [sample(start: "2026-10-03T23:00:00Z", end: "2026-10-03T23:30:00Z", stage: .deep),
                       sample(start: "2026-10-03T23:30:00Z", end: "2026-10-04T07:00:00Z", stage: .core)]
        XCTAssertTrue(SleepComparisonProjection.healthProviders(samples, window: range.window(now: now, calendar: utc), calendar: utc, observedThrough: now).isEmpty)
    }
    func testComputedNamespaceRequiresRecordedWhoopOwner() {
        XCTAssertFalse(SleepComparisonProjection.hasWhoopOwner(nil, rawIDs: ["my-whoop"]))
        XCTAssertFalse(SleepComparisonProjection.hasWhoopOwner("oura-import", rawIDs: ["my-whoop"]))
        XCTAssertTrue(SleepComparisonProjection.hasWhoopOwner("my-whoop", rawIDs: ["my-whoop"]))
    }
    func testWholeRecordPrecedenceNeverBorrowsStagesFromLowerPriority() {
        let imported = SleepComparisonDay(day: "2026-10-04", sourceID: "whoop", method: "Imported", total: 400, deep: nil, rem: 80, light: nil, unspecified: nil)
        let computed = SleepComparisonDay(day: "2026-10-04", sourceID: "whoop-noop", method: "Estimate", total: 450, deep: 100, rem: 90, light: 260, unspecified: 0)
        let result = SleepComparisonProjection.preferred([[imported], [computed]], window: window)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].total, 400); XCTAssertNil(result[0].deep)
    }
}
