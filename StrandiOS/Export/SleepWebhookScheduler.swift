#if os(iOS)
import Foundation
import BackgroundTasks

@MainActor
enum SleepWebhookScheduler {
    static let identifier = (Bundle.main.bundleIdentifier ?? "dhoop") + ".sleepwebhook"
    static func register(perform: @escaping @MainActor () async -> Bool) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let completion = Completion(task)
            let worker = Task { @MainActor in
                update(enabled: SleepWebhookClient.shared.checkpoint.enabled)
                let success = await perform()
                guard !Task.isCancelled else { return }
                completion.finish(success)
            }
            task.expirationHandler = { worker.cancel(); completion.finish(false) }
        }
    }
    static func update(enabled: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard enabled else { return }
        let task = BGProcessingTaskRequest(identifier: identifier)
        task.requiresNetworkConnectivity = true
        task.requiresExternalPower = false
        task.earliestBeginDate = Date().addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(task)
    }
    private final class Completion: @unchecked Sendable {
        let task: BGTask
        let lock = NSLock()
        var done = false
        init(_ task: BGTask) { self.task = task }
        func finish(_ success: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true; task.setTaskCompleted(success: success); task.expirationHandler = nil
        }
    }
}
#endif
