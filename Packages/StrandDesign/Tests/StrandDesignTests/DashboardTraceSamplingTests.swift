import XCTest
@testable import StrandDesign

final class DashboardTraceSamplingTests: XCTestCase {
    func testOneBudgetPreservesEveryRunBoundaryAndExtrema() {
        var input: [TrendPoint] = []
        for run in 0..<30 {
            for offset in 0..<700 {
                let timestamp = Double(run * 1000 + offset)
                let value: Double = offset == 137 ? 200 : offset == 515 ? 40 : 72
                input.append(TrendPoint(date: Date(timeIntervalSince1970: timestamp), value: value, segment: String(run)))
            }
        }
        let output = DashboardTraceSampling.reduce(input, targetCount: 400)
        XCTAssertLessThanOrEqual(output.count, 400)
        XCTAssertEqual(Set(output.map(\.segment)), Set(input.map(\.segment)))
        for run in 0..<30 {
            let points = output.filter { $0.segment == String(run) }
            XCTAssertEqual(points.first?.date, Date(timeIntervalSince1970: Double(run * 1000)))
            XCTAssertEqual(points.last?.date, Date(timeIntervalSince1970: Double(run * 1000 + 699)))
            XCTAssertTrue(points.contains { $0.value == 200 })
            XCTAssertTrue(points.contains { $0.value == 40 })
        }
        let actual = Dictionary(uniqueKeysWithValues: input.map { ($0.date, $0.value) })
        XCTAssertTrue(output.allSatisfy { actual[$0.date] == $0.value }, "Display reduction must never invent a sample")
        XCTAssertEqual(output.map(\.date), output.map(\.date).sorted())
    }

    func testManyIsolatedReadingsArePreservedInsteadOfDeletingRunsToMeetBudget() {
        let input = (0..<500).map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0)), value: 72, segment: String($0))
        }
        XCTAssertEqual(DashboardTraceSampling.reduce(input, targetCount: 400).map(\.date), input.map(\.date))
    }

    func testSmallTrendsAndShortRunsRemainUnchanged() {
        let input = (0..<30).map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0)), value: Double($0), segment: String($0 / 2))
        }
        XCTAssertEqual(DashboardTraceSampling.reduce(input, targetCount: 400).map(\.date), input.map(\.date))
    }
}
