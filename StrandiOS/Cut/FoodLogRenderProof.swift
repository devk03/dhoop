import SwiftUI
import StrandDesign

@MainActor
enum FoodLogRenderProof {
    private static func screen(store: ProteinLogStore, goals: NutritionGoalClient, defaults: UserDefaults, expanded: Bool = false) -> some View {
        ScreenScaffold(title: nil) {
            Text("Food").font(StrandFont.title1).frame(maxWidth: .infinity, alignment: .leading)
            FoodInlineEntry(store: store, day: "2026-10-24")
            if !store.storageUnavailable {
                FoodCalorieSummaryCard(estimates: [250, 400, nil, 0], dayTotals: [650], singleDay: true, proteinGrams: 84)
            }
            NutritionGoalEditor(day: "2026-10-24", client: goals, initiallyExpanded: expanded, automaticallyConnect: false)
        }.defaultAppStorage(defaults)
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--food-log-render-proof") else { return }
        let prefix = "--food-log-render-run="
        let run = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }.flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }?.uuidString ?? "manual"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-food-log-ui-v1")
        var success = false
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let defaults = UserDefaults(suiteName: "dhoop-food-fixture-" + run)!
            let store = ProteinLogStore(defaults: defaults)
            let connection = NutritionGoalConnection(credentials: .init(endpoint: "https://track.kunjadia.dev/api/webhooks/sleep", bearer: String(repeating: "s", count: 43), clientId: "synthetic", clientSecret: "synthetic", proteinBearer: String(repeating: "p", count: 43)), installationId: "00000000-0000-4000-8000-000000000001")
            let period = CalorieGoalPeriod(id: "00000000-0000-4000-8000-000000000002", startDate: "2026-10-24", endDate: "2026-11-07", minCalories: 2000, maxCalories: 2400)
            let goals = NutritionGoalClient(defaults: defaults, connection: { connection }, send: { _, _ in
                try JSONEncoder().encode(NutritionGoalDocument(schemaVersion: 1, kind: "nutrition_goals", installationId: connection.installationId, version: 1, periods: [period]))
            })
            _ = await goals.refresh(activate: true)
            for (key, value) in [("id", period.id), ("from", period.startDate), ("through", period.endDate), ("minimum", "2000"), ("maximum", "2400")] { defaults.set(value, forKey: "dhoop.food.goalDraft." + key) }
            try await CalendarReaderRenderProof.capture(screen(store: store, goals: goals, defaults: defaults), name: "food-390", width: 390, height: 1000, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(store: store, goals: goals, defaults: defaults), name: "food-320", width: 320, height: 1100, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(store: store, goals: goals, defaults: defaults), name: "food-light", width: 390, height: 1000, scheme: .light, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(store: store, goals: goals, defaults: defaults), name: "food-accessibility", width: 390, height: 1600, type: .accessibility3, folder: folder)
            try await CalendarReaderRenderProof.capture(screen(store: store, goals: goals, defaults: defaults, expanded: true), name: "goal-expanded", width: 390, height: 1400, folder: folder)
            try await CalendarReaderRenderProof.capture(FoodCalorieSummaryCard(estimates: [nil, nil], dayTotals: [], singleDay: true, proteinGrams: 25).padding(NoopMetrics.space4), name: "calories-unknown", width: 390, height: 350, folder: folder)
            let bad = UserDefaults(suiteName: "dhoop-food-fixture-error-" + run)!
            bad.set(Data("synthetic unreadable food log".utf8), forKey: ProteinLogStore.entriesKey)
            try await CalendarReaderRenderProof.capture(screen(store: ProteinLogStore(defaults: bad), goals: goals, defaults: defaults), name: "food-storage-error", width: 390, height: 1100, folder: folder)
            success = true
        } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "rendered": success, "syntheticOnly": true, "fixtureNetworkUsed": false,
            "runId": run, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic) }
    }
}
