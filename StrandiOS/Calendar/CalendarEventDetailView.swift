#if os(iOS)
import SwiftUI
import StrandDesign

struct CalendarEventDetailView: View {
    let day: String
    let event: CalendarReaderEvent
    @ObservedObject private var client: CalendarReaderClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: CalendarReaderDetail?
    @State private var progress: [String: CalendarReaderProgress] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var refresh = 0
    @State private var agentExpanded = false
    init(day: String, event: CalendarReaderEvent, client: CalendarReaderClient = .shared,
         initialDetail: CalendarReaderDetail? = nil, expandedAgent: Bool = false) {
        self.day = day; self.event = event; _client = ObservedObject(wrappedValue: client)
        _detail = State(initialValue: initialDetail); _agentExpanded = State(initialValue: expandedAgent)
    }
    private var identity: String { "\(day)|\(event.id)|\(client.identity)|\(refresh)" }
    var body: some View {
        ScreenScaffold(title: nil, onRefresh: load) {
            LazyVStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text(verbatim: detail?.event.title ?? event.title).font(StrandFont.title1).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: day).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                CalendarEventTime(event: detail?.event ?? event).font(StrandFont.title2)
                Label((detail?.event.source ?? event.source) == "local_projection" ? "Pending sync" : "Google Calendar", systemImage: "calendar")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if let error {
                    Text(LocalizedStringKey(error)).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning)
                    NoopAsyncButton("Refresh", systemImage: "arrow.clockwise", kind: .secondary) { await load() }.disabled(busy)
                }
                if busy { ProgressView("Reading task context…") }
                if let detail {
                    if let readAt = CalendarReaderDates.instant(detail.readAt) {
                        Text("Updated \(CalendarReaderDates.display(readAt))")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                    if let description = detail.event.description, !description.isEmpty { textSection("Event notes", description) }
                    if detail.tasks.isEmpty {
                        Text("No tracker task is linked to this event.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                    ForEach(detail.tasks) { result in
                        if result.available, let task = result.task, let brief = result.brief {
                            NoopCard {
                                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                                    Text(verbatim: task.title).font(StrandFont.title2)
                                    Label(task.done ? "Completed" : LocalizedStringKey(task.status.replacingOccurrences(of: "_", with: " ").capitalized),
                                          systemImage: task.done ? "checkmark.circle" : "circle")
                                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.metricCyan)
                                    if let taskDate = task.date, taskDate != day {
                                        LabeledContent("Current task date", value: taskDate).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    }
                                    if !brief.humanDescription.isEmpty { textSection("Purpose", brief.humanDescription) }
                                    if !task.note.isEmpty { textSection("Notes", task.note) }
                                    if !task.description.isEmpty && task.description != task.note { textSection("Description", task.description) }
                                    DisclosureGroup("Agent context", isExpanded: $agentExpanded) {
                                        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                                            if !brief.agentDescription.isEmpty { textSection("Working context", brief.agentDescription) }
                                            if !brief.instructions.isEmpty { textSection("Instructions", brief.instructions) }
                                            if !brief.acceptanceCriteria.isEmpty { textSection("Acceptance criteria", brief.acceptanceCriteria) }
                                            if let url = CalendarReaderDates.safeLink(brief.repoUrl) { Link("Repository", destination: url).font(StrandFont.body) }
                                            else if !brief.repoUrl.isEmpty { Text(verbatim: brief.repoUrl).font(StrandFont.body).textSelection(.enabled) }
                                        }.padding(.top, NoopMetrics.space3)
                                    }.font(StrandFont.headline).tint(StrandPalette.metricPurple)
                                    if let history = progress[result.ref] ?? task.progress { progressView(history, ref: result.ref) }
                                    if let url = result.url.flatMap(CalendarReaderDates.safeLink) { Link("Open in Life", destination: url).font(StrandFont.body) }
                                }
                            }
                        } else {
                            NoopCard {
                                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                    Text("Linked task unavailable").font(StrandFont.headline)
                                    NoopAsyncButton("Retry", systemImage: "arrow.clockwise", kind: .secondary) { await load() }.disabled(busy)
                                }
                            }
                        }
                    }
                }
            }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: identity) { await load() }
        .onChange(of: client.identity) { _, _ in detail = nil; progress = [:]; error = nil }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
    }
    private func textSection(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(title).font(StrandFont.headline)
            Text(verbatim: value).font(StrandFont.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func progressView(_ history: CalendarReaderProgress, ref: String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Progress").font(StrandFont.headline)
            if history.entries.isEmpty { Text("No progress updates yet.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary) }
            ForEach(history.entries) { entry in
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(verbatim: entry.workDate).font(StrandFont.caption).foregroundStyle(StrandPalette.metricPurple)
                    textSection("Accomplished", entry.accomplished)
                    textSection("Next steps", entry.nextStep)
                }
            }
            if let before = history.nextBeforeVersion {
                NoopAsyncButton("Earlier updates", systemImage: "arrow.down", kind: .secondary) { await more(ref: ref, before: before) }.disabled(busy)
            }
        }
    }
    private func load() async {
        let ticket = identity; busy = true
        defer { if ticket == identity { busy = false } }
        do {
            let value = try await client.readEvent(date: day, id: event.id)
            guard ticket == identity, !Task.isCancelled else { return }
            detail = value; progress = [:]; error = nil
        } catch is CancellationError { }
        catch { if ticket == identity { self.error = CalendarReaderClient.message(error) } }
    }
    private func more(ref: String, before: Int) async {
        let ticket = identity; busy = true
        defer { if ticket == identity { busy = false } }
        do {
            let value = try await client.readEvent(date: day, id: event.id, taskRef: ref, before: before)
            guard ticket == identity, !Task.isCancelled,
                  let old = progress[ref] ?? detail?.tasks.first(where: { $0.ref == ref })?.task?.progress,
                  let next = value.tasks.first(where: { $0.ref == ref })?.task?.progress else { throw CalendarReaderFailure.historyChanged }
            var combined = old; try combined.append(next, before: before); progress[ref] = combined; error = nil
        } catch is CancellationError { }
        catch { if ticket == identity { self.error = CalendarReaderClient.message(error) } }
    }
}
#endif
