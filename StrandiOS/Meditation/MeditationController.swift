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
    @Published private(set) var storageError: String?
    private let store: MeditationSessionFileStore
    private var loaded = false
    private let notifications = UNUserNotificationCenter.current()
    private weak var model: AppModel?
    private var isForeground = false
    private var timerTask: Task<Void, Never>?
    private var keepAwake: ((Bool) -> Void)?
    private var holdsScreenAwake = false

    init(store: MeditationSessionFileStore = MeditationSessionFileStore()) {
        self.store = store
        session = MeditationSession()
        load()
    }

    func attach(model: AppModel, foreground: Bool, keepAwake: @escaping (Bool) -> Void) {
        self.model = model
        // Release the old owner before replacing the callback on repeated root attachment.
        if holdsScreenAwake { self.keepAwake?(false); holdsScreenAwake = false }
        self.keepAwake = keepAwake
        isForeground = foreground
        reconcile()
        if session.phase == .running { scheduleNotification(requestPermission: false) }
        startTicker()
        updateScreenAwake()
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        reconcile()
        if foreground && session.phase == .running { scheduleNotification(requestPermission: false) }
        startTicker()
        updateScreenAwake()
    }

    func retryStorage() {
        if !loaded { load() } else if !commit(session) { return }
        reconcile()
        if loaded && session.phase == .running { scheduleNotification(requestPermission: false) }
        startTicker()
        updateScreenAwake()
    }

    func start() {
        guard loaded else { return }
        var next = session
        guard next.start(at: Date(), deviceId: model?.deviceRegistry?.activeDeviceId), commit(next) else { return }
        log("started; foreground WHOOP cue only; no background strap alarm scheduled")
        scheduleNotification(requestPermission: true)
        startTicker()
        updateScreenAwake()
    }

    func pause() {
        reconcile()
        let oldId = session.notificationId
        var next = session
        guard next.pause(at: Date()), commit(next) else { return }
        clearNotification(oldId)
        notificationStatus = .none
        timerTask?.cancel()
        updateScreenAwake()
    }

    func resume() {
        var next = session
        guard next.resume(at: Date()), commit(next) else { return }
        scheduleNotification(requestPermission: false)
        startTicker()
        updateScreenAwake()
    }

    func cancel() {
        let oldId = session.notificationId
        var next = session
        guard next.cancel(), commit(next) else { return }
        clearNotification(oldId)
        notificationStatus = .none
        timerTask?.cancel()
        updateScreenAwake()
    }

    private func reconcile() {
        guard loaded else { return }
        var next = session
        guard let disposition = next.completeIfDue(at: Date(), foreground: isForeground,
                                                    strapReady: strapReady) else { return }
        // Commit before the external effect. Failure keeps the old state and never requests a buzz.
        guard commit(next) else { updateScreenAwake(); return }
        // Let the notification fire even if a background tick wins the deadline race.
        timerTask?.cancel()
        updateScreenAwake()
        log("completion saved; disposition=\(disposition.rawValue); foreground=\(isForeground); physical delivery unconfirmed")
        if disposition == .buzzRequested { model?.buzz(loops: 1) }
    }

    private func load() {
        do {
            session = try store.load()
            loaded = true
            storageError = nil
        } catch {
            storageError = String(localized: "The saved meditation timer could not be read. Retry before starting.")
        }
    }

    @discardableResult
    private func commit(_ next: MeditationSession) -> Bool {
        do {
            try store.save(next)
            session = next
            storageError = nil
            return true
        } catch {
            if storageError == nil { log("state save failed; transition not applied; no completion buzz requested") }
            storageError = String(localized: "Timer change could not be saved. The previous timer is still in effect; no new completion buzz was requested. Retry the action.")
            return false
        }
    }

    private func updateScreenAwake() {
        // Release even on a failed completion save: an expired timer must not hold the screen.
        let wanted = isForeground && session.phase == .running && session.remaining(at: Date()) > 0
        guard wanted != holdsScreenAwake else { return }
        holdsScreenAwake = wanted
        keepAwake?(wanted)
    }

    private func log(_ message: String) {
        model?.live.append(log: AppModel.stamped("[Meditation] " + message))
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
