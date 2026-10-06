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
    func testAwakeOverridesOverlappingCoarseAndPreciseAsleepSamples() {
        for stage in [SleepComparisonSample.Stage.unspecified, .core] {
            let samples = [
                sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T08:00:00Z", stage: stage),
                sample(start: "2026-10-04T02:00:00Z", end: "2026-10-04T03:00:00Z", stage: .awake)
            ]
            let row = SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc)[0].days[0]
            XCTAssertEqual(row.total, 420, "The explicitly awake hour must not count as sleep")
            XCTAssertEqual((row.deep ?? 0) + (row.rem ?? 0) + (row.light ?? 0) + (row.unspecified ?? 0), 420)
        }
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
    func testHealthComparisonExcludesActualExternalUUIDWritebackAcrossBuilds() {
        XCTAssertTrue(SleepComparisonProjection.isAppWriteback(sourceID: "our.build", ownBundleID: "our.build", syncID: nil, externalID: nil))
        XCTAssertTrue(SleepComparisonProjection.isAppWriteback(sourceID: "other.noop.build", ownBundleID: "our.build", syncID: nil, externalID: "noop:sleep:1234"))
        XCTAssertTrue(SleepComparisonProjection.isAppWriteback(sourceID: "other.noop.build", ownBundleID: "our.build", syncID: "noop:sleep:1234", externalID: nil))
        XCTAssertFalse(SleepComparisonProjection.isAppWriteback(sourceID: "eight.bundle", ownBundleID: "our.build", syncID: nil, externalID: "eight:1234"))
        XCTAssertFalse(SleepComparisonProjection.isAppWriteback(sourceID: "watch.bundle", ownBundleID: "our.build", syncID: nil, externalID: nil))
    }

    func testWholeRecordPrecedenceNeverBorrowsStagesFromLowerPriority() {
        let imported = SleepComparisonDay(day: "2026-10-04", sourceID: "whoop", method: "Imported", total: 400, deep: nil, rem: 80, light: nil, unspecified: nil)
        let computed = SleepComparisonDay(day: "2026-10-04", sourceID: "whoop-noop", method: "Estimate", total: 450, deep: 100, rem: 90, light: 260, unspecified: 0)
        let result = SleepComparisonProjection.preferred([[imported], [computed]], window: window)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].total, 400); XCTAssertNil(result[0].deep)
    }
    func testTimelineRetainsActualStagesAndMissingIntervals() {
        let samples = [
            sample(start: "2026-10-03T23:00:00Z", end: "2026-10-04T01:00:00Z", stage: .deep),
            sample(start: "2026-10-04T01:20:00Z", end: "2026-10-04T01:30:00Z", stage: .awake),
            sample(start: "2026-10-04T01:30:00Z", end: "2026-10-04T07:00:00Z", stage: .rem)
        ]
        let timeline = SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc)[0].days[0].timelines[0]
        XCTAssertEqual(timeline.sourceID, "eight.bundle")
        XCTAssertEqual(timeline.day, "2026-10-04")
        XCTAssertEqual(timeline.intervals.map(\.stage), [.deep, .awake, .rem])
        XCTAssertEqual(timeline.intervals[1].start - timeline.intervals[0].end, 20 * 60)
        XCTAssertEqual(timeline.asleepMinutes, 450)
        XCTAssertEqual(timeline.start, date("2026-10-03T23:00:00Z").timeIntervalSince1970)
        XCTAssertEqual(timeline.end, date("2026-10-04T07:00:00Z").timeIntervalSince1970)
    }

    func testTimelineConflictAndCoarseDuplicatePreserveUnknownRatherThanInventStage() {
        let samples = [
            sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T04:00:00Z", stage: .unspecified),
            sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T02:00:00Z", stage: .deep),
            sample(start: "2026-10-04T01:00:00Z", end: "2026-10-04T02:00:00Z", stage: .rem),
            sample(start: "2026-10-04T02:00:00Z", end: "2026-10-04T03:00:00Z", stage: .awake)
        ]
        let intervals = SleepComparisonProjection.normalizedIntervals(samples + [samples[1]])
        XCTAssertEqual(intervals.map(\.stage), [.deep, .unspecified, .awake, .unspecified])
        XCTAssertEqual(intervals.map { ($0.end - $0.start) / 60 }, [60, 60, 60, 60])
    }

    func testStoredAggregateNeverGeneratesStageOrderAndEditedBoundsClipRealStages() {
        let aggregate = SleepComparisonProjection.storedTimeline(json: "{\"light\":180,\"deep\":60,\"rem\":80}",
            start: 100, end: 700, sourceID: "whoop", method: "Imported WHOOP record", calendar: utc)!
        XCTAssertTrue(aggregate.intervals.isEmpty)
        XCTAssertNil(aggregate.asleepMinutes)
        let json = "[{\"start\":0,\"end\":200,\"stage\":\"wake\"},{\"start\":250,\"end\":800,\"stage\":\"light\"}]"
        let staged = SleepComparisonProjection.storedTimeline(json: json, start: 100, end: 700,
            sourceID: "whoop-noop", method: "Dhoop estimate", calendar: utc)!
        XCTAssertEqual(staged.method, "Dhoop estimate")
        XCTAssertEqual(staged.sourceID, "whoop-noop")
        XCTAssertEqual(staged.intervals, [SleepStageInterval(start: 100, end: 200, stage: .awake),
                                        SleepStageInterval(start: 250, end: 700, stage: .core)])
    }

    func testProviderEpisodesRemainSeparateAndNeverJoinTheNapToTheNight() {
        let samples = [sample(start: "2026-10-04T00:00:00Z", end: "2026-10-04T06:00:00Z", stage: .core),
                       sample(start: "2026-10-04T10:00:00Z", end: "2026-10-04T10:30:00Z", stage: .deep),
                       sample("other.bundle", start: "2026-10-04T00:00:00Z", end: "2026-10-04T06:00:00Z", stage: .rem)]
        let providers = SleepComparisonProjection.healthProviders(samples, window: window, calendar: utc)
        let eight = providers.first { $0.id == "eight.bundle" }!.days[0]
        XCTAssertEqual(eight.timelines.count, 2)
        XCTAssertEqual(eight.timelines.map { $0.intervals[0].stage }, [.core, .deep])
        XCTAssertEqual(providers.first { $0.id == "other.bundle" }!.days[0].timelines[0].intervals[0].stage, .rem)
    }

    func testNightSelectionFallsBackInsideRangeAndKeepsExplicitChoice() {
        let now = date("2026-10-04T12:00:00Z")
        var range = MetricRangeSelection(now: now); range.preset = .custom
        range.customStart = date("2026-10-01T00:00:00Z"); range.customEnd = now
        let window = range.window(now: now, calendar: utc)
        let days = ["2026-09-30", "2026-10-01", "2026-10-03", "2026-10-05"]
        XCTAssertEqual(SleepComparisonProjection.selectedNight("", available: days, window: window), "2026-10-03")
        XCTAssertEqual(SleepComparisonProjection.selectedNight("2026-10-01", available: days, window: window), "2026-10-01")
        XCTAssertEqual(SleepComparisonProjection.selectedNight("2026-10-05", available: days, window: window), "2026-10-03")
        XCTAssertNil(SleepComparisonProjection.selectedNight("", available: ["2026-09-30"], window: window))
    }

}
