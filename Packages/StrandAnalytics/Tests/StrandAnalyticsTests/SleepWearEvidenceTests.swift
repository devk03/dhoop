import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class SleepWearEvidenceTests: XCTestCase {
    private func dense(_ from: Int, _ through: Int, bpm: Int = 60) -> [(ts: Int, bpm: Int)] {
        (from...through).map { ($0, bpm) }
    }
    func testSustainedEvidenceAndRejectionBoundaries() {
        let cases: [[(ts: Int, bpm: Int)]] = [
            [], dense(1, 60), dense(1, 61), Array(dense(1, 61).reversed()),
            Array(repeating: (1, 60), count: 500), stride(from: 1, through: 181, by: 5).map { ($0, 60) },
            dense(1, 30) + dense(40, 101), dense(1, 30) + [(31, 0)] + dense(32, 100),
            dense(1, 100) + [(31, 0)], dense(1, 61, bpm: 29), dense(1, 61, bpm: 221),
            dense(1, 61, bpm: 30), dense(1, 61, bpm: 220), dense(1, 100).filter { $0.ts % 5 != 0 },
            dense(1, 30) + dense(35, 65), dense(1, 30) + dense(36, 65),
            dense(1, 61).filter { !Set(stride(from: 3, through: 47, by: 4)).contains($0.ts) },
            dense(1, 61).filter { !Set(stride(from: 3, through: 51, by: 4)).contains($0.ts) },
        ]
        let expected: [Int?] = [nil, nil, 1, 1, nil, nil, 40, 32, 32, nil, nil, 1, 1, 1, 1, nil, 1, nil]
        XCTAssertEqual(cases.map { SleepWearEvidence.confirmedWearStart(samples: $0, after: 0, through: 500) }, expected)
        XCTAssertNil(SleepWearEvidence.confirmedWearStart(samples: dense(1, 100), after: 0, through: 60))
        XCTAssertEqual(SleepWearEvidence.confirmedWearStart(samples: dense(1, 100), after: 30, through: 100), 31)
    }
    func testLaterEventsDoNotEraseEarlierSustainedWear() {
        func event(_ ts: Int, _ kind: String) -> WhoopEvent { WhoopEvent(ts: ts, kind: kind, payload: [:]) }
        let hr = dense(1, 80).map { HRSample(ts: $0.ts, bpm: $0.bpm) }
        let off = event(0, "WRIST_OFF(10)")
        XCTAssertEqual(AnalyticsEngine.offWristIntervals(events: [off], windowEnd: 500, hr: hr).map(\.end), [1])
        XCTAssertEqual(AnalyticsEngine.offWristIntervals(events: [off], windowEnd: 500).map(\.end), [500])
        XCTAssertEqual(AnalyticsEngine.offWristIntervals(events: [event(100, "WRIST_OFF(10)"), off], windowEnd: 500, hr: hr).map(\.end), [1, 500])
        XCTAssertEqual(AnalyticsEngine.offWristIntervals(events: [off, event(300, "WRIST_ON(9)")], windowEnd: 500, hr: hr).map(\.end), [1])
        XCTAssertEqual(AnalyticsEngine.offWristIntervals(events: [off, event(300, "WRIST_ON(9)")], windowEnd: 500).map(\.end), [300])
    }

    func testCutoffTiesAndHalfOpenIntervals() {
        let hr = dense(1, 61)
        func spans(_ events: [(Int, Bool)], _ through: Int, _ readings: [(Int, Int)] = []) -> String {
            SleepWearEvidence.offWristIntervals(events: events, samples: readings, through: through)
                .map { "\($0.start):\($0.end)" }.joined(separator: ",")
        }
        XCTAssertEqual(spans([(0, true), (200, false)], 100), "0:100")
        XCTAssertEqual(spans([(0, true), (200, true)], 100, hr), spans([(0, true)], 100, hr))
        XCTAssertEqual(spans([(0, true), (0, false)], 100), "0:100")
        XCTAssertEqual(spans([(0, false), (0, true), (0, true)], 100), "0:100")
        XCTAssertEqual(spans([(0, true), (61, false)], 100, hr), "0:61")
        XCTAssertEqual(spans([(0, true), (62, false)], 100, hr), "0:1")
        XCTAssertEqual(spans([(0, true), (100, true), (200, false)], 500, hr), "0:1,100:200")
        XCTAssertEqual(spans([(0, true), (100, true), (200, false)], 500), "0:200")
    }
}
