import SwiftUI
import StrandDesign

/// One date-range interaction shared by metric, protein, sleep and Cardio history screens.
struct MetricRangeControl: View {
    @Binding var selection: MetricRangeSelection
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NoopMetrics.space1) {
                            ForEach(MetricRangeSelection.Preset.allCases) { preset in
                                Button { selection.preset = preset } label: {
                                    Text(preset.shortTitle).font(StrandFont.subhead).fixedSize()
                                        .padding(.horizontal, NoopMetrics.space3)
                                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                                        .foregroundStyle(selection.preset == preset ? NoopVisualStyle.selectedControlInk : StrandPalette.textSecondary)
                                        .background(selection.preset == preset ? NoopVisualStyle.selectedControlFill : .clear, in: Capsule())
                                }
                                .buttonStyle(.plain).id(preset)
                                .accessibilityLabel(preset.title)
                                .accessibilityAddTraits(selection.preset == preset ? .isSelected : [])
                            }
                        }
                    }
                    .padding(NoopMetrics.space1)
                    .background(StrandPalette.surfaceInset, in: Capsule())
                    .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                    .onAppear { proxy.scrollTo(selection.preset, anchor: .center) }
                    .onChange(of: selection.preset) { _, value in proxy.scrollTo(value, anchor: .center) }
                }
                if selection.preset == .custom {
                    DisclosureGroup("Custom date range") {
                    DatePicker("From", selection: $selection.customStart, in: ...min(selection.customEnd, now), displayedComponents: .date)
                    DatePicker("Through", selection: $selection.customEnd, in: min(selection.customStart, now)...now, displayedComponents: .date)
                    }.font(StrandFont.subhead)
                }
                if selection.window(now: now).isSingleDay {
                    HStack(spacing: NoopMetrics.space2) {
                        Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous day")
                        Spacer(minLength: NoopMetrics.space1)
                        DatePicker("Day", selection: Binding(get: { selection.window(now: now).start },
                            set: { selection.selectDay($0, now: now) }), in: ...now, displayedComponents: .date)
                            .labelsHidden().accessibilityLabel("Selected day")
                        Spacer(minLength: NoopMetrics.space1)
                        Button { moveDay(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Next day")
                            .disabled(Calendar.current.isDate(selection.window(now: now).start, inSameDayAs: now))
                    }.buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                if !selection.window(now: now).isSingleDay {
                    Text(selection.window(now: now).label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
    }
    private func moveDay(_ offset: Int) {
        let date = selection.window(now: now).start
        if let next = Calendar.current.date(byAdding: .day, value: offset, to: date) {
            selection.selectDay(next, now: now)
        }
    }
}
