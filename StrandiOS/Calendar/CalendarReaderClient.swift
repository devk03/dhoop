import Foundation
import Combine

/// One in-memory day. Configuration changes invalidate every in-flight day and event response.
@MainActor
final class CalendarReaderClient: ObservableObject {
    static let shared = CalendarReaderClient()
    @Published private(set) var configuration: CalendarReaderConfiguration?
    @Published private(set) var day = CalendarReaderDayChain()
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var stale = false
    private var generation = 0
    private var dayTicket = UUID()
    private let send: (CalendarReaderEndpoint, CalendarReaderConfiguration) async throws -> Data
    private let read: () throws -> CalendarReaderConfiguration?
    private let save: (CalendarReaderConfiguration) throws -> Void
    var enabled: Bool { configuration?.enabled == true }
    var identity: String { "\(generation)|\(configuration?.installationId.uuidString ?? "")|\(enabled)" }
    init(read: @escaping () throws -> CalendarReaderConfiguration? = CalendarReaderKeychain.read,
         save: @escaping (CalendarReaderConfiguration) throws -> Void = CalendarReaderKeychain.save,
         send: @escaping (CalendarReaderEndpoint, CalendarReaderConfiguration) async throws -> Data = { try await CalendarReaderTransport().send($0, configuration: $1) }) {
        self.read = read; self.save = save; self.send = send
        do {
            let candidate = try read()
            guard candidate?.valid != false else { throw CalendarReaderFailure.configuration }
            configuration = candidate
        } catch { self.error = CalendarReaderFailure.configuration.localizedDescription }
    }
    func snapshot(for date: String) -> CalendarReaderDayChain? { enabled && day.first?.date == date ? day : nil }
    /// A background launch may precede the device unlock required by this foreground-only Keychain item.
    @discardableResult
    func reloadConfiguration() -> Bool {
        do {
            let next = try read()
            guard next?.valid != false else { throw CalendarReaderFailure.configuration }
            if next != configuration {
                generation += 1; dayTicket = UUID(); configuration = next; day = .init(); busy = false; stale = false; error = nil
            }
            return true
        } catch { self.error = CalendarReaderFailure.configuration.localizedDescription; stale = day.first != nil; return false }
    }
    func setEnabled(_ enabled: Bool) throws {
        guard var next = configuration else { throw CalendarReaderFailure.configuration }
        next.enabled = enabled; try save(next); replace(next)
    }
    private func replace(_ next: CalendarReaderConfiguration) {
        generation += 1; dayTicket = UUID(); configuration = next; day = .init(); busy = false; error = nil; stale = false
    }
    /// Candidate reads precede credential replacement; a failed setup preserves the previous connection.
    func install(_ candidate: CalendarReaderConfiguration, today: String = CalendarReaderDates.key(Date())) async throws {
        guard candidate.valid, candidate.enabled else { throw CalendarReaderFailure.configuration }
        if let old = try read() {
            var expected = old; expected.enabled = true
            guard expected == candidate else { throw CalendarReaderFailure.configuration }
        }
        let ticket = generation
        let page = try await decodeDay(.day(today, nil), configuration: candidate, date: today)
        try Task.checkCancellation(); guard generation == ticket else { throw CancellationError() }
        try save(candidate)
        guard try read() == candidate else { throw CalendarReaderFailure.configuration }
        replace(candidate)
        try day.accept(page, date: today, requestedCursor: nil)
    }
    func loadDay(_ date: String, more: Bool = false) async {
        guard reloadConfiguration(), let configuration, configuration.enabled else { return }
        let ticket = UUID(), version = generation; dayTicket = ticket; busy = true; error = nil
        defer { if dayTicket == ticket { busy = false } }
        var cursor = more && day.first?.date == date ? day.cursor : nil
        do {
            var response: CalendarReaderDay
            do { response = try await decodeDay(.day(date, cursor), configuration: configuration, date: date) }
            catch CalendarReaderFailure.snapshotChanged where cursor != nil {
                guard generation == version, dayTicket == ticket else { throw CancellationError() }
                day = .init(); cursor = nil
                response = try await decodeDay(.day(date, nil), configuration: configuration, date: date)
            }
            try Task.checkCancellation(); guard generation == version, dayTicket == ticket else { throw CancellationError() }
            do { try day.accept(response, date: date, requestedCursor: cursor) }
            catch CalendarReaderFailure.snapshotChanged where cursor != nil {
                day = .init()
                let first = try await decodeDay(.day(date, nil), configuration: configuration, date: date)
                try Task.checkCancellation(); guard generation == version, dayTicket == ticket else { throw CancellationError() }
                try day.accept(first, date: date, requestedCursor: nil)
            }
            stale = false
        } catch is CancellationError { }
        catch {
            guard generation == version, dayTicket == ticket else { return }
            self.error = Self.message(error); stale = day.first != nil
        }
    }
    private func decodeDay(_ endpoint: CalendarReaderEndpoint, configuration: CalendarReaderConfiguration, date: String) async throws -> CalendarReaderDay {
        let data = try await send(endpoint, configuration)
        guard data.count < CalendarReaderTransport.responseLimit else { throw CalendarReaderFailure.http(413) }
        let page = try JSONDecoder().decode(CalendarReaderDay.self, from: data); try page.validate(date: date); return page
    }
    func readEvent(date: String, id: String, taskRef: String? = nil, before: Int? = nil) async throws -> CalendarReaderDetail {
        guard reloadConfiguration(), let configuration, configuration.enabled else { throw CalendarReaderFailure.disabled }
        let version = generation
        let data = try await send(.event(date, id, taskRef, before), configuration)
        try Task.checkCancellation(); guard version == generation else { throw CancellationError() }
        guard data.count < CalendarReaderTransport.responseLimit else { throw CalendarReaderFailure.http(413) }
        let result = try JSONDecoder().decode(CalendarReaderDetail.self, from: data)
        try result.validate(date: date, eventId: id, taskRef: taskRef, before: before); return result
    }
    static func message(_ error: Error) -> String {
        (error as? CalendarReaderFailure)?.localizedDescription ?? CalendarReaderFailure.http(502).localizedDescription
    }
}

