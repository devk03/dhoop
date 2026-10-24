import SwiftUI
import StrandDesign

/// Both rings describe the same selected wake date and the same duration goal.
struct SleepComparisonRings: View {
    let dateLabel: String
    let whoopMinutes: Double?
    let comparisonName: String
    let comparisonMinutes: Double?
    let whoopDetail: String?
    let comparisonDetail: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.sleepGoalNumber
    private var outsideLabels: Bool { typeSize >= .xxxLarge }
    var body: some View {
        NoopCard {
            VStack(spacing: NoopMetrics.space3) {
                Text(verbatim: dateLabel).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                ZStack {
                    ring(whoopMinutes, tint: StrandPalette.metricHRV)
                    ring(comparisonMinutes, tint: StrandPalette.metricSteps)
                        .padding(NoopMetrics.sleepComparisonRingInset)
                    if !outsideLabels {
                        readings.padding(NoopMetrics.sleepComparisonRingInset + NoopMetrics.space4)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: NoopMetrics.sleepComparisonDiameter)
                if outsideLabels { readings }
                Text("Goal · 8h 15m").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                if whoopDetail != nil || comparisonDetail != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: NoopMetrics.space4) { provenance }
                        VStack(spacing: NoopMetrics.space1) { provenance }
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }.frame(maxWidth: .infinity)
        }
    }
    private var readings: some View {
        VStack(spacing: NoopMetrics.space3) {
            reading("WHOOP", minutes: whoopMinutes, tint: StrandPalette.metricHRV)
            reading(comparisonName, minutes: comparisonMinutes, tint: StrandPalette.metricSteps)
        }
    }
    private func reading(_ name: String, minutes: Double?, tint: Color) -> some View {
        let goal = SleepDurationGoal(recordedMinutes: minutes)
        return VStack(spacing: NoopMetrics.spaceHalf) {
            HStack(spacing: NoopMetrics.space1) {
                Circle().fill(tint).frame(width: NoopMetrics.space2, height: NoopMetrics.space2).accessibilityHidden(true)
                Text(verbatim: name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            Text(goal.recordedMinutes.map(sleepHM) ?? String(localized: "No record"))
                .font(StrandFont.number(numberSize, weight: .semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityValue(Text(verbatim: goal.recordedMinutes.map(sleepHM) ?? String(localized: "No sleep duration recorded")))
    }
    private func ring(_ minutes: Double?, tint: Color) -> some View {
        let goal = SleepDurationGoal(recordedMinutes: minutes)
        return ZStack {
            Circle().stroke(StrandPalette.textTertiary.opacity(0.2), lineWidth: NoopMetrics.sleepComparisonStroke)
            Circle().trim(from: 0, to: goal.ringFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: NoopMetrics.sleepComparisonStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.padding(NoopMetrics.sleepComparisonStroke / 2).accessibilityHidden(true)
    }
    private func provenanceLabel(_ name: String, detail: String) -> Text {
        let label = name + " · " + NSLocalizedString(detail, comment: "Sleep duration provenance")
        return Text(verbatim: label)
    }
    @ViewBuilder private var provenance: some View {
        if let whoopDetail { provenanceLabel("WHOOP", detail: whoopDetail) }
        if let comparisonDetail { provenanceLabel(comparisonName, detail: comparisonDetail) }
    }
}
