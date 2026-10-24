#if os(iOS)
import SwiftUI
import WidgetKit
import StrandDesign

@MainActor
enum CalendarInvitationRenderProof {
    private static let date = "2026-10-24"
    private static func event(status: String = "needsAction", allowed: Bool = true) throws -> CalendarReaderEvent {
        let values: [String: Any] = ["eventId": "synthetic-invitation", "title": "Design review", "startAt": "2026-10-24T17:00:00Z", "endAt": "2026-10-24T17:30:00Z",
            "allDay": false, "source": "google", "status": "confirmed", "linkedTaskRefs": [], "etag": "\"synthetic-v1\"",
            "invitation": ["organizer": ["email": "maya@example.test", "displayName": "Maya Chen", "self": false],
                "creator": ["email": "jordan@example.test", "displayName": "Jordan Lee", "self": false],
                "self": ["email": "owner@example.test", "displayName": NSNull(), "self": true], "responseStatus": status,
                "isInvitation": true, "pending": status == "needsAction", "canAccept": allowed, "acceptBlockedReason": allowed ? NSNull() : "rsvp_not_configured",
                "scope": "occurrence", "recurringEventId": "synthetic-series"]]
        return try JSONDecoder().decode(CalendarReaderEvent.self, from: JSONSerialization.data(withJSONObject: values))
    }
    private static func screen(event: CalendarReaderEvent, connected: Bool, error: String? = nil) -> some View {
        ScreenScaffold(title: nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text(verbatim: event.title).font(StrandFont.title1)
                Text(verbatim: date).font(StrandFont.caption)
                CalendarEventTime(event: event).font(StrandFont.title2)
                CalendarInvitationCard(event: event, connected: connected, accepting: false, requiresRefresh: error != nil, accept: {})
                CalendarAcceptanceStatus(error: error, requiresRefresh: error != nil, refresh: {})
            }
        }
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--calendar-invitation-render-proof") else { return }
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--calendar-invitation-render-run=") }
        let run = argument.flatMap { UUID(uuidString: String($0.dropFirst("--calendar-invitation-render-run=".count))) }?.uuidString ?? "manual"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-calendar-invitation-ui-v1")
        var success = false
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pending = try event()
            try await CalendarReaderRenderProof.capture(screen(event: pending, connected: true), name: "invitation-pending-390", width: 390, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(event: pending, connected: true), name: "invitation-pending-320", width: 320, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(event: pending, connected: true), name: "invitation-light", width: 390, scheme: .light, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(event: pending, connected: true), name: "invitation-accessibility", width: 390, height: 1400, type: .accessibility3, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(event: try event(status: "accepted", allowed: false), connected: true), name: "invitation-accepted", width: 390, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(event: try event(allowed: false), connected: false), name: "invitation-setup-pending", width: 390, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(event: pending, connected: true, error: CalendarRSVPFailure.unconfirmed.localizedDescription), name: "invitation-error", width: 390, folder: folder)
            let now = CalendarReaderDates.instant("2026-10-24T16:15:00Z")!
            let first = CalendarWidgetSnapshot.Event(id: "demo1", title: "Design review", start: now.addingTimeInterval(2700), end: now.addingTimeInterval(4500), allDay: false, organizer: "Maya Chen", pending: true, localProjection: false)
            let second = CalendarWidgetSnapshot.Event(id: "demo2", title: "Product sync", start: now.addingTimeInterval(13500), end: now.addingTimeInterval(17100), allDay: false, organizer: "Alex Rivera", pending: false, localProjection: false)
            let snapshot = CalendarWidgetSnapshot(days: [.init(date: date, readAt: now, complete: true, events: [first, second])])
            let entry = CalendarWidgetEntry(date: now, snapshot: snapshot)
            try await CalendarReaderRenderProof.capture(CalendarWidgetView(entry: entry, family: .systemSmall), name: "widget-small", width: 170, height: 220, folder: folder)
            try await CalendarReaderRenderProof.capture(CalendarWidgetView(entry: entry, family: .systemMedium), name: "widget-medium", width: 360, height: 230, folder: folder)
            try await CalendarReaderRenderProof.capture(CalendarWidgetView(entry: entry, family: .systemLarge), name: "widget-large", width: 360, height: 430, folder: folder)
            try await CalendarReaderRenderProof.capture(CalendarWidgetView(entry: .init(date: now, snapshot: nil), family: .systemMedium), name: "widget-unavailable", width: 360, height: 230, folder: folder)
            success = true
        } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "rendered": success, "syntheticOnly": true, "fixtureNetworkUsed": false,
            "runId": run, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
}
#endif
