#if os(iOS)
import SwiftUI
import StrandDesign

/// Shared row presentation; actions still use Life's immutable command receipts.
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var operation = NoopActionController()

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                : AnyLayout(HStackLayout(alignment: .center, spacing: NoopMetrics.space2))
            layout {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("\(number)").font(StrandFont.bodyNumber)
                    if kind != "work" { Text(kind.capitalized).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                }.frame(minWidth: NoopMetrics.minimumTouchTarget, alignment: .leading)
                if let loadUnit { field(loadUnit, hint: loadHint, text: $load, label: "Set \(number) actual weight in \(loadUnit)") }
                if let repsHint { field("Reps", hint: repsHint, text: $reps, label: "Set \(number) actual repetitions", integer: true) }
                Button { operation.submit(save) } label: {
                    Group {
                        if operation.state.isWorking { ProgressView().progressViewStyle(.circular) }
                        else { Image(systemName: completed && !dirty ? "checkmark.circle.fill" : "checkmark.circle") }
                    }.foregroundStyle(completed && !dirty ? StrandPalette.metricCyan : StrandPalette.textSecondary)
                }.buttonStyle(NoopIconButtonStyle()).disabled(operation.state.isWorking)
                    .accessibilityLabel(dirty ? "Save set \(number)" : completed ? "Mark set \(number) incomplete" : "Complete set \(number)")
                    .accessibilityValue(dirty ? "Unsaved changes" : completed ? "Saved in Life" : "Not completed")
            }
            if showRIR && repsHint != nil {
                field("RIR · optional", hint: "0–5", text: $rir, label: "Set \(number) repetitions in reserve", integer: true)
            }
        }.alert("Set not saved", isPresented: Binding(
            get: { if case .failed = operation.state { return true }; return false },
            set: { if !$0 { operation.reset() } })) {
                Button("OK", role: .cancel) { operation.reset() }
            } message: {
                if case .failed(let message) = operation.state { Text(message) }
            }
    }
    private func field(_ title: String, hint: String, text: Binding<String>, label: String, integer: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            if typeSize.isAccessibilitySize || title.hasPrefix("RIR") {
                Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            TextField(hint, text: text)
                .font(StrandFont.bodyNumber).keyboardType(integer ? .numberPad : .decimalPad)
                .padding(NoopMetrics.space2).frame(minHeight: NoopMetrics.minimumTouchTarget)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
                .accessibilityLabel(label)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
