import Foundation

/// Authenticates the whole bounded fetch batch before any command enters the delivery funnel.
struct RemoteBuzzInboxResponse: Decodable {
    let version: Int
    let status: String
    let enrollmentId: String
    let generation: Int
    let installationId: String
    let commands: [RemoteBuzzCommandV2]
    let hasMore: Bool
    func valid(for enrollment: RemoteBuzzEnrollment) -> Bool {
        version == 2 && status == "accepted" && enrollmentId == enrollment.enrollmentId
            && generation == enrollment.generation && installationId == enrollment.installationId
            && commands.count <= 16 && Set(commands.map(\.eventId)).count == commands.count
            && commands.allSatisfy { $0.authenticated(by: enrollment) }
    }
}
