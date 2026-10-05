import SwiftUI
import StrandDesign

struct MetricRangeControl: View {
    @Binding var selection: MetricRangeSelection
    let now: Date
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Picker("Time range", selection: $selection.preset) {
                    ForEach(MetricRangeSelection.Preset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).font(StrandFont.subhead)
                .frame(minHeight: NoopMetrics.minimumTouchTarget)
                if selection.preset == .custom {
                    DatePicker("From", selection: $selection.customStart, in: ...min(selection.customEnd, now), displayedComponents: .date)
                    DatePicker("Through", selection: $selection.customEnd, in: min(selection.customStart, now)...now, displayedComponents: .date)
                }
                Text(selection.window(now: now).label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}
