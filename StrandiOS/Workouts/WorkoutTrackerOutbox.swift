import Foundation
import WhoopStore

struct WorkoutTrackerDelivery: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case prepared, ready, accepted, review, failed }
    let id: UUID
    let sourceWorkoutId: UUID
    let installationId: UUID
    let origin: String
    let revision: Int
    let bytes: Data?
    let record: LiftSessionRow
    let sets: [LiftSetRow]
    let binding: WorkoutTrackerCaptureBinding
    var status: Status = .prepared
    var message = "Waiting for verified local persistence"
    var acknowledgement: Data?
    var needsReconciliation: Bool {
        status == .accepted && acknowledgement.flatMap {
            try? JSONDecoder().decode(WorkoutCaptureAcknowledgement.self, from: $0)
        }?.reconciliation.pending == true
    }
    var valid: Bool {
        (bytes?.count ?? 0) <= WorkoutSyncTransport.bodyLimit && revision > 0 && record.id.lowercased() == sourceWorkoutId.uuidString.lowercased()
            && sets.allSatisfy { $0.sessionId == record.id && $0.deviceId == record.deviceId }
            && (try? WorkoutSyncEndpoint.observations.url(origin: origin)) != nil
            && (try? binding.validate()) != nil && binding.sourceWorkoutId == sourceWorkoutId
            && (binding.connection.map { $0.origin == origin && $0.installationId == installationId } ?? true)
    }
    /// The queue cannot claim persistence until the exact UUID-bound recording is present.
    func matches(store: WhoopStore) async throws -> Bool {
        let rows = try await store.liftSessions(deviceId: record.deviceId, fromTs: record.startTs, toTs: record.startTs)
        guard rows.contains(record) else { return false }
        let saved = try await store.liftSets(sessionId: record.id)
        guard saved.sorted(by: { $0.id < $1.id }) == sets.sorted(by: { $0.id < $1.id }) else { return false }
        let workouts = try await store.workouts(deviceId: record.deviceId, from: record.startTs, to: record.startTs, limit: 100)
        return workouts.contains { $0.startTs == record.startTs && $0.endTs == record.endTs && $0.sport == record.sport && $0.source == "manual" }
    }
    func validateBody() throws {
        guard let bytes,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              (object["schemaVersion"] as? Int) == 1, (object["kind"] as? String) == "strength_workout",
              (object["eventId"] as? String).flatMap(UUID.init(uuidString:)) == id,
              (object["sourceWorkoutId"] as? String).flatMap(UUID.init(uuidString:)) == sourceWorkoutId,
              (object["installationId"] as? String).flatMap(UUID.init(uuidString:)) == installationId,
              (object["sourceRevision"] as? Int) == revision else { throw WorkoutTrackerContractError.invalidSnapshot }
    }
}
