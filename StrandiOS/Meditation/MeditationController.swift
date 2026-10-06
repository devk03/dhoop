#if os(iOS)
import Combine
import Foundation
import UserNotifications

/// App-root ownership keeps the timer alive when a dashboard or tab disappears.
@MainActor
final class MeditationController: ObservableObject {
    enum NotificationStatus { case checking, scheduled, unavailable, failed, none }

    @Published private(set) var session: MeditationSession
    @Published private(set) var notificationStatus: NotificationStatus = .none
    private let defaults: UserDefaults
    private let notifications = UNUserNotificationCenter.current()
    private let storageKey = "dhoop.meditation.session.v1"
    private weak var model: AppModel?
    private var isForeground = false
    private var timerTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        session = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(MeditationSession.self, from: $0) } ?? MeditationSession()
    }

    func attach(model: AppModel, foreground: Bool) {
        self.model = model
        isForeground = foreground
        reconcile()
        if session.phase == .running { scheduleNotification(requestPermission: false) }
        startTicker()
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        reconcile()
        if foreground && session.phase == .running { scheduleNotification(requestPermission: false) }
        startTicker()
    }

    func start() {
        let deviceId = model?.deviceRegistry?.activeDeviceId
        guard session.start(at: Date(), deviceId: deviceId) else { return }
        persist()
        scheduleNotification(requestPermission: true)
        startTicker()
    }

    func pause() {
        // A tap after the deadline completes the session instead of reviving an expired timer.
        reconcile()
        let oldId = session.notificationId
        guard session.pause(at: Date()) else { return }
        persist()
        clearNotification(oldId)
        notificationStatus = .none
        timerTask?.cancel()
    }

    func resume() {
        guard session.resume(at: Date()) else { return }
        persist()
        scheduleNotification(requestPermission: false)
        startTicker()
    }

    func cancel() {
        let oldId = session.notificationId
        guard session.cancel() else { return }
        persist()
        clearNotification(oldId)
        notificationStatus = .none
        timerTask?.cancel()
    }

    private func reconcile() {
        guard let disposition = session.completeIfDue(at: Date(), foreground: isForeground,
                                                       strapReady: strapReady) else { return }
        // Mark before writing: relaunch/repeated lifecycle events cannot request another buzz.
        persist()
        // Let the scheduled notification fire even if a background tick wins the deadline race.
        timerTask?.cancel()
        if disposition == .buzzRequested { model?.buzz(loops: 1) }
    }

    private var strapReady: Bool {
        guard let model, let deviceId = session.deviceId else { return false }
        return model.deviceRegistry?.activeDeviceId == deviceId
            && model.live.connectedWhoopDeviceId == deviceId
            && model.live.activeIsWhoop && model.live.connected
            && model.live.encryptedBond && model.live.historyReady
    }

    private func startTicker() {
        timerTask?.cancel()
        guard session.phase == .running else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.reconcile()
                if self.session.phase != .running { return }
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: storageKey) }
    }

    private func clearNotification(_ id: String?, includeDelivered: Bool = true) {
        guard let id else { return }
        notifications.removePendingNotificationRequests(withIdentifiers: [id])
        if includeDelivered { notifications.removeDeliveredNotifications(withIdentifiers: [id]) }
    }

    private func scheduleNotification(requestPermission: Bool) {
        guard let id = session.notificationId, let deadline = session.deadline else { return }
        notificationStatus = .checking
        Task { [weak self] in
            guard let self else { return }
            var settings = await notifications.notificationSettings()
            if requestPermission && settings.authorizationStatus == .notDetermined {
                _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
                settings = await notifications.notificationSettings()
            }
            guard session.notificationId == id, session.phase == .running else { return }
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
                notificationStatus = .unavailable
                return
            }
            let interval = deadline.timeIntervalSinceNow
            guard interval > 0 else { reconcile(); return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Meditation complete")
            content.body = String(localized: "Your 15-minute session has finished.")
            content.sound = .default
            let request = UNNotificationRequest(identifier: id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
            do {
                try await notifications.add(request)
                // A pause/cancel can race the asynchronous system add. Each run gets a unique id.
                guard session.notificationId == id, session.phase == .running else {
                    clearNotification(id)
                    return
                }
                notificationStatus = .scheduled
            } catch {
                if session.notificationId == id { notificationStatus = .failed }
            }
        }
    }
}
#endif
