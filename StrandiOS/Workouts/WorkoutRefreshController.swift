import Foundation
import Combine

/// One bounded read per visible context. Concurrent refresh callers await the same result.
@MainActor
final class WorkoutRefreshController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var errorMessage: String?
    private var task: Task<Void, Error>?
    private var identity = ""
    private var generation = 0

    func refresh(identity: String, operation: @escaping @MainActor () async throws -> Void) async throws {
        if let task, self.identity == identity { try await task.value; return }
        cancel()
        self.identity = identity
        let ticket = generation
        busy = true; errorMessage = nil
        let next = Task { @MainActor in
            do {
                try await operation()
                try Task.checkCancellation()
                guard ticket == self.generation else { throw CancellationError() }
                self.lastSuccess = Date()
            } catch {
                if ticket == self.generation, !(error is CancellationError), !Task.isCancelled {
                    self.errorMessage = Self.message(error)
                }
                throw error
            }
        }
        task = next
        defer { if ticket == generation { task = nil; busy = false } }
        try await next.value
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; busy = false
    }
    func reset() { cancel(); lastSuccess = nil; errorMessage = nil }
    static func message(_ error: Error) -> String {
        if let value = error as? WorkoutSyncTransportError { return value.localizedDescription }
        if let value = error as? WorkoutFrontendClient.Failure { return value.localizedDescription }
        if let value = error as? URLError {
            switch value.code {
            case .notConnectedToInternet, .networkConnectionLost: return "You're offline. Your saved workouts and edits are still here. Reconnect and retry."
            case .timedOut: return "Life took too long to respond. Your saved workouts and edits are still here. Try again."
            default: break
            }
        }
        return "Couldn't refresh workouts. Your saved data and edits are still here. Try again."
    }
}
