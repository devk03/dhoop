#if !os(watchOS)
import SwiftUI

public extension View {
    /// Coordinates are normalized to the rendered canvas. Labels retain the original value and units.
    func canvasInspection(_ data: [ChartScrubDatum], label: String, twoDimensional: Bool = false,
                          tint: Color = StrandPalette.accent) -> some View {
        modifier(CanvasInspectionModifier(data: data.filter { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }, label: label, twoDimensional: twoDimensional, tint: tint))
    }
}
private struct CanvasInspectionModifier: ViewModifier {
    let data: [ChartScrubDatum]
    let label: String
    let twoDimensional: Bool
    let tint: Color
    @State private var selectedID: String?
    private var selected: ChartScrubDatum? { data.first { $0.id == selectedID } }
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                    if let selected {
                        let point = CGPoint(x: selected.x * geometry.size.width, y: selected.y * geometry.size.height)
                        CrosshairRule(x: point.x, height: geometry.size.height)
                        HighlightDot(color: tint).position(point)
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text(selected.value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                            Text(selected.context).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }.padding(NoopMetrics.space2)
                            .frame(maxWidth: min(geometry.size.width, NoopMetrics.detailSheetMinWidth / 2), alignment: .leading)
                            .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: NoopMetrics.space2))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .chartTouchScrub(enabled: !data.isEmpty) { select($0, size: geometry.size) }
                .onContinuousHover { phase in
                    switch phase { case .active(let point): select(point, size: geometry.size); case .ended: selectedID = nil }
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
        .accessibilityValue(selected.map { "\($0.value), \($0.context)" } ?? "\(data.count) recorded points. Adjust to inspect.")
        .accessibilityHint("Touch and hold, then drag. With VoiceOver, swipe up or down through recorded points.")
        .accessibilityAdjustableAction { direction in
            guard !data.isEmpty else { return }
            let current = data.firstIndex { $0.id == selectedID } ?? (direction == .increment ? -1 : data.count)
            selectedID = data[min(data.count - 1, max(0, current + (direction == .increment ? 1 : -1)))].id
        }
        .onChange(of: data.map(\.id)) { _ in selectedID = nil }
    }
    private func select(_ point: CGPoint?, size: CGSize) {
        guard let point, size.width > 0, size.height > 0, CGRect(origin: .zero, size: size).contains(point) else { selectedID = nil; return }
        let x = point.x / size.width, y = point.y / size.height
        func distance(_ datum: ChartScrubDatum) -> Double { pow(datum.x - x, 2) + (twoDimensional ? pow(datum.y - y, 2) : 0) }
        selectedID = data.min { distance($0) < distance($1) }?.id
    }
}
#endif
