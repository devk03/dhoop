import Foundation
import Combine

/// Weight-loss tracking is opt-in and independent of whether a plan was previously configured.
final class CutGoalPreferences: ObservableObject {
    static let shared = CutGoalPreferences()
    static let enabledKey = "cut.goalEnabled"

    private let defaults: UserDefaults
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Check at the time of publication too, so a refresh started before disabling cannot write later.
    func performTrackingUpdate(_ update: () -> Void) {
        guard isEnabled else { return }
        update()
    }
}
