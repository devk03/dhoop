#if os(iOS)
import Foundation
import UIKit
import Combine

/// Personal-fork APNs test receiver. Enabled explicitly for at most two hours, with no polling.
@MainActor
final class RemoteBuzzReceiver: ObservableObject {
    static let shared = RemoteBuzzReceiver()
    @Published private(set) var status = "Remote buzz test is off"
    @Published private(set) var registrationStatus = "Apple push not registered"
    @Published private(set) var receipt: String?
    @Published private(set) var enabledUntil: Date?
    private weak var model: AppModel?
    private let account = "remote-buzz-test-v1"
    private var token: String?

    func attach(model: AppModel) { self.model = model; reload() }
    private func setup() throws -> RemoteBuzzTestSetup? {
        guard let bytes = try SleepWebhookKeychain.read(account), !bytes.isEmpty else { return nil }
        return try JSONDecoder().decode(RemoteBuzzTestSetup.self, from: bytes)
    }
    private func reload() {
        do {
            let value = try setup()
            enabledUntil = value?.expiresAt
            status = value.map { $0.expiresAt > Date() ? "Remote buzz test enabled" : "Remote buzz test expired" } ?? "Remote buzz test is off"
        } catch { status = "Remote test configuration unavailable" }
    }
    func importAndEnable() {
        do {
            let file = documents.appendingPathComponent("dhoop-remote-buzz-setup.json")
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= 2048 else { throw CocoaError(.fileReadCorruptFile) }
            let value = try JSONDecoder().decode(RemoteBuzzTestSetup.self, from: bytes)
            guard value.valid(now: Date()) else { throw CocoaError(.fileReadCorruptFile) }
            // Consume the inbox by moving it to a protected, backup-excluded archive; never delete data.
            var archive = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dhoop/RemoteBuzz", isDirectory: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try archive.setResourceValues(values)
            let consumed = archive.appendingPathComponent("setup-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: file, to: consumed)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: consumed.path)
            try SleepWebhookKeychain.save(bytes, account: account)
            reload()
            UIApplication.shared.registerForRemoteNotifications()
            registrationStatus = "Requesting Apple push token"
        } catch { status = "Could not enable test. Setup must be valid, unexpired, and readable." }
    }
    func disable() {
        do {
            // Empty bytes represent an intentional off state; no other Keychain account is changed.
            try SleepWebhookKeychain.save(Data(), account: account)
            model?.ble.buzzDelivery.cancel(owner: "remote-test")
            enabledUntil = nil; status = "Remote buzz test is off"
        } catch { status = "Could not save disabled state. Retry before continuing." }
    }
    func registered(_ bytes: Data) {
        token = bytes.map { String(format: "%02x", $0) }.joined()
        registrationStatus = "Apple push token received"
        do {
            guard let value = try setup(), value.expiresAt > Date(), let token else { return }
            struct Registration: Codable { let installationId: String; let token: String; let topic: String; let environment: String }
            let file = documents.appendingPathComponent("dhoop-remote-buzz-registration.json")
            let data = try JSONEncoder().encode(Registration(installationId: value.installationId, token: token,
                topic: Bundle.main.bundleIdentifier ?? "", environment: "sandbox"))
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var mutableFile = file; var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try mutableFile.setResourceValues(resources)
        } catch { registrationStatus = "Push token received; registration export failed" }
    }
    func registrationFailed() { registrationStatus = "Apple push registration failed. Check entitlement and connection." }

    func receive(_ notification: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        let now = Date()
        do {
            guard let model, let value = try setup(), value.expiresAt > now,
                  let secret = value.secretBytes, let body = notification["dhoopBuzz"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(body) else { receipt = "Push ignored: test disabled or invalid"; return .noData }
            let bytes = try JSONSerialization.data(withJSONObject: body)
            guard bytes.count <= 2048 else { receipt = "Push rejected: too large"; return .noData }
            let command = try JSONDecoder().decode(RemoteBuzzCommand.self, from: bytes)
            guard command.validate(secret: secret, installation: value.installationId,
                                   topic: Bundle.main.bundleIdentifier ?? "", now: now) else {
                receipt = "Push rejected: signature, identity, or expiry"; return .noData
            }
            struct PushReceipt: Codable {
                let eventId: String
                let receivedAt: Date
                let applicationState: Int
                let stage: String
            }
            let proof = PushReceipt(eventId: command.eventId, receivedAt: now,
                applicationState: UIApplication.shared.applicationState.rawValue, stage: "authenticated_push_received")
            let proofFile = documents.appendingPathComponent("dhoop-remote-buzz-receipt.json")
            try JSONEncoder().encode(proof).write(to: proofFile,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let cueID = "remote|\(command.eventId)"
            let duplicate = model.ble.buzzDelivery.cues.contains { $0.id == cueID }
            if !duplicate, let previous = model.ble.buzzDelivery.cues.filter({ $0.owner == "remote-test" }).compactMap(\.requestedAt).max(), now.timeIntervalSince(previous) < 30 {
                receipt = "Push ignored: thirty-second buzz cooldown"; return .noData
            }
            model.requestBuzz(owner: "remote-test", id: cueID, loops: 1, due: now, grace: 2)
            receipt = "\(now.formatted(date: .abbreviated, time: .standard)) · \(command.eventId) · \(duplicate ? "duplicate ignored" : "push received; inspect WHOOP delivery")"
            model.live.append(log: AppModel.stamped("[RemoteBuzz] valid push received; event=\(command.eventId); applicationState=\(UIApplication.shared.applicationState.rawValue); duplicate=\(duplicate)"))
            return duplicate ? .noData : .newData
        } catch { receipt = "Push rejected: unreadable test configuration or payload"; return .failed }
    }
    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
}
#endif
