#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

struct HealthJournalDetail: View {
    @ObservedObject var client: HealthJournalClient
    let observationId: String
    @State private var detail: HealthJournalDocument?
    @State private var loading=false
    @State private var error:String?
    @State private var editor:HealthJournalEditorRoute?
    @State private var image:HealthJournalImage?
    @State private var showHistory=false
    private var entry:HealthJournalObservation? {detail?.observations.first}
    var body:some View {
        ScreenScaffold(title:nil,onRefresh:{await load()}) {
            if let error {HealthJournalNotice(message:error);NoopAsyncButton("Retry",systemImage:"arrow.clockwise",kind:.secondary) {await load()}}
            if loading {ProgressView("Reading Health…")}
            if let entry {
                NoopCard {
                    VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                        Text(verbatim:detail?.topics.first(where:{$0.id==entry.topicId})?.title ?? NSLocalizedString("Health entry",comment:"")).font(StrandFont.title2)
                        Text(verbatim:HealthJournalDates.display(entry.observedAt,zone:entry.timeZone)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        Text(verbatim:entry.timeZone).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if !entry.notes.isEmpty {Text(verbatim:entry.notes).font(StrandFont.body).textSelection(.enabled)}
                        if !entry.symptoms.isEmpty {
                            Text("Symptoms").font(StrandFont.headline)
                            Text(verbatim:entry.symptoms).font(StrandFont.body).textSelection(.enabled)
                        }
                        Text(verbatim:entry.source).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        NoopAsyncButton("Correct entry",systemImage:"square.and.pencil",kind:.secondary) {
                            do {
                                let latest=try await client.detail(observationId);detail=latest
                                editor = .init(id:try client.create(.correction(latest.observations[0])))
                            }catch {self.error=HealthJournalClient.message(error)}
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                if let images=entry.images,!images.isEmpty {
                    Text("Photos").font(StrandFont.headline)
                    ForEach(images) {photo in
                        Button {image=photo} label:{
                            HStack(spacing:NoopMetrics.space3) {
                                Image(systemName:"photo").foregroundStyle(StrandPalette.metricPurple)
                                Text(verbatim:photo.filename).font(StrandFont.body).lineLimit(2).truncationMode(.middle)
                                Spacer(minLength:NoopMetrics.space1)
                                Image(systemName:"chevron.right").foregroundStyle(StrandPalette.textSecondary)
                            }.frame(minHeight:NoopMetrics.minimumTouchTarget).padding(NoopMetrics.space3)
                        }.buttonStyle(NoopFeedbackButtonStyle())
                    }
                }
                Button(showHistory ? "Hide correction history":"Correction history") {showHistory.toggle()}.buttonStyle(NoopButtonStyle(.secondary))
                if showHistory {
                    ForEach(detail?.revisions ?? []) {revision in
                        NoopCard {
                            VStack(alignment:.leading,spacing:NoopMetrics.space2) {
                                Text("Version \(revision.version)").font(StrandFont.headline)
                                Text(verbatim:HealthJournalDates.display(revision.recordedAt,zone:revision.snapshot.timeZone)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Text(verbatim:revision.snapshot.notes).font(StrandFont.body)
                                if !revision.snapshot.symptoms.isEmpty {Text(verbatim:revision.snapshot.symptoms).font(StrandFont.subhead)}
                                Text(verbatim:revision.source).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                    if detail?.nextBeforeVersion != nil {
                        NoopAsyncButton("Older corrections",systemImage:"arrow.down",kind:.secondary) {await load(more:true)}.disabled(loading)
                    }
                }
            }
        }.navigationTitle("Health entry").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .task {await load()}
        .sheet(item:$editor,onDismiss:{Task {await load()}}) {route in
            NavigationStack {HealthJournalEditor(client:client,draftId:route.id,existingPhotos:entry?.images?.count ?? 0)}
        }
        .sheet(item:$image) {photo in NavigationStack {HealthJournalPhotoView(client:client,image:photo)}}
    }
    private func load(more:Bool=false) async {
        guard !loading else {return};loading=true;error=nil;defer {loading=false}
        do {
            var next=try await client.detail(observationId,before:more ? detail?.nextBeforeVersion:nil)
            if more,let old=detail {
                guard next.observations.first?.version == old.observations.first?.version else {throw HealthJournalFailure.conflict}
                next.revisions=(old.revisions ?? [])+(next.revisions ?? []).filter {r in !(old.revisions ?? []).contains(where:{$0.version==r.version})}
            }
            detail=next
        }catch {self.error=HealthJournalClient.message(error)}
    }
}
struct HealthJournalPhotoView:View {
    @ObservedObject var client:HealthJournalClient
    let image:HealthJournalImage
    @Environment(\.dismiss) private var dismiss
    @State private var preview:UIImage?
    @State private var error:String?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                if let preview {Image(uiImage:preview).resizable().scaledToFit().accessibilityLabel("Selected Health photo")}
                else if error == nil {ProgressView("Loading original photo…")}
                if let error {HealthJournalNotice(message:error)}
                Text(verbatim:image.filename).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }.padding(NoopMetrics.screenHPadding)
        }.background(StrandPalette.surfaceBase.ignoresSafeArea()).navigationTitle("Photo").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.confirmationAction) {Button("Done") {dismiss()}}}
        .task {
            do {
                let bytes=try await client.image(image)
                guard let decoded=UIImage(data:bytes) else {throw HealthJournalFailure.invalidResponse}
                preview=decoded
            }catch {if !Task.isCancelled {self.error=HealthJournalClient.message(error)}}
        }
    }
}
#endif
