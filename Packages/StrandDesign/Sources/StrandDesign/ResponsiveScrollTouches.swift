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
        private var previousDelay = true
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); configure() }
        func configure() {
            var ancestor = superview
            while let view = ancestor {
                if let candidate = view as? UIScrollView {
                    guard scroll !== candidate else { return }
                    restore(); scroll = candidate; previousDelay = candidate.delaysContentTouches
                    candidate.delaysContentTouches = false
                    return
                }
                ancestor = view.superview
            }
        }
        func restore() { scroll?.delaysContentTouches = previousDelay; scroll = nil }
    }
}
#endif
