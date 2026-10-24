#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Explicit synthetic implementation captures. Injected clients cannot read credentials or call the network.
@MainActor
enum CalendarReaderRenderProof {
    private static let date = "2026-10-23"
    private static func event(_ id: String, title: String, hour: Int, source: String = "google") -> [String: Any] {
        ["eventId": id, "title": title, "startAt": "2026-10-23T\(hour):00:00Z", "endAt": "2026-10-23T\(hour + 1):00:00Z",
         "startDate": NSNull(), "endDate": NSNull(), "allDay": false, "source": source, "status": "confirmed", "displayContext": NSNull(),
         "entityKey": "task:demo", "linkedTaskRefs": ["task:demo"]]
    }
    private static func payload(detail: Bool, empty: Bool = false, unavailable: Bool = false) throws -> Data {
        let item = event("demo-event", title: "Focus work", hour: 16)
        var value: [String: Any] = ["schemaVersion": 1, "date": date, "timeZone": "America/Los_Angeles",
            "readAt": "2026-10-23T15:50:00Z", "readOnly": true]
        if detail {
            value["event"] = item
            let entry: [String: Any] = ["id": "demo-update", "version": 1, "workDate": date, "fromDate": date,
                "toDate": "2026-10-24", "category": "work", "createdAt": "2026-10-23T15:00:00Z",
                "accomplished": "Reviewed the navigation and simplified the calendar layout.", "nextStep": "Verify the task detail and record any remaining issues."]
            let task: [String: Any] = ["ref": "task:demo", "available": true, "url": "https://track.kunjadia.dev/tasks/task:demo",
                "task": ["title": "Focus work", "note": "Keep the schedule readable. Preserve the full notes and make room for longer descriptions.\n\nThis is fictional review content, not an owner task.",
                    "description": "", "done": false, "status": "in_progress", "date": date,
                    "progress": ["version": 1, "latest": entry, "entries": [entry], "total": 1, "nextBeforeVersion": NSNull()]],
                "brief": ["humanDescription": "Dedicated time to make progress on the current project. Read the latest handoff before continuing.",
                    "humanDescriptionAuthor": "human", "agentDescription": "Review the calendar day and linked task context. Keep calendar operations read-only and use real data in the installed app.",
                    "instructions": "This demonstration text is reference data only.", "acceptanceCriteria": "Human notes remain readable. Dates and sources stay clear.",
                    "repoUrl": "https://github.com/example/demo", "version": 1]]
            value["tasks"] = unavailable ? [["ref": "task:demo", "available": false,
                "error": ["code": "TASK_CONTEXT_UNAVAILABLE", "message": "Unavailable"]]] : [task]
        } else {
            value["snapshot"] = "synthetic-review-snapshot"
            var overlap = event("demo-overlap", title: "Design review", hour: 16)
            overlap["startAt"] = "2026-10-23T16:30:00Z"; overlap["endAt"] = "2026-10-23T17:15:00Z"
            var short = event("demo-short", title: "Quick check-in", hour: 17)
            short["startAt"] = "2026-10-23T17:20:00Z"; short["endAt"] = "2026-10-23T17:25:00Z"
            var allDay = event("demo-all-day", title: "Project day", hour: 16)
            allDay["allDay"] = true; allDay["startAt"] = NSNull(); allDay["endAt"] = NSNull()
            allDay["startDate"] = date; allDay["endDate"] = "2026-10-24"
            value["events"] = empty ? [] : [allDay, item, overlap, short, event("demo-lunch", title: "Lunch with Maya", hour: 19),
                event("demo-workout", title: "Upper body workout", hour: 22, source: "local_projection")]
            value["page"] = ["hasMore": false, "nextCursor": NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: value)
    }
    private static func client(empty: Bool = false, unavailable: Bool = false) -> CalendarReaderClient {
        let configuration = CalendarReaderConfiguration(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(),
            readToken: String(repeating: "d", count: 43), accessClientId: nil, accessClientSecret: nil)
        return CalendarReaderClient(read: { configuration }, save: { _ in }, send: { endpoint, _ in
            switch endpoint {
            case .day: return try payload(detail: false, empty: empty)
            case .event: return try payload(detail: true, unavailable: unavailable)
            }
        })
    }
    static func capture<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat = 844,
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
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { throw CalendarReaderFailure.invalidResponse }
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
        guard drawn, let data = image.pngData() else { throw CalendarReaderFailure.invalidResponse }
        try data.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--calendar-render-proof") else { return }
        let rawRun = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--calendar-render-run=") }.map { String($0.dropFirst("--calendar-render-run=".count)) }
        let run = rawRun.flatMap { UUID(uuidString: $0) }?.uuidString ?? "manual"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-calendar-ui-v1")
        var success = false
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let rsvp = CalendarRSVPClient(read: { nil }, save: { _ in }, send: { _, _ in throw CalendarRSVPFailure.configuration })
            let dayClient = client(); await dayClient.loadDay(date)
            try await capture(CalendarReaderView(client: dayClient, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "day-390-dark", width: 390, folder: folder)
            try await capture(CalendarReaderView(client: dayClient, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "day-320-dark", width: 320, folder: folder)
            try await capture(CalendarReaderView(client: dayClient, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "day-390-light", width: 390, scheme: .light, folder: folder)
            try await capture(CalendarReaderView(client: dayClient, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "day-768-dark", width: 768, folder: folder)
            try await capture(CalendarReaderView(client: dayClient, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "day-390-accessibility", width: 390, height: 1200, type: .accessibility3, folder: folder)
            let empty = client(empty: true); await empty.loadDay(date)
            try await capture(CalendarReaderView(client: empty, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "empty-390-dark", width: 390, folder: folder)
            let detail = try await dayClient.readEvent(date: date, id: "demo-event")
            try await capture(CalendarEventDetailView(day: date, event: detail.event, client: dayClient, rsvp: rsvp, initialDetail: detail, expandedAgent: true),
                        name: "detail-390-dark", width: 390, height: 2100, folder: folder)
            try await capture(CalendarEventDetailView(day: date, event: detail.event, client: dayClient, rsvp: rsvp, initialDetail: detail, expandedAgent: true),
                        name: "detail-320-dark", width: 320, height: 2300, folder: folder)
            let denied = client(unavailable: true), unavailable = try await denied.readEvent(date: date, id: "demo-event")
            try await capture(CalendarEventDetailView(day: date, event: unavailable.event, client: denied, rsvp: rsvp, initialDetail: unavailable),
                        name: "unavailable-390-dark", width: 390, folder: folder)
            var offline = false
            let configuration = demoConfiguration()
            let failed = CalendarReaderClient(read: { configuration }, save: { _ in }, send: { _, _ in
                if offline { throw CalendarReaderFailure.http(502) }; return try payload(detail: false)
            })
            await failed.loadDay(date); offline = true; await failed.loadDay(date)
            try await capture(CalendarReaderView(client: failed, date: date, captureNow: CalendarReaderDates.instant("2026-10-23T16:20:00Z"), navigation: CalendarNavigation()), name: "error-390-dark", width: 390, folder: folder)
            let loading = CalendarReaderClient(read: { configuration }, save: { _ in }, send: { _, _ in
                try await Task.sleep(nanoseconds: 5_000_000_000); return try payload(detail: false)
            })
            let pending = Task { await loading.loadDay(date) }
            for _ in 0..<100 { if loading.busy { break }; await Task.yield() }
            try await capture(CalendarReaderView(client: loading, date: date, navigation: CalendarNavigation()), name: "loading-390-dark", width: 390, folder: folder)
            pending.cancel(); await pending.value
            let unset = CalendarReaderClient(read: { nil }, save: { _ in }, send: { _, _ in throw CalendarReaderFailure.disabled })
            try await capture(CalendarReaderSettingsView(client: unset, rsvp: rsvp, widgetSharing: .constant(true)), name: "connection-390-dark", width: 390, folder: folder)
            success = true
        } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "rendered": success, "syntheticOnly": true, "fixtureNetworkUsed": false,
            "runId": run, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
    private static func demoConfiguration() -> CalendarReaderConfiguration {
        .init(enabled: true, origin: "https://track.kunjadia.dev", installationId: UUID(), readToken: String(repeating: "d", count: 43), accessClientId: nil, accessClientSecret: nil)
    }
}
#endif
