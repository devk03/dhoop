import SwiftUI

/// A stable label with a reserved state region. Work never changes the control's geometry.
public struct NoopActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let kind: NoopButtonKind
    let fullWidth: Bool
    let state: NoopActionState
    let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String? = nil,
                kind: NoopButtonKind = .primary, fullWidth: Bool = false,
                state: NoopActionState = .idle, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.kind = kind
        self.fullWidth = fullWidth; self.state = state; self.action = action
    }

    public var body: some View {
        Button(role: kind.role, action: action) {
            HStack(spacing: NoopButtonMetrics.iconSpacing) {
                ZStack {
                    if state.isWorking {
                        ProgressView().progressViewStyle(.circular)
                            .tint(NoopButtonAppearance(kind).label)
                    } else if let icon {
                        Image(systemName: icon)
                    }
                }
                .frame(width: NoopButtonMetrics.stateWidth, height: NoopButtonMetrics.stateWidth)
                .accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(NoopButtonStyle(kind, fullWidth: fullWidth, isPending: state.isWorking))
        .disabled(state.isWorking)
        .accessibilityValue(value)
    }

    private var icon: String? {
        switch state {
        case .idle: return systemImage
        case .working: return nil
        case .succeeded: return "checkmark"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var value: Text {
        switch state {
        case .idle: return Text("")
        case .working: return Text("In progress")
        case .succeeded: return Text("Completed")
        case .failed(let message): return Text("Failed: \(message)")
        }
    }
}

/// Convenience for throwing asynchronous actions. Input remains owned by the containing screen.
@MainActor
public struct NoopAsyncButton: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let kind: NoopButtonKind
    let fullWidth: Bool
    let action: @MainActor () async throws -> Void
    @StateObject private var operation = NoopActionController()

    public init(_ title: LocalizedStringKey, systemImage: String? = nil,
                kind: NoopButtonKind = .primary, fullWidth: Bool = false,
                action: @escaping @MainActor () async throws -> Void) {
        self.title = title; self.systemImage = systemImage; self.kind = kind
        self.fullWidth = fullWidth; self.action = action
    }

    public var body: some View {
        NoopActionButton(title, systemImage: systemImage, kind: kind, fullWidth: fullWidth,
                         state: operation.state) {
            Task { await operation.run(action) }
        }
        .alert("Action failed", isPresented: Binding(
            get: { if case .failed = operation.state { return true }; return false },
            set: { if !$0 { operation.reset() } })) {
                Button("OK", role: .cancel) { operation.reset() }
        } message: {
            if case .failed(let message) = operation.state { Text(message) }
        }
    }
}
