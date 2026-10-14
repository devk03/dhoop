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
                        Text("WHOOP sleep totals and their source. Manual sleep on Life takes priority.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        Divider()
                        Toggle("Protein", isOn: Binding(get: { client.checkpoint.proteinEnabled == true }, set: { enabled in
                            if perform({ try client.setProteinEnabled(enabled) }), enabled { client.enqueue(model: model, force: true) }
                        }))
                        .font(StrandFont.headline).toggleStyle(NoopSwitchStyle())
                        .disabled(client.storageUnavailable || (client.checkpoint.proteinEnabled != true && !client.hasProteinCredentials))
                        Text("Grams logged in Dhoop. Manual totals on Life take priority. An unlogged day stays blank.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        Text("Sends after the day ends, when iOS allows. Protein needs no calorie log, weight or target.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Label("Delivery", systemImage: "paperplane").font(StrandFont.headline)
                        Text("Sleep · \(client.checkpoint.message)").font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary).accessibilityIdentifier("sleepWebhookStatus")
                        if let event = client.checkpoint.delivery.lastAcceptedEvent,
                           let date = client.checkpoint.delivery.lastAcceptedAt {
                            Text("Wake date \(event.wakeDate) · received \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        Divider()
                        Text("Protein · \(client.checkpoint.proteinMessage ?? "Not enabled")")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        if let event = client.checkpoint.delivery.lastAcceptedProtein,
                           let date = client.checkpoint.delivery.proteinAcceptedAt {
                            Text("Logged date \(event.day) · received \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        if client.checkpoint.delivery.hasPending {
                            Label("Pending event saved on this phone", systemImage: "tray.full")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        NoopAsyncButton("Check & send summaries", systemImage: "arrow.up.circle", fullWidth: true) {
                            try await client.sendAvailableSummaries(model: model)
                            error = nil
                        }
                            .disabled(!client.checkpoint.anyEnabled || client.isSending || client.storageUnavailable)
                        Text("Completion means the available-summary check finished. Only the dated receipt above confirms website acceptance.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
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
                if let error { Text(error).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusCritical) }
                Text("Verified sleep summaries can send on their wake date after processing. Protein sends after the consumption day ends. Opening Dhoop retries pending updates; iOS controls background timing. Export pauses outside America/Los_Angeles. No meal names, calories, weight or raw sensor traces are sent.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(StrandPalette.textPrimary)
        }
        .task { if !client.checkpoint.delivery.endpoint.isEmpty { endpoint = client.checkpoint.delivery.endpoint } }
    }
    @discardableResult private func perform(_ work: () throws -> Void) -> Bool {
        do { try work(); error = nil; return true } catch { self.error = SleepWebhookClient.safeMessage(error); return false }
    }
}
#endif
