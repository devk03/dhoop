import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopProtocol

struct AlarmsView: View {
    @EnvironmentObject private var app: AppModel
    var body: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--alarm-diagnostics") {
            AlarmsContent(manager: app.ble.alarmManager).equatable()
        } else { deviceSurface }
        #else
        deviceSurface
        #endif
    }
    @ViewBuilder private var deviceSurface: some View {
        if app.ble.isWhoop5 { AlarmsContent(manager: app.ble.alarmManager).equatable() }
        else { SmartAlarmView() }
    }
}

private enum AlarmRoute: Hashable { case detail(String), slots, history }

private struct AlarmsContent: View, Equatable {
    @ObservedObject var manager: DhoopAlarmManager
    @EnvironmentObject private var app: AppModel
    @State private var editor: DhoopAlarmDefinition?
    @State private var remove: DhoopAlarmDefinition?
    @State private var capturedAt = Date()
    @State private var localActionError: String?
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = NoopMetrics.alarmTimeNumber
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.manager === rhs.manager }

    var body: some View {
        ScreenScaffold(title: nil, onRefresh: { capturedAt = Date(); await manager.refresh() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack {
                    Text("Alarms").font(StrandFont.title1)
                    Spacer()
                    Button { editor = DhoopAlarmDefinition() } label: {
                        Image(systemName: "plus").font(StrandFont.title2)
                            .frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                    }.buttonStyle(NoopFeedbackButtonStyle()).foregroundStyle(StrandPalette.alarmAccent).accessibilityLabel("Add alarm")
                }
                NavigationLink(value: AlarmRoute.slots) {
                    NoopCard(padding: NoopMetrics.space4) {
                        HStack(spacing: NoopMetrics.space3) {
                            Image(systemName: "applewatch").foregroundStyle(StrandPalette.alarmAccent)
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text(manager.context.whoop5 ? "WHOOP 5" : "WHOOP alarms").font(StrandFont.headline)
                                Text(manager.context.ready ? "Connected · \(manager.context.deviceID)" : "Connect your WHOOP 5")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            if let battery = manager.context.battery { Text("\(Int(battery.rounded()))%").font(StrandFont.captionNumber) }
                            Image(systemName: "chevron.right").foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }.buttonStyle(NoopFeedbackButtonStyle())
                let removalRisks = manager.pendingRemovalRisks(now: capturedAt)
                if !removalRisks.isEmpty {
                    NoopCard(padding: NoopMetrics.space4) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Label("WHOOP removal unresolved", systemImage: "exclamationmark.triangle")
                                .font(StrandFont.headline).foregroundStyle(StrandPalette.statusWarning)
                            Text("These previously scheduled times may still fire, including alarms deleted in Dhoop.")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            ForEach(removalRisks) { risk in
                                Text("Slot \(risk.slot) · \(risk.epochs.map { Date(timeIntervalSince1970: Double($0)).formatted(date: .abbreviated, time: .shortened) }.joined(separator: "; "))")
                                    .font(StrandFont.caption).fixedSize(horizontal: false, vertical: true)
                            }
                            NoopAsyncButton("Retry WHOOP sync", systemImage: "arrow.clockwise", kind: .secondary, fullWidth: true) {
                                try await manager.synchronizeReviewed()
                            }.disabled(manager.busy)
                            NavigationLink("Review WHOOP slots", value: AlarmRoute.slots).font(StrandFont.caption)
                                .frame(minHeight: NoopMetrics.minimumTouchTarget)
                        }
                    }
                }
                if let alarm = nextDefinition {
                    NoopCard(padding: NoopMetrics.space5) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Next alarm").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            Text(manager.nextEpoch(alarm, now: capturedAt).map {
                                Date(timeIntervalSince1970: Double($0)).formatted(date: .omitted, time: .shortened)
                            } ?? timeLabel(alarm.rule.minute)).font(StrandFont.number(timeSize)).monospacedDigit()
                            Text(nextStamp(alarm)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            Text(manager.status(alarm, now: capturedAt)).font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.alarmAccent).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if manager.definitions.isEmpty {
                    NoopCard(padding: NoopMetrics.space5) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Your next wake, on your wrist").font(StrandFont.title2)
                            Text("Add an alarm, then choose which WHOOP slot Dhoop may use. Existing strap alarms stay protected.")
                                .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                            Button("Add alarm") { editor = DhoopAlarmDefinition() }
                                .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                        }
                    }
                } else {
                    NoopCard(padding: NoopMetrics.space4) {
                        VStack(spacing: NoopMetrics.space4) {
                            ForEach(sortedDefinitions) { alarm in
                                HStack(alignment: .center, spacing: NoopMetrics.space4) {
                                    NavigationLink(value: AlarmRoute.detail(alarm.id)) {
                                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                            Text(timeLabel(alarm.rule.minute)).font(StrandFont.number(timeSize))
                                                .monospacedDigit().foregroundStyle(alarm.enabled ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                                            Text("\(alarm.label) · \(repeatDescription(alarm.rule.weekdays))")
                                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                                            Text(manager.status(alarm, now: capturedAt)).font(StrandFont.caption)
                                                .foregroundStyle(StrandPalette.alarmAccent).fixedSize(horizontal: false, vertical: true)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(NoopFeedbackButtonStyle())
                                    Toggle("Enable \(alarm.label)", isOn: Binding(get: { alarm.enabled }, set: { manager.toggle(alarm.id, enabled: $0) }))
                                        .labelsHidden().toggleStyle(NoopSwitchStyle())
                                }
                                .contextMenu {
                                    Button("Edit alarm") { editor = alarm }
                                    Button("Skip next alarm") {
                                        if !manager.skipNext(alarm.id) { localActionError = alarmChangeError(manager) }
                                    }
                                    Button("Delete alarm", role: .destructive) { remove = alarm }
                                }
                                if alarm.id != sortedDefinitions.last?.id { Divider().overlay(StrandPalette.hairline) }
                            }
                        }
                    }
                }
                coverage
                if let alarm = nextDefinition, let epoch = manager.nextEpoch(alarm, now: capturedAt) {
                    NoopCard(padding: NoopMetrics.space4) {
                        HStack(alignment: .top, spacing: NoopMetrics.space4) {
                            Image(systemName: "moon.fill").foregroundStyle(StrandPalette.alarmAccent)
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text("Sleep goal · 8h 15m").font(StrandFont.subhead)
                                Text("Plan to be in bed by \(Date(timeIntervalSince1970: Double(epoch - DhoopSleepGoal.minutes * 60)).formatted(date: .omitted, time: .shortened))")
                                    .font(StrandFont.bodyNumber)
                                Text("Planned sleep opportunity, before any wind-down or fall-asleep allowance.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                }
                NavigationLink("Alarm history", value: AlarmRoute.history).font(StrandFont.subhead)
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                if manager.busy { ProgressView("Checking WHOOP…").font(StrandFont.caption) }
                if let error = manager.storageError ?? manager.error {
                    Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Experimental WHOOP scheduling. A stored record is not proof that an alarm fired or woke you.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .tint(StrandPalette.alarmAccent)
        .navigationDestination(for: AlarmRoute.self) { route in
            switch route {
            case .slots: AlarmSlotsView(manager: manager)
            case .history: AlarmHistoryView(manager: manager)
            case .detail(let id): AlarmDetailView(manager: manager, id: id)
            }
        }
        .sheet(item: $editor) { alarm in AlarmEditorView(manager: manager, original: alarm) }
        .confirmationDialog("Delete this alarm?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), presenting: remove) { alarm in
            Button("Delete \(alarm.label)", role: .destructive) {
                if !manager.delete(alarm.id) { localActionError = alarmChangeError(manager) }
                remove = nil
            }
        } message: { _ in Text("Pending strap removal stays visible until WHOOP reports it cleared. Alarm history is kept.") }
        .alert("Alarm change was not saved", isPresented: Binding(get: { localActionError != nil }, set: { if !$0 { localActionError = nil } })) {
            Button("OK", role: .cancel) { localActionError = nil }
        } message: { Text(localActionError ?? "") }
        .task {
            #if os(iOS)
            DhoopPhoneAlarmBackup.configure(manager)
            #endif
            manager.importLegacy(enabled: app.behavior.smartAlarmEnabled, minute: app.behavior.smartAlarmMinutes,
                weekdays: app.behavior.smartAlarmWeekdays, overrides: WindDownNudge.perDayWakeOverrides)
            capturedAt = Date(); await manager.refresh()
        }
        .onReceive(manager.$state) { _ in capturedAt = Date() }
        // Only refresh presentation of dates; alarm execution never depends on this UI clock.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { capturedAt = $0 }
    }
    private var sortedDefinitions: [DhoopAlarmDefinition] { manager.definitions.sorted { $0.rule.minute < $1.rule.minute } }
    private var nextDefinition: DhoopAlarmDefinition? {
        manager.definitions.filter(\.enabled).filter { manager.nextEpoch($0, now: capturedAt) != nil }
            .min { manager.nextEpoch($0, now: capturedAt)! < manager.nextEpoch($1, now: capturedAt)! }
    }
    private func nextStamp(_ alarm: DhoopAlarmDefinition) -> String {
        guard let epoch = manager.nextEpoch(alarm, now: capturedAt) else { return "No upcoming date" }
        return "\(Date(timeIntervalSince1970: Double(epoch)).formatted(date: .abbreviated, time: .shortened)) · \(alarm.label)"
    }
    private var coverage: some View {
        NoopCard(padding: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Scheduled coverage").font(StrandFont.headline)
                let slots = manager.verifiedOccurrences(now: capturedAt)
                if let last = slots.map(\.expected.epoch).max() {
                    Text("\(slots.count) occurrences stored · Furthest \(Date(timeIntervalSince1970: Double(last)).formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.subhead)
                } else { Text("No future alarm verified on WHOOP").font(StrandFont.subhead) }
                NavigationLink("Manage WHOOP slots", value: AlarmRoute.slots).font(StrandFont.caption)
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                Text("Repeat rules are saved in Dhoop. Future dates need available slots and successful syncing.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(manager.phoneStatus).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}

private struct AlarmEditorView: View {
    @ObservedObject var manager: DhoopAlarmManager
    let original: DhoopAlarmDefinition
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DhoopAlarmDefinition
    @State private var time: Date
    @State private var day: Date
    @State private var saving = false
    init(manager: DhoopAlarmManager, original: DhoopAlarmDefinition) {
        self.manager = manager; self.original = original
        _draft = State(initialValue: original)
        let epoch = original.rule.oneTimeEpoch ?? AlarmOccurrencePlanner.nextWallTime(minute: original.rule.minute, after: Date())!
        let date = Date(timeIntervalSince1970: Double(epoch))
        _time = State(initialValue: date); _day = State(initialValue: date)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        #if os(iOS)
                        .datePickerStyle(.wheel)
                        #endif
                    TextField("Label", text: $draft.label)
                    Picker("Repeat", selection: repeatBinding) {
                        Text("Never").tag("Never"); Text("Every day").tag("Every day")
                        Text("Weekdays").tag("Weekdays"); Text("Weekends").tag("Weekends"); Text("Custom").tag("Custom")
                    }
                    if draft.rule.weekdays.isEmpty {
                        DatePicker("Date", selection: $day, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    } else {
                        ForEach([2,3,4,5,6,7,1], id: \.self) { weekday in
                            Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: Binding(
                                get: { draft.rule.weekdays.contains(weekday) },
                                set: { if $0 { draft.rule.weekdays.insert(weekday) } else { draft.rule.weekdays.remove(weekday) } }))
                                .toggleStyle(NoopSwitchStyle())
                        }
                    }
                }
                Section {
                    LabeledContent("WHOOP vibration", value: "Standard · Experimental")
                    Toggle("Phone backup", isOn: $draft.phoneBackup).toggleStyle(NoopSwitchStyle())
                    Toggle("Keep this time zone", isOn: Binding(get: { draft.rule.timeZoneID != nil },
                        set: { draft.rule.timeZoneID = $0 ? TimeZone.current.identifier : nil }))
                        .toggleStyle(NoopSwitchStyle())
                    Text(draft.rule.timeZoneID ?? "Follows local time; stored WHOOP dates need syncing after travel.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    #if os(iOS)
                    if #available(iOS 26.0, *) {
                        Text("Optional system phone alarms have separate permission and finite dated coverage.").font(StrandFont.caption)
                    } else { Text("Phone backup uses notifications; Focus or silent mode may mute it.").font(StrandFont.caption) }
                    #else
                    Text("Phone backup is available in the iPhone app.").font(StrandFont.caption)
                    #endif
                }
                Section {
                    Text("Automatic WHOOP verification").font(StrandFont.headline)
                    Text("Dhoop checks the strap after saving. Pending changes stay visible. No existing slot is used without your approval.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .disabled(saving)
            .navigationTitle(manager.definitions.contains(where: { $0.id == original.id }) ? "Edit alarm" : "New alarm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    NoopAsyncButton("Save", systemImage: "checkmark") { try await save() }
                        .disabled(saving || draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(StrandPalette.alarmAccent)
            .environment(\.timeZone, TimeZone(identifier: draft.rule.timeZoneID ?? TimeZone.current.identifier) ?? .current)
        }
        .interactiveDismissDisabled(saving)
        #if os(iOS)
        .noopSheetPresentation(largeFirst: true)
        #else
        .frame(minWidth: NoopMetrics.editorSheetMinWidth, minHeight: NoopMetrics.editorSheetMinHeight)
        #endif
    }
    private var repeatBinding: Binding<String> {
        Binding(get: { repeatLabel(draft.rule.weekdays) }, set: { value in
            switch value {
            case "Never": draft.rule.weekdays = []
            case "Every day": draft.rule.weekdays = Set(1...7)
            case "Weekdays": draft.rule.weekdays = [2,3,4,5,6]
            case "Weekends": draft.rule.weekdays = [1,7]
            default: if draft.rule.weekdays.isEmpty { draft.rule.weekdays = [Calendar.current.component(.weekday, from: Date())] }
            }
        })
    }
    private struct SaveFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    @MainActor private func save() async throws {
        guard !saving else { throw DhoopAlarmManager.Failure.busy }
        var value = draft, cal = Calendar.current
        if let id = value.rule.timeZoneID, let zone = TimeZone(identifier: id) { cal.timeZone = zone }
        let parts = cal.dateComponents([.hour,.minute], from: time)
        value.rule.minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        value.label = value.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.rule.weekdays.isEmpty {
            guard let due = cal.date(bySettingHour: value.rule.minute / 60, minute: value.rule.minute % 60, second: 0,
                                     of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first), due > Date() else {
                throw SaveFailure(message: "Choose a future date and time. Your draft is retained.")
            }
            value.rule.oneTimeEpoch = Int(due.timeIntervalSince1970)
        } else { value.rule.oneTimeEpoch = nil }
        guard value.valid else { throw SaveFailure(message: "The label is limited to 100 characters. Check the time and repeat days. Your draft is retained.") }
        saving = true
        defer { saving = false }
        if value.phoneBackup && !original.phoneBackup {
            guard await manager.authorizeBackup() else {
                throw SaveFailure(message: "Phone permission was not granted. Turn off Phone backup to save the WHOOP alarm alone. Your draft is retained.")
            }
        }
        try Task.checkCancellation()
        guard manager.save(value) else { throw SaveFailure(message: manager.storageError ?? manager.error ?? "The alarm could not be saved. Your draft is retained.") }
        dismiss()
    }
}

private struct AlarmSlotsView: View {
    @ObservedObject var manager: DhoopAlarmManager
    @State private var approval: DhoopAlarmManager.Reading?
    var body: some View {
        ScreenScaffold(title: "WHOOP alarm slots", onRefresh: { await manager.refresh() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text("Existing and unreadable slots are protected. Zero time can also mean a read failure; it is not proof of an empty slot.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Read WHOOP slots", systemImage: "arrow.clockwise", kind: .secondary, fullWidth: true) {
                    try await manager.readSlotsReviewed()
                }.disabled(manager.busy)
                ForEach(manager.readings) { reading in
                    NoopCard(padding: NoopMetrics.space4) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Slot \(reading.slot)").font(StrandFont.headline)
                            Text(reading.detail).font(StrandFont.subhead)
                            if let record = reading.record, record.epoch > 0 {
                                Text(Date(timeIntervalSince1970: Double(record.epoch)).formatted(date: .abbreviated, time: .shortened))
                                    .font(StrandFont.bodyNumber)
                            }
                            if let owned = manager.currentSlots.first(where: { $0.slot == reading.slot }) {
                                Text("Dhoop · \(owned.detail)").font(StrandFont.caption).foregroundStyle(StrandPalette.alarmAccent)
                            } else if reading.record != nil {
                                Button("Approve use of slot \(reading.slot)") { approval = reading }
                                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true)).disabled(manager.busy)
                            }
                            Text(reading.at.formatted(date: .abbreviated, time: .shortened)).font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
                if let error = manager.error { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                Text("\(manager.context.deviceID) · \(manager.context.firmware)").font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .confirmationDialog("Allow Dhoop to use this WHOOP slot?", isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } }), presenting: approval) { row in
            Button("Use slot \(row.slot)", role: .destructive) {
                if let record = row.record { manager.approveSlot(row.slot, expected: record) }
                approval = nil
            }
        } message: { row in
            Text(row.record?.isZeroTime == true
                 ? "WHOOP reports zero time, which may also mean a read failure. Using slot \(row.slot) could replace an unreadable alarm. Its reported full record will be retained; restoration is unverified. This enables experimental scheduling only in this slot."
                 : "Dhoop may replace the alarm currently reported in slot \(row.slot). Its full record will be retained; restoration is unverified. Other slots remain protected.")
        }
        .task { await manager.refresh() }
    }
}

private struct AlarmDetailView: View {
    @ObservedObject var manager: DhoopAlarmManager
    let id: String
    @EnvironmentObject private var app: AppModel
    @State private var showEditor = false
    @State private var delete = false
    @State private var localActionError: String?
    var body: some View {
        if let alarm = manager.definitions.first(where: { $0.id == id }) {
            ScreenScaffold(title: LocalizedStringKey(alarm.label)) {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    NoopCard(padding: NoopMetrics.space5) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text(timeLabel(alarm.rule.minute)).font(StrandFont.title1).monospacedDigit()
                            Text(repeatDescription(alarm.rule.weekdays)).font(StrandFont.subhead)
                            if let epoch = manager.nextEpoch(alarm, now: Date()) {
                                Text(Date(timeIntervalSince1970: Double(epoch)).formatted(date: .abbreviated, time: .shortened))
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            Text(manager.status(alarm, now: Date())).font(StrandFont.caption).foregroundStyle(StrandPalette.alarmAccent)
                        }
                    }
                    Button("Edit alarm") { showEditor = true }.buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                    NoopAsyncButton("Skip next alarm", systemImage: "forward.end", kind: .secondary, fullWidth: true) {
                        try requireAlarmChange(manager.skipNext(id), manager: manager)
                    }
                    Button("Test vibration") { app.requestBuzz(owner: "alarm-preview", loops: 1) }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                        .disabled(!manager.context.ready || manager.blocksMotor(now: Date()))
                    Text("The test is one connection buzz. It does not run, consume, or change your stored alarms.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    NavigationLink("View stored WHOOP records", value: AlarmRoute.slots).font(StrandFont.subhead)
                        .frame(minHeight: NoopMetrics.minimumTouchTarget).buttonStyle(NoopFeedbackButtonStyle())
                    Button("Delete alarm", role: .destructive) { delete = true }
                        .buttonStyle(NoopButtonStyle(.destructive, fullWidth: true))
                    ForEach(manager.currentSlots.filter { $0.definitionIDs.contains(id) }) { slot in
                        if slot.expected.epoch <= Int64(Date().timeIntervalSince1970) && slot.expected.epoch > 0 {
                            NoopAsyncButton("I felt this alarm", systemImage: "checkmark", kind: .secondary, fullWidth: true) {
                                try requireAlarmChange(manager.confirmFelt(slot: slot.slot, epoch: Int(slot.expected.epoch), felt: true), manager: manager)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditor) { AlarmEditorView(manager: manager, original: alarm) }
            .confirmationDialog("Delete \(alarm.label)?", isPresented: $delete) {
                Button("Delete alarm", role: .destructive) {
                    if !manager.delete(id) { localActionError = alarmChangeError(manager) }
                }
            } message: { Text("A stored alarm may still fire until removal is verified on WHOOP. History is kept.") }
            .alert("Alarm change was not saved", isPresented: Binding(get: { localActionError != nil }, set: { if !$0 { localActionError = nil } })) {
                Button("OK", role: .cancel) { localActionError = nil }
            } message: { Text(localActionError ?? "") }
        } else { Text("Alarm removed. Any pending strap removal is shown in WHOOP slots.").font(StrandFont.body) }
    }
}

private struct AlarmHistoryView: View {
    @ObservedObject var manager: DhoopAlarmManager
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScreenScaffold(title: "Alarm history") {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                if manager.state.history.isEmpty { Text("No alarm events yet").font(StrandFont.body) }
                ForEach(manager.state.history.reversed()) { item in
                    NoopCard(padding: NoopMetrics.space4) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text(item.message).font(StrandFont.subhead)
                            Text(item.at.formatted(date: .abbreviated, time: .shortened)).font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                            if let epoch = item.epoch {
                                Text("Scheduled \(Date(timeIntervalSince1970: Double(epoch)).formatted(date: .abbreviated, time: .shortened))")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                if epoch <= Int(Date().timeIntervalSince1970), let slot = item.slot,
                                   item.deviceID == manager.context.deviceID {
                                    if typeSize.isAccessibilitySize {
                                        VStack(spacing: NoopMetrics.space3) { reportControls(slot: slot, epoch: epoch) }
                                    } else {
                                        HStack(spacing: NoopMetrics.space3) { reportControls(slot: slot, epoch: epoch) }
                                    }
                                }
                            }
                        }
                    }
                }
                if FileManager.default.fileExists(atPath: manager.exportURL.path) {
                    ShareLink("Export alarm state", item: manager.exportURL)
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                }
            }
        }
    }
    @ViewBuilder private func reportControls(slot: Int, epoch: Int) -> some View {
        NoopAsyncButton("Felt it", systemImage: "checkmark", kind: .secondary, fullWidth: true) {
            try requireAlarmChange(manager.confirmFelt(slot: slot, epoch: epoch, felt: true), manager: manager)
        }
        NoopAsyncButton("No vibration", systemImage: "xmark", kind: .secondary, fullWidth: true) {
            try requireAlarmChange(manager.confirmFelt(slot: slot, epoch: epoch, felt: false), manager: manager)
        }
    }

}

private struct AlarmLocalActionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private func alarmChangeError(_ manager: DhoopAlarmManager) -> String {
    manager.storageError ?? "The local alarm change was not saved. Check that this alarm or occurrence is still available."
}

@MainActor
private func requireAlarmChange(_ saved: Bool, manager: DhoopAlarmManager) throws {
    guard saved else { throw AlarmLocalActionFailure(message: alarmChangeError(manager)) }
}

private func repeatLabel(_ weekdays: Set<Int>) -> String {
    if weekdays.isEmpty { return "Never" }
    if weekdays == Set(1...7) { return "Every day" }
    if weekdays == [2,3,4,5,6] { return "Weekdays" }
    if weekdays == [1,7] { return "Weekends" }
    return "Custom"
}
private func timeLabel(_ minute: Int) -> String {
    let format = DateFormatter(); format.locale = .autoupdatingCurrent
    format.timeStyle = .short; format.dateStyle = .none
    format.timeZone = TimeZone(secondsFromGMT: 0)
    return format.string(from: Date(timeIntervalSince1970: Double(minute * 60)))
}
private func repeatDescription(_ weekdays: Set<Int>) -> String {
    let label = repeatLabel(weekdays)
    guard label == "Custom" else { return label }
    return [2,3,4,5,6,7,1].filter(weekdays.contains)
        .map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
}
