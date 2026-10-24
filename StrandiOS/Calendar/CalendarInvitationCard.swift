#if os(iOS)
import SwiftUI
import StrandDesign

struct CalendarInvitationCard: View {
    let event: CalendarReaderEvent
    let connected: Bool
    let accepting: Bool
    let requiresRefresh: Bool
    let accept: () async -> Void
    var body: some View {
        if let invitation = event.invitation {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    if let organizer = invitation.organizer { person("Organizer", organizer) }
                    if let creator = invitation.creator, creator != invitation.organizer { person("Created by", creator) }
                    if invitation.isInvitation {
                        Divider().overlay(StrandPalette.hairline)
                        LabeledContent("Your response") { Text(LocalizedStringKey(invitation.responseLabel)) }.font(StrandFont.subhead)
                        if invitation.responseStatus != "accepted" {
                            NoopAsyncButton("Accept invitation", systemImage: "checkmark", fullWidth: true) { await accept() }
                                .disabled(!connected || !invitation.eligibleToAccept || !CalendarAcceptRequest.strongEtag(event.etag ?? "") || accepting || requiresRefresh)
                            if !connected || invitation.acceptBlockedReason == "rsvp_not_configured" {
                                Text("Accept setup pending").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            } else if !invitation.eligibleToAccept {
                                Text("This invitation cannot be accepted here.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                        if invitation.scope == "occurrence" { Text("This occurrence only").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func person(_ title: LocalizedStringKey, _ identity: CalendarInvitation.Identity) -> some View {
        if let name = identity.label {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: name).font(StrandFont.headline).textSelection(.enabled)
                if let email = identity.email, email != name { Text(verbatim: email).font(StrandFont.caption).textSelection(.enabled) }
            }
        }
    }
}
struct CalendarAcceptanceStatus: View {
    let error: String?
    let requiresRefresh: Bool
    let refresh: () async -> Void
    var body: some View {
        if let error {
            Text(LocalizedStringKey(error)).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning)
            if requiresRefresh { NoopAsyncButton("Refresh invitation", systemImage: "arrow.clockwise", kind: .secondary) { await refresh() } }
        }
    }
}
#endif
