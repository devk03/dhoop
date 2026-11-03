#if os(iOS)
import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
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
    @State private var camera = false
    @State private var cameraAccessDenied = false
    @State private var retainedNewTopic: HealthJournalNewTopic?
    @State private var retainedNewTopicId: String?
    private var draft: HealthJournalDraft? { client.draft(draftId) }
    private func text(_ key: WritableKeyPath<HealthJournalMutation,String?>) -> Binding<String> {
        Binding(get: { draft?.mutation[keyPath:key] ?? "" }, set: { value in
            guard var mutation=draft?.mutation else {return};mutation[keyPath:key]=value;client.edit(draftId,mutation:mutation)
        })
    }
    private func newTopicText(_ key: WritableKeyPath<HealthJournalNewTopic, String>) -> Binding<String> {
        Binding(get: { draft?.mutation.newTopic?[keyPath: key] ?? "" }, set: { value in
            guard var mutation = draft?.mutation, mutation.newTopic != nil else { return }
            mutation.newTopic?[keyPath: key] = value; client.edit(draftId, mutation: mutation)
        })
    }
    var body: some View {
        ScreenScaffold(title: nil) {
            if let draft {
                if draft.mutation.action == "topic" { topicFields(draft) } else { entryFields(draft) }
                if let error = localError ?? draft.lastError { HealthJournalNotice(message: error) }
                if client.storageError { HealthJournalNotice(message: HealthJournalFailure.storage.localizedDescription) }
            }
        }
        .safeAreaInset(edge: .bottom) { if let draft { saveActions(draft) } }
        .navigationTitle(draft?.mutation.action == "topic" ? "Topic" : draft?.mutation.action == "correct" ? "Edit entry" : "New entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { focused = nil; client.flush(); dismiss() } } }
        .keyboardDoneToolbar($focused)
        .onDisappear { client.flush() }
        .onChange(of: picked) { _, items in
            importing = true; focused = nil
            Task {
                defer { importing = false; picked = [] }
                for item in items {
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self) else { throw HealthJournalFailure.media }
                        try await client.addPhoto(bytes, draftId: draftId, existingCount: existingPhotos)
                    } catch { localError = HealthJournalClient.message(error); break }
                }
            }
        }
        .sheet(isPresented: $reviewing) { NavigationStack { HealthJournalConflictView(client: client, draftId: draftId) } }
        .sheet(isPresented: $camera) { HealthJournalCamera(completion: receivedCameraImage).ignoresSafeArea() }
        .alert("Camera access", isPresented: $cameraAccessDenied) {
            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Allow camera access in iPhone Settings, or choose Photos.") }
    }
    private func saveActions(_ draft: HealthJournalDraft) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Label(LocalizedStringKey(draft.status), systemImage: draft.completed ? "checkmark.circle" : "lock")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            if draft.conflict && !draft.bodyAccepted {
                Button("Review latest version") { reviewing = true }.buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
            } else if draft.needsEditing && !draft.bodyAccepted {
                NoopAsyncButton("Edit retained draft", systemImage: "square.and.pencil", kind: .secondary, fullWidth: true) {
                    do { try await client.review(draftId) } catch { localError = HealthJournalClient.message(error) }
                }
            } else if !draft.completed {
                NoopAsyncButton(draft.queued ? "Retry save" : "Save entry", systemImage: "checkmark", fullWidth: true) {
                    focused = nil; await client.send(draftId)
                    guard client.draft(draftId)?.completed == true else {
                        let message = client.draft(draftId)?.lastError ?? client.error ?? HealthJournalFailure.http(503).localizedDescription
                        throw NSError(domain: "DhoopHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(message, comment: "")])
                    }
                    dismiss()
                }.disabled(client.sending || importing || client.connection == nil || client.storageError)
                .accessibilityIdentifier("health-save-entry")
            }
        }.padding(NoopMetrics.space3).background(StrandPalette.surfaceBase)
    }
    @ViewBuilder private func entryFields(_ draft: HealthJournalDraft) -> some View {
        photos(draft)
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Notes").font(StrandFont.headline)
                TextField("What did you notice?", text: text(\.notes), axis: .vertical)
                    .lineLimit(4...10).focused($focused, equals: "notes").font(StrandFont.body)
                    .accessibilityIdentifier("health-entry-notes")
                DisclosureGroup("Symptoms · Optional") {
                    TextField("Add symptoms", text: text(\.symptoms), axis: .vertical)
                        .lineLimit(2...6).focused($focused, equals: "symptoms").font(StrandFont.body)
                }.font(StrandFont.subhead)
            }.disabled(!draft.editable)
        }
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                if draft.mutation.action == "observe" {
                    Picker("Topic", selection: Binding(get: { draft.mutation.newTopic == nil ? draft.mutation.topicId ?? "" : "new" }, set: selectTopic)) {
                        ForEach(client.document.topics) { topic in Text(verbatim: topic.title).tag(topic.id) }
                        Text("New topic").tag("new")
                    }.pickerStyle(.menu).font(StrandFont.headline)
                    if draft.mutation.newTopic != nil {
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text("Topic name").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            TextField("Topic name", text: newTopicText(\.title)).font(StrandFont.body).focused($focused, equals: "topicTitle")
                        }
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text("Body area").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            TextField("Body area", text: newTopicText(\.bodyArea)).font(StrandFont.body).focused($focused, equals: "bodyArea")
                        }
                        Picker("Side", selection: newTopicText(\.side)) {
                            Text("Unspecified").tag("unspecified"); Text("Left").tag("left"); Text("Right").tag("right")
                            Text("Both").tag("both"); Text("Center").tag("center")
                        }.font(StrandFont.body)
                    }
                }
                if draft.editable {
                    DatePicker("Observed", selection: Binding(get: { HealthJournalDates.instant(draft.mutation.observedAt ?? "") ?? Date() }, set: { date in
                        var mutation = draft.mutation; mutation.observedAt = HealthJournalDates.timestamp(date, zone: mutation.timeZone ?? TimeZone.current.identifier)
                        client.edit(draftId, mutation: mutation)
                    })).environment(\.timeZone, TimeZone(identifier: draft.mutation.timeZone ?? "") ?? .current).font(StrandFont.body)
                    DisclosureGroup("Time zone") {
                        TextField("Timezone", text: text(\.timeZone)).font(StrandFont.subhead)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: "zone")
                        Button("Use current timezone") {
                            var mutation = draft.mutation; let date = HealthJournalDates.instant(mutation.observedAt ?? "") ?? Date()
                            mutation.timeZone = TimeZone.current.identifier; mutation.observedAt = HealthJournalDates.timestamp(date, zone: TimeZone.current.identifier)
                            client.edit(draftId, mutation: mutation)
                        }.buttonStyle(NoopFeedbackButtonStyle()).font(StrandFont.caption).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    }.font(StrandFont.subhead)
                } else { Text(verbatim: HealthJournalDates.display(draft.mutation.observedAt ?? "", zone: draft.mutation.timeZone ?? "")).font(StrandFont.body) }
            }.frame(maxWidth: .infinity, alignment: .leading).disabled(!draft.editable)
        }
    }
    private func photos(_ draft: HealthJournalDraft) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                if !draft.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: NoopMetrics.space2) {
                            ForEach(draft.photos) { photo in
                                VStack(spacing: NoopMetrics.space1) {
                                    HealthJournalThumbnail(client: client, source: .local(photo))
                                    if draft.editable {
                                        Button { do { try client.removePhoto(photo.id, draftId: draftId) } catch { localError = HealthJournalClient.message(error) } } label: { Label("Remove", systemImage: "xmark") }
                                            .buttonStyle(NoopFeedbackButtonStyle()).font(StrandFont.caption)
                                            .frame(minHeight: NoopMetrics.minimumTouchTarget).accessibilityLabel("Remove selected photo")
                                    }
                                }
                            }
                        }
                    }
                }
                if importing { ProgressView("Preparing original photos…").font(StrandFont.body) }
                if draft.editable, draft.photos.count + existingPhotos < 8 {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: NoopMetrics.space3) { cameraButton; photoPicker(draft) }
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) { cameraButton; photoPicker(draft) }
                    }.disabled(importing)
                }
                Text("Photos · Optional").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if !draft.photos.isEmpty { Text("Original photos may include location metadata.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var cameraButton: some View {
        Button { requestCamera() } label: { Label("Camera", systemImage: "camera").frame(minHeight: NoopMetrics.minimumTouchTarget) }
            .buttonStyle(NoopButtonStyle(.secondary)).disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            .accessibilityIdentifier("health-entry-camera")
    }
    private func photoPicker(_ draft: HealthJournalDraft) -> some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 8 - draft.photos.count - existingPhotos, matching: .images, preferredItemEncoding: .current) {
            Label("Add photos", systemImage: "photo.on.rectangle").frame(minHeight: NoopMetrics.minimumTouchTarget)
        }.buttonStyle(NoopButtonStyle(.secondary)).accessibilityIdentifier("health-entry-photos")
    }
    private func selectTopic(_ id: String) {
        guard var mutation = draft?.mutation, draft?.editable == true else { return }
        if id == "new" {
            mutation.topicId = retainedNewTopicId ?? UUID().uuidString.lowercased()
            mutation.newTopic = retainedNewTopic ?? HealthJournalMutation.newEntry().newTopic
        } else {
            if let value = mutation.newTopic { retainedNewTopic = value; retainedNewTopicId = mutation.topicId }
            mutation.topicId = id; mutation.newTopic = nil
        }
        client.edit(draftId, mutation: mutation)
    }
    private func requestCamera() {
        focused = nil
        Task { @MainActor in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: camera = true
            case .notDetermined:
                if await AVCaptureDevice.requestAccess(for: .video) { camera = true } else { cameraAccessDenied = true }
            default: cameraAccessDenied = true
            }
        }
    }
    private func receivedCameraImage(_ image: UIImage?) {
        camera = false
        guard let image else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    guard let data = image.jpegData(compressionQuality: 0.95) else { throw HealthJournalFailure.media }; return data
                }.value
                try await client.addPhoto(data, draftId: draftId, existingCount: existingPhotos)
            } catch { localError = HealthJournalClient.message(error) }
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
