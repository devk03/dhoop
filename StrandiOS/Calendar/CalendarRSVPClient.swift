import Foundation
import Combine

@MainActor
final class CalendarRSVPClient: ObservableObject {
    static let shared = CalendarRSVPClient()
    @Published private(set) var configuration: CalendarRSVPConfiguration?
    @Published private(set) var busyEventID: String?
    private let read: () throws -> CalendarRSVPConfiguration?
    private let save: (CalendarRSVPConfiguration) throws -> Void
    private let send: (CalendarRSVPConfiguration, CalendarAcceptRequest?) async throws -> Data
    private var generation = 0
    var enabled: Bool { configuration?.enabled == true && configuration?.valid == true }
    init(read: @escaping () throws -> CalendarRSVPConfiguration? = CalendarRSVPKeychain.read,
         save: @escaping (CalendarRSVPConfiguration) throws -> Void = CalendarRSVPKeychain.save,
         send: @escaping (CalendarRSVPConfiguration, CalendarAcceptRequest?) async throws -> Data = { try await CalendarRSVPTransport().send(configuration: $0, accept: $1) }) {
        self.read = read; self.save = save; self.send = send; reload()
    }
    func reload() {
        let next = try? read()
        if next != configuration { generation += 1; configuration = next }
    }
    func setEnabled(_ enabled: Bool) throws {
        guard var value = configuration else { throw CalendarRSVPFailure.configuration }; value.enabled = enabled; try save(value); reload()
    }
    func accept(date: String, event: CalendarReaderEvent) async throws -> CalendarReaderEvent {
        reload(); guard enabled, let configuration else { throw CalendarRSVPFailure.configuration }
        guard busyEventID == nil else { throw CalendarRSVPFailure.busy }
        let request = try CalendarAcceptRequest(date: date, event: event), version = generation
        busyEventID = event.id; defer { busyEventID = nil }
        // No queue or automatic POST retry: uncertainty requires a fresh reader result and owner tap.
        let bytes = try await send(configuration, request)
        guard generation == version, self.configuration == configuration else { throw CalendarRSVPFailure.unconfirmed }
        let value = try JSONDecoder().decode(CalendarAcceptResponse.self, from: bytes); try value.validate(request)
        return value.event
    }
    func install(_ candidate: CalendarRSVPConfiguration) async throws {
        guard candidate.enabled, candidate.valid, busyEventID == nil else { throw CalendarRSVPFailure.configuration }
        if let existing = try read(), existing != candidate { throw CalendarRSVPFailure.configuration }
        struct Capabilities: Decodable { let schemaVersion: Int; let installationId: UUID; let acceptOnly: Bool; let eventCrud: Bool }
        let data = try await send(candidate, nil), capabilities = try JSONDecoder().decode(Capabilities.self, from: data)
        guard capabilities.schemaVersion == 1, capabilities.installationId == candidate.installationId,
              capabilities.acceptOnly, !capabilities.eventCrud else { throw CalendarRSVPFailure.configuration }
        try save(candidate); guard try read() == candidate else { throw CalendarRSVPFailure.configuration }; reload()
    }
    static func message(_ error: Error) -> String {
        (error as? CalendarRSVPFailure)?.localizedDescription ?? CalendarRSVPFailure.unconfirmed.localizedDescription
    }
}

@MainActor
enum CalendarRSVPProvisioner {
    struct Envelope: Decodable {
        let schemaVersion: Int; let baseURL: String; let installationId: UUID; let acceptToken: String
        let accessClientId: String?; let accessClientSecret: String?
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--configure-calendar-rsvp") else { return }
        let folder = FileManager.default.temporaryDirectory, file = folder.appendingPathComponent("dhoop-calendar-rsvp-provisioning.json")
        var status = "setup_not_verified"
        do {
            let data = try Data(contentsOf: file); guard data.count <= 8192 else { throw CalendarRSVPFailure.configuration }
            let v = try JSONDecoder().decode(Envelope.self, from: data); guard v.schemaVersion == 1 else { throw CalendarRSVPFailure.configuration }
            try await CalendarRSVPClient.shared.install(.init(origin: v.baseURL, installationId: v.installationId, acceptToken: v.acceptToken,
                accessClientId: v.accessClientId, accessClientSecret: v.accessClientSecret))
            try Data("{\"schemaVersion\":1,\"consumed\":true}".utf8).write(to: file, options: .atomic)
            status = "accept_only_capabilities_verified"
        } catch { }
        let result: [String: Any] = ["schemaVersion": 1, "status": status, "enabled": CalendarRSVPClient.shared.enabled,
            "writesAttempted": false, "runId": CalendarReaderProvisioner.verificationRun,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: result) { try? data.write(to: folder.appendingPathComponent("dhoop-calendar-rsvp-result.json"), options: .atomic) }
    }
}
