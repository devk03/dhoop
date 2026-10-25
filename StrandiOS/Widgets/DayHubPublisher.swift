#if os(iOS)
import Foundation
import Combine
import WidgetKit

/// Publishes existing app data only. Network reads are bounded foreground opportunities, never a poll loop.
@MainActor
final class DayHubPublisher: ObservableObject {
    static let shared = DayHubPublisher()
    @Published private(set) var snapshot: DayHubSnapshot?
    @Published private(set) var refreshing = false
    private var subscriptions = Set<AnyCancellable>()
    private weak var model: AppModel?
    private var nextRefresh = Date.distantPast
    private var task: Task<Void, Never>?
    private var pendingRefresh = false
    private var nextSleepRead = Date.distantPast
    private var sleepLoading = false
    private var deviceID: String?
    private var workoutIdentity = ""
    private var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.suiteName) }
    private init() { snapshot = DayHubSnapshot.load(UserDefaults(suiteName: WidgetSnapshot.suiteName)) }
    private func base(now: Date = Date()) -> DayHubSnapshot {
        snapshot ?? DayHubSnapshot(savedAt: now, timeZoneID: TimeZone.current.identifier, calendarDays: [])
    }
    private func save(_ value: DayHubSnapshot) {
        guard let defaults, let bytes = try? JSONEncoder().encode(value), bytes.count <= 256 * 1024 else { return }
        snapshot = value; defaults.set(bytes, forKey: DayHubSnapshot.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: DayHubSnapshot.widgetKind)
    }
    func attach(model: AppModel) {
        guard self.model == nil else { return }; self.model = model
        publishFood()
        ProteinLogStore.shared.$entries.dropFirst().debounce(for: .milliseconds(250), scheduler: RunLoop.main).sink { [weak self] _ in self?.publishFood() }.store(in: &subscriptions)
        ProteinLogStore.shared.$storageError.dropFirst().debounce(for: .milliseconds(250), scheduler: RunLoop.main).sink { [weak self] _ in self?.publishFood() }.store(in: &subscriptions)
        CutPlanStore.shared.$food.dropFirst().debounce(for: .milliseconds(250), scheduler: RunLoop.main).sink { [weak self] _ in self?.publishFood() }.store(in: &subscriptions)
        model.repo.$refreshSeq.dropFirst().debounce(for: .seconds(2), scheduler: RunLoop.main).sink { [weak self] _ in self?.refreshLocalSleep() }.store(in: &subscriptions)
        WorkoutTrackerClient.shared.$state.map { state in
            (state.origin ?? "") + (state.installationId?.uuidString ?? "") + String(state.enabled) +
            (state.frontendPage?.dashboard.sessions.map { "\($0.id)|\($0.scheduledDate)|\($0.status)|\($0.title)" }.joined(separator: ";") ?? "")
        }.removeDuplicates().dropFirst().debounce(for: .seconds(1), scheduler: RunLoop.main).sink { [weak self] _ in self?.refreshIfNeeded(force: true) }.store(in: &subscriptions)
        refreshIfNeeded()
    }
    func publishFood() {
        let now = Date(), day = Repository.localDayKey(now), store = ProteinLogStore.shared
        var value = base(now: now); value.savedAt = now; value.timeZoneID = TimeZone.current.identifier
        if store.storageUnavailable { value.food = nil }
        else {
            let entries = store.entries.filter { $0.day == day }, legacy = CutPlanStore.shared.entries(day: day)
            let estimates = entries.map(\.calories) + legacy.map { Optional(Double($0.kcal)) }
            let known = estimates.compactMap { $0 }
            value.food = .init(day: day, readAt: now, protein: entries.reduce(0) { $0 + $1.grams } + legacy.reduce(0) { $0 + ($1.protein ?? 0) },
                calories: known.isEmpty ? nil : known.reduce(0,+), entries: estimates.count, estimatedEntries: known.count)
        }
        save(value)
    }
    func clearCalendar() {
        var value = base(); value.calendarDays = []; save(value)
    }
    func refreshIfNeeded(force: Bool = false) {
        guard let model else { return }
        if !WorkoutTrackerClient.shared.state.enabled || !WorkoutTrackerClient.shared.configured {
            var value = base(); value.workouts = nil; save(value)
        }
        if task != nil { if force { pendingRefresh = true }; return }
        guard force || Date() >= nextRefresh else { publishFood(); return }
        nextRefresh = Date().addingTimeInterval(15 * 60); refreshing = true
        if force { nextSleepRead = .distantPast }
        task = Task { [weak self, weak model] in
            guard let self, let model else { return }
            defer {
                task = nil; refreshing = false
                if pendingRefresh { pendingRefresh = false; refreshIfNeeded(force: true) }
            }
            publishFood()
            await loadSleep(model: model)
            await loadCalendar()
            await loadWorkouts()
        }
    }
    func waitForRefresh() async { await task?.value }
    private var sleepTask: Task<Void, Never>?
    private func refreshLocalSleep() {
        guard sleepTask == nil, let model else { return }
        sleepTask = Task { [weak self, weak model] in
            defer { self?.sleepTask = nil }
            guard let self, let model else { return }; await loadSleep(model: model)
        }
    }
    private func loadSleep(model: AppModel) async {
        let source = model.repo.deviceId
        if deviceID != source { deviceID = source; nextSleepRead = .distantPast; var value = base(); value.sleep = nil; save(value) }
        guard !sleepLoading, Date() >= nextSleepRead else { return }
        sleepLoading = true; nextSleepRead = Date().addingTimeInterval(5 * 60)
        defer { sleepLoading = false }
        // A dedicated reader avoids superseding the Sleep page's requests.
        let reader = SleepRangeModel(), now = Date()
        await reader.load(repo: model.repo, window: MetricRangeSelection(now: now).window(now: now))
        guard model.repo.deviceId == source, reader.error == nil, let result = reader.snapshot else { return }
        let eight = result.apple.first { $0.isEightSleep }
        let day = (result.whoop.map(\.day) + (eight?.days.map(\.day) ?? [])).max()
        var value = base(); value.savedAt = Date()
        value.sleep = day.map { key in .init(wakeDay: key, readAt: Date(), whoopMinutes: result.whoop.first { $0.day == key }?.total,
            eightSleepMinutes: eight?.days.first { $0.day == key }?.total, whoopMethod: result.whoop.first { $0.day == key }?.method) }
        save(value)
    }
    private func loadCalendar() async {
        let client = CalendarReaderClient.shared
        guard CalendarWidgetPublisher.shared.enabled, client.reloadConfiguration(), client.enabled, let config = client.configuration else {
            var value = base(); value.calendarDays = []; save(value); return
        }
        let window = DayHubWindow(now: Date()); var days: [CalendarWidgetSnapshot.Day] = []
        do {
            for day in window.requiredDays.sorted() {
                let bytes = try await CalendarReaderTransport().send(.day(day, nil), configuration: config)
                let page = try JSONDecoder().decode(CalendarReaderDay.self, from: bytes); try page.validate(date: day)
                guard CalendarWidgetPublisher.shared.enabled, client.enabled, client.configuration == config, let readAt = CalendarReaderDates.instant(page.readAt) else { return }
                days.append(.init(date: day, readAt: readAt, complete: !page.page.hasMore && page.events.count <= 100, events: page.events.prefix(100).map {
                    .init(id: $0.id, title: $0.title, start: $0.startAt.flatMap(CalendarReaderDates.instant), end: $0.endAt.flatMap(CalendarReaderDates.instant),
                        allDay: $0.allDay, organizer: $0.invitation?.organizer?.label, pending: $0.invitation?.pending == true, localProjection: $0.source == "local_projection")
                }))
            }
            var value = base(); value.calendarDays = days; value.savedAt = Date(); save(value)
        } catch { /* Preserve the last successful calendar and its real read date. */ }
    }
    private func loadWorkouts() async {
        let client = WorkoutTrackerClient.shared
        let identity = "\(client.state.origin ?? "")|\(client.state.installationId?.uuidString ?? "")"
        if identity != workoutIdentity || !client.state.enabled || !client.configured {
            workoutIdentity = identity; var value = base(); value.workouts = nil; save(value)
        }
        guard client.state.enabled, client.configured else { return }
        let now = Date(), day = Repository.localDayKey(now)
        do {
            let program = try await client.readStrength()
            var rows: [DayHubSnapshot.Workout] = []; var complete = true
            if let id = program.program?.id {
                for status in ["planned", "in_progress", "completed", "skipped"] {
                    let page = try await client.readHistory(filters: .init(mesocycleId: id, status: status, kind: "strength", since: day, until: day), cursor: nil)
                    guard page.lifeRevision == program.lifeRevision else { return }
                    complete = complete && !page.pagination.hasMore
                    rows += page.sessions.filter { $0.scheduledDate == day && $0.kind == "strength" && $0.status == status }.map {
                        .init(id: $0.id, title: $0.title, status: $0.status, timing: $0.timing)
                    }
                }
            }
            guard identity == "\(client.state.origin ?? "")|\(client.state.installationId?.uuidString ?? "")", client.state.enabled else { return }
            var value = base(); value.workouts = .init(day: day, readAt: Date(), complete: complete, rows: rows.sorted { $0.id < $1.id }); value.savedAt = Date(); save(value)
        } catch { /* A failed read never changes a completed workout into an uncompleted one. */ }
    }
}
#endif
