import Foundation

/// Local developer-assisted setup. No credential is compiled into the app or accepted by a URL.
@MainActor
struct WorkoutConnectionProvisioner {
    struct Envelope: Codable {
        let schemaVersion: Int
        let installationId: UUID
        let baseURL: String
        let sourceToken: String
        let frontendToken: String
        let accessClientId: String?
        let accessClientSecret: String?

        func configurations() throws -> (WorkoutSyncConfiguration, WorkoutSyncConfiguration) {
            let source = WorkoutSyncConfiguration(origin: baseURL, installationId: installationId, credential: sourceToken,
                accessClientId: accessClientId, accessClientSecret: accessClientSecret)
            let frontend = WorkoutSyncConfiguration(origin: baseURL, installationId: installationId, credential: frontendToken,
                accessClientId: accessClientId, accessClientSecret: accessClientSecret)
            guard schemaVersion == 1, source.valid, frontend.valid, sourceToken != frontendToken else { throw Failure.configuration }
            return (source, frontend)
        }
    }
    enum Failure: Error { case configuration, existingConnection, permission, incomplete }
    let tracker: WorkoutTrackerClient
    let frontend: WorkoutFrontendClient
    var sourceCredential: () throws -> WorkoutSyncConfiguration? = WorkoutTrackerKeychain.read
    var frontendCredential: () throws -> WorkoutSyncConfiguration? = WorkoutTrackerKeychain.readFrontend

    func install(_ envelope: Envelope) async throws {
        let (source, editor) = try envelope.configurations()
        guard !tracker.busy, !frontend.busy, !tracker.storageUnavailable, !frontend.storageUnavailable,
              tracker.historyReferences.isEmpty, frontend.unresolved == nil,
              tracker.state.installationId == nil || tracker.state.installationId == source.installationId,
              tracker.state.origin == nil || tracker.state.origin == source.origin,
              frontend.state.installationId == nil || frontend.state.installationId == editor.installationId,
              frontend.state.origin == nil || frontend.state.origin == editor.origin else { throw Failure.existingConnection }
        let oldSource = try sourceCredential(), oldEditor = try frontendCredential()
        guard oldSource.map({ same($0, source) }) ?? true, oldEditor.map({ same($0, editor) }) ?? true else { throw Failure.existingConnection }
        if !tracker.configured {
            try tracker.configure(origin: source.origin, token: source.credential, installationId: source.installationId,
                accessClientId: source.accessClientId, accessClientSecret: source.accessClientSecret)
        }
        if !frontend.configured {
            try frontend.configure(origin: editor.origin, installationId: editor.installationId, token: editor.credential,
                accessClientId: editor.accessClientId, accessClientSecret: editor.accessClientSecret)
        }
        // Enable only this explicitly requested owner connection; no workout mutation is tested.
        try tracker.setEnabled(true)
        try await tracker.refreshDashboard()
        try frontend.setEnabled(true)
        do {
            try await frontend.checkCapabilities()
            guard frontend.state.capabilities?.manualCommands == true,
                  frontend.state.capabilities?.frontendStart == false else { throw Failure.permission }
        } catch {
            try frontend.setEnabled(false)
            throw error
        }
        guard let savedSource = try sourceCredential(), let savedEditor = try frontendCredential(),
              same(savedSource, source), same(savedEditor, editor), tracker.state.frontendPage != nil else { throw Failure.incomplete }
    }

    func consumeFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 8192 else { throw Failure.configuration }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        try await install(envelope)
        // Retire only the local transfer contents after verified Keychain storage and authenticated reads.
        try Data("{\"schemaVersion\":1,\"consumed\":true}".utf8).write(to: url, options: .atomic)
    }
    private func same(_ lhs: WorkoutSyncConfiguration, _ rhs: WorkoutSyncConfiguration) -> Bool {
        lhs.origin == rhs.origin && lhs.installationId == rhs.installationId && lhs.credential == rhs.credential &&
            lhs.accessClientId == rhs.accessClientId && lhs.accessClientSecret == rhs.accessClientSecret
    }

    static func runLocalLaunchImport() async {
        guard ProcessInfo.processInfo.arguments.contains("--configure-workout") else { return }
        let folder = FileManager.default.temporaryDirectory
        let input = folder.appendingPathComponent("dhoop-workout-provisioning.json")
        let output = folder.appendingPathComponent("dhoop-workout-connection-result.json")
        let provisioner = Self(tracker: .shared, frontend: .shared)
        var result = "setup_not_verified"
        do { try await provisioner.consumeFile(at: input); result = "connected_reads_verified_lifecycle_off" }
        catch { /* Never log the envelope, credential values or arbitrary decoding/server error text. */ }
        let report: [String: Any] = ["schemaVersion": 1, "status": result,
            "installationId": provisioner.tracker.state.installationId?.uuidString.lowercased() ?? "unconfigured",
            "readEnabled": provisioner.tracker.state.enabled, "editingEnabled": provisioner.frontend.state.enabled,
            "lifecycleEnabled": provisioner.frontend.state.capabilities?.frontendStart ?? false]
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: output, options: .atomic) }
    }
}
