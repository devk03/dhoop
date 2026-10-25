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
        let sync = SleepWebhookClient.shared
        let raw: Data?
        let credentialReadStatus: String
        do { raw = try SleepWebhookKeychain.read("credentials"); credentialReadStatus = raw == nil ? "not_found" : "present" }
        catch { raw = nil; credentialReadStatus = "unreadable" }
        let secret = raw.flatMap { try? JSONDecoder().decode(SleepWebhookCredentials.self, from: $0) }
        let report: [String: Any] = ["schemaVersion": 1, "goalsReadVerified": verified, "writesAttempted": false,
            "caloriesEnabled": caloriesEnabled || SleepWebhookClient.shared.checkpoint.caloriesEnabled == true,
            "goalVersion": client.cached?.document.version ?? -1, "goalCount": client.periods.count,
            "diagnostic": client.diagnostic ?? "none", "syncStorageUnavailable": sync.storageUnavailable,
            "syncDestinationVerified": !sync.storageUnavailable && !sync.checkpoint.delivery.endpoint.isEmpty,
            "credentialReadStatus": credentialReadStatus, "credentialValidVerified": secret?.isValid == true,
            "proteinCredentialVerified": secret?.hasProteinBearer == true,
            "credentialDestinationMatchVerified": secret?.endpoint == sync.checkpoint.delivery.endpoint,
            "proteinExportActive": !sync.storageUnavailable && sync.checkpoint.proteinEnabled == true,
            "runId": CalendarReaderProvisioner.verificationRun,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-nutrition-read-proof.json"), options: .atomic)
        }
    }
}
#endif
