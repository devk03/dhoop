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
    @State private var error: String?

    var body: some View {
        ScreenScaffold(title: "Sleep webhook", subtitle: "Experimental · your sleep, on your website") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                StrandCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Automatic delivery", isOn: Binding(get: { client.checkpoint.enabled }, set: { enabled in
                            perform { try client.setEnabled(enabled) }
                            if enabled { client.enqueue(model: model, force: true) }
                        }))
                        .font(StrandFont.headline).tint(StrandPalette.accent)
                        .disabled(client.storageUnavailable || (!client.checkpoint.enabled && !client.hasCredentials))
                        Text("Send WHOOP sleep totals to the connected website. Your manual website entries stay yours.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        Label("WHOOP · Dhoop estimate or imported record", systemImage: "moon.zzz")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        Text("Only duration, wake date, source and delivery identifiers are sent. No heart-rate trace or sleep stages.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Label("Delivery", systemImage: "paperplane").font(StrandFont.headline)
                        Text(client.checkpoint.message).font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary).accessibilityIdentifier("sleepWebhookStatus")
                        if let event = client.checkpoint.delivery.lastAcceptedEvent,
                           let date = client.checkpoint.delivery.lastAcceptedAt {
                            Text("Wake date \(event.wakeDate) · received \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        if client.checkpoint.delivery.pending != nil {
                            Label("Pending event saved on this phone", systemImage: "tray.full")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        Button { client.enqueue(model: model, force: true) } label: {
                            Label(client.isSending ? "Sending…" : "Send now", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                        }.buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                            .disabled(!client.checkpoint.enabled || client.isSending || client.storageUnavailable)
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
                                SecureField("Cloudflare Access client ID", text: $clientId)
                                SecureField("Cloudflare Access client secret", text: $clientSecret)
                                Button("Save connection") {
                                    perform {
                                        try client.configure(SleepWebhookCredentials(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                                            bearer: bearer.trimmingCharacters(in: .whitespacesAndNewlines),
                                            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
                                            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)))
                                        bearer = ""; clientId = ""; clientSecret = ""
                                    }
                                }.frame(minHeight: NoopMetrics.minimumTouchTarget).disabled(client.isSending)
                                Text("Saving pauses delivery. Turn it on when the destination is ready.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            }.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                                .padding(.top, NoopMetrics.space3)
                        }.font(StrandFont.subhead)
                        DisclosureGroup("Encrypted setup from this Mac") {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                Text("Prepare a public setup file, then import the encrypted reply transferred by your paired Mac. No credential is stored in a plain-text file on your phone.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Button("Prepare secure setup") { perform { try client.prepareSecureSetup() } }
                                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                                Button("Import encrypted setup") { perform { try client.importSecureSetup() } }
                                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                            }.padding(.top, NoopMetrics.space3)
                        }.font(StrandFont.subhead).disabled(client.isSending)
                    }
                }
                if let error { Text(error).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusCritical) }
                Text("Sends recent sleep after processing and when iOS allows background time. Opening Dhoop retries pending updates. Export pauses outside America/Los_Angeles. Sleep estimates can change as more data arrives.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(StrandPalette.textPrimary)
        }
        .task { if !client.checkpoint.delivery.endpoint.isEmpty { endpoint = client.checkpoint.delivery.endpoint } }
    }
    private func perform(_ work: () throws -> Void) {
        do { try work(); error = nil } catch { self.error = SleepWebhookClient.safeMessage(error) }
    }
}
#endif
