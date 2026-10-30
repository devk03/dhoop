#if os(iOS)
import SwiftUI
import PhotosUI
import StrandDesign

struct HealthJournalEditor: View {
    @ObservedObject var client: HealthJournalClient
    let draftId: UUID
    var existingPhotos = 0
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: String?
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var localError: String?
    @State private var reviewing = false
    private var draft: HealthJournalDraft? { client.draft(draftId) }
    private func text(_ key: WritableKeyPath<HealthJournalMutation,String?>) -> Binding<String> {
        Binding(get: { draft?.mutation[keyPath:key] ?? "" }, set: { value in
            guard var mutation=draft?.mutation else {return};mutation[keyPath:key]=value;client.edit(draftId,mutation:mutation)
        })
    }
    var body: some View {
        ScreenScaffold(title:nil) {
            if let draft {
                if draft.mutation.action == "topic" { topicFields(draft) } else { entryFields(draft) }
                if let error=localError ?? draft.lastError { HealthJournalNotice(message:error) }
                if client.storageError { HealthJournalNotice(message:HealthJournalFailure.storage.localizedDescription) }
                Text(LocalizedStringKey(draft.status)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if draft.conflict && !draft.bodyAccepted {
                    Button("Review latest version") { reviewing=true }.buttonStyle(NoopButtonStyle(.secondary))
                } else if draft.needsEditing && !draft.bodyAccepted {
                    NoopAsyncButton("Edit retained draft",systemImage:"square.and.pencil",kind:.secondary) {
                        do { try await client.review(draftId) } catch { localError=HealthJournalClient.message(error) }
                    }
                } else if !draft.completed {
                    NoopAsyncButton(draft.queued ? "Retry save":"Save entry",systemImage:"checkmark",fullWidth:true) {
                        focused=nil;await client.send(draftId)
                        guard client.draft(draftId)?.completed == true else {
                            let message=client.draft(draftId)?.lastError ?? client.error ?? HealthJournalFailure.http(503).localizedDescription
                            throw NSError(domain:"DhoopHealth",code:1,userInfo:[NSLocalizedDescriptionKey:NSLocalizedString(message,comment:"")])
                        }
                        dismiss()
                    }.disabled(client.sending || importing || client.connection == nil || client.storageError)
                }
            }
        }
        .navigationTitle(draft?.mutation.action == "topic" ? "Topic":"Health entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { focused=nil;client.flush();dismiss() } } }
        .keyboardDoneToolbar($focused)
        .onDisappear {client.flush()}
        .onChange(of:picked) {_,items in
            importing=true;focused=nil
            Task {
                defer {importing=false;picked=[]}
                for item in items {
                    do {
                        guard let bytes=try await item.loadTransferable(type:Data.self) else {throw HealthJournalFailure.media}
                        try await client.addPhoto(bytes,draftId:draftId,existingCount:existingPhotos)
                    }catch {localError=HealthJournalClient.message(error);break}
                }
            }
        }
        .sheet(isPresented:$reviewing) {NavigationStack {HealthJournalConflictView(client:client,draftId:draftId)}}
    }
    @ViewBuilder private func entryFields(_ draft:HealthJournalDraft) -> some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                if draft.mutation.action == "observe" {
                    Picker("Topic",selection:text(\.topicId)) {
                        ForEach(client.document.topics) {topic in Text(verbatim:topic.title).tag(topic.id)}
                    }.disabled(!draft.editable).pickerStyle(.menu).font(StrandFont.headline)
                }
                if draft.editable {
                    DatePicker("Observed",selection:Binding(get:{HealthJournalDates.instant(draft.mutation.observedAt ?? "") ?? Date()},set:{date in
                        var mutation=draft.mutation;mutation.observedAt=HealthJournalDates.timestamp(date,zone:mutation.timeZone ?? TimeZone.current.identifier)
                        client.edit(draftId,mutation:mutation)
                    })).environment(\.timeZone,TimeZone(identifier:draft.mutation.timeZone ?? "") ?? .current).font(StrandFont.body)
                    TextField("Timezone",text:text(\.timeZone)).font(StrandFont.subhead).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused,equals:"zone")
                    Button("Use current timezone") {
                        var mutation=draft.mutation;let date=HealthJournalDates.instant(mutation.observedAt ?? "") ?? Date()
                        mutation.timeZone=TimeZone.current.identifier;mutation.observedAt=HealthJournalDates.timestamp(date,zone:TimeZone.current.identifier)
                        client.edit(draftId,mutation:mutation)
                    }.buttonStyle(NoopFeedbackButtonStyle()).font(StrandFont.caption).frame(minHeight:NoopMetrics.minimumTouchTarget)
                }else {
                    Text(verbatim:HealthJournalDates.display(draft.mutation.observedAt ?? "",zone:draft.mutation.timeZone ?? "")).font(StrandFont.body)
                    Text(verbatim:draft.mutation.timeZone ?? "").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                Text("Notes").font(StrandFont.headline)
                TextField("What did you notice?",text:text(\.notes),axis:.vertical).lineLimit(4...12).focused($focused,equals:"notes").font(StrandFont.body).disabled(!draft.editable)
                Divider()
                Text("Symptoms · Optional").font(StrandFont.headline)
                TextField("Add symptoms",text:text(\.symptoms),axis:.vertical).lineLimit(2...6).focused($focused,equals:"symptoms").font(StrandFont.body).disabled(!draft.editable)
            }
        }
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                Text("Photos · Optional").font(StrandFont.headline)
                ForEach(draft.photos) {photo in
                    HStack(spacing:NoopMetrics.space2) {
                        Image(systemName:photo.accepted ? "checkmark.circle":"photo").foregroundStyle(StrandPalette.metricPurple)
                        Text(verbatim:photo.filename).font(StrandFont.caption).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength:NoopMetrics.space1)
                        if draft.editable {
                            Button {do {try client.removePhoto(photo.id,draftId:draftId)}catch {localError=HealthJournalClient.message(error)}} label:{Image(systemName:"xmark")}
                                .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Remove selected photo")
                        }
                    }
                }
                if importing {ProgressView("Preparing original photos…").font(StrandFont.body)}
                if draft.editable,draft.photos.count+existingPhotos < 8 {
                    PhotosPicker(selection:$picked,maxSelectionCount:8-draft.photos.count-existingPhotos,matching:.images,preferredItemEncoding:.current) {
                        Label("Add photos",systemImage:"plus").frame(minHeight:NoopMetrics.minimumTouchTarget)
                    }.buttonStyle(NoopButtonStyle(.secondary)).disabled(importing)
                }
                Text("Original photos may include location metadata.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func topicFields(_ draft:HealthJournalDraft) -> some View {
        NoopCard {
            VStack(alignment:.leading,spacing:NoopMetrics.space4) {
                TextField("Topic name",text:text(\.title)).font(StrandFont.headline).focused($focused,equals:"title")
                TextField("Body area",text:text(\.bodyArea)).font(StrandFont.body).focused($focused,equals:"body")
                Picker("Side",selection:text(\.side)) {
                    Text("Unspecified").tag("unspecified");Text("Left").tag("left");Text("Right").tag("right");Text("Both").tag("both");Text("Center").tag("center")
                }.font(StrandFont.body)
                Picker("Status",selection:text(\.status)) {Text("Open").tag("open");Text("Closed").tag("closed")}.font(StrandFont.body)
            }.disabled(!draft.editable)
        }
    }
}

