import XCTest
import SwiftUI
import StrandDesign

@MainActor
final class LayoutRenderingTests: XCTestCase {
    func testStageBreakdownAndWorkoutChartRenderAtNarrowLargeAndLightDarkSizes() throws {
        let rows = SleepStageBreakdown.Kind.allCases.map {
            SleepStageBreakdown.Row(kind: $0, duration: $0 == .unclassified ? "Unavailable" : "1h 30m", fraction: $0 == .unclassified ? nil : 0.25)
        }
        let sleep = SleepStageBreakdown(dateLabel: "Layout fixture · Demo data", sources: [
            .init(name: "WHOOP", detail: "Demo estimate", rows: rows),
            .init(name: "8sleep", detail: "Demo import via Apple Health", rows: rows)
        ])
        let start = Date(timeIntervalSince1970: 1000)
        let points = [RunningTracePoint(timestamp: 1000, bpm: 100, segment: 1),
                      .init(timestamp: 1060, bpm: 140, segment: 1),
                      .init(timestamp: 1200, bpm: 130, segment: 2), .init(timestamp: 1300, bpm: 150, segment: 2)]
        let chart = WorkoutHeartRateCard(points: points, start: start, end: start.addingTimeInterval(300), source: "Demo data · layout fixture", interactive: false)
        let lifting = StrengthWorkoutCard(title: "Demo · Upper A", scheduledLabel: "Tomorrow · Thu, Oct 15", summary: "6 exercises · 18 sets", open: {}, schedule: {})
        let empty = WorkoutHeartRateCard(points: [], start: start, end: start.addingTimeInterval(300), source: "No stored trace", interactive: false)
        for (label, size, scheme, width) in [("narrow-dark", DynamicTypeSize.large, ColorScheme.dark, CGFloat(320)),
                                            ("large-dark", .accessibility3, .dark, 390),
                                            ("narrow-light", .large, .light, 320)] {
            try render(lifting, name: "lifting-" + label, size: size, scheme: scheme, width: width)
            try render(sleep, name: "sleep-" + label, size: size, scheme: scheme, width: width)
            try render(chart, name: "workout-" + label, size: size, scheme: scheme, width: width)
            try render(empty, name: "empty-" + label, size: size, scheme: scheme, width: width)
        }
    }
    private func render<V: View>(_ view: V, name: String, size: DynamicTypeSize, scheme: ColorScheme, width: CGFloat) throws {
        let renderer = ImageRenderer(content: view.frame(width: width).environment(\.dynamicTypeSize, size).environment(\.colorScheme, scheme))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        XCTAssertGreaterThan(image.size.height, 100)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testPendingReservationTimingOnNativeMainActor() async {
        let action = NoopActionController()
        let begin = CACurrentMediaTime()
        action.submit { }
        XCTAssertEqual(action.state, .working)
        let elapsed = CACurrentMediaTime() - begin
        XCTAssertLessThan(elapsed, 0.100)
        let note = XCTAttachment(string: "MainActor pending reservation: \(elapsed * 1000) ms. This does not measure finger-to-display latency.")
        note.lifetime = .keepAlways; add(note)
    }
}
