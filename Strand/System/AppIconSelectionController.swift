import Foundation
import Combine
import StrandDesign
#if os(iOS)
import UIKit
#endif

/// The requested choice is distinct from the icon reported by the system.
@MainActor
final class AppIconSelectionController: ObservableObject {
    @Published private(set) var requested: Bool?
    @Published private(set) var confirmedName: String?
    @Published private(set) var state: NoopActionState = .idle
    private let defaults: UserDefaults
    private let supports: () -> Bool
    private let read: () -> String?
    private let apply: (String?) async throws -> Void
    static let preferenceKey = "appIcon.alt"
    static let navyName = "AppIcon-Navy"
    var isWorking: Bool { state.isWorking }
    var isSupported: Bool { supports() }
    var selection: Bool { requested ?? (confirmedName == Self.navyName) }
    var error: String? { if case .failed(let message) = state { return message }; return nil }

    enum Failure: LocalizedError {
        case unsupported, notConfirmed
        var errorDescription: String? {
            switch self {
            case .unsupported: return "This installation does not support alternate icons. Your requested choice is retained."
            case .notConfirmed: return "The system did not confirm the requested icon. Your choice is retained; retry or keep the current icon."
            }
        }
    }

    init(defaults: UserDefaults, supports: @escaping () -> Bool,
         read: @escaping () -> String?, apply: @escaping (String?) async throws -> Void) {
        self.defaults = defaults; self.supports = supports; self.read = read; self.apply = apply
        confirmedName = read()
    }

    @discardableResult
    func change(to choice: Bool) async -> Bool {
        guard !isWorking else { return false }
        requested = choice; state = .working
        let target = choice ? Self.navyName : nil
        do {
            guard supports() else { throw Failure.unsupported }
            if read() != target { try await apply(target) }
            confirmedName = read()
            guard confirmedName == target else { throw Failure.notConfirmed }
            defaults.set(choice, forKey: Self.preferenceKey)
            requested = nil; state = .succeeded
            return true
        } catch {
            confirmedName = read()
            // The persisted preference follows actual system state, never an inverted draft.
            defaults.set(confirmedName == Self.navyName, forKey: Self.preferenceKey)
            state = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func retry() async -> Bool {
        guard let requested, !isWorking else { return false }
        return await change(to: requested)
    }

    func keepCurrent() {
        guard !isWorking else { return }
        requested = nil; confirmedName = read(); state = .idle
        defaults.set(confirmedName == Self.navyName, forKey: Self.preferenceKey)
    }

    #if os(iOS)
    static func native() -> AppIconSelectionController {
        AppIconSelectionController(defaults: .standard,
            supports: { UIApplication.shared.supportsAlternateIcons },
            read: { UIApplication.shared.alternateIconName },
            apply: { try await UIApplication.shared.setAlternateIconName($0) })
    }
    #endif
}
