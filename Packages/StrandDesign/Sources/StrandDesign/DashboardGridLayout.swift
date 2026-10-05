import SwiftUI

/// Equal dashboard columns with square minimums; content can grow each row for larger text.
public struct DashboardGridLayout: Layout {
    let columns: Int
    let squareMinimum: Bool
    let spacing: CGFloat

    public init(columns: Int = 2, squareMinimum: Bool = true, spacing: CGFloat = NoopMetrics.gap) {
        self.columns = max(1, columns)
        self.squareMinimum = squareMinimum
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? ideal * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let heights = rowHeights(width: width, subviews: subviews)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(heights.count - 1))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columnCount(bounds.width)
        let width = columnWidth(bounds.width)
        let heights = rowHeights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (width + spacing), y: y),
                    anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        let count = columnCount(width)
        return max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    private func columnCount(_ width: CGFloat) -> Int {
        min(columns, max(1, Int((width + spacing) / (NoopMetrics.dashboardTileMinimumWidth + spacing))))
    }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let columns = columnCount(width)
        let column = columnWidth(width)
        return stride(from: 0, to: subviews.count, by: columns).map { start in
            let content = (start..<min(start + columns, subviews.count)).map {
                subviews[$0].sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            }.max() ?? 0
            return max(squareMinimum ? column : 0, content)
        }
    }
}
