import XCTest

final class DayHubTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func event(_ id: String, _ start: Date, _ end: Date) -> CalendarWidgetSnapshot.Event {
        .init(id: id, title: id, start: start, end: end, allDay: false, organizer: nil, pending: false, localProjection: false)
    }
    func testThreeHourWindowClipsAndKeepsOverlapLanes() {
        let now = date("2026-10-24T19:00:00Z"), window = DayHubWindow(now: now)
        let rows = [event("past", now.addingTimeInterval(-7200), now.addingTimeInterval(-3600)), event("a", now.addingTimeInterval(-300), now.addingTimeInterval(1200)), event("b", now, now.addingTimeInterval(900)), event("future", now.addingTimeInterval(5000), now.addingTimeInterval(7200)), event("outside", now.addingTimeInterval(7200), now.addingTimeInterval(8000))]
        let days: [CalendarWidgetSnapshot.Day] = [.init(date: "2026-10-24", readAt: now, complete: true, events: rows)]
        let placed = window.placements(days)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 10800)
        XCTAssertEqual(placed.map(\.id), ["past", "a", "b", "future"])
        XCTAssertEqual(placed.first?.start, 0); XCTAssertEqual(placed.last?.end, 10800)
        XCTAssertEqual(placed[1].columns, 2); XCTAssertNotEqual(placed[1].column, placed[2].column)
        XCTAssertTrue(window.complete(days))
    }
    func testMidnightRequiresBothDatesAndDeduplicatesCrossingEvent() {
        let now = date("2026-10-25T07:10:00Z"), window = DayHubWindow(now: now)
        let e = event("cross", now.addingTimeInterval(-1200), now.addingTimeInterval(1200))
        let left = CalendarWidgetSnapshot.Day(date: "2026-10-24", readAt: now, complete: true, events: [e])
        let right = CalendarWidgetSnapshot.Day(date: "2026-10-25", readAt: now, complete: true, events: [e])
        XCTAssertFalse(window.complete([right])); XCTAssertTrue(window.complete([left, right]))
        XCTAssertEqual(window.placements([left, right]).count, 1)
    }
    func testDstKeepsRealThreeHoursAndBoundedTimeline() {
        let now = date("2026-11-01T09:00:00Z"), w = DayHubWindow(now: now)
        XCTAssertEqual(w.end.timeIntervalSince(w.start), 10800)
        let dates = DayHubWindow.timelineDates(from: now)
        XCTAssertEqual(dates.count, 73); XCTAssertEqual(dates.last!.timeIntervalSince(now), 21600)
        XCTAssertTrue(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 300 })
    }
    func testDayRolloverNeverShowsYesterdayFoodOrWorkoutAsToday() {
        let now = date("2026-10-25T07:10:00Z")
        let snap = DayHubSnapshot(savedAt: now, timeZoneID: "America/Los_Angeles", food: .init(day: "2026-10-24", readAt: now, protein: 30, calories: nil, entries: 1, estimatedEntries: 0), workouts: .init(day: "2026-10-24", readAt: now, complete: true, rows: [.init(id: 1, title: "Lift", status: "completed", timing: nil)]), sleep: nil, calendarDays: [])
        XCTAssertNil(snap.food(at: now)); XCTAssertNil(snap.workouts(at: now))
    }
    func testUnknownCaloriesAndZeroSurviveRoundTrip() throws {
        let now = Date(), defaults = UserDefaults(suiteName: UUID().uuidString)!
        for calories: Double? in [nil, 0] {
            let snap = DayHubSnapshot(savedAt: now, timeZoneID: "UTC", food: .init(day: DayHubSnapshot.day(now, zone: TimeZone(secondsFromGMT: 0)!), readAt: now, protein: 0, calories: calories, entries: 1, estimatedEntries: calories == nil ? 0 : 1), workouts: nil, sleep: nil, calendarDays: [])
            defaults.set(try JSONEncoder().encode(snap), forKey: DayHubSnapshot.storageKey)
            XCTAssertEqual(DayHubSnapshot.load(defaults), snap)
            XCTAssertEqual(snap.food(at: now)?.calories, calories)
        }
    }
    func testUnavailableSleepReadRetainsSameDeviceButNeverCarriesToAnother() {
        let old = DayHubSnapshot.Sleep(wakeDay: "2026-10-24", readAt: Date(timeIntervalSince1970: 100), whoopMinutes: 450, eightSleepMinutes: 460, whoopMethod: "Dhoop estimate")
        XCTAssertEqual(DayHubSnapshot.resolvedSleep(previous: old, cachedDeviceID: "strap-a", activeDeviceID: "strap-a", fresh: nil, healthReadable: false), old)
        XCTAssertNil(DayHubSnapshot.resolvedSleep(previous: old, cachedDeviceID: "strap-a", activeDeviceID: "strap-b", fresh: nil, healthReadable: false))
        XCTAssertNil(DayHubSnapshot.resolvedSleep(previous: old, cachedDeviceID: nil, activeDeviceID: "strap-a", fresh: nil, healthReadable: false))
    }
    func testLockedHealthReadPreservesOnlyTheSameNightAndItsActualReadDate() {
        let old = DayHubSnapshot.Sleep(wakeDay: "2026-10-24", readAt: Date(timeIntervalSince1970: 100), whoopMinutes: 450, eightSleepMinutes: 460, whoopMethod: "Dhoop estimate")
        let fresh = DayHubSnapshot.Sleep(wakeDay: "2026-10-24", readAt: Date(timeIntervalSince1970: 200), whoopMinutes: 455, eightSleepMinutes: nil, whoopMethod: "Dhoop estimate")
        let kept = DayHubSnapshot.resolvedSleep(previous: old, cachedDeviceID: "a", activeDeviceID: "a", fresh: fresh, healthReadable: false)
        XCTAssertEqual(kept?.whoopMinutes, 455); XCTAssertEqual(kept?.eightSleepMinutes, 460); XCTAssertEqual(kept?.readAt, old.readAt)
        let nextNight = DayHubSnapshot.Sleep(wakeDay: "2026-10-25", readAt: fresh.readAt, whoopMinutes: 455, eightSleepMinutes: nil, whoopMethod: "Dhoop estimate")
        XCTAssertNil(DayHubSnapshot.resolvedSleep(previous: old, cachedDeviceID: "a", activeDeviceID: "a", fresh: nextNight, healthReadable: false)?.eightSleepMinutes)
    }

}
