#if os(iOS)
import SwiftUI
import StrandDesign

/// Shared row presentation with immediate local checkmarks and visible touch feedback.
struct WorkoutSetEntryRow: View {
    let number: Int
    let kind: String
    let loadUnit: String?
    let loadHint: String
    let repsHint: String?
    let completed: Bool
    let dirty: Bool
    let showRIR: Bool
    @Binding var load: String
    @Binding var reps: String
    @Binding var rir: String
    let save: () async throws -> Void
    var editingEnabled = true
    var showHistory: (() -> Void)? = nil
    var savedLocally = false
    var showColumnLabels = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var operation = NoopActionController()

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize { entryLayout(inlineRIR: true) }
                entryLayout(inlineRIR: false)
            }
        }.alert("Set not saved", isPresented: Binding(
            get: { if case .failed = operation.state { return true }; return false },
            set: { if !$0 { operation.reset() } })) {
                Button("OK", role: .cancel) { operation.reset() }
            } message: {
                if case .failed(let message) = operation.state { Text(message) }
            }
    }
    private func entryLayout(inlineRIR: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                : AnyLayout(HStackLayout(alignment: .center, spacing: NoopMetrics.space2))
            layout {
                if let showHistory {
                    Button(action: showHistory) {
                        HStack(spacing: NoopMetrics.space1) {
                            Image(systemName: "info.circle").font(StrandFont.caption).foregroundStyle(StrandPalette.metricCyan)
                            setLabel
                        }
                    }.buttonStyle(NoopIconButtonStyle())
                        .accessibilityLabel("Last week's results for set \(number)")
                        .accessibilityHint("Shows recorded weight and repetitions without changing this set")
                } else { setLabel.frame(minWidth: NoopMetrics.minimumTouchTarget, alignment: .leading) }
                if let loadUnit { field(loadUnit, hint: loadHint, text: $load, label: "Set \(number) actual weight in \(loadUnit)") }
                if let repsHint { field("Reps", hint: repsHint, text: $reps, label: "Set \(number) actual repetitions", integer: true) }
                if inlineRIR && showRIR && repsHint != nil {
                    field("RIR", hint: "—", text: $rir, label: "Set \(number) repetitions in reserve", integer: true)
                }
                VStack(spacing: NoopMetrics.space1) {
                    if showColumnLabels { Text("Done").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                    Button { operation.submit(save) } label: {
                    Group {
                        if operation.state.isWorking { ProgressView().progressViewStyle(.circular) }
                        else { Image(systemName: completed && !dirty ? "checkmark.circle.fill" : "circle") }
                    }.foregroundStyle(completed && !dirty ? StrandPalette.metricCyan : StrandPalette.textSecondary)
                }.buttonStyle(NoopIconButtonStyle()).disabled(!editingEnabled || operation.state.isWorking)
                    .accessibilityLabel(dirty ? "Save set \(number)" : completed ? "Mark set \(number) incomplete" : "Complete set \(number)")
                    .accessibilityValue(dirty ? "Unsaved changes" : completed ? (savedLocally ? "Saved on this phone" : "Saved in Life") : "Not completed")
                }
            }
            if !inlineRIR && showRIR && repsHint != nil {
                field("RIR · optional", hint: "0–5", text: $rir, label: "Set \(number) repetitions in reserve", integer: true)
            }
        }
    }
    private var setLabel: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            if showColumnLabels { Text("Set").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            Text("\(number)").font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
            if kind != "work" { Text(kind.capitalized).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
        }
    }
    private func field(_ title: String, hint: String, text: Binding<String>, label: String, integer: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            if typeSize.isAccessibilitySize || showColumnLabels || title == "RIR · optional" {
                Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            TextField(hint, text: text)
                .font(StrandFont.bodyNumber).keyboardType(integer ? .numberPad : .decimalPad)
                .padding(NoopMetrics.space2).frame(minHeight: NoopMetrics.minimumTouchTarget)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
                .accessibilityLabel(label)
                .disabled(!editingEnabled)
        }.frame(minWidth: NoopMetrics.minimumTouchTarget + NoopMetrics.space6,
                idealWidth: NoopMetrics.minimumTouchTarget + NoopMetrics.space6, maxWidth: .infinity, alignment: .leading)
    }
}

#endif
