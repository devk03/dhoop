#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign

struct HealthJournalView: View {
    @ObservedObject var client: HealthJournalClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: HealthJournalEditorRoute?
    @State private var settings = false
    @State private var topics = false
    @State private var filters = false
    @State private var localError: String?
    init(client: HealthJournalClient = .shared) { self.client = client }
    var body: some View {
        ScreenScaffold(title: "Health", onRefresh: { await client.refresh() }, lazy: true, trailing: {
            HStack(spacing: NoopMetrics.space1) {
                Button { filters = true } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Filter Health entries")
                Button { settings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Health connection")
                Button { createEntry() } label: { Image(systemName: "plus") }
                    .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("New Health entry")
            }
        }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NoopMetrics.space2) {
                    Button("All") { Task { await client.refresh(.init(from: client.filter.from, through: client.filter.through)) } }
                        .buttonStyle(NoopButtonStyle(client.filter.topicId == nil ? .primary : .secondary))
                    ForEach(client.document.topics) { topic in
                        Button { Task { await client.refresh(.init(topicId: topic.id, from: client.filter.from, through: client.filter.through)) } } label: {
                            Text(verbatim: topic.title).lineLimit(1)
                        }.buttonStyle(NoopButtonStyle(client.filter.topicId == topic.id ? .primary : .secondary))
                    }
                    Button("Topics") { topics = true }.buttonStyle(NoopButtonStyle(.secondary))
                }
            }
            if let from = client.filter.from, let through = client.filter.through {
                Text(verbatim: from + " — " + through).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if client.connection == nil {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Label("Private Health journal", systemImage: "lock.shield").font(StrandFont.headline)
                        Text("Notes and optional photos, shared with your Life journal.").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        Button("Health connection") { settings = true }.buttonStyle(NoopButtonStyle(.secondary))
                    }
                }
            }
            if let error = localError ?? client.error {
                HealthJournalNotice(message: error)
                if client.connection != nil { NoopAsyncButton("Retry", systemImage: "arrow.clockwise", kind: .secondary) { await client.refresh() }.disabled(client.loading) }
            }
            if !client.pending.isEmpty {
                Text("On this phone").font(StrandFont.headline)
                ForEach(client.pending) { draft in
                    Button { editor = .init(id: draft.id) } label: {
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                HStack {
                                    Image(systemName: draft.conflict ? "exclamationmark.arrow.triangle.2.circlepath" : "square.and.pencil").foregroundStyle(StrandPalette.metricPurple)
                                    Text(verbatim: draft.mutation.title ?? title(draft.mutation.topicId)).font(StrandFont.headline)
                                    Spacer(minLength: NoopMetrics.space1)
                                    Image(systemName: "chevron.right").foregroundStyle(StrandPalette.textSecondary)
                                }
                                Text(LocalizedStringKey(draft.status)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                if let notes = draft.mutation.notes, !notes.isEmpty { Text(verbatim: notes).font(StrandFont.body).lineLimit(2) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(NoopFeedbackButtonStyle())
                }
            }
            if client.loading { ProgressView("Reading Health…").font(StrandFont.body).frame(maxWidth: .infinity) }
            if client.loaded, client.document.observations.isEmpty, client.error == nil {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("No entries in this range").font(StrandFont.headline)
                        Text("Start with a note. Photos are optional.").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        Button("New Health entry") { createEntry() }.buttonStyle(NoopButtonStyle(.primary))
                    }
                }
            }
            ForEach(client.document.observations) { row in
                NavigationLink {
                    HealthJournalDetail(client: client, observationId: row.id)
                } label: { HealthJournalEntryCard(entry: row, topic: title(row.topicId)) }
                .buttonStyle(NoopFeedbackButtonStyle())
            }
            if client.document.nextOffset != nil {
                NoopAsyncButton("Older entries", systemImage: "arrow.down", kind: .secondary, fullWidth: true) { await client.refresh(more: true) }.disabled(client.loading)
            }
        }
        .task { client.reloadWhenAccessible(); if client.connection != nil { await client.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { client.reloadWhenAccessible() }
            else { client.flush() }
        }
        .sheet(item: $editor) { route in NavigationStack { HealthJournalEditor(client: client, draftId: route.id) } }
        .sheet(isPresented: $settings) { NavigationStack { HealthJournalConnectionView(client: client) } }
        .sheet(isPresented: $topics) { NavigationStack { HealthJournalTopicsView(client: client) } }
        .sheet(isPresented: $filters) { NavigationStack { HealthJournalFilterView(client: client) } }
    }
    private func title(_ id: String?) -> String { client.document.topics.first { $0.id == id }?.title ?? NSLocalizedString("Health entry", comment: "") }
    private func createEntry() {
        guard let topic = client.document.topics.first(where: { $0.id == client.filter.topicId }) ?? client.document.topics.first(where: { $0.status == "open" }) else { topics = true; return }
        do { editor = .init(id: try client.create(.entry(topicId: topic.id))) } catch { localError = HealthJournalClient.message(error) }
    }
}
struct HealthJournalEditorRoute: Identifiable { let id: UUID }

