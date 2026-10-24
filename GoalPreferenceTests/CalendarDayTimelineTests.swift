import Foundation
import XCTest

final class CalendarDayTimelineTests: XCTestCase {
    private func instant(_ value: String) -> Date { CalendarReaderDates.instant(value)! }
    private func event(_ id: String, _ start: String, _ end: String) -> CalendarReaderEvent {
        CalendarReaderEvent(eventId: id, title: id, startAt: start, endAt: end, startDate: nil, endDate: nil,
            allDay: false, source: "google", status: "confirmed", displayContext: nil, entityKey: nil, linkedTaskRefs: [], description: nil)
    }
    func testHoursFollowPacificDaylightSavingAndNowOnlyAppearsWithinSelectedDay() {
        let spring = CalendarDayTimeline(day: "2026-03-08")!, fall = CalendarDayTimeline(day: "2026-11-01")!
        XCTAssertEqual(spring.hours, 23); XCTAssertEqual(fall.hours, 25)
        XCTAssertEqual(fall.offset(of: instant("2026-11-01T08:30:00Z")), 5400)
        XCTAssertEqual(fall.offset(of: instant("2026-11-01T09:30:00Z")), 9000)
        XCTAssertNil(fall.offset(of: fall.end)); XCTAssertNil(fall.offset(of: fall.start.addingTimeInterval(-1)))
        XCTAssertEqual(spring.offset(of: instant("2026-03-08T10:00:00Z")), 7200)
    }
    func testCrossMidnightEventsAreClippedAndUnrelatedEventsAreOmitted() {
        let day = CalendarDayTimeline(day: "2026-10-23")!
        let blocks = day.placements([
            event("overnight", "2026-10-23T06:30:00Z", "2026-10-23T08:00:00Z"),
            event("tomorrow", "2026-10-24T07:00:00Z", "2026-10-24T08:00:00Z"),
            event("late", "2026-10-24T06:30:00Z", "2026-10-24T08:00:00Z")], minimumDuration: 0)
        XCTAssertEqual(blocks.map(\.id), ["overnight", "late"])
        XCTAssertEqual(blocks[0].start, 0); XCTAssertEqual(blocks[0].end, 3600)
        XCTAssertEqual(blocks[1].start, 84600); XCTAssertEqual(blocks[1].end, 86400)
    }
    func testOverlappingChainsUseSeparateLanesAndAdjacentEventsReuseFullWidth() {
        let day = CalendarDayTimeline(day: "2026-10-23")!
        let blocks = day.placements([
            event("a", "2026-10-23T16:00:00Z", "2026-10-23T18:00:00Z"),
            event("b", "2026-10-23T17:00:00Z", "2026-10-23T19:00:00Z"),
            event("c", "2026-10-23T18:00:00Z", "2026-10-23T20:00:00Z"),
            event("d", "2026-10-23T20:00:00Z", "2026-10-23T21:00:00Z")], minimumDuration: 0)
        XCTAssertEqual(blocks.map(\.column), [0, 1, 0, 0]); XCTAssertEqual(blocks.map(\.columnCount), [2, 2, 2, 1])
    }
    func testShortEventHitAreasDoNotOverlapInSameLaneButActualTimesStayIntact() {
        let day = CalendarDayTimeline(day: "2026-10-23")!
        let blocks = day.placements([
            event("short", "2026-10-23T16:00:00Z", "2026-10-23T16:05:00Z"),
            event("next", "2026-10-23T16:10:00Z", "2026-10-23T16:15:00Z")], minimumDuration: 1800)
        XCTAssertEqual(blocks.map(\.column), [0, 1]); XCTAssertEqual(blocks.map(\.columnCount), [2, 2])
        XCTAssertEqual(blocks[0].end - blocks[0].start, 300)
    }
    func testAllDayUsesExclusiveEndWithoutInventingAnHour() {
        let day = CalendarDayTimeline(day: "2026-10-23")!
        let allDay = CalendarReaderEvent(eventId: "all", title: "All", startAt: nil, endAt: nil, startDate: "2026-10-22", endDate: "2026-10-24",
            allDay: true, source: "google", status: "confirmed", displayContext: nil, entityKey: nil, linkedTaskRefs: [], description: nil)
        XCTAssertEqual(day.allDayEvents([allDay]).map(\.id), ["all"])
        XCTAssertTrue(day.placements([allDay], minimumDuration: 0).isEmpty)
        XCTAssertTrue(CalendarDayTimeline(day: "2026-10-24")!.allDayEvents([allDay]).isEmpty)
    }
}
