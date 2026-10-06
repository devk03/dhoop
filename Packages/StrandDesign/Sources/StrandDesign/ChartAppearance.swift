import SwiftUI

/// Quiet chart ink shared by metric history, sleep comparison and recorded workouts.
public enum StrandChartStyle {
    public static let lineWidth: CGFloat = 2
    public static let pointArea: CGFloat = 14
    public static let sparsePointLimit = 8
    public static let gridOpacity = 0.5

    /// Plot-aligned fade; callers keep each recorded run separate so missing data has no fill.
    public static func area(_ tint: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: tint.opacity(0.30), location: 0),
            .init(color: tint.opacity(0.12), location: 0.55),
            .init(color: tint.opacity(0), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    public static func bar(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.30)], startPoint: .top, endPoint: .bottom)
    }
}