struct HealthJournalEntryCard: View {
    let entry: HealthJournalObservation
    let topic: String
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(verbatim: topic).font(StrandFont.headline)
                    Spacer(minLength: NoopMetrics.space1)
                    Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                Text(verbatim: HealthJournalDates.display(entry.observedAt, zone: entry.timeZone)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if !entry.notes.isEmpty { Text(verbatim: entry.notes).font(StrandFont.body).lineLimit(4) }
                if !entry.symptoms.isEmpty { Text(verbatim: entry.symptoms).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary).lineLimit(2) }
                if !(entry.images ?? []).isEmpty {
                    Label("\(entry.images?.count ?? 0) photos", systemImage: "photo.on.rectangle").font(StrandFont.caption).foregroundStyle(StrandPalette.metricPurple)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(StrandPalette.textPrimary).accessibilityElement(children: .combine)
    }
}
struct HealthJournalNotice: View {
    let message: String
    var body: some View {
        Label { Text(LocalizedStringKey(message)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle") }
            .font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct HealthJournalTopicsView: View {
    @ObservedObject var client: HealthJournalClient
    @Environment(\.dismiss) private var dismiss
    @State private var editor: HealthJournalEditorRoute?
    @State private var error: String?
    var body: some View {
        ScreenScaffold(title: "Topics") {
            if let error { HealthJournalNotice(message: error) }
            Button("New topic") { open(nil) }.buttonStyle(NoopButtonStyle(.primary))
            ForEach(client.document.topics) { topic in
                Button { open(topic) } label: {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text(verbatim: topic.title).font(StrandFont.headline)
                            Text(verbatim: topic.bodyArea).font(StrandFont.body)
                            Text(LocalizedStringKey(topic.status == "open" ? "Open" : "Closed")).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(NoopFeedbackButtonStyle())
            }
        }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $editor) { route in NavigationStack { HealthJournalEditor(client: client, draftId: route.id) } }
    }
    private func open(_ topic: HealthJournalTopic?) {
        Task {
            if topic != nil { await client.refresh(); guard client.error == nil else { error = client.error; return } }
            let latest = topic.flatMap { item in client.document.topics.first { $0.id == item.id } }
            do { editor = .init(id: try client.create(.topic(latest))) } catch { self.error = HealthJournalClient.message(error) }
        }
    }
}

struct HealthJournalFilterView: View {
    @ObservedObject var client: HealthJournalClient
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var through: Date
    @State private var enabled: Bool
    init(client: HealthJournalClient) {
        self.client=client
        _from=State(initialValue:HealthJournalDates.instant((client.filter.from ?? "")+"T12:00:00Z") ?? Date())
        _through=State(initialValue:HealthJournalDates.instant((client.filter.through ?? "")+"T12:00:00Z") ?? Date())
        _enabled=State(initialValue:client.filter.from != nil)
    }
    private let zone=TimeZone(secondsFromGMT:0)!
    var body: some View {
        Form {
            Toggle("Date range", isOn:$enabled).toggleStyle(NoopSwitchStyle())
            if enabled {
                DatePicker("From",selection:$from,displayedComponents:.date)
                DatePicker("Through",selection:$through,in:from...,displayedComponents:.date)
                Text("Dates follow each entry’s recorded timezone.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }.font(StrandFont.body).environment(\.timeZone,zone).scrollContentBackground(.hidden).background(StrandPalette.surfaceBase)
        .navigationTitle("Filter Health entries")
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement:.confirmationAction) { Button("Apply") {
                let fromDay=String(HealthJournalDates.timestamp(from,zone:"UTC").prefix(10)),throughDay=String(HealthJournalDates.timestamp(through,zone:"UTC").prefix(10))
                Task { await client.refresh(.init(topicId:client.filter.topicId,from:enabled ? fromDay:nil,through:enabled ? max(fromDay,throughDay):nil)) }
                dismiss()
            } }
        }
    }
}

struct HealthJournalConnectionView: View {
    @ObservedObject var client: HealthJournalClient
    @Environment(\.dismiss) private var dismiss
    @State private var importing=false
    @State private var busy=false
    @State private var error:String?
    var body: some View {
        ScreenScaffold(title:"Health connection") {
            NoopCard {
                VStack(alignment:.leading,spacing:NoopMetrics.space3) {
                    Label(client.connection == nil ? "Not connected":"Connected to Life",systemImage:"lock.shield").font(StrandFont.headline)
                    Text("Your private Life journal. Photos upload only when you save an entry.").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    Button("Import Health connection") { importing=true }.buttonStyle(NoopButtonStyle(.secondary)).disabled(busy)
                    if busy { ProgressView("Connecting…") }
                    if let error { HealthJournalNotice(message:error) }
                }
            }
        }.toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            guard case .success(let url)=result else { return }
            busy=true
            Task {
                let access=url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() };busy=false }
                do { try await HealthJournalProvisioner.consume(url,client:client);error=nil }
                catch { self.error=HealthJournalClient.message(error) }
            }
        }
    }
}
#endif
