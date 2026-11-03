#if DEBUG && os(iOS) && targetEnvironment(simulator)
import SwiftUI
import StrandDesign

/// Opt-in interactive fixture, isolated from owner credentials, HTTP and production Health records.
struct HealthJournalDemoScreen: View {
    @StateObject private var client: HealthJournalClient
    @State private var seeded = false
    init() {
        let args = ProcessInfo.processInfo.arguments
        let raw = args.first { $0.hasPrefix("--health-ui-run=") }.map { String($0.dropFirst("--health-ui-run=".count)) } ?? UUID().uuidString
        let run = UUID(uuidString: raw)?.uuidString ?? "manual"
        _client = StateObject(wrappedValue: HealthJournalRenderProof.client(empty: args.contains("--health-ui-empty"),
            failure: args.contains("--health-ui-offline"), folder: FileManager.default.temporaryDirectory.appendingPathComponent("health-ui-" + run)))
    }
    var body: some View {
        NavigationStack {
            HealthJournalView(client: client)
                .safeAreaInset(edge: .top) {
                    Text(verbatim: "Design verification · Demo data · No HTTP")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity).padding(NoopMetrics.space2).background(StrandPalette.surfaceBase)
                }
        }.task {
            guard !seeded else { return }; seeded = true
            if ProcessInfo.processInfo.arguments.contains("--health-ui-seed-photo"), client.state.drafts.isEmpty,
               let bytes = HealthJournalRenderProof.photoBytes, let id = try? client.createEntry() {
                try? await client.addPhoto(bytes, draftId: id)
            }
        }
    }
}
#endif
