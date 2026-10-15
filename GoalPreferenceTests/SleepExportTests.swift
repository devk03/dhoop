import XCTest

final class SleepExportTests: XCTestCase {
    private func row(day: String = "2026-10-15", source: String = "strap") -> SleepComparisonDay {
        .init(day: day, sourceID: source, method: "Imported WHOOP record", total: 480,
            deep: 80, rem: nil, light: 300, unspecified: 0)
    }
    private func episode(day: String = "2026-10-15", source: String = "strap", start: Double = 0, end: Double = 30) -> SleepComparisonTimeline {
        .init(day: day, sourceID: source, sourceName: "WHOOP", method: "Stored stages", start: start, end: end,
            intervals: [.init(start: start, end: start + 10, stage: .deep), .init(start: start + 15, end: start + 20, stage: .awake),
                        .init(start: start + 20, end: end, stage: .rem)])
    }
    func testDateAndOwnerStayAlignedAndAbsentStageDoesNotBecomeZero() throws {
        let source = SleepExportProjection.source(day: "2026-10-15", id: "whoop", name: "WHOOP", reading: row(),
            timelines: [episode(day: "2026-10-14"), episode(source: "other-provider"), episode()])
        XCTAssertEqual(source.totalMinutes, 480)
        XCTAssertEqual(source.stages[0], 80); XCTAssertNil(source.stages[1]); XCTAssertEqual(source.stages[3], 0)
        let timeline = try XCTUnwrap(source.timeline)
        XCTAssertEqual(timeline.intervals.count, 3)
        XCTAssertEqual(SleepExportProjection.asleepWindows(timeline), [0..<10, 20..<30])
        XCTAssertTrue(source.metrics.allSatisfy { $0.value == nil })
        let absent = SleepExportProjection.source(day: "2026-10-16", id: "whoop", name: "WHOOP", reading: row(), timelines: [episode()])
        XCTAssertNil(absent.totalMinutes); XCTAssertNil(absent.timeline); XCTAssertTrue(absent.stages.allSatisfy { $0 == nil })
    }
    func testSelectedEpisodeMustBelongToTheSameSourceAndWakeDate() throws {
        let short = episode(start: 100, end: 125), long = episode(start: 200, end: 260)
        let selected = SleepExportProjection.source(day: "2026-10-15", id: "whoop", name: "WHOOP", reading: row(),
            timelines: [long, short, episode(source: "different")], selectedEpisodeID: short.id)
        XCTAssertEqual(selected.timeline?.start, 100)
        let fallback = SleepExportProjection.source(day: "2026-10-15", id: "whoop", name: "WHOOP", reading: row(),
            timelines: [short, long], selectedEpisodeID: "no-such-episode")
        XCTAssertEqual(fallback.timeline?.start, 200)
        let eight = SleepExportProjection.source(day: "2026-10-15", id: "comparison", name: "8sleep", reading: row(source: "eight"),
            timelines: [episode()], selectedEpisodeID: episode().id)
        XCTAssertNil(eight.timeline, "A WHOOP timeline cannot fill an 8sleep source")
        XCTAssertTrue(eight.method.contains("via Apple Health"))
        XCTAssertTrue(eight.metrics.allSatisfy { $0.value == nil })
        let other = episode(source: "computed-owner")
        let timelineOnly = SleepExportProjection.source(day: "2026-10-15", id: "whoop", name: "WHOOP", reading: nil,
            timelines: [episode(), other], selectedEpisodeID: other.id)
        XCTAssertEqual(timelineOnly.readingSourceID, "computed-owner", "Equal bounds do not imply equal data ownership")
    }
    func testMeansExcludeOtherProvidersAwakeGapsAndBoundaryPoints() {
        let timeline = SleepExportReport.Timeline(start: 0, end: 30, method: "Test", intervals: [
            .init(start: 0, end: 10, stage: "deep"), .init(start: 15, end: 20, stage: "awake"), .init(start: 20, end: 30, stage: "rem")])
        let summary = SleepExportProjection.mean([
            .init(sourceID: "eight", start: 1, end: 2, value: 50),
            .init(sourceID: "eight", start: 29, end: 30, value: 70),
            .init(sourceID: "other", start: 2, end: 3, value: 200),
            .init(sourceID: "eight", start: 12, end: 13, value: 150),
            .init(sourceID: "eight", start: 16, end: 17, value: 150),
            .init(sourceID: "eight", start: 30, end: 30, value: 150),
            .init(sourceID: "eight", start: 3, end: 4, value: .nan),
            .init(sourceID: "eight", start: 3, end: 4, value: 0)], sourceID: "eight", timeline: timeline)
        XCTAssertEqual(summary.count, 2); XCTAssertEqual(summary.value, 60)
        XCTAssertNil(SleepExportProjection.mean([], sourceID: "eight", timeline: timeline).value)
    }
    func testUnknownStagesRemainObservedAndFractionalSecondsArePreservedForHealth() {
        let timeline = SleepExportReport.Timeline(start: 0.2, end: 10.2, method: "Test", intervals: [
            .init(start: 0.2, end: 5.2, stage: "unspecified"), .init(start: 6.1, end: 10.2, stage: "core")])
        XCTAssertEqual(SleepExportProjection.asleepWindows(timeline), [1..<6, 7..<11])
        let summary = SleepExportProjection.mean([.init(sourceID: "eight", start: 0.3, end: 0.4, value: 64)], sourceID: "eight", timeline: timeline)
        XCTAssertEqual(summary.value, 64)
        XCTAssertEqual(SleepExportReport.duration(nil), "Unavailable")
        XCTAssertEqual(SleepExportReport.duration(0), "0m")
    }
}
