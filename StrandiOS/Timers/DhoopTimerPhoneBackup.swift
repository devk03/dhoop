#if os(iOS)
import Foundation
import UserNotifications

/// Explicitly enabled iPhone notification backup; never presented as a WHOOP vibration.
@MainActor
enum DhoopTimerPhoneBackup {
    static func attach(_ timer: DhoopTimerController) {
        timer.cancelPhone = { id in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
        timer.schedulePhone = { id, due, permission in
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if permission && settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound]); settings = await center.notificationSettings()
            }
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return "iPhone backup unavailable" }
            let seconds = due.timeIntervalSinceNow
            guard seconds > 0 else { return "iPhone backup expired" }
            let content = UNMutableNotificationContent(); content.title = String(localized: "Timer finished")
            content.body = String(localized: "iPhone backup notification. WHOOP vibration is not confirmed."); content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)))
                return "iPhone backup scheduled"
            } catch { return "iPhone backup unavailable" }
        }
    }
}
#endif
