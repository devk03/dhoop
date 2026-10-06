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
    let compact: Bool
    let singletonSegments: Set<String>
    let inspectionData: [ChartScrubDatum]

    public init(points: [TrendPoint], domain: ClosedRange<Date>, range: ClosedRange<Double>, tint: Color,
                style: Style = .line, height: CGFloat = NoopMetrics.dashboardTrendHeight,
                label: String, dailyLabels: Bool = false, compact: Bool = false,
                valueFormat: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...2))) },
                inspectionData: [ChartScrubDatum]? = nil) {
        // Callers prepare chronological, gap-preserving display points once with their snapshot.
        self.points = points
        self.singletonSegments = Set(Dictionary(grouping: points, by: \.segment).filter { $0.value.count == 1 }.keys)
        self.domain = domain; self.range = range; self.tint = tint; self.style = style
        self.height = height; self.label = label; self.dailyLabels = dailyLabels
        self.compact = compact
        self.inspectionData = inspectionData ?? points.map {
            ChartScrubDatum(id: "\($0.segment)|\($0.date.timeIntervalSince1970)", x: $0.date.timeIntervalSince1970,
                y: $0.value, value: valueFormat($0.value),
                context: style == .bars || domain.upperBound.timeIntervalSince(domain.lowerBound) > 86_400
                    ? $0.date.formatted(date: .abbreviated, time: .omitted)
                    : $0.date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().second()),
                segment: $0.segment)
        }
    }

    public var body: some View {
        Chart {
            ForEach(points) { point in
                if style == .bars {
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                        .foregroundStyle(StrandChartStyle.bar(tint))
                        .cornerRadius(NoopMetrics.space1)
                } else {
                    AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", range.lowerBound),
                             yEnd: .value("Value", point.value), series: .value("Recorded run", point.segment))
                        .interpolationMethod(.linear).foregroundStyle(StrandChartStyle.area(tint))
                        .alignsMarkStylesWithPlotArea()
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value),
                             series: .value("Recorded run", point.segment))
                        .interpolationMethod(.linear).foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: StrandChartStyle.lineWidth, lineCap: .round, lineJoin: .round))
                    if points.count <= StrandChartStyle.sparsePointLimit || singletonSegments.contains(point.segment) {
                        PointMark(x: .value("Time", point.date), y: .value("Value", point.value))
                            .foregroundStyle(tint).symbolSize(StrandChartStyle.pointArea)
                    }
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: range)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            if !compact {
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
                                     ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(StrandChartStyle.gridOpacity))
                    AxisValueLabel().foregroundStyle(StrandPalette.textSecondary).font(StrandFont.caption)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(summary)
        .chartInspection(inspectionData, label: label, tint: tint, dailyBuckets: style == .bars, readoutBelow: compact)
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "No recorded data" }
        let values = points.map(\.value)
        return "\(points.count) plotted observations from \(first.date.formatted(date: .abbreviated, time: .shortened)) to \(last.date.formatted(date: .abbreviated, time: .shortened)); range \((values.min() ?? 0).formatted()) to \((values.max() ?? 0).formatted()). Missing intervals are not filled."
    }
}
#endif
