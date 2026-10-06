import SwiftUI

/// Native switch semantics with a track color that stays distinct from the white thumb.
public struct NoopSwitchStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(NoopVisualStyle.switchTint)
            .frame(minHeight: NoopMetrics.minimumTouchTarget)
    }
}
