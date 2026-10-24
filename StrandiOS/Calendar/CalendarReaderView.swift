#if os(iOS)
import SwiftUI
import StrandDesign

struct CalendarReaderView: View {
    @ObservedObject private var client: CalendarReaderClient
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var visible = false
    @State private var selectedDay = CalendarReaderDates.key(Date())
    @State private var refresh = 0
    @State private var selected: CalendarReaderEvent?
    @State private var settings = false
    private var current: CalendarReaderDay? { client.snapshot(for: selectedDay)?.first }
    init(client: CalendarReaderClient = .shared, date: String? = nil) {
        _client = ObservedObject(wrappedValue: client)
        _selectedDay = State(initialValue: date ?? CalendarReaderDates.key(Date()))
    }
    var body: some View {
        ScreenScaffold(title: "Calendar", onRefresh: { await client.loadDay(selectedDay) }) {
            LazyVStack(alignment: .leading, spacing: NoopMetrics.space4) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                    : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
                layout {
                    Button { selectedDay = CalendarReaderDates.shifted(selectedDay, by: -1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Previous day")
                    DatePicker("Calendar date", selection: Binding(get: { CalendarReaderDates.date(selectedDay) ?? Date() },
                        set: { selectedDay = CalendarReaderDates.key($0) }), displayedComponents: .date)
                        .labelsHidden().environment(\.timeZone, CalendarReaderDates.zone)
                    Spacer(minLength: NoopMetrics.space1)
                    Button { selectedDay = CalendarReaderDates.shifted(selectedDay, by: 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Next day")
                }
                HStack {
                    Button("Today") { selectedDay = CalendarReaderDates.key(Date()); refresh += 1 }.buttonStyle(NoopButtonStyle(.secondary))
                    Spacer(minLength: NoopMetrics.space2)
                    Button { settings = true } label: { Image(systemName: "gearshape") }
                        .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Calendar connection")
                }
                if !client.enabled {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Label("Life calendar", systemImage: "calendar").font(StrandFont.headline)
                            Text("Read your daily schedule and linked task context.").font(StrandFont.body)
                            if let error = client.error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                            Button("Calendar connection") { settings = true }.buttonStyle(NoopButtonStyle(.secondary))
                        }
                    }
                } else {
                    if let error = client.error {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text(LocalizedStringKey(error)).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning)
                            NoopAsyncButton("Retry", systemImage: "arrow.clockwise", kind: .secondary) { await client.loadDay(selectedDay) }.disabled(client.busy)
                        }
                    }
                    if let current {
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text(verbatim: TimeZone(identifier: current.timeZone)?.localizedName(for: .generic, locale: .current) ?? current.timeZone)
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            if let date = CalendarReaderDates.instant(current.readAt) {
                                Text("Updated \(CalendarReaderDates.display(date))")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            if client.stale { Text("Showing the last successful read.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                        }
                        if client.day.events.isEmpty && client.day.cursor == nil {
                            NoopCard { Text("No events on this day.").font(StrandFont.body).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        ForEach(client.day.events) { event in
                            Button { selected = event } label: { CalendarAgendaRow(event: event) }
                                .buttonStyle(NoopFeedbackButtonStyle())
                        }
                        if client.day.cursor != nil {
                            NoopAsyncButton("More events", systemImage: "arrow.down", kind: .secondary, fullWidth: true) {
                                await client.loadDay(selectedDay, more: true)
                            }.disabled(client.busy)
                        }
                    }
                    if client.busy { ProgressView("Reading calendar…").font(StrandFont.subhead).frame(maxWidth: .infinity) }
                }
            }
        }
        .task(id: "\(selectedDay)|\(client.identity)|\(refresh)") { await client.loadDay(selectedDay) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active && visible { refresh += 1 } }
        .sheet(isPresented: $settings) { NavigationStack { CalendarReaderSettingsView(client: client) } }
        .sheet(item: $selected) { event in
            NavigationStack { CalendarEventDetailView(day: selectedDay, event: event, client: client) }
        }
    }
}

private struct CalendarAgendaRow: View {
    let event: CalendarReaderEvent
    private var tint: Color {
        if event.displayContext == "work" { return StrandPalette.textTertiary }
        if event.source == "local_projection" { return StrandPalette.metricPurple }
        return event.linkedTaskRefs.isEmpty ? StrandPalette.accent : StrandPalette.metricCyan
    }
    var body: some View {
        NoopCard {
            HStack(alignment: .top, spacing: NoopMetrics.space3) {
                RoundedRectangle(cornerRadius: NoopMetrics.space1).fill(tint)
                    .frame(width: NoopMetrics.space1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    CalendarEventTime(event: event).font(StrandFont.caption).foregroundStyle(tint)
                    Text(verbatim: event.title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: NoopMetrics.space2) {
                        Label(event.source == "local_projection" ? "Pending sync" : "Google Calendar", systemImage: "calendar")
                        if event.displayContext == "work" { Text("Work") }
                        Spacer(minLength: NoopMetrics.space1)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: NoopMetrics.minimumTouchTarget)
        }
    }
}

struct CalendarEventTime: View {
    let event: CalendarReaderEvent
    var body: some View {
        if event.allDay { Text("All-day") }
        else if let start = event.startAt.flatMap(CalendarReaderDates.instant), let end = event.endAt.flatMap(CalendarReaderDates.instant) {
            Text(verbatim: formatted(start) + " – " + formatted(end))
        }
    }
    private func formatted(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute(); style.timeZone = CalendarReaderDates.zone
        return date.formatted(style)
    }
}

struct CalendarReaderSettingsView: View {
    @ObservedObject private var client: CalendarReaderClient
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    init(client: CalendarReaderClient = .shared) { _client = ObservedObject(wrappedValue: client) }
    var body: some View {
        ScreenScaffold(title: "Calendar connection") {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("Read-only Life calendar").font(StrandFont.headline)
                    Text("Events and linked task details are read from Life. Calendar editing stays in Life.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    if client.configuration != nil {
                        Toggle("Read calendar", isOn: Binding(get: { client.enabled }, set: {
                            do { try client.setEnabled($0) } catch { self.error = CalendarReaderClient.message(error) }
                        })).toggleStyle(NoopSwitchStyle())
                    } else { Text("This phone needs its dedicated calendar connection.").font(StrandFont.body) }
                    if let error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                }
            }
        }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
#endif
