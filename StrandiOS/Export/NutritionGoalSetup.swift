#if os(iOS)
import Foundation

/// Explicit setup flags run a bounded read before enabling the already-enrolled nutrition adapter.
@MainActor
enum NutritionGoalSetup {
    static func connectForFoodScreen() async {
        let client = NutritionGoalClient.shared
        guard await client.refresh(activate: true) else { return }
        // The owner requested both apps. Preserve any explicit later opt-out, including false.
        let sync = SleepWebhookClient.shared
        if sync.checkpoint.caloriesEnabled == nil, sync.checkpoint.proteinEnabled == true {
            try? sync.setCaloriesEnabled(true)
        }
    }
    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--enable-nutrition-goals") || arguments.contains("--nutrition-read-proof") else { return }
        let client = NutritionGoalClient.shared
        let verified = await client.refresh(activate: arguments.contains("--enable-nutrition-goals"))
        var caloriesEnabled = false
        if verified && arguments.contains("--enable-calorie-summaries"), SleepWebhookClient.shared.checkpoint.caloriesEnabled != false {
            do { try SleepWebhookClient.shared.setCaloriesEnabled(true); caloriesEnabled = true } catch { }
        }
        let report: [String: Any] = ["schemaVersion": 1, "goalsReadVerified": verified, "writesAttempted": false,
            "caloriesEnabled": caloriesEnabled || SleepWebhookClient.shared.checkpoint.caloriesEnabled == true,
            "goalVersion": client.cached?.document.version ?? -1, "goalCount": client.periods.count,
            "runId": CalendarReaderProvisioner.verificationRun,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-nutrition-read-proof.json"), options: .atomic)
        }
    }
}
#endif
