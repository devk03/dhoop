import SwiftUI
import Charts
import StrandDesign

struct WorkoutHeartRateCard: View {
    let points: [RunningTracePoint]
    let start: Date
    let end: Date
    var target: RunningZoneTarget? = nil
    let source: String
    var loading = false
    var interactive = true
    private var trace: [TrendPoint] {
        DashboardTraceSampling.reduce(points.map { TrendPoint(date: Date(timeIntervalSince1970: $0.timestamp), value: Double($0.bpm), segment: String($0.segment)) })
    }
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Heart rate").font(StrandFont.headline)
                if let target { Text("Target · \(target.rangeLabel)").font(StrandFont.caption).foregroundStyle(StrandPalette.metricPurple) }
                if loading { ProgressView("Reading stored heart rate…") }
                else if points.isEmpty {
                    Text("No recorded heart-rate trace for this workout.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    let lower = max(0, min(Double(points.map(\.bpm).min() ?? 30) - 10, Double(target?.lowerBPM ?? 220)))
                    let upper = max(lower + 1, Double(points.map(\.bpm).max() ?? 220) + 10, Double(target?.upperBPM ?? 0))
                    let singletons = Set(Dictionary(grouping: trace, by: \.segment).filter { $0.value.count == 1 }.keys)
                    let chart = Chart {
                        if let target {
                            RectangleMark(xStart: .value("Start", start), xEnd: .value("End", end),
                                yStart: .value("Lower target", target.lowerBPM), yEnd: .value("Upper target", target.upperBPM ?? Int(upper)))
                                .foregroundStyle(StrandPalette.metricPurple.opacity(StrandChartStyle.gridOpacity))
                        }
                        ForEach(trace) { point in
                            AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", lower), yEnd: .value("BPM", point.value), series: .value("Segment", point.segment))
                                .foregroundStyle(StrandChartStyle.area(StrandPalette.liquidHeart)).interpolationMethod(.linear).alignsMarkStylesWithPlotArea()
                            LineMark(x: .value("Time", point.date), y: .value("BPM", point.value), series: .value("Segment", point.segment))
                                .foregroundStyle(StrandPalette.liquidHeart).interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: StrandChartStyle.lineWidth, lineCap: .round))
                            if trace.count <= StrandChartStyle.sparsePointLimit || singletons.contains(point.segment) {
                                PointMark(x: .value("Time", point.date), y: .value("BPM", point.value))
                                    .foregroundStyle(StrandPalette.liquidHeart).symbolSize(StrandChartStyle.pointArea)
                            }
                        }
                    }
                    .chartXScale(domain: start...max(start.addingTimeInterval(1), end)).chartYScale(domain: lower...upper)
                    .chartXAxis { AxisMarks(values: [start, start.addingTimeInterval(end.timeIntervalSince(start) / 2), end]) { _ in AxisValueLabel(format: .dateTime.hour().minute()).font(StrandFont.caption) } }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(StrandChartStyle.gridOpacity))
                        AxisValueLabel().font(StrandFont.caption)
                    } }.chartLegend(.hidden).chartPlotStyle { $0.clipped() }.frame(height: NoopMetrics.dashboardTraceHeight)
                    if interactive {
                        chart.chartInspection(points.map { .init(id: String($0.timestamp), x: $0.timestamp, y: Double($0.bpm), value: "\($0.bpm) bpm", context: Date(timeIntervalSince1970: $0.timestamp).formatted(date: .omitted, time: .standard), series: "WHOOP", segment: String($0.segment)) }, label: "Workout heart rate", tint: StrandPalette.liquidHeart)
                    } else { chart }
                }
                Text(source).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}

struct WorkoutSharePreview: View {
    let title: String
    let start: Date
    let end: Date
    let duration: Double
    let average: Double?
    let peak: Int?
    let points: [RunningTracePoint]
    var target: RunningZoneTarget? = nil
    var inZone: Double? = nil
    let source: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?
    @State private var preparationFailed = false

    private var card: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            Text("Dhoop · \(title)").font(StrandFont.title2)
            Text(start.formatted(date: .abbreviated, time: .shortened)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: NoopMetrics.space4) { statistics }
                VStack(alignment: .leading, spacing: NoopMetrics.space3) { statistics }
            }
            if let inZone, let target {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("\(clock(inZone)) in target · \(target.rangeLabel)").font(StrandFont.subhead)
                    NoopProgressTrack(fraction: inZone / max(1, duration), tint: StrandPalette.metricPurple)
                }
            }
            WorkoutHeartRateCard(points: points, start: start, end: end, target: target, source: source, interactive: false)
        }.padding(NoopMetrics.space4).background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary)
    }
    @ViewBuilder private var statistics: some View {
        statistic("Duration", clock(duration))
        statistic("Average HR", average.map { "\(Int($0.rounded())) bpm" } ?? "Unavailable")
        statistic("Peak HR", peak.map { "\($0) bpm" } ?? "Unavailable")
    }
    private func statistic(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(value).font(StrandFont.headline).monospacedDigit()
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View { WorkoutShareSheet(title: title, content: card) }
    private func clock(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds)); return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Shared local-only preview/export shell. Publishing still requires the native share sheet.
struct WorkoutShareSheet<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: Image?
    @State private var preparationFailed = false
    var body: some View {
        NavigationStack {
            ScrollView { content.responsiveScrollTouches() }
                .background(StrandPalette.surfaceBase)
                .navigationTitle("Share preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    Group {
                        if let image {
                            ShareLink(item: image, preview: SharePreview(title, image: image)) {
                                Label("Share workout", systemImage: "square.and.arrow.up")
                            }.buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                        } else if preparationFailed {
                            Text("Could not prepare the image. Your workout is unchanged.").font(StrandFont.caption)
                        } else { ProgressView("Preparing preview…") }
                    }.padding(NoopMetrics.space3).background(StrandPalette.surfaceBase)
                }
                .task {
                    await Task.yield()
                    let renderer = ImageRenderer(content: content.frame(width: NoopMetrics.sharePreviewWidth).environment(\.colorScheme, colorScheme).dynamicTypeSize(.large))
                    renderer.scale = min(displayScale, 2)
                    if let value = renderer.uiImage { image = Image(uiImage: value) }
                    else { preparationFailed = true }
                }
        }
    }
}
