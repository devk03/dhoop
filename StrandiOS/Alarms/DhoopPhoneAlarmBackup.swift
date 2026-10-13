import Foundation
import SwiftUI
import UserNotifications
import CryptoKit
import StrandAnalytics
import StrandDesign
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Optional phone delivery, with its own authorization and finite dated coverage.
/// Does not execute Bluetooth writes or certify WHOOP delivery.
@MainActor
enum DhoopPhoneAlarmBackup {
    private static let manifestKey = "dhoop.alarms.phoneManifest.v1"
    static func configure(_ manager: DhoopAlarmManager) {
        manager.backup = { definitions, now in
            let status = await reconcile(definitions, now: now)
            let legacy = await UNUserNotificationCenter.current().pendingNotificationRequests()
                .filter { $0.identifier == "smart-alarm-wake-backup" || $0.identifier.hasPrefix("smart-alarm-wake-backup-d") }
            return legacy.isEmpty ? status : status + "; \(legacy.count) legacy wake notifications retained"
        }
        manager.authorizeBackup = {
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                do { return try await AlarmManager.shared.requestAuthorization() == .authorized }
                catch { return false }
            }
            #endif
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }
    private static func identifier(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128
        let h = bytes.map { String(format: "%02x", $0) }.joined()
        let offsets = [0,8,12,16,20,32], pieces = (0..<5).map { i in
            String(h[h.index(h.startIndex,offsetBy:offsets[i])..<h.index(h.startIndex,offsetBy:offsets[i+1])])
        }
        return UUID(uuidString: pieces.joined(separator: "-"))!
    }
    private static func reconcile(_ definitions: [DhoopAlarmDefinition], now: Date) async -> String {
        var desired: [String: (epoch: Int, label: String)] = [:]
        for alarm in definitions where alarm.enabled && !alarm.deleted && alarm.phoneBackup {
            for epoch in AlarmOccurrencePlanner.dates(rule: alarm.rule, after: now) {
                desired[alarm.id + "|" + String(epoch)] = (epoch, alarm.label)
            }
        }
        var manifest = UserDefaults.standard.dictionary(forKey: manifestKey) as? [String: String] ?? [:]
        var failed = false
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let actual: [Alarm]
            do { actual = try AlarmManager.shared.alarms }
            catch { return "Phone alarm state could not be read; backup unverified" }
            let scheduled = Set(actual.map(\.id))
            for key in Array(manifest.keys) where desired[key] == nil {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dhoop-alarm-" + identifier(key).uuidString])
                if !scheduled.contains(identifier(key)) { manifest.removeValue(forKey: key); continue }
                do { try AlarmManager.shared.cancel(id: identifier(key)); manifest.removeValue(forKey: key) }
                catch { failed = true }
            }
            if !desired.isEmpty && AlarmManager.shared.authorizationState != .authorized {
                return "Phone alarm permission is off; WHOOP status is separate"
            }
            for key in desired.keys.sorted() {
                let item = desired[key]!, id = identifier(key)
                if manifest[key] == item.label && scheduled.contains(id) { continue }
                // Retain this exact deterministic ID before scheduling so a crash cannot orphan a backup.
                manifest[key] = "pending:" + item.label
                UserDefaults.standard.set(manifest, forKey: manifestKey)
                do {
                    let presentation = AlarmPresentation(alert: .init(title: LocalizedStringResource(stringLiteral: item.label),
                        stopButton: AlarmButton(text: "Stop", textColor: StrandPalette.textPrimary, systemImageName: "stop.fill")))
                    let attributes = AlarmAttributes(presentation: presentation, metadata: Metadata(), tintColor: StrandPalette.alarmAccent)
                    let configuration = AlarmManager.AlarmConfiguration.alarm(
                        schedule: .fixed(Date(timeIntervalSince1970: Double(item.epoch))), attributes: attributes)
                    _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                    manifest[key] = item.label
                    // Remove only this owned notification after its system-alarm replacement succeeds.
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dhoop-alarm-" + id.uuidString])
                } catch { failed = true }
            }
            UserDefaults.standard.set(manifest, forKey: manifestKey)
            if failed { return "Phone backup needs attention; some changes failed" }
            return desired.isEmpty ? "Phone backup off" : "\(desired.count) dated phone alarms scheduled"
        }
        #endif
        let center = UNUserNotificationCenter.current()
        let removed = manifest.keys.filter { desired[$0] == nil }
        center.removePendingNotificationRequests(withIdentifiers: removed.map { "dhoop-alarm-" + identifier($0).uuidString })
        for key in removed { manifest.removeValue(forKey: key) }
        let settings = await center.notificationSettings()
        guard desired.isEmpty || settings.authorizationStatus == .authorized else {
            return "Notification permission is off; no phone backup scheduled"
        }
        for key in desired.keys.sorted() {
            let item = desired[key]!
            let content = UNMutableNotificationContent(); content.title = item.label
            content.body = "Dhoop alarm notification backup"; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, Double(item.epoch) - now.timeIntervalSince1970), repeats: false)
            do {
                try await center.add(.init(identifier: "dhoop-alarm-" + identifier(key).uuidString, content: content, trigger: trigger))
                manifest[key] = item.label
            } catch { failed = true }
        }
        UserDefaults.standard.set(manifest, forKey: manifestKey)
        return failed ? "Notification backup failed" : desired.isEmpty ? "Phone backup off"
            : "\(desired.count) notification backups scheduled; Focus/silent mode may mute them"
    }
    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private struct Metadata: AlarmMetadata { }
    #endif
}
