#if !os(watchOS)
import SwiftUI
import Charts

/// A compact, linear chart of prepared observations; distinct runs keep gaps and isolated points visible.
public struct DashboardChart: View {
    public enum Style { case line, bars }
    let points: [TrendPoint]
    let domain: ClosedRange<Date>
    let range: ClosedRange<Double>
    let tint: Color
    let style: Style
    let height: CGFloat
    let label: String
    let dailyLabels: Bool
    let singletonSegments: Set<String>

    public init(points: [TrendPoint], domain: ClosedRange<Date>, range: ClosedRange<Double>, tint: Color,
                style: Style = .line, height: CGFloat = NoopMetrics.dashboardTrendHeight,
                label: String, dailyLabels: Bool = false) {
        // Callers prepare chronological, gap-preserving display points once with their snapshot.
        self.points = points
        self.singletonSegments = Set(Dictionary(grouping: points, by: \.segment).filter { $0.value.count == 1 }.keys)
        self.domain = domain; self.range = range; self.tint = tint; self.style = style
        self.height = height; self.label = label; self.dailyLabels = dailyLabels
    }

    public var body: some View {
        Chart {
            ForEach(points) { point in
                if style == .bars {
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                        .foregroundStyle(tint.opacity(Calendar.current.isDateInToday(point.date) ? 1 : 0.45))
                        .cornerRadius(NoopMetrics.space1)
                } else {
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value),
                             series: .value("Recorded run", point.segment))
                        .interpolationMethod(.linear).foregroundStyle(tint)
                    if points.count < 40 || singletonSegments.contains(point.segment) {
                        PointMark(x: .value("Time", point.date), y: .value("Value", point.value))
                            .foregroundStyle(tint)
                    }
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: range)
        .chartLegend(.hidden)
        .chartXAxis {
            if dailyLabels {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(StrandPalette.textSecondary).font(StrandFont.caption)
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: domain.upperBound.timeIntervalSince(domain.lowerBound) <= 86_400
                                 ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day())
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if style == .line {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline)
                    AxisValueLabel().foregroundStyle(StrandPalette.textSecondary).font(StrandFont.caption)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(summary)
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "No recorded data" }
        let values = points.map(\.value)
        return "\(points.count) plotted observations from \(first.date.formatted(date: .abbreviated, time: .shortened)) to \(last.date.formatted(date: .abbreviated, time: .shortened)); range \((values.min() ?? 0).formatted()) to \((values.max() ?? 0).formatted()). Missing intervals are not filled."
    }
}
#endif
