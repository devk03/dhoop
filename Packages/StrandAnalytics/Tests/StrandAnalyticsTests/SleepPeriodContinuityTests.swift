import XCTest
@testable import StrandAnalytics

final class SleepPeriodContinuityTests: XCTestCase {
    func testMergingUsesOnlyConnectedNeighbors() {
        func p(_ start: Int, _ end: Int, _ stage: String = "sleep") -> SleepStager.Period {
            SleepStager.Period(stage: stage, start: start, end: end)
        }
        let cases = [
            [p(0,599),p(21600,26999)],
            [p(0,5399),p(27000,27599)],
            [p(0,5399),p(5400,5599,"active"),p(27000,32399)],
            [p(0,5399),p(27000,27199,"active"),p(27200,32599)],
            [p(0,5399),p(5400,5599,"active"),p(5600,10999)],
            [p(0,599),p(1799,7198)], [p(0,599),p(1800,7199)],
        ]
        let expected = ["sleep:21600:26999", "sleep:0:5399", "sleep:0:5599,sleep:27000:32399",
                        "sleep:0:5399,sleep:27000:32599", "sleep:0:10999", "sleep:0:7198", "sleep:1800:7199"]
        XCTAssertEqual(cases.map { SleepStager.mergePeriods($0).map { "\($0.stage):\($0.start):\($0.end)" }.joined(separator: ",") }, expected)
    }
}
