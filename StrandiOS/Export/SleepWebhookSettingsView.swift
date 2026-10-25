#if os(iOS)
import SwiftUI
import StrandDesign

struct SleepWebhookSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var client = SleepWebhookClient.shared
    @State private var endpoint = "https://track.kunjadia.dev/api/webhooks/sleep"
    @State private var bearer = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var proteinBearer = ""
    @State private var error: String?

    var body: some View {
        ScreenScaffold(title: "Life sync", subtitle: "Sleep and protein, on your website") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                StrandCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Sleep", isOn: Binding(get: { client.checkpoint.enabled }, set: { enabled in
                            if perform({ try client.setEnabled(enabled) }), enabled { client.enqueue(model: model, force: true) }
                        }))
                        .font(StrandFont.headline).toggleStyle(NoopSwitchStyle())
                        .disabled(client.storageUnavailable || (!client.checkpoint.enabled && !client.hasCredentials))
                        LifeSyncStatusView(status: LifeSyncStatus(checkpoint: client.checkpoint, protein: false,
                            checking: client.isSending, storageUnavailable: client.storageUnavailable))
                        Divider()
                        Toggle("Protein", isOn: Binding(get: { client.checkpoint.proteinEnabled == true }, set: { enabled in
                            if perform({ try client.setProteinEnabled(enabled) }), enabled { client.enqueue(model: model, force: true) }
                        }))
                        .font(StrandFont.headline).toggleStyle(NoopSwitchStyle())
                        .disabled(client.storageUnavailable || (client.checkpoint.proteinEnabled != true && !client.hasProteinCredentials))
                        LifeSyncStatusView(status: LifeSyncStatus(checkpoint: client.checkpoint, protein: true,
                            checking: client.isSending, storageUnavailable: client.storageUnavailable))
                        Toggle("Calorie estimates", isOn: Binding(get: { client.checkpoint.caloriesEnabled == true }, set: { enabled in
                            if perform({ try client.setCaloriesEnabled(enabled) }), enabled { client.enqueue(model: model, force: true) }
                        })).font(StrandFont.headline).toggleStyle(NoopSwitchStyle())
                            .disabled(client.storageUnavailable || !client.hasProteinCredentials || client.checkpoint.proteinEnabled != true)
                        Text("Completed-day estimated subtotals. Missing estimates stay unknown.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    NoopAsyncButton("Sync now", systemImage: "arrow.triangle.2.circlepath", fullWidth: true) {
                        try await client.sendAvailableSummaries(model: model)
                        error = nil
                    }.disabled(!client.checkpoint.anyEnabled || client.isSending || client.storageUnavailable)
                    if let result = client.checkResult {
                        Text(result).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            .accessibilityIdentifier("lifeSyncCheckResult")
                    }
                }
                DisclosureGroup("Connection settings") {
                StrandCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Label("Connection", systemImage: "lock.shield").font(StrandFont.headline)
                        Text(client.hasCredentials ? "Credentials are stored in this phone's Keychain." : "Connect your website to enable delivery.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        DisclosureGroup("Enter or replace credentials") {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                TextField("HTTPS endpoint", text: $endpoint)
                                    .keyboardType(.URL).textContentType(.URL)
                                SecureField("Sleep access token", text: $bearer)
                                SecureField("Protein access token (optional)", text: $proteinBearer)
                                SecureField("Cloudflare Access client ID", text: $clientId)
                                SecureField("Cloudflare Access client secret", text: $clientSecret)
                                NoopAsyncButton("Save connection", systemImage: "lock.shield", kind: .secondary, fullWidth: true) {
                                    do {
                                        try client.configure(SleepWebhookCredentials(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                                            bearer: bearer.trimmingCharacters(in: .whitespacesAndNewlines),
                                            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
                                            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                                            proteinBearer: proteinBearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : proteinBearer.trimmingCharacters(in: .whitespacesAndNewlines)))
                                        bearer = ""; clientId = ""; clientSecret = ""; proteinBearer = ""; error = nil
                                    } catch { throw SleepWebhookClient.ActionFailure(message: SleepWebhookClient.safeMessage(error)) }
                                }.disabled(client.isSending || client.storageUnavailable)
                                Text("Saving pauses delivery. Turn it on when the destination is ready.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            }.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                                .padding(.top, NoopMetrics.space3)
                        }.font(StrandFont.subhead)
                        DisclosureGroup("Encrypted setup from this Mac") {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                Text("Prepare a public setup file, then import the encrypted reply transferred by your paired Mac. No credential is stored in a plain-text file on your phone.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                NoopAsyncButton("Prepare secure setup", systemImage: "key", kind: .secondary, fullWidth: true) {
                                    do {
                                        try client.prepareSecureSetup()
                                        guard !client.storageUnavailable else { throw SleepWebhookFailure.storage }
                                        error = nil
                                    }
                                    catch { throw SleepWebhookClient.ActionFailure(message: SleepWebhookClient.safeMessage(error)) }
                                }
                                NoopAsyncButton("Import encrypted setup", systemImage: "square.and.arrow.down", kind: .secondary, fullWidth: true) {
                                    do {
                                        try client.importSecureSetup()
                                        guard !client.storageUnavailable else { throw SleepWebhookFailure.storage }
                                        error = nil
                                    }
                                    catch { throw SleepWebhookClient.ActionFailure(message: SleepWebhookClient.safeMessage(error)) }
                                }
                            }.padding(.top, NoopMetrics.space3)
                        }.font(StrandFont.subhead).disabled(client.isSending)
                    }
                }
                }.font(StrandFont.subhead)
                if let error { Text(error).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusCritical) }
                DisclosureGroup("How Life sync works") {
                    Text("Verified WHOOP sleep sends after processing. Protein sends after the logged day ends; no calories or weight are required. Life keeps manual values. Newer sleep analysis may still be pending. Opening Dhoop retries saved events; iOS controls background timing. Export pauses outside America/Los_Angeles.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, NoopMetrics.space2)
                }.font(StrandFont.subhead)
            }.foregroundStyle(StrandPalette.textPrimary)
        }
        .task { if !client.checkpoint.delivery.endpoint.isEmpty { endpoint = client.checkpoint.delivery.endpoint } }
    }
    @discardableResult private func perform(_ work: () throws -> Void) -> Bool {
        do { try work(); error = nil; return true } catch { self.error = SleepWebhookClient.safeMessage(error); return false }
    }
}
#endif
