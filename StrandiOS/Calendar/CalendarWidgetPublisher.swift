#if os(iOS)
import Foundation
import WidgetKit

/// Bounded foreground prefetch of seven read-only days. Widgets read only this App Group cache.
@MainActor
final class CalendarWidgetPublisher {
    static let shared = CalendarWidgetPublisher()
    static let enabledKey = "dhoop.calendar.widget.enabled"
    private var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.suiteName) }
    private var task: Task<Void, Never>?
    private var identity: UUID?
    private var generation = 0
    private var ticket: UUID?
    private var nextRefresh = Date.distantPast
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue { refreshIfNeeded(force: true) } else { clear() }
        }
    }
    func clear() {
        generation += 1; ticket = nil; task?.cancel(); task = nil; identity = nil; nextRefresh = .distantPast
        defaults?.removeObject(forKey: CalendarWidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetSnapshot.widgetKind)
    }
    func record(_ chain: CalendarReaderDayChain) {
        guard enabled, let first = chain.first, let at = CalendarReaderDates.instant(first.readAt) else { return }
        store(date: first.date, readAt: at, complete: chain.cursor == nil, events: chain.events)
    }
    private func store(date: String, readAt: Date, complete: Bool, events: [CalendarReaderEvent]) {
        guard enabled, let defaults else { return }
        let today = CalendarReaderDates.key(Date()), last = CalendarReaderDates.shifted(today, by: 6)
        guard date >= today, date <= last else { return }
        var snapshot = CalendarWidgetSnapshot().loadDefaults(defaults) ?? CalendarWidgetSnapshot()
        if snapshot.days.contains(where: { $0.date == date && $0.readAt > readAt }) { return }
        snapshot.days.removeAll { $0.date == date || $0.date < today || $0.date > last }
        let values = events.prefix(100).map { event in
            CalendarWidgetSnapshot.Event(id: event.id, title: event.title, start: event.startAt.flatMap(CalendarReaderDates.instant),
                end: event.endAt.flatMap(CalendarReaderDates.instant), allDay: event.allDay, organizer: event.invitation?.organizer?.label,
                pending: event.invitation?.pending == true, localProjection: event.source == "local_projection")
        }
        snapshot.days.append(.init(date: date, readAt: readAt, complete: complete && events.count <= 100, events: values)); snapshot.days.sort { $0.date < $1.date }
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= 512 * 1024 else { return }
        defaults.set(data, forKey: CalendarWidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetSnapshot.widgetKind)
    }
    func refreshIfNeeded(force: Bool = false) {
        let reader = CalendarReaderClient.shared
        guard reader.reloadConfiguration(), reader.enabled, let config = reader.configuration, enabled else { return }
        guard task == nil, force || Date() >= nextRefresh else { return }
        identity = config.installationId; nextRefresh = Date().addingTimeInterval(15 * 60)
        let currentTicket = UUID(), version = generation; ticket = currentTicket
        task = Task { [weak self] in
            guard let self else { return }; defer { if ticket == currentTicket { task = nil } }
            let today = CalendarReaderDates.key(Date())
            for offset in 0..<7 {
                guard !Task.isCancelled, enabled, generation == version, identity == config.installationId,
                      CalendarReaderClient.shared.configuration == config else { return }
                let day = CalendarReaderDates.shifted(today, by: offset)
                do {
                    let bytes = try await CalendarReaderTransport().send(.day(day, nil), configuration: config)
                    let page = try JSONDecoder().decode(CalendarReaderDay.self, from: bytes); try page.validate(date: day)
                    guard !Task.isCancelled, enabled, generation == version, CalendarReaderClient.shared.configuration == config else { return }
                    guard let readAt = CalendarReaderDates.instant(page.readAt) else { continue }
                    store(date: day, readAt: readAt, complete: !page.page.hasMore, events: page.events)
                } catch { /* Keep last successful reads and their actual timestamps. No retry loop. */ }
            }
        }
    }
}
#endif
