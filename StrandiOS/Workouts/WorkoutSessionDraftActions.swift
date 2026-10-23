#if os(iOS)
import SwiftUI
import StrandDesign

/// Only workout-level actions schedule delivery. Set rows remain responsive while this runs.
struct WorkoutSessionDraftActions: View {
    @ObservedObject var drafts: WorkoutSessionDraftController
    @ObservedObject var frontend: WorkoutFrontendClient
    var enabled = true
    let refresh: () async throws -> WorkoutSessionDraft.Remote
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var error: String?
    private var canFinish: Bool {
        !drafts.state.baseline.scheduledDate.isEmpty && ["planned", "in_progress"].contains(drafts.state.baseline.status)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if let message = drafts.message {
                HStack(spacing: NoopMetrics.space2) {
                    if drafts.working || drafts.checkingLatest { ProgressView().controlSize(.small) }
                    Text(LocalizedStringKey(message)).font(StrandFont.caption).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(StrandPalette.textSecondary).accessibilityAddTraits(.updatesFrequently)
            } else if drafts.state.hasChanges {
                Label("Saved on this phone", systemImage: "iphone").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if drafts.storageUnavailable {
                if drafts.canRetryLocalStorage {
                    Button("Retry local save") { drafts.retryLocalStorage() }.buttonStyle(NoopButtonStyle(.secondary))
                }
            } else if let pending = drafts.state.pending {
                if frontend.state.operations.first(where: { $0.id == pending.id })?.state == .rejected {
                    NoopAsyncButton("Review rejected save", systemImage: "arrow.clockwise", kind: .secondary) {
                        let latest = try await refresh(); try drafts.receive(latest); try drafts.reviewRejected()
                    }.disabled(drafts.working || !enabled)
                } else if !drafts.working {
                    Button("Retry sync") { drafts.setRefresh(refresh); drafts.resume() }.buttonStyle(NoopButtonStyle(.secondary)).disabled(!enabled)
                }
                if drafts.state.finishQueued {
                    Button("Cancel queued finish") { perform { try drafts.cancelQueuedFinish() } }
                        .buttonStyle(NoopButtonStyle(.secondary))
                }
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
            layout {
                Button("Save workout") { save(finishing: false) }
                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                    .disabled(!enabled || drafts.checkingLatest || !drafts.canSend || !drafts.state.hasChanges || drafts.state.pending != nil)
                if drafts.state.baseline.status != "completed" {
                    Button(drafts.state.finishQueued ? "Finish queued" : "Finish workout") {
                        save(finishing: true)
                    }.buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                        .disabled(!enabled || drafts.checkingLatest || !drafts.canSend || !canFinish || drafts.state.finishQueued || drafts.state.pending?.finishing == true || frontend.state.capabilities?.sessionCompletion != true)
                }
            }
            if frontend.state.capabilities?.sessionBatchSave != true {
                Text("Workout batch saving needs an updated Life connection. Your edits remain on this phone.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(NoopMetrics.space3).background(StrandPalette.surfaceBase)
        .alert("Workout not sent", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { if let error { Text(LocalizedStringKey(error)) } }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { self.error = error.localizedDescription }
    }
    private func save(finishing: Bool) {
        Task { @MainActor in
            do { try await drafts.requestSaveAfterRefreshing(finishing: finishing, refresh: refresh) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct WorkoutDraftConflictView: View {
    @ObservedObject var drafts: WorkoutSessionDraftController
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Text("Review workout changes").font(StrandFont.title2)
                    Text("Your edits are still on this phone. Keeping them replaces only the fields you deliberately edited.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    ForEach(drafts.state.edits.values.sorted(by: { $0.baseline.id < $1.baseline.id }), id: \.baseline.id) { edit in
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                let exercise = drafts.state.baseline.exercises.first { $0.sets.contains { $0.id == edit.baseline.id } }
                                Text("\(exercise?.name ?? "") · set \(edit.baseline.setNumber)").font(StrandFont.headline)
                                LabeledContent("On this phone", value: summary(edit)).font(StrandFont.subhead)
                                if let row = drafts.state.remote?.session.exercises.flatMap(\.sets).first(where: { $0.id == edit.baseline.id }) {
                                    LabeledContent("In Life", value: summary(.init(row: row, massScale: drafts.state.massScale))).font(StrandFont.subhead)
                                } else { Text("This set is no longer in Life.").font(StrandFont.subhead) }
                            }
                        }
                    }
                    if let error { Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning) }
                    Button("Keep my edited fields") { resolve(true) }.buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                    Button("Use Life values", role: .destructive) { resolve(false) }.buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                }.padding(NoopMetrics.space4)
            }.background(StrandPalette.surfaceBase)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func summary(_ edit: WorkoutInlineSetDraft) -> String {
        [edit.load.isEmpty ? "—" : "\(edit.load) \(drafts.state.massScale == 1 ? "lb" : "kg")",
         edit.reps.isEmpty ? "—" : "\(edit.reps) reps", edit.completed ? String(localized: "Done") : String(localized: "Not completed")].joined(separator: " · ")
    }
    private func resolve(_ keep: Bool) {
        do { try drafts.resolveRemote(keepEdits: keep); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
#endif
