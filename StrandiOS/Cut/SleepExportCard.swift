import SwiftUI
import Charts
import StrandDesign

/// Code-rendered share artwork; the preview and exported image receive the same frozen snapshot.
struct SleepExportCard: View {
    let report: SleepExportReport
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSize = NoopMetrics.sleepGoalDiameter
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.sleepGoalNumber
    private var dateLabel: String {
        let formatter = DateFormatter(); formatter.locale = .current; formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: report.day)?.formatted(.dateTime.month(.wide).day().year()) ?? report.day
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack {
                Text("Dhoop").font(StrandFont.headline)
                Spacer(minLength: NoopMetrics.space2)
                Image(systemName: "moon.stars").font(StrandFont.title2).foregroundStyle(StrandPalette.metricPurple)
            }
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Sleep report").font(StrandFont.title1)
                Text("Wake date · \(dateLabel)").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: NoopMetrics.space3) { summaries }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: NoopMetrics.space3) { summaries }.fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: NoopMetrics.space3) { summaries }
                }
            }
            if let source = report.highlighted {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Sleep stages · \(source.name)").font(StrandFont.headline).fixedSize(horizontal: false, vertical: true)
                        if let timeline = source.timeline, !timeline.intervals.isEmpty {
                            chart(timeline)
                            Text("\(clock(timeline.start))–\(clock(timeline.end)) · selected sleep period")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            Text(timeline.method).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            Text("Gaps have no readings.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No timestamped stages available").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                stageSummary(source)
            }
            let metrics = report.sources.filter(\.hasMetrics)
            ForEach(metrics.isEmpty ? Array(report.sources.filter { $0.id == report.selectedSource }.prefix(1)) : metrics) { source in
                heartSummary(source)
            }
            Text("Wake-date totals may include more than one sleep period. Duration goal · \(SleepExportReport.duration(report.goalMinutes)).")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("Sources: \(report.sources.map { "\($0.name) · \($0.method)" }.joined(separator: "; ")).")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("Stage estimates are not a medical assessment.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(NoopMetrics.space4).background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary)
        .environment(\.colorScheme, .dark)
    }
    @ViewBuilder private var summaries: some View {
        ForEach(report.sources) { source in
            let fraction = source.totalMinutes.map { $0 / max(1, report.goalMinutes) }
            let tint = source.id == "whoop" ? StrandChartStyle.stageDeep : StrandPalette.metricPurple
            NoopCard(padding: NoopMetrics.space3, fillHeight: true) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(source.name).font(StrandFont.headline)
                    ZStack {
                        Circle().stroke(StrandPalette.hairline, lineWidth: NoopMetrics.sleepGoalStroke)
                        Circle().trim(from: 0, to: min(1, max(0, fraction ?? 0)))
                            .stroke(tint, style: StrokeStyle(lineWidth: NoopMetrics.sleepGoalStroke, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: NoopMetrics.space1) {
                            Text(source.totalMinutes.map { SleepExportReport.duration($0) } ?? "—")
                                .font(StrandFont.number(numberSize, weight: .semibold)).monospacedDigit()
                            Text("Total sleep").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }.frame(width: ringSize, height: ringSize).frame(maxWidth: .infinity)
                    Text(fraction.map { "\(($0 * 100).rounded().formatted(.number.precision(.fractionLength(0))))% of duration goal" } ?? "No record for this date")
                        .font(StrandFont.caption).foregroundStyle(tint)
                    if source.totalMinutes != nil { Text(source.method).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: ringSize)
            }
        }
    }
    private func stageSummary(_ source: SleepExportReport.Source) -> some View {
        let values = Array(zip(["deep", "rem", "core", "unspecified"], source.stages))
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Stage totals · \(source.name)").font(StrandFont.headline).fixedSize(horizontal: false, vertical: true)
                if typeSize.isAccessibilitySize {
                    ForEach(values.indices, id: \.self) { index in stageCell(values[index], total: source.totalMinutes) }
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: NoopMetrics.space3, verticalSpacing: NoopMetrics.space3) {
                        ForEach(Array(stride(from: 0, to: values.count, by: 2)), id: \.self) { index in
                            GridRow {
                                stageCell(values[index], total: source.totalMinutes)
                                if index + 1 < values.count { stageCell(values[index + 1], total: source.totalMinutes) }
                            }
                        }
                    }
                }
            }
        }
    }
    private func stageCell(_ value: (String, Double?), total: Double?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(stageName(value.0)).font(StrandFont.caption).foregroundStyle(stageColor(value.0))
            Text(SleepExportReport.duration(value.1)).font(StrandFont.headline).monospacedDigit()
            if let minutes = value.1, let total, total > 0, minutes <= total {
                NoopProgressTrack(fraction: minutes / total, tint: stageColor(value.0))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func heartSummary(_ source: SleepExportReport.Source) -> some View {
        let values = source.metrics + [.init(title: "Snoring time", value: nil, unit: "min", detail: "")]
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Nightly stats · \(source.name)").font(StrandFont.headline).fixedSize(horizontal: false, vertical: true)
                if typeSize.isAccessibilitySize {
                    ForEach(values) { metricCell($0) }
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: NoopMetrics.space3, verticalSpacing: NoopMetrics.space3) {
                        ForEach(Array(stride(from: 0, to: values.count, by: 2)), id: \.self) { index in
                            GridRow {
                                metricCell(values[index])
                                if index + 1 < values.count { metricCell(values[index + 1]) }
                            }
                        }
                    }
                }
            }
        }
    }
    private func metricCell(_ metric: SleepExportReport.Metric) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(metric.title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(metric.title == "Snoring time" ? "Not collected" : metric.text).font(StrandFont.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if !metric.detail.isEmpty { Text(metric.detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
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
        .chartXAxis { AxisMarks(values: typeSize.isAccessibilitySize ? [] : [timeline.start, (timeline.start + timeline.end) / 2, timeline.end].map { Date(timeIntervalSince1970: $0) }) { _ in AxisValueLabel(format: .dateTime.hour().minute()).font(StrandFont.caption) } }
        .chartYAxis { AxisMarks(position: .leading, values: unknown ? [0, 1, 2, 3, 4] : [1, 2, 3, 4]) { value in
            AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(StrandChartStyle.gridOpacity))
            AxisValueLabel { if let level = value.as(Int.self) { Text(["Unclassified", "Deep", "Light", "REM", "Awake"][level]).font(StrandFont.caption) } }
        } }.chartLegend(.hidden).frame(height: typeSize.isAccessibilitySize ? NoopMetrics.dashboardTraceHeight * 2 : NoopMetrics.dashboardTraceHeight)
        .accessibilityLabel("Recorded sleep stages with gaps preserved")
    }
    private func clock(_ ts: Double) -> String { Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened) }
    private func level(_ stage: String) -> Double { switch stage { case "awake": return 4; case "rem": return 3; case "core": return 2; case "deep": return 1; default: return 0 } }
    private func stageName(_ stage: String) -> String { switch stage { case "awake": return "Awake"; case "rem": return "REM"; case "core": return "Light"; case "deep": return "Deep"; default: return "Unclassified" } }
    private func stageColor(_ stage: String) -> Color { switch stage { case "awake": return StrandChartStyle.stageAwake; case "rem": return StrandChartStyle.stageREM; case "core": return StrandChartStyle.stageLight; case "deep": return StrandChartStyle.stageDeep; default: return StrandPalette.textTertiary } }
}
