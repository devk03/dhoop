#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign

struct RemoteBuzzSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @ObservedObject private var client = RemoteBuzzClient.shared
    @State private var envelopeText = ""
    @State private var importingFile = false
    @State private var confirmRevocation = false
    @State private var importError: String?
    private struct ActionFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var latest: RemoteBuzzState.Event? { client.state.events.last }
    var body: some View {
        ScreenScaffold(title: "WHOOP alerts", subtitle: "Agent cues, permissions, and delivery evidence.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Toggle("Remote alerts", isOn: Binding(get: { client.state.enabled && !client.state.revoked },
                            set: { client.setEnabled($0) }))
                            .font(StrandFont.headline).toggleStyle(NoopSwitchStyle())
                            .disabled(!client.paired || client.state.revoked)
                        Text(client.status).font(StrandFont.subhead)
                        Text(client.registrationStatus).font(StrandFont.caption)
                        Text(client.inboxStatus).font(StrandFont.caption)
                        Text("Life must also permit sends. One short WHOOP cue per request, with no private-API hourly limit or cooldown. No health data is sent by this feature.")
                        Text("When locked: Apple may let Dhoop run briefly to send the buzz. Delivery is best effort; a lost connection or delayed push can prevent it. Force-quitting stops normal background delivery.")
                    }.foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if !client.paired { pairingCard }
                if let latest {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Latest remote alert").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                            Text(Date(timeIntervalSince1970: Double(latest.receivedAt)).formatted(date: .abbreviated, time: .standard))
                            evidence("Apple acceptance", "See the separate event status in Life")
                            evidence("Dhoop receipt", latest.outcome.replacingOccurrences(of: "_", with: " "))
                            let receipts = client.state.receipts.filter { $0.receipt.eventId == latest.id }.map(\.receipt)
                            if let delivery = receipts.first(where: { $0.stage == "phone_received" }), let source = delivery.transport {
                                evidence("Delivery path", (source == "inbox" ? "Inbox fetch" : "Apple push")
                                    + (delivery.appState.map { " · " + $0 } ?? ""))
                            }
                            evidence("WHOOP command", receipts.last(where: { ["strap_requested", "strap_response"].contains($0.stage) })?.outcome.replacingOccurrences(of: "_", with: " ") ?? "No command evidence")
                            evidence("Felt vibration", receipts.last(where: { $0.stage == "wearer_confirmed" })?.outcome == "felt" ? "You confirmed it" : receipts.contains(where: { $0.stage == "wearer_confirmed" && $0.outcome == "not_felt" }) ? "You reported no vibration" : "Not confirmed by you")
                            if receipts.contains(where: { $0.stage == "strap_requested" && $0.outcome == "requested" }) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: NoopMetrics.space2) { confirmation(latest.id) }
                                    VStack(alignment: .leading, spacing: NoopMetrics.space2) { confirmation(latest.id) }
                                }
                            }
                            Text("A command response alone does not prove a vibration.").font(StrandFont.caption)
                        }.font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if client.paired {
                    Button("Revoke Life connection", role: .destructive) { confirmRevocation = true }
                        .buttonStyle(NoopButtonStyle(.secondary)).frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Label("Wake alarms", systemImage: "alarm").font(StrandFont.headline)
                        Text("Manage wake alarms in Alarms. Slot ownership and verified readback remain separate from remote agent cues; pairing does not grant alarm-slot ownership.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                DisclosureGroup("Troubleshooting") {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        NoopActionButton("Retry pending Life updates", systemImage: "arrow.clockwise", kind: .secondary,
                                         state: client.retryingUpdates ? .working : .idle) { client.retryPending() }
                        NoopActionButton("Check for waiting buzzes", systemImage: "tray", kind: .secondary,
                                         state: client.checkingInbox ? .working : .idle) { client.checkInbox() }
                        Text("These actions request bounded checks. The evidence above confirms receipt, strap response and your felt-vibration report separately.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        Text("Missed requests are checked on opening, reconnecting and real Bluetooth wakes, with a ten-minute adaptive foreground window. No background keepalive is used. Expired requests never buzz late.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        BuzzDeliveryStatusView(ble: app.ble)
                        RemoteBuzzTestView()
                    }
                }.font(StrandFont.subhead).tint(StrandPalette.accent)
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8192 else { throw RemoteBuzzEnrollmentError.invalid }
                    guard client.importEnvelope(try Data(contentsOf: url)) else { throw ActionFailure(message: client.status) }
                    importError = nil
                } catch { importError = "Encrypted pairing could not be imported. The file is unchanged; check connection status before retrying." }
            } else if case .failure = result {
                importError = "The encrypted response file could not be opened. Your pasted response is retained."
            }
        }
        .alert("Pairing import needs attention", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .confirmationDialog("Revoke this Life connection? Remote alerts stop immediately on this phone. A new pairing will be required.", isPresented: $confirmRevocation, titleVisibility: .visible) {
            Button("Revoke connection", role: .destructive) { client.revoke() }
        }
        .onAppear { client.retryPending() }
    }
    private var pairingCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label("Connect to Life", systemImage: "link").font(StrandFont.headline)
                Text("Create a public invitation, approve it in your Life Settings, then import the encrypted response. The private pairing key stays on this phone.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Create pairing invitation", systemImage: "link") {
                    guard client.preparePairing() else { throw ActionFailure(message: client.status) }
                }
                if let invitation = client.invitationJSON {
                    Button("Open pairing in Life") { if let url = client.pairingURL() { openURL(url) } }
                        .buttonStyle(NoopButtonStyle(.primary)).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    ShareLink(item: invitation) { Label("Share public invitation", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                    DisclosureGroup("Public invitation") {
                        Text(invitation).font(StrandFont.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Encrypted response from Life").font(StrandFont.subhead)
                    TextEditor(text: $envelopeText).font(StrandFont.caption)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget * 3)
                        .accessibilityLabel("Encrypted pairing response")
                    NoopAsyncButton("Import encrypted response", systemImage: "lock.shield") {
                        guard client.importEnvelope(Data(envelopeText.utf8)) else { throw ActionFailure(message: client.status) }
                        envelopeText = ""
                    }
                        .disabled(envelopeText.isEmpty)
                    Button("Choose encrypted response file") { importingFile = true }
                        .buttonStyle(NoopButtonStyle(.secondary)).frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
            }
        }
    }
    private func evidence(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption)
            Text(value).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    @ViewBuilder private func confirmation(_ eventId: String) -> some View {
        NoopAsyncButton("I felt it", systemImage: "checkmark") {
            guard client.confirm(eventId: eventId, felt: true) else { throw ActionFailure(message: client.status) }
        }
        NoopAsyncButton("I didn’t feel it", systemImage: "xmark", kind: .secondary) {
            guard client.confirm(eventId: eventId, felt: false) else { throw ActionFailure(message: client.status) }
        }
    }
}
#endif
