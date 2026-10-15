import SwiftUI
import StrandDesign

struct StrengthWorkoutCard: View {
    let title: String
    let scheduledLabel: String
    let summary: String
    var prominent = true
    var openTitle = "View workout"
    let open: () -> Void
    var schedule: (() -> Void)? = nil
    var body: some View {
        NoopCard(tint: prominent ? StrandPalette.metricPurple : nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                if prominent { header }
                else { Button(action: open) { header }.buttonStyle(NoopFeedbackButtonStyle()) }
                if prominent {
                    Button(action: open) { Label(openTitle, systemImage: "chevron.right") }
                        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                }
                if let schedule {
                    Button(action: schedule) { Label(prominent ? "Schedule workout" : "Schedule", systemImage: "calendar.badge.plus") }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: prominent))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space3) {
            Image(systemName: "dumbbell.fill").font(StrandFont.number(NoopMetrics.dashboardTileNumber)).foregroundStyle(StrandPalette.metricPurple)
                .frame(width: NoopMetrics.minimumTouchTarget, height: NoopMetrics.minimumTouchTarget)
                .background(StrandPalette.metricPurple.opacity(0.15), in: RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text(title).font(prominent ? StrandFont.title2 : StrandFont.headline)
                Text(scheduledLabel).font(StrandFont.subhead).foregroundStyle(prominent ? StrandPalette.metricSteps : StrandPalette.textSecondary)
                Text(summary).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !prominent { Image(systemName: "chevron.right").font(StrandFont.caption) }
        }.accessibilityElement(children: .combine)
    }
}
