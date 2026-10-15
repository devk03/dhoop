#if os(iOS)
import SwiftUI
import StrandDesign
import UniformTypeIdentifiers

struct WorkoutFrontendSettingsView: View {
    @ObservedObject private var client = WorkoutFrontendClient.shared
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var token = ""
    @State private var error: String?
    @State private var exporting = false
    @State private var document: WorkoutFrontendQueueDocument?

    var body: some View {
        ScreenScaffold(title: "Website editing", subtitle: "The same workout actions as Life and its MCP") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Enable website editing", isOn: Binding(get: { client.state.enabled }, set: {
                            do { try client.setEnabled($0) } catch { self.error = error.localizedDescription }
                        })).toggleStyle(NoopSwitchStyle())
                            .disabled(client.busy || client.storageUnavailable || (!client.configured && !client.state.enabled))
                        Text("Programs, prescriptions, performed values and progression stay in Life. WHOOP recordings remain separate evidence.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        NoopAsyncButton("Check editing capabilities", systemImage: "arrow.clockwise", kind: .secondary) {
                            try await client.checkCapabilities()
                        }.disabled(!client.state.enabled || client.busy || client.storageUnavailable)
                        if let capabilities = client.state.capabilities, let checked = client.state.checkedAt {
                            Text(capabilities.frontendStart ? "Workout start and status changes available" : "Workout start and status changes unavailable")
                                .font(StrandFont.subhead)
                            Text("Checked \(checked.formatted(date: .abbreviated, time: .shortened)) · revision \(capabilities.lifeRevision)")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        if client.storageUnavailable {
                            Text("The command queue could not be read. It has been retained; editing is paused.")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.statusCritical)
                        }
                    }
                }
                if !client.state.operations.isEmpty {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Website changes").font(StrandFont.headline)
                            Text("Receipt recovery only reads. A timeout never starts a replacement operation.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            ForEach(client.state.operations.reversed().prefix(30)) { item in
                                DisclosureGroup {
                                    Text(item.id.uuidString.lowercased()).font(StrandFont.caption).textSelection(.enabled)
                                    Text("Prepared \(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · base revision \(item.intent.expectedLifeRevision)")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    ForEach(item.intent.command.keys.sorted(), id: \.self) { key in
                                        if let value = item.intent.command[key] {
                                            Text("\(key): \(value.displayText)").font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    if item.attemptedAt != nil {
                                        NoopAsyncButton("Recover exact receipt", systemImage: "arrow.clockwise", kind: .secondary) { try await client.recover(item.id) }
                                            .disabled(client.busy || !client.state.enabled)
                                    }
                                    if item.state == .prepared || item.state == .notObserved {
                                        NoopAsyncButton(item.state == .prepared ? "Send retained change" : "Retry same operation", systemImage: "paperplane") { try await client.submit(item.id) }
                                            .disabled(client.busy || !client.state.enabled)
                                    }
                                    if item.state == .prepared {
                                        NoopAsyncButton("Cancel unsent change", systemImage: "xmark", kind: .secondary) { try client.cancelUnsent(item.id) }.disabled(client.busy)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                        Text(item.intent.command["action"]?.displayText.replacingOccurrences(of: "_", with: " ").capitalized ?? "Website change").font(StrandFont.subhead)
                                        Text(status(item.state)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    }.frame(minHeight: NoopMetrics.minimumTouchTarget, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Dedicated editing credential").font(StrandFont.headline)
                        Text("Uses the workout connection's origin and installation ID. This is a separate permission from reading plans or sending WHOOP observations.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        SecureField("Workout frontend credential", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        NoopAsyncButton("Save editing connection", systemImage: "key", kind: .secondary) {
                            guard let origin = tracker.state.origin, let id = tracker.state.installationId else { throw WorkoutSyncTransportError.configuration }
                            try client.configure(origin: origin, installationId: id, token: token); token = ""
                        }.disabled(client.busy || client.unresolved != nil || token.isEmpty || tracker.state.origin == nil || tracker.state.installationId == nil)
                        Text("Saving leaves editing off. The credential stays in Keychain. Existing source deliveries and receipts are preserved.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                NoopAsyncButton("Export command receipts", systemImage: "square.and.arrow.up", kind: .secondary) {
                    document = try WorkoutFrontendQueueDocument(state: client.state); exporting = true
                }.disabled(client.busy || client.storageUnavailable)
                Text("This export contains retained command input and receipts, without credentials. It is separate from WHOOP metadata and SQLite backups. Keep it private.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Dhoop-website-command-receipts") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .alert("Editing unchanged", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Please try again.") }
    }
    private func status(_ state: WorkoutFrontendOperation.State) -> String {
        switch state {
        case .prepared: return "Prepared on this phone · not sent"
        case .sending, .uncertain: return "Acceptance unresolved · recover receipt"
        case .committed: return "Saved in Life · receipt verified"
        case .rejected: return "Rejected · no primary effects applied"
        case .notObserved: return "Not observed · same operation retained"
        case .cancelled: return "Cancelled before sending"
        }
    }
}

struct WorkoutFrontendQueueDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(state: WorkoutFrontendState) throws {
        try state.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(state)
    }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif
