import XCTest
@testable import StrandAnalytics

final class AlarmOccurrencePlannerTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testDSTGapFoldAndWeekdaysOracle() {
        let cases: [(String, Int, Set<Int>, [Int])] = [
            ("2026-03-08T09:00:00Z", 150, [1], [1772964000,1773567000]),
            ("2026-11-01T07:00:00Z", 90, [1], [1793521800,1794130200]),
            ("2026-10-13T05:00:00Z", 420, [2,3,4,5,6], [1791900000,1791986400])
        ]
        for (stamp, minute, days, expected) in cases {
            XCTAssertEqual(AlarmOccurrencePlanner.dates(rule: .init(minute: minute, weekdays: days),
                after: date(stamp), limit: 2, calendar: calendar), expected)
        }
    }
    func testOneTimeSkipAndSharedOccurrence() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(AlarmOccurrencePlanner.dates(rule: .init(minute: 0), after: now), [])
        let one = AlarmScheduleRule(minute: 0, oneTimeEpoch: 2000)
        XCTAssertEqual(AlarmOccurrencePlanner.dates(rule: one, after: now), [2000])
        var skipped = one; skipped.skippedEpochs = [2000]
        XCTAssertEqual(AlarmOccurrencePlanner.dates(rule: skipped, after: now), [])
        XCTAssertEqual(AlarmOccurrencePlanner.plan(rules: ["b":one,"a":one], after: now),
            [.init(epoch: 2000, definitionIDs: ["a","b"])])
        XCTAssertEqual(AlarmOccurrencePlanner.dates(rule: one, after: Date(timeIntervalSince1970: 2000)), [])
        XCTAssertEqual(AlarmOccurrencePlanner.dates(rule: .init(minute: 1440, weekdays: [1]), after: now), [])
    }
}
