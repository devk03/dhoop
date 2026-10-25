#if os(iOS)
import SwiftUI
import StrandDesign

@MainActor
enum DayHubRenderProof {
    static func readIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--day-hub-read-proof") else { return }
        await DayHubPublisher.shared.waitForRefresh()
        let snap = DayHubPublisher.shared.snapshot, now = Date()
        let report: [String: Any] = ["schemaVersion": 1, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "runId": CalendarReaderProvisioner.verificationRun, "writesAttempted": false,
            "snapshotPresent": snap != nil, "foodToday": snap?.food(at: now) != nil,
            "workoutsToday": snap?.workouts(at: now) != nil, "workoutCompleteRead": snap?.workouts(at: now)?.complete == true,
            "calendarWindowComplete": DayHubWindow(now: now).complete(snap?.calendarDays ?? []),
            "sleepRecordPresent": snap?.sleep != nil, "eightSleepRecordPresent": snap?.sleep?.eightSleepMinutes != nil]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-day-hub-read-proof.json"), options: .atomic)
        }
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--day-hub-render-proof") else { return }
        let prefix = "--day-hub-render-run="
        let run = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }.flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }?.uuidString ?? "manual"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-day-hub-ui-v1")
        var success = false
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now = CalendarReaderDates.instant("2026-10-24T19:30:00Z")!
            let events: [CalendarWidgetSnapshot.Event] = [
                .init(id: "demo1", title: "Design review", start: now.addingTimeInterval(-4500), end: now.addingTimeInterval(-1800), allDay: false, organizer: "Maya Chen", pending: false, localProjection: false),
                .init(id: "demo2", title: "Focus work", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(1800), allDay: false, organizer: nil, pending: false, localProjection: false),
                .init(id: "demo3", title: "Lunch with Alex", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), allDay: false, organizer: nil, pending: true, localProjection: false)]
            let snap = DayHubSnapshot(savedAt: now, timeZoneID: "America/Los_Angeles", food: .init(day: "2026-10-24", readAt: now, protein: 84, calories: 1650, entries: 4, estimatedEntries: 3),
                workouts: .init(day: "2026-10-24", readAt: now, complete: true, rows: [.init(id: 1, title: "Upper body", status: "completed", timing: "5:00 PM")]),
                sleep: .init(wakeDay: "2026-10-24", readAt: now, whoopMinutes: 468, eightSleepMinutes: 457, whoopMethod: "Dhoop estimate"),
                calendarDays: [.init(date: "2026-10-24", readAt: now, complete: true, events: events)])
            try await CalendarReaderRenderProof.capture(DayHubView(snapshot: snap, now: now).padding(NoopMetrics.space3), name: "widget-large", width: 364, height: 440, folder: folder)
            try await CalendarReaderRenderProof.capture(DayHubView(snapshot: snap, now: now).padding(NoopMetrics.space3), name: "widget-narrow", width: 320, height: 440, folder: folder)
            try await CalendarReaderRenderProof.capture(DayHubView(snapshot: snap, now: now).padding(NoopMetrics.space3), name: "widget-light", width: 364, height: 440, scheme: .light, folder: folder)
            try await CalendarReaderRenderProof.capture(DayHubView(snapshot: nil, now: now).padding(NoopMetrics.space3), name: "widget-unavailable", width: 364, height: 440, folder: folder)
            try await CalendarReaderRenderProof.capture(ScreenScaffold(title: nil) { DayHubView(snapshot: snap, now: now, expanded: true) }, name: "overview-390", width: 390, height: 1400, folder: folder)
            try await CalendarReaderRenderProof.capture(ScreenScaffold(title: nil) { DayHubView(snapshot: snap, now: now, expanded: true) }, name: "overview-accessibility", width: 390, height: 2200, type: .accessibility3, folder: folder)
            success = true
        } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "rendered": success, "syntheticOnly": true, "fixtureNetworkUsed": false, "runId": run,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
}
#endif