struct HealthJournalConflictView:View {
    @ObservedObject var client:HealthJournalClient
    let draftId:UUID
    @Environment(\.dismiss) private var dismiss
    @State private var latest:HealthJournalMutation?
    @State private var error:String?
    var body:some View {
        ScreenScaffold(title:"Review conflict") {
            if let error {HealthJournalNotice(message:error)}
            if let draft=client.draft(draftId),let latest {
                NoopCard {
                    VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                        Text("Latest in Life").font(StrandFont.headline)
                        HealthJournalReviewFields(mutation:latest)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                NoopCard {
                    VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                        Text("Your retained draft").font(StrandFont.headline)
                        HealthJournalReviewFields(mutation:draft.mutation)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                Text("Continue editing your draft against this version. Nothing is overwritten until you save.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Continue with my draft",systemImage:"square.and.pencil",fullWidth:true) {
                    do {try await client.review(draftId,reviewedVersion:latest.expectedVersion);dismiss()}catch {self.error=HealthJournalClient.message(error)}
                }
            }else if error == nil {ProgressView("Reading Health…")}
        }.task {do {latest=try await client.latestForReview(draftId)}catch {self.error=HealthJournalClient.message(error)}}
        .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Cancel") {dismiss()}}}
    }
}
private struct HealthJournalReviewFields:View {
    let mutation:HealthJournalMutation
    var body:some View {
        VStack(alignment:.leading,spacing:NoopMetrics.space2) {
            if mutation.action == "topic" {
                LabeledContent("Topic") {Text(verbatim:mutation.title ?? "")}
                LabeledContent("Body area") {Text(verbatim:mutation.bodyArea ?? "")}
                LabeledContent("Side") {Text(LocalizedStringKey((mutation.side ?? "unspecified").capitalized))}
                LabeledContent("Status") {Text(LocalizedStringKey((mutation.status ?? "open").capitalized))}
            }else {
                Text("Observed").font(StrandFont.headline)
                Text(verbatim:HealthJournalDates.display(mutation.observedAt ?? "",zone:mutation.timeZone ?? ""))
                Text(verbatim:mutation.timeZone ?? "").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Notes").font(StrandFont.headline)
                Text(verbatim:(mutation.notes?.isEmpty == false ? mutation.notes:nil) ?? "—")
                Text("Symptoms").font(StrandFont.headline)
                Text(verbatim:(mutation.symptoms?.isEmpty == false ? mutation.symptoms:nil) ?? "—")
            }
        }.font(StrandFont.body).fixedSize(horizontal:false,vertical:true)
    }
}
#endif
