#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Explicit visual QA. All controller/files/transmissions are synthetic and cannot reach real BLE.
@MainActor
enum DhoopTimerRenderProof {
    private static func capture<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat = 844,
                                         scheme: ColorScheme = .dark, type: DynamicTypeSize = .large, folder: URL) async throws {
        let caption = ["IMPLEMENTATION", "SYNTHETIC DATA", "\(Int(width)) PT"].joined(separator: " · ")
        let content = VStack(spacing: 0) {
            Text(verbatim: caption)
                .font(StrandFont.caption).padding(NoopMetrics.space2)
            view
        }.frame(width: width, height: height)
            .background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, type)
            .environment(\.horizontalSizeClass, width >= 768 ? .regular : .compact)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { throw CocoaError(.fileReadCorruptFile) }
        let host = UIHostingController(rootView: content), window = UIWindow(windowScene: scene)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.frame = bounds; window.windowLevel = .init(rawValue: UIWindow.Level.normal.rawValue - 1)
        window.backgroundColor = UIColor(StrandPalette.surfaceBase); window.isOpaque = true
        host.view.backgroundColor = UIColor(StrandPalette.surfaceBase); host.view.isOpaque = true
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = bounds; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            drawn = host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        guard drawn, let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
        try data.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--alarm-timer-render-proof") else { return }
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--alarm-timer-render-run=") }
        let run = argument.flatMap { UUID(uuidString: String($0.dropFirst("--alarm-timer-render-run=".count))) }?.uuidString ?? "manual"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-alarm-timer-ui-v1")
        let fixtures = FileManager.default.temporaryDirectory.appendingPathComponent("alarm-timer-fixtures-" + run)
        var success = false, stage = "starting"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
            let buzz = BuzzDeliveryCoordinator(file: fixtures.appendingPathComponent("buzz.json"))
            let connection = UUID(); buzz.link = { .init(deviceId: "synthetic-strap", connection: connection, ready: true) }
            buzz.transmit = { _ in nil }
            let idle = DhoopTimerController(file: .init(url: fixtures.appendingPathComponent("idle.json")))
            idle.attach(coordinator: buzz, foreground: false, keepAwake: { _ in })
            let rows = [AlarmOverviewRow(id: "demo1", time: "7:00 AM", label: "Wake up", repeatText: "Weekdays", status: "Stored on WHOOP", enabled: true),
                AlarmOverviewRow(id: "demo2", time: "8:30 AM", label: "Weekend", repeatText: "Weekends", status: "Off", enabled: false)]
            stage = "overview"
            try await capture(overview(rows: rows, buzz: buzz), name: "alarms-390-dark", width: 390, folder: folder)
            try await capture(overview(rows: rows, buzz: buzz), name: "alarms-320-dark", width: 320, folder: folder)
            try await capture(overview(rows: rows, buzz: buzz), name: "alarms-390-light", width: 390, scheme: .light, folder: folder)
            try await capture(overview(rows: [], buzz: buzz), name: "alarms-empty", width: 390, folder: folder)
            stage = "timer-idle"
            try await capture(timerScreen(idle), name: "timer-idle-390", width: 390, folder: folder)
            try await capture(timerScreen(idle), name: "timer-idle-320", width: 320, folder: folder)
            try await capture(timerScreen(idle), name: "timer-idle-light", width: 390, scheme: .light, folder: folder)
            var now = Date().addingTimeInterval(-18)
            let running = DhoopTimerController(file: .init(url: fixtures.appendingPathComponent("running.json")), clock: { now })
            running.attach(coordinator: buzz, foreground: false, keepAwake: { _ in }); _ = running.start(seconds: 600, backup: false)
            stage = "timer-running"
            try await capture(timerScreen(running), name: "timer-running", width: 390, folder: folder)
            try await capture(timerScreen(running), name: "timer-accessibility", width: 390, height: 1200, type: .accessibility3, folder: folder)
            now = Date(); _ = running.pause()
            try await capture(timerScreen(running), name: "timer-paused", width: 390, folder: folder)
            _ = running.cancel()
            let bad = fixtures.appendingPathComponent("corrupt.json"); try Data("synthetic invalid timer".utf8).write(to: bad)
            let failed = DhoopTimerController(file: .init(url: bad))
            try await capture(timerScreen(failed), name: "timer-storage-error", width: 390, folder: folder)
            let alarmManager = DhoopAlarmManager(file: .init(url: fixtures.appendingPathComponent("alarm-state.json")))
            stage = "settings"
            try await capture(AlarmOptionsContent(manager: alarmManager, capturedAt: Date()), name: "alarm-settings", width: 390, height: 1100, folder: folder)
            success = true
        } catch { }
        let result: [String: Any] = ["schemaVersion": 1, "rendered": success, "syntheticOnly": true, "fixtureBLEUsed": false,
            "stage": stage, "runId": run, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: result) { try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
    private static func overview(rows: [AlarmOverviewRow], buzz: BuzzDeliveryCoordinator) -> some View {
        ScreenScaffold(title: nil) {
            VStack(spacing: NoopMetrics.space4) {
                AlarmHomeHeader(section: .constant("Alarms"), showSettings: {}, add: {})
                AlarmConnectionBadge(connected: true, battery: 78)
                AlarmOverviewRows(rows: rows, add: {}, toggle: { _, _ in }, edit: { _ in }, skip: { _ in }, remove: { _ in })
                AlarmTestBuzzButton(coordinator: buzz, deviceID: "synthetic-strap", ready: true)
            }
        }
    }
    private static func timerScreen(_ timer: DhoopTimerController) -> some View {
        ScreenScaffold(title: nil) {
            VStack(spacing: NoopMetrics.space4) {
                AlarmHomeHeader(section: .constant("Timers"), showSettings: {}, add: {})
                DhoopTimerPanel(timer: timer)
            }
        }
    }
}
#endif
