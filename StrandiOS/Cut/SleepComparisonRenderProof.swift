import SwiftUI
import StrandDesign

@MainActor
enum SleepComparisonRenderProof {
    private static func screen(whoop: Double? = 468, comparison: Double? = 457) -> some View {
        ScreenScaffold(title: nil) {
            Text("Sleep").font(StrandFont.title1).frame(maxWidth: .infinity, alignment: .leading)
            SleepComparisonRings(dateLabel: "Oct 24, 2026", whoopMinutes: whoop, comparisonName: "8sleep",
                comparisonMinutes: comparison, whoopDetail: whoop == nil ? nil : "Dhoop estimate",
                comparisonDetail: comparison == nil ? nil : "Via Apple Health")
        }
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--sleep-comparison-render-proof") else { return }
        let prefix = "--sleep-comparison-render-run="
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
        let run = argument.flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }?.uuidString ?? "manual"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-sleep-comparison-ui-v1")
        var success = false
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await CalendarReaderRenderProof.capture(screen(), name: "sleep-rings-390", width: 390, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(), name: "sleep-rings-320", width: 320, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(), name: "sleep-rings-light", width: 390, scheme: .light, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(), name: "sleep-rings-accessibility", width: 390, height: 1400, type: .accessibility3, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(comparison: nil), name: "sleep-rings-missing-provider", width: 390, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(whoop: nil, comparison: nil), name: "sleep-rings-empty", width: 390, folder: folder)
            success = true
        } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "rendered": success, "syntheticOnly": true,
            "fixtureNetworkUsed": false, "runId": run, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
}
