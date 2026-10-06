import SwiftUI

/// One quiet, accessible selection treatment for the app's small sets of screen modes.
public struct NoopSegmentedControl: View {
    let title: String
    let options: [String]
    let labels: [String: String]
    @Binding var selection: String
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ title: String, options: [String], selection: Binding<String>, labels: [String: String] = [:]) {
        self.title = title; self.options = options; self._selection = selection; self.labels = labels
    }

    public var body: some View {
        Group {
            if typeSize >= .xxLarge {
                ScrollView(.horizontal, showsIndicators: false) { choices }
            } else {
                choices
            }
        }
        .padding(NoopMetrics.space1)
        .background(StrandPalette.surfaceInset, in: Capsule())
        .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }

    private var choices: some View {
        HStack(spacing: NoopMetrics.space1) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(labels[option] ?? option).font(StrandFont.subhead).fixedSize()
                        .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget)
                        .padding(.horizontal, options.count > 3 ? NoopMetrics.space1 : NoopMetrics.space2)
                        .foregroundStyle(selection == option ? NoopVisualStyle.selectedControlInk : StrandPalette.textSecondary)
                        .background(selection == option ? NoopVisualStyle.selectedControlFill : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}
