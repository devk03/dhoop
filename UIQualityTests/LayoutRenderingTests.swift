import XCTest
import SwiftUI
import StrandDesign
import UIKit

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
    func testInlineSetRowsRemainReadableAtNarrowLargeAndLightDarkSizes() async throws {
        for (label, size, scheme, width) in [("narrow-dark", DynamicTypeSize.large, ColorScheme.dark, CGFloat(320)),
                                            ("large-dark", .accessibility3, .dark, 390),
                                            ("narrow-light", .large, .light, 320)] {
            let entry = VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Front Squat · Demo layout").font(StrandFont.headline)
                WorkoutSetEntryRow(number: 1, kind: "work", loadUnit: "lb", loadHint: "190", repsHint: "6", completed: true, dirty: false, showRIR: false,
                    load: .constant("190"), reps: .constant("6"), rir: .constant(""), save: {})
                WorkoutSetEntryRow(number: 2, kind: "work", loadUnit: "lb", loadHint: "190", repsHint: "6", completed: false, dirty: false, showRIR: true,
                    load: .constant(""), reps: .constant(""), rir: .constant(""), save: {})
                WorkoutSetEntryRow(number: 3, kind: "warmup", loadUnit: nil, loadHint: "", repsHint: "10", completed: false, dirty: false, showRIR: false,
                    load: .constant(""), reps: .constant(""), rir: .constant(""), save: {})
            }.padding(NoopMetrics.space4).background(StrandPalette.surfaceRaised).foregroundStyle(StrandPalette.textPrimary)
            try await renderHosted(entry, name: "inline-sets-" + label, size: size, scheme: scheme, width: width)
        }
    }

    func testSleepShareArtworkRendersWithRealControlsExcludedAndMissingData() throws {
        let start = ISO8601DateFormatter().date(from: "2026-10-15T06:00:00Z")!.timeIntervalSince1970
        let source = SleepExportReport.Source(id: "whoop", name: "WHOOP", method: "Demo estimate", totalMinutes: 462,
            stages: [88, 105, 252, 17], timeline: .init(start: start, end: start + 480 * 60, method: "Demo stages", intervals: [
                .init(start: start, end: start + 88 * 60, stage: "deep"),
                .init(start: start + 88 * 60, end: start + 208 * 60, stage: "core"),
                .init(start: start + 218 * 60, end: start + 323 * 60, stage: "rem"),
                .init(start: start + 323 * 60, end: start + 455 * 60, stage: "core"),
                .init(start: start + 455 * 60, end: start + 472 * 60, stage: "unspecified"),
                .init(start: start + 472 * 60, end: start + 480 * 60, stage: "awake")]),
            metrics: [.init(title: "Average HR", value: 57, unit: "bpm", detail: "Demo readings"),
                .init(title: "HRV", value: 64, unit: "ms", detail: "Demo rMSSD"), .init(title: "Resting HR", value: 51, unit: "bpm", detail: "Demo RHR")])
        let missing = SleepExportReport.Source(id: "comparison", name: "8sleep", method: "No record for this date", totalMinutes: nil,
            stages: [nil, nil, nil, nil], timeline: nil, metrics: [])
        let report = SleepExportReport(day: "2026-10-15", goalMinutes: 495, selectedSource: "whoop", sources: [source, missing])
        try render(SleepExportCard(report: report), name: "sleep-export-demo-390", size: .large, scheme: .dark, width: 390)
        try render(SleepExportCard(report: report), name: "sleep-export-demo-narrow", size: .large, scheme: .light, width: 320)
        try render(SleepExportCard(report: report), name: "sleep-export-demo-large-text", size: .accessibility3, scheme: .dark, width: 390)
        let absent = SleepExportReport(day: "2026-10-15", goalMinutes: 495, selectedSource: "comparison", sources: [missing])
        try render(SleepExportCard(report: absent), name: "sleep-export-demo-unavailable", size: .large, scheme: .dark, width: 390)
    }

    private func renderHosted<V: View>(_ content: V, name: String, size: DynamicTypeSize, scheme: ColorScheme, width: CGFloat) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: content.frame(width: width).environment(\.dynamicTypeSize, size).environment(\.colorScheme, scheme).ignoresSafeArea())
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: 10000))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: fitted)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; oldKey?.makeKey() }
        await Task.yield(); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: fitted).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: fitted), afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        XCTAssertGreaterThan(image.size.height, 100)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
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
    func testScrollDeliversPressWithoutDelayAndKeepsNativePanCancellation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ScrollView {
            Button("UI test fixture") { }.buttonStyle(NoopButtonStyle(.primary))
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; oldKey?.makeKey() }
        host.view.layoutIfNeeded()
        await Task.yield()
        host.view.layoutIfNeeded()
        func find(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap(find).first
        }
        let scroll = try XCTUnwrap(find(host.view))
        XCTAssertFalse(scroll.delaysContentTouches)
        XCTAssertTrue(scroll.canCancelContentTouches)
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
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
