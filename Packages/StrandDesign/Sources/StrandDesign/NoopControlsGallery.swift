import SwiftUI

#if DEBUG
/// Interactive reference for checking shared states, accessibility and geometry.
public struct NoopControlsGallery: View {
    @State private var selection = "Day"
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text("Controls").font(StrandFont.title1)
                Text("Hold a control to inspect its pressed state.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NoopButton("Primary action", systemImage: "checkmark", fullWidth: true) {}
                NoopButton("Secondary action", kind: .secondary, fullWidth: true) {}
                NoopButton("Delete recording", systemImage: "trash", kind: .destructive, fullWidth: true) {}
                NoopButton("Disabled action", fullWidth: true) {}.disabled(true)
                NoopActionButton("Save changes", fullWidth: true, state: .working) {}
                NoopActionButton("Save changes", fullWidth: true, state: .succeeded) {}
                NoopActionButton("Save changes", fullWidth: true, state: .failed("Storage unavailable")) {}
                HStack(spacing: NoopMetrics.space3) {
                    Button {} label: { Image(systemName: "pencil") }
                        .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Edit")
                    Button(role: .destructive) {} label: { Image(systemName: "trash") }
                        .buttonStyle(NoopIconButtonStyle()).accessibilityLabel("Delete")
                }
                NoopSegmentedControl("Range", options: ["Day", "Week", "Month", "Year"], selection: $selection)
            }
            .screenPadding()
            .padding(.vertical, NoopMetrics.space4)
        }
        .background(StrandPalette.surfaceBase)
    }
}

#Preview("Shared control states") { NoopControlsGallery().frame(width: 390, height: 850) }
#endif
