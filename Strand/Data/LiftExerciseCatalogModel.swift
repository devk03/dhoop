import Foundation
import Combine
import WhoopStore

/// A failed catalog read is not an empty catalog or permission to replace saved classification.
@MainActor
final class LiftExerciseCatalogModel: ObservableObject {
    enum Failure: LocalizedError {
        case unavailable, unreadable, changedSource
        case full(Int)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Exercise storage is unavailable. Your draft is retained."
            case .unreadable: return "The exercise catalog could not be read. Existing entries and your draft are retained."
            case .changedSource: return "The exercise source changed. Refresh the catalog before saving."
            case .full(let limit): return "The catalog contains its maximum of \(limit) exercises. Forget an unused entry before adding another. Logged sessions and your draft are retained."
            }
        }
    }
    @Published private(set) var rows: [LiftExerciseRow] = []
    @Published private(set) var deviceID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var readable = false
    private var generation = 0

    func isReady(for source: String) -> Bool { readable && !isLoading && deviceID == source }
    func entries(for source: String) -> [LiftExerciseRow] { deviceID == source ? rows : [] }

    func load(deviceID source: String, read: @MainActor (String) async throws -> [LiftExerciseRow]) async throws {
        generation += 1
        let ticket = generation
        readable = false; error = nil; isLoading = true
        if deviceID != source { rows = []; deviceID = nil }
        defer { if generation == ticket { isLoading = false } }
        do {
            let result = try await read(source)
            try Task.checkCancellation()
            guard ticket == generation else { throw Failure.changedSource }
            guard result.allSatisfy({ $0.deviceId == source }), Set(result.map(\.id)).count == result.count else {
                throw Failure.unreadable
            }
            rows = result; deviceID = source; readable = true
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard ticket == generation else { throw Failure.changedSource }
            let failure = (error as? Failure) ?? .unreadable
            self.error = failure.localizedDescription
            throw failure
        }
    }
}
