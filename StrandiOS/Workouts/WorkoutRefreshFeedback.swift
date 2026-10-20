#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutRefreshFeedback: View {
    @ObservedObject var state: WorkoutRefreshController
    let retry: () async throws -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if state.busy {
                ProgressView("Refreshing workouts…").font(StrandFont.caption)
            } else if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                NoopAsyncButton("Retry", systemImage: "arrow.clockwise", kind: .secondary, action: retry)
            } else if let date = state.lastSuccess {
                Label("Updated \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }.accessibilityElement(children: .contain)
    }
}
#endif
