import Foundation
import Combine

/// Widget links navigate only. No URL or external text can trigger an invitation response.
struct CalendarNavigationRequest: Equatable {
    let id: UUID
    let day: String
    let eventID: String?
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "dhoop", parts.host == "calendar",
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              let items = parts.queryItems, items.count == Set(items.map(\.name)).count,
              Set(items.map(\.name)).isSubset(of: ["date", "eventId"]),
              let day = items.first(where: { $0.name == "date" })?.value, CalendarReaderDates.date(day) != nil else { return nil }
        let eventID = items.first(where: { $0.name == "eventId" })?.value
        guard eventID.map({ !$0.isEmpty && $0.utf8.count <= 1024 }) ?? true else { return nil }
        id = UUID(); self.day = day; self.eventID = eventID
    }
}
@MainActor
final class CalendarNavigation: ObservableObject {
    static let shared = CalendarNavigation()
    @Published private(set) var request: CalendarNavigationRequest?
    func consume(_ id: UUID) { if request?.id == id { request = nil } }
    @discardableResult func open(_ url: URL) -> Bool {
        guard let next = CalendarNavigationRequest(url: url) else { return false }; request = next; return true
    }
}
