#if os(iOS)
import SwiftUI
import Combine
import StrandDesign

@MainActor
final class DayHubNavigation: ObservableObject {
    static let shared = DayHubNavigation()
    @Published private(set) var section: String?
    func consume() { section = nil }
    @discardableResult func open(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "dhoop", c.host == "day-hub",
              c.user == nil, c.password == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              let items = c.queryItems, items.count == 1, items.first?.name == "section",
              let value = items.first?.value, ["overview", "food", "workouts", "sleep"].contains(value) else { return false }
        section = value; return true
    }
}
struct DayHubOverview: View {
    @ObservedObject private var publisher = DayHubPublisher.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScreenScaffold(title: nil, onRefresh: { publisher.refreshIfNeeded(force: true) }, lazy: false) {
                    DayHubView(snapshot: publisher.snapshot, now: context.date, expanded: true)
                    if publisher.refreshing { ProgressView().accessibilityLabel("Refresh") }
                }
            }.toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { publisher.refreshIfNeeded(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(NoopFeedbackButtonStyle()).accessibilityLabel("Refresh")
                }
            }
        }.task { publisher.refreshIfNeeded() }
    }
}
#endif
