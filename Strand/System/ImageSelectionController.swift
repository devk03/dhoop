import Foundation
import Combine
import StrandDesign

/// One selected image input and its retry. Selection generations fence the synchronous commit.
@MainActor
final class ImageSelectionController: ObservableObject {
    @Published private(set) var state: NoopActionState = .idle
    private var generation = UUID()
    private var input: (() async throws -> Data?)?
    private var commit: ((Data) throws -> Void)?
    private var loading: Set<UUID> = []
    var isWorking: Bool { state.isWorking }
    var hasInput: Bool { input != nil }
    var selectionID: UUID { generation }
    var error: String? { if case .failed(let message) = state { return message }; return nil }

    enum Failure: LocalizedError {
        case unreadable, invalidImage
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The selected image could not be read. The current image and selection are retained; retry or choose another image."
            case .invalidImage: return "The selected image could not be decoded. The current image and selection are retained; choose a supported image."
            }
        }
    }

    func select(read: @escaping () async throws -> Data?, commit: @escaping (Data) throws -> Void) -> UUID {
        generation = UUID(); input = read; self.commit = commit; state = .working
        return generation
    }
    func isCurrent(_ token: UUID) -> Bool { token == generation }
    func cancel() { generation = UUID(); input = nil; commit = nil; state = .idle }
    func retry() async -> Bool {
        guard !isWorking, hasInput else { return false }
        return await load(generation)
    }
    func load(_ token: UUID) async -> Bool {
        guard isCurrent(token), let input, let commit, loading.insert(token).inserted else { return false }
        defer { loading.remove(token) }
        state = .working
        do {
            guard let data = try await input(), !data.isEmpty else { throw Failure.unreadable }
            try Task.checkCancellation()
            guard isCurrent(token) else { return false }
            try commit(data)
            guard isCurrent(token) else { return false }
            self.input = nil; self.commit = nil; state = .succeeded
            return true
        } catch {
            guard isCurrent(token) else { return false }
            if error is CancellationError { state = .idle }
            else { state = .failed(error.localizedDescription) }
            return false
        }
    }
}
