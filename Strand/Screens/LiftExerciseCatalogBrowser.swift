import SwiftUI
import StrandDesign
import WhoopStore

struct LiftExerciseCatalogBrowser: View {
    @ObservedObject var catalog: LiftExerciseCatalogModel
    let deviceID: String
    let onPick: (LiftExerciseRow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var matches: [LiftExerciseRow] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.entries(for: deviceID).filter { text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) }
    }
    var body: some View {
        NavigationStack {
            ScreenScaffold(title: "Your exercises", subtitle: "Search every saved movement.") {
                if !catalog.isReady(for: deviceID) {
                    Text("The catalog is unavailable. Return to your draft and retry reading it.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                } else if matches.isEmpty {
                    Text(query.isEmpty ? "No saved exercises yet. Add a movement from your draft." : "No matching exercises. Your search is retained.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        ForEach(matches, id: \.id) { row in
                            Button {
                                guard catalog.isReady(for: deviceID), let current = catalog.entries(for: deviceID).first(where: { $0.id == row.id }) else { return }
                                onPick(current); dismiss()
                            } label: {
                                NoopCard { LiftExerciseSuggestionLabel(row: row) }
                            }.buttonStyle(NoopFeedbackButtonStyle())
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
