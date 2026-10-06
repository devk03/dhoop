import SwiftUI

// MARK: - NOOP visual foundation
//
// These tokens describe the visual treatment used by NOOP's existing views. They deliberately
// contain no navigation, state, or domain semantics: screens keep their current hierarchy and data
// bindings, while cards, gauges, typography, and chrome share one maintainable source of truth.

public enum NoopVisualStyle {
    // Neutral, low-chroma surfaces sampled from the supplied dark-mode reference.
    public static let canvas = Color(light: "#F3F4F6", dark: "#000000")
    public static let surface = Color(light: "#FFFFFF", dark: "#101114")
    public static let surfaceTop = Color(light: "#FFFFFF", dark: "#121316")
    public static let surfaceBottom = Color(light: "#F4F5F7", dark: "#101114")
    public static let inset = Color(light: "#E8E9ED", dark: "#090A0C")

    public static let border = Color(light: "#D8DAE0", dark: "#282A30")
    public static let borderHighlight = Color(light: "#FFFFFF", dark: "#41454B")
    public static let divider = Color(light: "#E4E5E9", dark: "#2E3237")

    public static let primaryText = Color(light: "#17181C", dark: "#F7F7FA")
    public static let secondaryText = Color(light: "#555861", dark: "#B9BEC5")
    public static let tertiaryText = Color(light: "#7D808A", dark: "#8F969F")

    public static let switchTint = Color(light: "#235D9F", dark: "#2968AC")

    public static let selectedControlFill = Color(light: "#20232A", dark: "#F0F1F4")
    public static let selectedControlInk = Color(light: "#FFFFFF", dark: "#111216")

    public static let mint = Color(light: "#149A78", dark: "#69DDB8")
    public static let mintDeep = Color(light: "#0D765C", dark: "#13A982")
    public static let mintGlow = Color(light: "#38C99E", dark: "#54E6BD")

    public static let cardRadius: CGFloat = 14
    public static let compactRadius: CGFloat = 10
    public static let pillRadius: CGFloat = 999
    public static let pagePadding: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let itemGap: CGFloat = 12
    public static let sectionGap: CGFloat = 16
}

/// Shared card/panel treatment: charcoal surfaces, a quiet rim, and elevation reserved for overlays.
/// `tint` is intentionally faint so metric identity never turns the whole card into a coloured tile.
public struct NoopPanelSurface: View {
    public var tint: Color?
    public var cornerRadius: CGFloat
    public var elevated: Bool
    public var surfaceOpacity: Double
    @Environment(\.colorScheme) private var scheme

    public init(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.surfaceOpacity = surfaceOpacity
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                if let tint {
                    shape.fill(
                        LinearGradient(
                            colors: [tint.opacity(0.018), tint.opacity(0.004), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [NoopVisualStyle.border.opacity(0.8), NoopVisualStyle.border.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            )
            .shadow(
                color: scheme == .dark ? .black.opacity(elevated ? 0.24 : 0) : .black.opacity(elevated ? 0.10 : 0.025),
                radius: elevated ? 18 : 9,
                x: 0,
                y: elevated ? 10 : 5
            )
            .opacity(surfaceOpacity)
    }
}

/// Shared edge-to-edge chrome for sheet and split-view headers. Unlike a card it has no
/// rounded outline or elevation, but it uses the same top-lit surface ramp and divider token.
public struct NoopChromeSurface: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NoopVisualStyle.divider)
                .frame(height: 0.5)
        }
    }
}

public extension View {
    func noopPanel(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) -> some View {
        background {
            NoopPanelSurface(
                tint: tint,
                cornerRadius: cornerRadius,
                elevated: elevated,
                surfaceOpacity: surfaceOpacity
            )
        }
    }
}
