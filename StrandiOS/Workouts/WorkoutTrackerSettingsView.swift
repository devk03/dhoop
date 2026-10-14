#if os(iOS)
import SwiftUI
import StrandDesign
import UniformTypeIdentifiers

struct WorkoutTrackerSettingsView: View {
    @ObservedObject private var client = WorkoutTrackerClient.shared
    @State private var origin = ""
    @State private var token = ""
    @State private var error: String?
    @State private var backupDocument: WorkoutTrackerBackupDocument?
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var selectedBackup: URL?
    @State private var backupSummary: WorkoutTrackerBackupManifest?
    @State private var backupMessage: String?
    @State private var inspectingBackup = false
    @EnvironmentObject private var repo: Repository

    var body: some View {
        ScreenScaffold(title: "Workout tracker", subtitle: "Life routines and progression · Dhoop observations and WHOOP data") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Connect workout tracker", isOn: Binding(get: { client.state.enabled }, set: { enabled in
                            do { try client.setEnabled(enabled) } catch { self.error = error.localizedDescription }
                        })).toggleStyle(NoopSwitchStyle()).disabled(client.busy || (!client.configured && !client.state.enabled) || client.storageUnavailable)
                        Text(client.state.message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        if let captured = client.state.capturedAt {
                            Text("Last routine read: \(captured.formatted(date: .abbreviated, time: .shortened))")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        NoopAsyncButton("Refresh tracker routines", systemImage: "arrow.clockwise", kind: .secondary) {
                            try await client.refreshIndex()
                        }.disabled(!client.state.enabled || client.busy || client.storageUnavailable)
                    }
                }
                if !client.historyReferences.isEmpty {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Workout deliveries").font(StrandFont.headline)
                            NoopAsyncButton("Sync saved workouts", systemImage: "arrow.triangle.2.circlepath", kind: .secondary) {
                                guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                                try await client.synchronize(store: store)
                            }.disabled(!client.state.enabled || client.busy)
                            ForEach(client.historyReferences.prefix(20)) { delivery in
                                NavigationLink { WorkoutTrackerDeliveryView(deliveryId: delivery.id) } label: {
                                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                        Text(delivery.title ?? "Strength workout").font(StrandFont.subhead)
                                        Text(client.state.locallyKeptSources.contains(delivery.sourceWorkoutId) ? "Kept locally" : delivery.status == .accepted ? "Receipt recorded" : "Awaiting receipt or review")
                                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                        Text(Date(timeIntervalSince1970: Double(delivery.startedAt)).formatted(date: .abbreviated, time: .shortened)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    }.frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget, alignment: .leading)
                                }.buttonStyle(NoopFeedbackButtonStyle())
                            }
                        }
                    }
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Dedicated connection").font(StrandFont.headline)
                        Text("Use a credential limited to the workout integration. Sleep, protein, buzz, and MCP credentials do not belong here.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        if let installation = client.state.installationId {
                            Text("Installation ID").font(StrandFont.caption)
                            Text(installation.uuidString.lowercased()).font(StrandFont.caption).textSelection(.enabled)
                            ShareLink(item: installation.uuidString.lowercased()) { Label("Share connection ID", systemImage: "square.and.arrow.up") }
                                .buttonStyle(NoopButtonStyle(.secondary))
                        } else {
                            NoopAsyncButton("Create connection ID", systemImage: "link", kind: .secondary) { try client.createInstallationId() }
                        }
                        TextField("HTTPS origin", text: $origin).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        SecureField("Dedicated workout credential", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        NoopAsyncButton("Save connection", systemImage: "checkmark") {
                            guard let id = client.state.installationId else { throw WorkoutSyncTransportError.configuration }
                            try client.configure(origin: origin, token: token, installationId: id)
                            token = ""
                        }.disabled(client.busy || client.state.installationId == nil || client.storageUnavailable)
                        Text("Saving keeps the connection off. Credentials stay in Keychain. Local workout data is retained if sync fails.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                backupCard
            }
        }
        .onAppear { origin = client.state.origin ?? "" }
        .fileExporter(isPresented: $exportingBackup, document: backupDocument, contentType: .dhoopWorkoutMetadata,
                      defaultFilename: "Dhoop-workout-metadata") { result in
            switch result {
            case .success: backupMessage = "Metadata backup saved. SQLite data is backed up separately with .noopbak."
            case .failure(let error): backupMessage = "The package remains prepared; export was not confirmed. \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.dhoopWorkoutMetadata], allowsMultipleSelection: false) { result in
            do {
                guard let selected = try result.get().first else { return }
                inspectingBackup = true
                Task { @MainActor in
                    let access = selected.startAccessingSecurityScopedResource()
                    defer { if access { selected.stopAccessingSecurityScopedResource() }; inspectingBackup = false }
                    do { backupSummary = try await client.metadataBackupSummary(at: selected); selectedBackup = selected }
                    catch { backupMessage = "Metadata was not changed. \(error.localizedDescription)" }
                }
            } catch { backupMessage = "Metadata was not changed. \(error.localizedDescription)" }
        }
        .sheet(isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil; backupSummary = nil } })) { restoreSheet }
        .alert("Connection was not changed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Please try again.") }
    }

    private var backupCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Backup metadata").font(StrandFont.headline)
                Text("Tracker plans, source IDs, receipts and paused delivery choices.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Text("Credentials are excluded. SQLite workouts, notes and sensor data use the separate .noopbak backup. Active unsaved sessions remain on this phone.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Prepare metadata backup", systemImage: "square.and.arrow.up") {
                    let package = try await client.prepareMetadataBackup()
                    backupDocument = try WorkoutTrackerBackupDocument(package: package)
                    backupMessage = "Package prepared · choose where to save"
                    exportingBackup = true
                }.disabled(client.busy || client.storageUnavailable || inspectingBackup)
                NoopButton("Restore metadata backup", systemImage: "square.and.arrow.down", kind: .secondary) { importingBackup = true }
                    .disabled(client.busy || client.storageUnavailable || inspectingBackup)
                if let backupMessage { Text(backupMessage).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            }
        }
    }
    private var restoreSheet: some View {
        ScreenScaffold(title: "Restore metadata", subtitle: "Merge into this phone") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("Existing workouts stay untouched. The tracker connection stays off. Original source IDs and destinations are preserved.")
                    .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                if let backupSummary {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("\(backupSummary.state.deliveries.count) saved delivery intents").font(StrandFont.subhead)
                            Text("\(backupSummary.state.archives.count) archive references in manifest").font(StrandFont.subhead)
                            Text("Created \(backupSummary.createdAt.formatted(date: .abbreviated, time: .shortened))").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                NoopAsyncButton("Merge metadata", systemImage: "arrow.triangle.merge") {
                    guard let selectedBackup else { throw WorkoutTrackerContractError.invalidSnapshot }
                    let access = selectedBackup.startAccessingSecurityScopedResource()
                    defer { if access { selectedBackup.stopAccessingSecurityScopedResource() } }
                    try await client.restoreMetadataBackup(from: selectedBackup)
                    backupMessage = "Metadata merged. Tracker remains off; database and credentials are unchanged."
                    self.selectedBackup = nil; backupSummary = nil
                }.disabled(client.busy)
                NoopButton("Cancel", kind: .tertiary) { selectedBackup = nil; backupSummary = nil }.disabled(client.busy)
            }
        }.interactiveDismissDisabled(client.busy)
    }
}
#endif
