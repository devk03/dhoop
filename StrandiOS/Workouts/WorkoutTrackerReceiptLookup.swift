import Foundation

/// Exact stored receipt and current advisory state remain separate from local SQLite records.
struct WorkoutTrackerReceiptLookup: Codable {
    enum Status: String, Codable { case recorded; case notObserved = "not_observed" }
    struct Receipt: Codable {
        let schemaVersion: Int
        let eventId: UUID
        let sourceWorkoutId: UUID
        let acceptedSourceRevision: Int
        let outcome: String
        let lifeRevision: Int
        let receiptLifeRevision: Int
        let mappings: WorkoutCaptureAcknowledgement.Mappings
        let projectionPolicy: String?
        let projectionState: String?
        let preservedFields: [String]
    }
    struct Current: Codable {
        let lifeRevision: Int
        let sourcePresent: Bool
        let sourceRevision: Int?
        let tombstone: Bool?
        let projectionState: String
    }
    let schemaVersion: Int
    let eventId: UUID
    let sourceWorkoutId: UUID
    let installationId: UUID
    let status: Status
    let receipt: Receipt?
    let current: Current?
    let reconciliation: WorkoutCaptureAcknowledgement.Reconciliation

    func validate(for item: WorkoutTrackerDelivery) throws {
        guard schemaVersion == 1, eventId == item.id, sourceWorkoutId == item.sourceWorkoutId,
              installationId == item.installationId, reconciliation.state == "unknown" else {
            throw WorkoutSyncTransportError.invalidResponse
        }
        if status == .notObserved {
            guard receipt == nil, current == nil else { throw WorkoutSyncTransportError.invalidResponse }
            return
        }
        guard let receipt, let current,
              receipt.lifeRevision == receipt.receiptLifeRevision, current.lifeRevision >= receipt.lifeRevision,
              current.sourceRevision.map({ $0 > 0 && $0 <= 9_007_199_254_740_991 }) ?? true,
              current.sourcePresent ? (current.sourceRevision != nil && current.tombstone != nil &&
                  ["current", "capture_only", "retired"].contains(current.projectionState)) :
                  (current.sourceRevision == nil && current.tombstone == nil && current.projectionState == "unknown"),
              receipt.outcome == "stale" ? receipt.acceptedSourceRevision > item.revision : receipt.acceptedSourceRevision == item.revision else {
            throw WorkoutSyncTransportError.invalidResponse
        }
        let ack = try acknowledgement()
        try ack.validate(eventId: item.id, sourceWorkoutId: item.sourceWorkoutId, revision: item.revision)
        // A stale event's mappings describe the newer source. They are not its proposed set bindings.
        try ack.validate(binding: item.binding, sets: receipt.outcome == "stale" || item.operation == .delete ? [] : item.sets)
    }

    func acknowledgement() throws -> WorkoutCaptureAcknowledgement {
        guard status == .recorded, let receipt, let current else { throw WorkoutSyncTransportError.invalidResponse }
        return WorkoutCaptureAcknowledgement(schemaVersion: receipt.schemaVersion, eventId: receipt.eventId,
            sourceWorkoutId: receipt.sourceWorkoutId, acceptedSourceRevision: receipt.acceptedSourceRevision,
            outcome: receipt.outcome, lifeRevision: current.lifeRevision, receiptLifeRevision: receipt.receiptLifeRevision,
            preservedFields: receipt.preservedFields, mappings: receipt.mappings, reconciliation: reconciliation,
            currentSourceRevision: current.sourceRevision, currentTombstone: current.tombstone,
            projectionState: receipt.projectionState, currentProjectionState: current.projectionState == "unknown" ? nil : current.projectionState,
            projectionPolicy: receipt.projectionPolicy)
    }
}
