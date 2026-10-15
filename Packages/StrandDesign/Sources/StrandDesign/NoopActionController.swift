import Foundation
import Combine

/// Result state belongs to the operation, not to the finger animation.
public enum NoopActionState: Equatable {
    case idle, working, succeeded, failed(String)
    public var isWorking: Bool { self == .working }
}

/// Serializes a user action and exposes its actual completion. It never retries automatically.
@MainActor
public final class NoopActionController: ObservableObject {
    @Published public private(set) var state: NoopActionState = .idle
    public init() {}

    public func run(_ action: @MainActor () async throws -> Void) async {
        guard !state.isWorking else { return }
        state = .working
        await finish(action)
    }

    // Reserve synchronously in the tap callback, before another tap can enqueue a task.
    public func submit(_ action: @escaping @MainActor () async throws -> Void) {
        guard !state.isWorking else { return }
        state = .working
        Task { await finish(action) }
    }

    private func finish(_ action: @MainActor () async throws -> Void) async {
        await Task.yield()
        do {
            try await action()
            try Task.checkCancellation()
            state = .succeeded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func reset() {
        guard !state.isWorking else { return }
        state = .idle
    }
}
