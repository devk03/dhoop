import Foundation

/// One permission request may advance only its original page, once.
struct OnboardingPermissionGate {
    private var pending: (id: UUID, page: Int)?
    var isPending: Bool { pending != nil }

    mutating func begin(page: Int) -> UUID? {
        guard pending == nil else { return nil }
        let id = UUID()
        pending = (id, page)
        return id
    }

    mutating func consume(_ id: UUID, page: Int) -> Bool {
        guard let pending, pending.id == id else { return false }
        self.pending = nil
        return pending.page == page
    }

    mutating func invalidate() { pending = nil }
}
