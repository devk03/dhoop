#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutPreviousSetContent: View {
    let report: WorkoutPreviousSetReport

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text(report.exerciseName).font(StrandFont.title2)
                Text(report.weekLabel).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text(report.setLabel).font(StrandFont.headline)
                    if let result = report.result {
                        Text(result).font(StrandFont.title1).foregroundStyle(StrandPalette.metricCyan)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail = report.loadDetail { Text(detail).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary) }
                    if let rir = report.rirLabel { Text(rir).font(StrandFont.subhead).foregroundStyle(StrandPalette.metricPurple) }
                    if let unavailable = report.unavailable { Text(unavailable).font(StrandFont.body) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let title = report.workoutTitle {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label(title, systemImage: "calendar").font(StrandFont.headline)
                    if let date = report.dateLabel { Text(date).font(StrandFont.subhead) }
                    if let completed = report.completionLabel { Text(completed).font(StrandFont.caption) }
                }.foregroundStyle(StrandPalette.textSecondary)
            }
            Label("Recorded in Life", systemImage: "checkmark.shield")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(StrandPalette.textPrimary)
    }
}
#endif
