#if os(iOS)
import SwiftUI
import StrandDesign

struct CalendarReaderView: View {
    @ObservedObject private var client: CalendarReaderClient
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var navigation: CalendarNavigation
    @State private var navigationTask: Task<Void, Never>?
    @State private var navigationError: String?
    @State private var initialEventDetail: CalendarReaderDetail?
    @State private var visible = false
    @State private var selectedDay = CalendarReaderDates.key(Date())
    @State private var refresh = 0
    @State private var focusRevision = 0
    @State private var selected: CalendarReaderEvent?
    @State private var settings = false
    private var current: CalendarReaderDay? { client.snapshot(for: selectedDay)?.first }
    private let captureNow: Date?
    init(client: CalendarReaderClient = .shared, date: String? = nil, captureNow: Date? = nil, navigation: CalendarNavigation = .shared) {
        _navigation = ObservedObject(wrappedValue: navigation)
        self.captureNow = captureNow
        _client = ObservedObject(wrappedValue: client)
        _selectedDay = State(initialValue: date ?? CalendarReaderDates.key(Date()))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            let titleLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
            titleLayout {
                Text("Calendar").font(StrandFont.title1)
                if !typeSize.isAccessibilitySize { Spacer(minLength: NoopMetrics.space1) }
                Button("Today") { selectedDay = CalendarReaderDates.key(Date()); refresh += 1; focusRevision += 1 }
                    .font(StrandFont.subhead).frame(minHeight: NoopMetrics.minimumTouchTarget)
                    .buttonStyle(NoopFeedbackButtonStyle())
                Button { settings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Calendar connection")
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
            layout {
                Button { selectedDay = CalendarReaderDates.shifted(selectedDay, by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Previous day")
                DatePicker("Calendar date", selection: Binding(get: { CalendarReaderDates.date(selectedDay) ?? Date() },
                    set: { selectedDay = CalendarReaderDates.key($0) }), displayedComponents: .date)
                    .labelsHidden().environment(\.timeZone, CalendarReaderDates.zone)
                if !typeSize.isAccessibilitySize { Spacer(minLength: NoopMetrics.space1) }
                Button { selectedDay = CalendarReaderDates.shifted(selectedDay, by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Next day")
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            header.padding(.horizontal, NoopMetrics.screenHPadding)
            if client.enabled, let current, let timeline = CalendarDayTimeline(day: selectedDay) {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text(verbatim: TimeZone(identifier: current.timeZone)?.localizedName(for: .generic, locale: .current) ?? current.timeZone)
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if client.stale { Text("Showing the last successful read.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                }.padding(.horizontal, NoopMetrics.screenHPadding)
                if let error = client.error {
                    HStack {
                        Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                        NoopAsyncButton("Retry", systemImage: "arrow.clockwise", kind: .secondary) { await client.loadDay(selectedDay) }.disabled(client.busy)
                    }.padding(.horizontal, NoopMetrics.screenHPadding)
                }
                if client.day.cursor != nil {
                    NoopAsyncButton("More events", systemImage: "arrow.down", kind: .secondary, fullWidth: true) {
                        await client.loadDay(selectedDay, more: true)
                    }.disabled(client.busy)
                }
                CalendarDayTimelineView(timeline: timeline, events: client.day.events, captureNow: captureNow, focusRevision: focusRevision,
                    onSelect: { initialEventDetail = nil; selected = $0 }, onRefresh: { await client.loadDay(selectedDay) }) {
                    if client.busy { ProgressView("Reading calendar…").font(StrandFont.subhead) }
                    if let date = CalendarReaderDates.instant(current.readAt) {
                        Text("Updated \(CalendarReaderDates.display(date))").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }.id(selectedDay)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        if !client.enabled {
                            NoopCard {
                                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                    Label("Life calendar", systemImage: "calendar").font(StrandFont.headline)
                                    Text("Read your daily schedule and linked task context.").font(StrandFont.body)
                                    if let error = client.error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                                    Button("Calendar connection") { settings = true }.buttonStyle(NoopButtonStyle(.secondary))
                                }
                            }
                        } else if let error = client.error {
                            Text(LocalizedStringKey(error)).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusWarning)
                            NoopAsyncButton("Retry", systemImage: "arrow.clockwise", kind: .secondary) { await client.loadDay(selectedDay) }.disabled(client.busy)
                        }
                        if client.busy { ProgressView("Reading calendar…").frame(maxWidth: .infinity) }
                    }.padding(.horizontal, NoopMetrics.screenHPadding)
                }.refreshable { await client.loadDay(selectedDay) }
            }
        }
        .padding(.top, NoopMetrics.space3)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .task(id: "\(selectedDay)|\(client.identity)|\(refresh)") { await client.loadDay(selectedDay) }
        .onAppear { visible = true; if let request = navigation.request { open(request) } }
        .onDisappear { visible = false; navigationTask?.cancel() }
        .onReceive(navigation.$request) { if visible, let request = $0 { open(request) } }
        .alert("Calendar", isPresented: Binding(get: { navigationError != nil }, set: { if !$0 { navigationError = nil } })) {
            Button("Done") { navigationError = nil }
        } message: { Text(LocalizedStringKey(navigationError ?? "")) }
        .onChange(of: scenePhase) { _, phase in if phase == .active && visible { refresh += 1 } }
        .sheet(isPresented: $settings) { NavigationStack { CalendarReaderSettingsView(client: client) } }
        .sheet(item: $selected) { event in
            NavigationStack { CalendarEventDetailView(day: selectedDay, event: event, client: client, initialDetail: initialEventDetail?.event.id == event.id ? initialEventDetail : nil) }
        }
    }
    private func open(_ request: CalendarNavigationRequest) {
        navigation.consume(request.id); navigationTask?.cancel(); selectedDay = request.day
        guard let id = request.eventID else { return }
        navigationTask = Task {
            do {
                let detail = try await client.readEvent(date: request.day, id: id)
                guard !Task.isCancelled, selectedDay == request.day else { return }
                initialEventDetail = detail; selected = detail.event
            } catch is CancellationError { }
            catch { if !Task.isCancelled { navigationError = CalendarReaderClient.message(error) } }
        }
    }
}

struct CalendarEventTime: View {
    let event: CalendarReaderEvent
    var body: some View { Text(verbatim: Self.label(event)) }
    static func label(_ event: CalendarReaderEvent) -> String {
        if event.allDay { return String(localized: "All-day") }
        guard let start = event.startAt.flatMap(CalendarReaderDates.instant), let end = event.endAt.flatMap(CalendarReaderDates.instant) else { return "" }
        var style = Date.FormatStyle.dateTime.hour().minute(); style.timeZone = CalendarReaderDates.zone
        return start.formatted(style) + " – " + end.formatted(style)
    }
}

struct CalendarReaderSettingsView: View {
    @ObservedObject private var client: CalendarReaderClient
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var widgetEnabled: Bool
    @ObservedObject private var rsvp: CalendarRSVPClient
    private let widgetSharing: Binding<Bool>?
    init(client: CalendarReaderClient = .shared, rsvp: CalendarRSVPClient = .shared, widgetSharing: Binding<Bool>? = nil) {
        _client = ObservedObject(wrappedValue: client); _rsvp = ObservedObject(wrappedValue: rsvp)
        self.widgetSharing = widgetSharing; _widgetEnabled = State(initialValue: widgetSharing?.wrappedValue ?? CalendarWidgetPublisher.shared.enabled)
    }
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
                    Toggle("Home Screen Calendar widget", isOn: $widgetEnabled).toggleStyle(NoopSwitchStyle())
                        .onChange(of: widgetEnabled) { _, value in if let widgetSharing { widgetSharing.wrappedValue = value } else { CalendarWidgetPublisher.shared.enabled = value } }
                    if rsvp.configuration != nil {
                        Toggle("Accept invitations", isOn: Binding(get: { rsvp.enabled }, set: {
                            do { try rsvp.setEnabled($0) } catch { self.error = CalendarRSVPClient.message(error) }
                        })).toggleStyle(NoopSwitchStyle())
                    } else { Text("Accept setup pending").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    if let error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                }
            }
        }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
#endif
