import SwiftUI

/// A lightweight, exportable progress track. The owning label supplies its accessible value.
public struct NoopProgressTrack: View {
    let fraction: Double
    let tint: Color
    public init(fraction: Double, tint: Color) { self.fraction = fraction; self.tint = tint }
    public var body: some View {
        GeometryReader { geometry in
            Capsule().fill(StrandPalette.surfaceInset)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: geometry.size.width * CGFloat(fraction.isFinite ? min(1, max(0, fraction)) : 0))
                }
        }.frame(height: NoopMetrics.space1).accessibilityHidden(true)
    }
}