@MainActor
enum CalendarReaderProvisioner {
    struct Envelope: Decodable {
        let schemaVersion: Int; let baseURL: String; let installationId: UUID; let readToken: String
        let accessClientId: String?; let accessClientSecret: String?
        var configuration: CalendarReaderConfiguration {
            .init(enabled: true, origin: baseURL, installationId: installationId, readToken: readToken,
                  accessClientId: accessClientId, accessClientSecret: accessClientSecret)
        }
    }
    static func consume(_ url: URL, client: CalendarReaderClient) async throws {
        let data = try Data(contentsOf: url); guard data.count <= 8192 else { throw CalendarReaderFailure.configuration }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw CalendarReaderFailure.configuration }
        try await client.install(envelope.configuration)
        try Data("{\"schemaVersion\":1,\"consumed\":true}".utf8).write(to: url, options: .atomic)
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--configure-calendar") else { return }
        let folder = FileManager.default.temporaryDirectory, client = CalendarReaderClient.shared
        var status = "setup_not_verified"
        do { try await consume(folder.appendingPathComponent("dhoop-calendar-provisioning.json"), client: client); status = "connected_authenticated_day_read" } catch { }
        let report: [String: Any] = ["schemaVersion": 1, "status": status, "readEnabled": client.enabled,
            "installationId": client.configuration?.installationId.uuidString.lowercased() ?? "unconfigured",
            "runId": verificationRun, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: folder.appendingPathComponent("dhoop-calendar-connection-result.json"), options: .atomic)
        }
    }
    static var verificationRun: String {
        let value = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--calendar-verification-run=") }
            .map { String($0.dropFirst("--calendar-verification-run=".count)) }
        return value.flatMap(UUID.init(uuidString:))?.uuidString ?? "manual"
    }
}
