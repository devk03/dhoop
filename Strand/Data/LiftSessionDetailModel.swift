import Foundation
import Combine
import WhoopStore

/// A last confirmed detail remains available after failed refresh, but cannot authorize edits.
@MainActor
final class LiftSessionDetailModel: ObservableObject {
    @Published private(set) var snapshot: LiftRecordingDetail?
    @Published private(set) var capturedAt: Date?
    @Published private(set) var readID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var generation = UUID()
    var isFresh: Bool { snapshot != nil && error == nil && !isLoading }

    enum Failure: LocalizedError {
        case missing, invalidIdentity
        var errorDescription: String? {
            switch self {
            case .missing: return "This session is no longer available under its recorded source. No replacement recording was created."
            case .invalidIdentity: return "The detail read did not match this session's recorded identity. The previous view is retained."
            }
        }
    }

    @discardableResult
    func load(record: LiftSessionRow,
              read: @MainActor (String, String) async throws -> LiftRecordingDetail?) async -> UUID? {
        let ticket = UUID(); generation = ticket; isLoading = true; error = nil
        defer { if generation == ticket { isLoading = false } }
        do {
            let value = try await read(record.deviceId, record.id)
            try Task.checkCancellation()
            guard generation == ticket else { return nil }
            guard let value else {
                snapshot = nil; capturedAt = nil; readID = nil
                throw Failure.missing
            }
            guard value.session.id == record.id, value.session.deviceId == record.deviceId,
                  value.session.startTs == record.startTs, value.session.sport == record.sport,
                  Set(value.sets.map(\.id)).count == value.sets.count,
                  value.sets.allSatisfy({ $0.sessionId == record.id && $0.deviceId == record.deviceId }),
                  value.previousSets.allSatisfy({ name, rows in rows.allSatisfy { $0.deviceId == record.deviceId && $0.exercise == name && $0.sessionId != record.id } }),
                  value.workout == nil || (value.workout?.startTs == record.startTs && value.workout?.sport == record.sport)
            else { throw Failure.invalidIdentity }
            snapshot = value; capturedAt = Date(); readID = ticket
            return ticket
        } catch {
            guard generation == ticket else { return nil }
            self.error = error.localizedDescription
            return nil
        }
    }
}
