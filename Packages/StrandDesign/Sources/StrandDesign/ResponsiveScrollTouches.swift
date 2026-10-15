import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension View {
    /// Deliver press highlighting immediately while retaining native scroll-pan cancellation.
    func responsiveScrollTouches() -> some View {
        #if os(iOS)
        background(ResponsiveScrollTouchBridge().allowsHitTesting(false))
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct ResponsiveScrollTouchBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.configure() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.restore() }

    final class Probe: UIView {
        private weak var scroll: UIScrollView?
        private let token = UUID()
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); configure() }
        func configure() {
            var ancestor = superview
            while let view = ancestor {
                if let candidate = view as? UIScrollView {
                    guard scroll !== candidate else { candidate.delaysContentTouches = false; return }
                    restore(); scroll = candidate
                    ScrollTouchLeases.acquire(candidate, token: token)
                    return
                }
                ancestor = view.superview
            }
        }
        func restore() { if let scroll { ScrollTouchLeases.release(scroll, token: token) }; scroll = nil }
    }
}

@MainActor
private enum ScrollTouchLeases {
    private final class Lease: NSObject {
        let original: Bool
        var owners = Set<UUID>()
        init(original: Bool) { self.original = original }
    }
    private static let leases = NSMapTable<UIScrollView, Lease>.weakToStrongObjects()
    static func acquire(_ scroll: UIScrollView, token: UUID) {
        let lease = leases.object(forKey: scroll) ?? Lease(original: scroll.delaysContentTouches)
        lease.owners.insert(token); leases.setObject(lease, forKey: scroll)
        scroll.delaysContentTouches = false
    }
    static func release(_ scroll: UIScrollView, token: UUID) {
        guard let lease = leases.object(forKey: scroll) else { return }
        lease.owners.remove(token)
        if lease.owners.isEmpty {
            scroll.delaysContentTouches = lease.original
            leases.removeObject(forKey: scroll)
        }
    }
}
#endif
