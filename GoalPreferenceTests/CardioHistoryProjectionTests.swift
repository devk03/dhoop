import XCTest

final class CardioHistoryProjectionTests: XCTestCase {
    private func row(_ id: String, kind: CardioHistoryKind = .recorded, start: Double = 1000, end: Double = 1600, title: String = "Running") -> CardioHistoryItem {
        CardioHistoryItem(id: id, kind: kind, title: title, source: kind == .recorded ? "Apple Health" : "WHOOP", start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end), duration: end - start, averageHR: nil, peakHR: nil)
    }
    func testRecordedRepresentationLinksWithoutDeletingEitherPayload() {
        let groups = CardioHistoryProjection.groups([row("local", kind: .zone), row("apple", start: 1001, end: 1601)])
        XCTAssertEqual(groups.count, 1); XCTAssertEqual(groups[0].primary.id, "local")
        XCTAssertEqual(Set(groups[0].recordings.map(\.id)), ["local", "apple"])
    }
    func testOverlappingAndAmbiguousSessionsRemainDistinct() {
        XCTAssertEqual(CardioHistoryProjection.groups([row("long", kind: .zone, start: 1000, end: 3000), row("part", start: 1200, end: 1600)]).count, 2)
        XCTAssertEqual(CardioHistoryProjection.groups([row("zone", kind: .zone), row("hiit", kind: .hiit), row("apple")]).count, 3)
    }
    func testHistoryDoesNotStopAtTwentyOrFortyRecords() {
        let records = (0..<101).map { row("\($0)", start: Double($0 * 1000), end: Double($0 * 1000 + 500)) }
        let groups = CardioHistoryProjection.groups(records)
        XCTAssertEqual(groups.count, 101); XCTAssertEqual(groups.first?.id, "100"); XCTAssertEqual(groups.last?.id, "0")
    }
    func testExactDateWindowKindAndSearchApplyTogether() {
        let window = MetricDateWindow(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2000), through: Date(timeIntervalSince1970: 2000), fromDay: "1970-01-01", toDay: "1970-01-01", days: 1)
        let groups = CardioHistoryProjection.groups([row("before", kind: .zone, start: 999), row("wanted", kind: .intervals, start: 1000, title: "Intervals"), row("after", kind: .intervals, start: 2001)])
        XCTAssertEqual(CardioHistoryProjection.filtered(groups, window: window, kind: .intervals, search: "WHOOP").map(\.id), ["wanted"])
        XCTAssertTrue(CardioHistoryProjection.filtered(groups, window: window, kind: .zone, search: "").isEmpty)
    }
    func testIndoorCardioAndUnclassifiedActivityAreNotLostToGPSFlags() {
        for sport in ["Indoor cycle", "Elliptical", "HIIT", "Treadmill run", "Workout", "Other", "Free-form sport"] {
            XCTAssertTrue(CardioHistoryProjection.includesSport(sport))
        }
        for sport in ["Strength", "Strength Training", "TraditionalStrengthTraining", "Functional Strength Training"] {
            XCTAssertFalse(CardioHistoryProjection.includesSport(sport))
        }
        XCTAssertFalse(CardioHistoryProjection.includesSport(" Meditation "))
    }
}
