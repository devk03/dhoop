import Foundation

/// Explicit bounded read-only installation evidence. No calendar content or credential values are exported.
@MainActor
enum CalendarReaderReadProof {
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--calendar-reader-proof") else { return }
        let client = CalendarReaderClient.shared, date = CalendarReaderDates.key(Date())
        var report: [String: Any] = ["schemaVersion": 1, "status": "not_verified", "writesAttempted": false]
        await client.loadDay(date)
        if let first = client.day.first, first.date == date, !client.stale, client.error == nil {
            report["status"] = "authenticated_day_verified"; report["date"] = date; report["readAt"] = first.readAt
            report["eventCount"] = client.day.events.count; report["hasMore"] = client.day.cursor != nil
            if let event = client.day.events.first(where: { !$0.linkedTaskRefs.isEmpty }) ?? client.day.events.first {
                do {
                    let detail = try await client.readEvent(date: date, id: event.id)
                    report["eventDetailVerified"] = true; report["linkedTaskCount"] = detail.tasks.count
                    report["availableTaskCount"] = detail.tasks.filter(\.available).count
                    report["humanAuthoredCount"] = detail.tasks.filter { $0.brief?.humanDescriptionAuthor == "human" }.count
                } catch { report["eventDetailVerified"] = false }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-calendar-read-proof.json"), options: .atomic)
        }
    }
}
