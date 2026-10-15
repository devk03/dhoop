#if os(iOS)
import SwiftUI
import StrandDesign

/// Shared command feedback. A committed receipt survives a later dashboard-read failure.
struct WorkoutFrontendSubmitSection: View {
    let title: String
    let action: String
    let revision: Int
    var lifecycle = false
    let command: () throws -> [String: WorkoutTrackerValue]
    let refresh: () async throws -> Void
    @ObservedObject private var client = WorkoutFrontendClient.shared
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var operationId: UUID?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            NoopAsyncButton(LocalizedStringKey(title), systemImage: "checkmark", fullWidth: true) {
                guard sameConnection else { throw WorkoutSyncTransportError.configuration }
                let id = try client.prepare(command: command(), revision: revision)
                operationId = id
                do { try await client.submit(id) }
                catch { message = "Input retained in pending changes. Recover its receipt before making another change."; throw error }
                message = "Saved in Life."
                do { try await refresh() }
                catch { message = "Saved in Life. The updated view could not be read; refresh it when connected." }
            }.disabled(operationId != nil || !sameConnection || !client.supports(action, lifecycle: lifecycle))
            if let message { Text(message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary).accessibilityAddTraits(.updatesFrequently) }
            if client.unresolved != nil || !client.state.enabled || client.state.capabilities == nil || !sameConnection {
                NavigationLink("Editing connection & pending changes") { WorkoutFrontendSettingsView() }
                    .buttonStyle(NoopButtonStyle(.secondary))
            }
            if operationId == nil && !client.supports(action, lifecycle: lifecycle) {
                Text("Editing needs a verified Life connection and no unresolved earlier change.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private var sameConnection: Bool {
        tracker.state.origin != nil && tracker.state.installationId != nil &&
            tracker.state.origin == client.state.origin && tracker.state.installationId == client.state.installationId
    }
}

struct WorkoutFrontendTextField: View {
    let title: String
    @Binding var text: String
    var numeric = false
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            TextField(title, text: $text).font(StrandFont.bodyNumber)
                .keyboardType(numeric ? .decimalPad : .default)
                .padding(NoopMetrics.space3).frame(minHeight: NoopMetrics.minimumTouchTarget)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
                .accessibilityLabel(title)
        }
    }
}

enum WorkoutFrontendInput {
    struct Invalid: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func number(_ text: String, label: String, range: ClosedRange<Double>, integer: Bool = false,
                       optional: Bool = false, scale: Double = 1) throws -> WorkoutTrackerValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if optional && trimmed.isEmpty { return .null }
        guard let value = try? Double(trimmed, format: .number.locale(.current)), value.isFinite,
              scale.isFinite, scale > 0, range.contains(value * scale), !integer || value.rounded() == value else {
            throw Invalid(message: "Enter a valid \(label).")
        }
        return .number(value * scale)
    }
    static func text(_ value: WorkoutTrackerValue?) -> String {
        guard let value else { return "" }
        switch value { case .number(let v): return v.formatted(.number.grouping(.never).precision(.fractionLength(0...8)))
        case .string(let v): return v
        default: return "" }
    }
}
#endif
