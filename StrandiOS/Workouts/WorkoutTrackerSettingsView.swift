#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutTrackerSettingsView: View {
    @ObservedObject private var client = WorkoutTrackerClient.shared
    @State private var origin = ""
    @State private var token = ""
    @State private var error: String?
    @EnvironmentObject private var repo: Repository

    var body: some View {
        ScreenScaffold(title: "Workout tracker", subtitle: "Life routines and progression · Dhoop observations and WHOOP data") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Connect workout tracker", isOn: Binding(get: { client.state.enabled }, set: { enabled in
                            do { try client.setEnabled(enabled) } catch { self.error = error.localizedDescription }
                        })).tint(StrandPalette.accent).disabled(!client.configured || client.storageUnavailable)
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
                if !client.state.deliveries.isEmpty {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Workout deliveries").font(StrandFont.headline)
                            NoopAsyncButton("Sync saved workouts", systemImage: "arrow.triangle.2.circlepath", kind: .secondary) {
                                guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                                try await client.synchronize(store: store)
                            }.disabled(!client.state.enabled || client.busy)
                            ForEach(client.state.deliveries.suffix(20).reversed()) { delivery in
                                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                    Text(delivery.record.programName ?? "Strength workout").font(StrandFont.subhead)
                                    Text(delivery.message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
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
            }
        }
        .onAppear { origin = client.state.origin ?? "" }
        .alert("Connection was not changed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Please try again.") }
    }
}
#endif
