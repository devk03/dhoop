import SwiftUI
import Charts
import StrandDesign

/// Compact artwork from the same immutable snapshot as the preview; diagnostics stay in the app.
struct SleepExportCard: View {
    let report: SleepExportReport
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSize = NoopMetrics.sleepGoalDiameter
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.sleepGoalNumber
    private var dateLabel: String {
        let formatter = DateFormatter(); formatter.locale = .current; formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: report.day)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? report.day
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep").font(StrandFont.title1)
                Spacer(minLength: NoopMetrics.space2)
                Text(dateLabel).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            NoopCard(padding: NoopMetrics.space3) {
                VStack(spacing: NoopMetrics.space3) {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: NoopMetrics.space4))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space3))
                    layout { ForEach(report.sources) { summary($0) } }
                    Text("Duration goal · \(SleepExportReport.duration(report.goalMinutes))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            if let source = report.highlighted { stageSummary(source) }
            if !report.shareMetricTitles.isEmpty { heartSummary }
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                HStack {
                    Text("Dhoop").font(StrandFont.caption)
                    Spacer(minLength: NoopMetrics.space2)
                    Text("Totals by wake date").font(StrandFont.caption)
                }
                Text(provenance).font(StrandFont.caption).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(StrandPalette.textTertiary)
        }.padding(NoopMetrics.space4)
            .background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary)
            .environment(\.colorScheme, .dark)
    }
    private func summary(_ source: SleepExportReport.Source) -> some View {
        let fraction = source.totalMinutes.map { $0 / max(1, report.goalMinutes) }
        let tint = source.id == "whoop" ? StrandChartStyle.stageDeep : StrandPalette.metricPurple
        return VStack(spacing: NoopMetrics.space2) {
            Text(source.name).font(StrandFont.headline)
            ZStack {
                Circle().stroke(StrandPalette.hairline, lineWidth: NoopMetrics.sleepGoalStroke)
                Circle().trim(from: 0, to: min(1, max(0, fraction ?? 0)))
                    .stroke(tint, style: StrokeStyle(lineWidth: NoopMetrics.sleepGoalStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: NoopMetrics.space1) {
                    Text(source.totalMinutes.map { SleepExportReport.duration($0) } ?? "—")
                        .font(StrandFont.number(numberSize, weight: .semibold)).monospacedDigit()
                    Text(fraction.map { "\(($0 * 100).rounded().formatted(.number.precision(.fractionLength(0))))%" } ?? "No record")
                        .font(StrandFont.captionNumber).foregroundStyle(tint)
                }
            }.frame(width: ringSize, height: ringSize)
        }.frame(maxWidth: .infinity)
    }
    private func stageSummary(_ source: SleepExportReport.Source) -> some View {
        let values = Array(zip(["deep", "rem", "core", "unspecified"], source.stages)).filter { $0.1 != nil }
        return NoopCard(padding: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Stages · \(source.name)").font(StrandFont.headline)
                if let timeline = source.timeline, !timeline.intervals.isEmpty {
                    chart(timeline)
                    Text("\(clock(timeline.start))–\(clock(timeline.end))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text("No timestamped stages available").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if !values.isEmpty {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            ForEach(values.indices, id: \.self) { stageCell(values[$0]) }
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: NoopMetrics.space3) {
                                ForEach(values.indices, id: \.self) { stageCell(values[$0]).fixedSize(horizontal: true, vertical: true) }
                            }
                            Grid(alignment: .topLeading, horizontalSpacing: NoopMetrics.space3, verticalSpacing: NoopMetrics.space2) {
                                ForEach(Array(stride(from: 0, to: values.count, by: 2)), id: \.self) { index in
                                    GridRow {
                                        stageCell(values[index])
                                        if index + 1 < values.count { stageCell(values[index + 1]) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private func stageCell(_ value: (String, Double?)) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(stageName(value.0)).font(StrandFont.caption).foregroundStyle(stageColor(value.0))
            Text(SleepExportReport.duration(value.1)).font(StrandFont.bodyNumber)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heartSummary: some View {
        NoopCard(padding: NoopMetrics.space3) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    ForEach(report.shareMetricTitles, id: \.self) { title in
                        Text(shortTitle(title)).font(StrandFont.headline)
                        ForEach(report.sources) { source in
                            if let metric = source.metrics.first(where: { $0.title == title && $0.isReadable }) {
                                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                    Text(source.name).font(StrandFont.caption)
                                    metricCell(metric)
                                }
                            }
                        }
                    }
                }
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: NoopMetrics.space3, verticalSpacing: NoopMetrics.space2) {
                    GridRow {
                        Text("Heart").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        ForEach(report.sources) { source in Text(source.name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    }
                    ForEach(report.shareMetricTitles, id: \.self) { title in
                        GridRow {
                            Text(shortTitle(title)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            ForEach(report.sources) { source in metricCell(source.metrics.first { $0.title == title && $0.isReadable }) }
                        }
                    }
                }
            }
        }
    }
    private func metricCell(_ metric: SleepExportReport.Metric?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(metric?.text ?? "—").font(StrandFont.bodyNumber).fixedSize(horizontal: false, vertical: true)
            if let qualifier = metric?.shareQualifier {
                Text(qualifier).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var provenance: String {
        report.sources.filter { $0.totalMinutes != nil || $0.timeline != nil || $0.hasMetrics }.map { source in
            source.id == "comparison" && source.method.contains("Apple Health")
                ? "\(source.name) via Apple Health" : "\(source.name) · \(source.method)"
        }.joined(separator: " · ")
    }
    private func shortTitle(_ title: String) -> String { title == "Average HR" ? "Avg HR" : title }
    private func chart(_ timeline: SleepExportReport.Timeline) -> some View {
        let unknown = timeline.intervals.contains { $0.stage == "unspecified" }
        return Chart {
            ForEach(Array(timeline.intervals.enumerated()), id: \.element.id) { index, interval in
                if index > 0, timeline.intervals[index - 1].end == interval.start,
                   timeline.intervals[index - 1].stage != interval.stage {
                    RuleMark(x: .value("Transition", Date(timeIntervalSince1970: interval.start)),
                        yStart: .value("Previous", level(timeline.intervals[index - 1].stage)), yEnd: .value("Next", level(interval.stage)))
                        .foregroundStyle(stageColor(interval.stage).opacity(StrandChartStyle.gridOpacity))
                }
                RectangleMark(xStart: .value("Start", Date(timeIntervalSince1970: interval.start)), xEnd: .value("End", Date(timeIntervalSince1970: interval.end)),
                    yStart: .value("Lower", level(interval.stage) - 0.32), yEnd: .value("Upper", level(interval.stage) + 0.32))
                    .foregroundStyle(stageColor(interval.stage)).cornerRadius(NoopMetrics.spaceHalf)
            }
        }
        .chartXScale(domain: Date(timeIntervalSince1970: timeline.start)...Date(timeIntervalSince1970: timeline.end))
        .chartYScale(domain: (unknown ? -0.5 : 0.5)...4.5)
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .leading, values: unknown ? [0, 1, 2, 3, 4] : [1, 2, 3, 4]) { value in
            AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(StrandChartStyle.gridOpacity))
            AxisValueLabel { if let level = value.as(Int.self) { Text(["Unclassified", "Deep", "Light", "REM", "Awake"][level]).font(StrandFont.caption) } }
        } }.chartLegend(.hidden)
            .frame(height: typeSize.isAccessibilitySize ? NoopMetrics.dashboardTraceHeight * 2 : NoopMetrics.dashboardHeartChartHeight)
            .accessibilityLabel("Recorded sleep stages with gaps preserved")
    }
    private func clock(_ ts: Double) -> String { Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened) }
    private func level(_ stage: String) -> Double { switch stage { case "awake": return 4; case "rem": return 3; case "core": return 2; case "deep": return 1; default: return 0 } }
    private func stageName(_ stage: String) -> String { switch stage { case "awake": return "Awake"; case "rem": return "REM"; case "core": return "Light"; case "deep": return "Deep"; default: return "Unclassified" } }
    private func stageColor(_ stage: String) -> Color { switch stage { case "awake": return StrandChartStyle.stageAwake; case "rem": return StrandChartStyle.stageREM; case "core": return StrandChartStyle.stageLight; case "deep": return StrandChartStyle.stageDeep; default: return StrandPalette.textTertiary } }
}
