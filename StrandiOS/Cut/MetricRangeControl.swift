import SwiftUI
import StrandDesign

/// One date-range interaction shared by metric, protein, sleep and Cardio history screens.
struct MetricRangeControl: View {
    @Binding var selection: MetricRangeSelection
    let now: Date
    var body: some View {
        NoopCard(padding: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NoopMetrics.space1) {
                            ForEach(MetricRangeSelection.Preset.allCases) { preset in
                                Button { selection.preset = preset } label: {
                                    Text(preset.shortTitle).font(StrandFont.subhead).fixedSize()
                                        .padding(.horizontal, NoopMetrics.space3)
                                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                                        .foregroundStyle(selection.preset == preset ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                                        .background(selection.preset == preset ? StrandPalette.surfaceRaised : .clear, in: Capsule())
                                }
                                .buttonStyle(.plain).id(preset)
                                .accessibilityLabel(preset.title)
                                .accessibilityAddTraits(selection.preset == preset ? .isSelected : [])
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(selection.preset, anchor: .center) }
                    .onChange(of: selection.preset) { _, value in proxy.scrollTo(value, anchor: .center) }
                }
                if selection.preset == .custom {
                    DatePicker("From", selection: $selection.customStart, in: ...min(selection.customEnd, now), displayedComponents: .date)
                    DatePicker("Through", selection: $selection.customEnd, in: min(selection.customStart, now)...now, displayedComponents: .date)
                }
                Text(selection.window(now: now).label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
