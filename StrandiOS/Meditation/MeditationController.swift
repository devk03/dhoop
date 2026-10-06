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
    @Published private(set) var buzzStatus = "No WHOOP completion cue scheduled"
    private var deliverySubscription: AnyCancellable?
    private let store: MeditationSessionFileStore
    private var loaded = false
    private let notifications = UNUserNotificationCenter.current()
    private weak var model: AppModel?
    private var isForeground = false
    private var timerTask: Task<Void, Never>?
    private var keepAwake: ((Bool) -> Void)?
    private var holdsScreenAwake = false
    private var receipts: AnyCancellable?
    private let buzzOwner = "meditation"
    private func scheduleBuzz() {
        guard let model, session.phase == .running, let deadline = session.deadline,
              let id = session.notificationId, let deviceId = session.deviceId,
              deviceId == model.repo.deviceId else { return }
        guard model.ble.buzzDelivery.claim(buzzOwner) else { return }
        model.ble.buzzDelivery.schedule(owner: buzzOwner, id: id, deviceId: deviceId,
            due: deadline, grace: MeditationSession.alertGrace, loops: 1)
    }

    init(store: MeditationSessionFileStore = MeditationSessionFileStore()) {
        self.store = store
        session = MeditationSession()
        load()
    }

    func attach(model: AppModel, foreground: Bool, keepAwake: @escaping (Bool) -> Void) {
        self.model = model
        deliverySubscription = model.ble.buzzDelivery.$cues.sink { [weak self] cues in
            guard let self else { return }
            if let cue = cues.last(where: { $0.owner == self.buzzOwner && $0.id == self.session.notificationId }) {
                self.buzzStatus = cue.status == .unavailable
                    ? "WHOOP cue cancelled after a connection problem. Pause and resume to re-arm it, or continue with the iPhone fallback."
                    : cue.detail
            }
        }
        receipts = model.live.readableHeartRateReceipts.sink { [weak self] _ in self?.reconcile() }
        scheduleBuzz()
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
        guard loaded, !session.isInProgress, model?.ble.buzzDelivery.claim(buzzOwner) == true else { return }
        var next = session
        guard next.start(at: Date(), deviceId: model?.deviceRegistry?.activeDeviceId), commit(next) else { model?.ble.buzzDelivery.release(buzzOwner); return }
        scheduleBuzz()
        log("started; app-side cue scheduled; wake alarm untouched; background delivery best-effort")
        scheduleNotification(requestPermission: true)
        startTicker()
        updateScreenAwake()
    }

    func pause() {
        reconcile()
        let oldId = session.notificationId
        var next = session
        guard next.pause(at: Date()), commit(next) else { return }
        model?.ble.buzzDelivery.release(buzzOwner)
        clearNotification(oldId)
        notificationStatus = .none
        timerTask?.cancel()
        updateScreenAwake()
    }

    func resume() {
        guard model?.ble.buzzDelivery.claim(buzzOwner) == true else { return }
        var next = session
        guard next.resume(at: Date()), commit(next) else { model?.ble.buzzDelivery.release(buzzOwner); return }
        scheduleBuzz()
        scheduleNotification(requestPermission: false)
        startTicker()
        updateScreenAwake()
    }

    func cancel() {
        let oldId = session.notificationId
        var next = session
        guard next.cancel(), commit(next) else { return }
        model?.ble.buzzDelivery.release(buzzOwner)
        clearNotification(oldId)
        notificationStatus = .none
        timerTask?.cancel()
        updateScreenAwake()
    }

    private func reconcile() {
        guard loaded else { return }
        model?.ble.buzzDelivery.service()
        let delivery = model?.ble.buzzDelivery.cues.first { $0.id == session.notificationId }
        let requested = delivery.map { [BuzzDeliveryCoordinator.Status.requested, .responseReceived, .acknowledged, .confirmed].contains($0.status) } ?? false
        var next = session
        guard let disposition = next.completeIfDue(at: Date(), foreground: false,
            strapReady: strapReady, deliveryRequested: requested) else { return }
        // The delivery ledger commits before transmission. Session completion is a separate durable record.
        guard commit(next) else { updateScreenAwake(); return }
        // Let the notification fire even if a background tick wins the deadline race.
        timerTask?.cancel()
        updateScreenAwake()
        log("completion saved; disposition=\(disposition.rawValue); foreground=\(isForeground); physical delivery unconfirmed")
        model?.ble.buzzDelivery.release(buzzOwner)
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
            if storageError == nil { log("session state save failed; transition not applied; inspect the separate buzz delivery ledger") }
            storageError = String(localized: "Timer change could not be saved. Check WHOOP alert delivery for any command already requested, then retry the timer action.")
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
            content.body = String(localized: "Your 15-minute session has finished. This is the iPhone fallback, not confirmation of a WHOOP vibration.")
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
