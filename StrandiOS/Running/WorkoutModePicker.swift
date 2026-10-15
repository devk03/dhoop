import SwiftUI
import StrandDesign

/// Compact native vector icons retain labels and full touch targets, including at large text sizes.
struct WorkoutModePicker: View {
    @Binding var selection: String
    @Environment(\.dynamicTypeSize) private var typeSize
    private let modes: [(String, String, String)] = [
        ("Strength", "Strength", "dumbbell"), ("Zone run", "BPM", "heart"),
        ("HIIT", "HIIT", "flame"), ("Intervals", "Intervals", "repeat"),
        ("Meditation", "Meditation", "figure.mind.and.body")]

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal) { HStack(spacing: NoopMetrics.space2) { buttons } }.scrollIndicators(.hidden)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoopMetrics.space1) { buttons }
                    ScrollView(.horizontal) { HStack(spacing: NoopMetrics.space1) { buttons } }.scrollIndicators(.hidden)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("Workout type")
    }
    private var buttons: some View {
        ForEach(modes, id: \.0) { value, label, icon in
            Button { selection = value } label: {
                VStack(spacing: NoopMetrics.space1) {
                    Image(systemName: icon).font(StrandFont.title2)
                    Text(label).font(StrandFont.caption).lineLimit(1).fixedSize()
                }
                .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                .padding(.vertical, NoopMetrics.space2)
                .padding(.horizontal, NoopMetrics.space1)
                .foregroundStyle(selection == value ? NoopVisualStyle.selectedControlInk : StrandPalette.textSecondary)
                .background(selection == value ? NoopVisualStyle.selectedControlFill : StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
            }.buttonStyle(NoopFeedbackButtonStyle()).accessibilityLabel(value == "Zone run" ? "Heart-rate target" : value)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
        }
    }
}
