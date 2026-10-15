import SwiftUI
import StrandDesign
import WhoopStore

// Add an exercise to the running session (Utku, 21 Sep 2026): one done before, picked from the user's own
// exercise names, or a new one, typed and given its muscles — and remembered, like a name typed into the
// program editor. It joins the session at the end of the sheet as one set planned at 0 kg × 0 reps; ⊕/⊖
// change its sets like any other line, and finishing asks whether the program keeps it. Sets, rest and
// max RPE are not asked here: they belong to the program editor, later.

struct LiftSessionExerciseSheet: View {
    /// Handed the exercise once it is remembered; the session adds it.
    var requiresLoadType = false
    var sourceDeviceId: String?
    var replacingExercise: String? = nil
    let onAdd: (_ name: String, _ primary: LiftMuscle?, _ secondaries: [LiftMuscle], _ sourceExerciseId: UUID?, _ loadMode: WorkoutTrackerLoadMode?) -> Bool

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var parentExerciseId: String?
    @State private var exercise = ""
    @State private var primary: LiftMuscle?
    @State private var secondaries: Set<LiftMuscle> = []
    /// The user's own exercise names, most recently used first.
    @StateObject private var catalog = LiftExerciseCatalogModel()
    @State private var browsing = false
    private var vocabulary: [LiftExerciseRow] { catalog.entries(for: deviceID) }
    @State private var classificationEdited = false
    @State private var adding = false
    @State private var loadMode: WorkoutTrackerLoadMode?

    @FocusState private var focused: Field?
    private enum Field: Hashable { case exercise }

    private var trimmedExercise: String {
        exercise.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var deviceID: String { sourceDeviceId ?? repo.deviceId }
    private var canAdd: Bool { catalog.isReady(for: deviceID) && !trimmedExercise.isEmpty && !adding && (!requiresLoadType || loadMode != nil) }

    var body: some View {
        ScreenScaffold(title: replacingExercise == nil ? "Add exercise" : "Replace exercise",
                       subtitle: "Pick one you have done before, or type a new name.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                exerciseSection.disabled(adding)
                if requiresLoadType { loadTypeSection }
                LiftVariationPicker(vocabulary: vocabulary, exerciseName: exercise, parentID: $parentExerciseId)
                    .disabled(adding || !catalog.isReady(for: deviceID))
                LiftMusclePicker(primary: Binding(get: { primary }, set: { primary = $0; classificationEdited = true }),
                                 secondaries: Binding(get: { secondaries }, set: { secondaries = $0; classificationEdited = true })).disabled(adding)
                Text(replacingExercise.map { "Replace the remaining sets of \($0). Completed sets keep their original exercise. Your routine stays unchanged." } ?? (requiresLoadType ? "Added to workout history. Your Life routine stays unchanged." : "It joins this session with one set. Type what you lift; finishing asks whether the program keeps it."))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                footer
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: NoopMetrics.detailSheetMinWidth, minHeight: NoopMetrics.detailSheetMinHeight)
        #endif
        .background(StrandPalette.surfaceBase)
        .interactiveDismissDisabled(adding)
        .keyboardDoneToolbar($focused)
        .dismissesKeyboardOnTap($focused)
        .task(id: deviceID) { try? await load() }
        .sheet(isPresented: $browsing) { LiftExerciseCatalogBrowser(catalog: catalog, deviceID: deviceID, onPick: adopt) }
        // A name typed out in full that is already known brings its muscles with it, as picking it from
        // the list does — unless muscles were already chosen here.
        .onChange(of: exercise) { _ in
            guard !classificationEdited, primary == nil, secondaries.isEmpty,
                  let known = vocabulary.first(where: { $0.name == trimmedExercise }) else { return }
            primary = known.primaryMuscle
            secondaries = Set(known.secondaryMuscles)
        }
    }

    private var exerciseSection: some View {
        let suggestions = LiftExerciseVocabulary.suggestions(vocabulary, matching: exercise, limit: 8)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Exercise", overline: "Movement")
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    TextField("Incline dumbbell press", text: $exercise)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .focused($focused, equals: .exercise)
                    if catalog.isLoading { ProgressView("Reading saved exercises…").font(StrandFont.caption) }
                    if let error = catalog.error {
                        Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical)
                        NoopAsyncButton("Retry reading exercises", systemImage: "arrow.clockwise", kind: .secondary) { try await load() }
                    }
                    NoopButton("Browse all exercises", systemImage: "list.bullet", kind: .secondary) { browsing = true }
                        .disabled(!catalog.isReady(for: deviceID))
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Used before").strandOverline()
                            ForEach(suggestions, id: \.id) { row in
                                Button { adopt(row) } label: { LiftExerciseSuggestionLabel(row: row) }
                                    .buttonStyle(NoopFeedbackButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private var loadTypeSection: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Load type").font(StrandFont.headline)
                Text("Choose how this exercise's weight is recorded.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NoopMetrics.space2), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: NoopMetrics.space2) {
                    ForEach(WorkoutTrackerLoadMode.allCases.filter { $0 != .duration }, id: \.self) { mode in
                        NoopButton(LocalizedStringKey(mode.title), systemImage: loadMode == mode ? "checkmark.circle.fill" : "circle",
                                   kind: loadMode == mode ? .primary : .secondary, fullWidth: true) { loadMode = mode }
                            .accessibilityAddTraits(loadMode == mode ? .isSelected : [])
                    }
                }
                if let loadMode { Text(loadMode.explanation).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            }
        }.disabled(adding)
    }

    private var footer: some View {
        VStack(spacing: NoopMetrics.space2) {
            NoopAsyncButton(replacingExercise == nil ? "Add exercise" : "Replace remaining sets", systemImage: replacingExercise == nil ? "plus" : "arrow.triangle.2.circlepath") { try await add() }.disabled(!canAdd)
            NoopButton("Cancel", kind: .tertiary) { dismiss() }.disabled(adding)
        }
    }

    /// Take a known exercise, with the muscles it is already known by.
    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name
        primary = row.primaryMuscle
        secondaries = Set(row.secondaryMuscles)
        classificationEdited = true
        focused = nil
    }

    @MainActor private func load() async throws {
        try await catalog.load(deviceID: deviceID) { source in
            guard let store = await repo.storeHandle() else { throw LiftExerciseCatalogModel.Failure.unavailable }
            return try await store.liftExercises(deviceId: source)
        }
        if !classificationEdited, let known = vocabulary.first(where: { $0.name == trimmedExercise }) {
            primary = known.primaryMuscle; secondaries = Set(known.secondaryMuscles)
        }
    }

    /// Remember the exercise — a new name is saved to the vocabulary, a known one is marked used — then
    /// hand it to the session.
    private func add() async throws {
        guard canAdd else { throw WorkoutTrackerContractError.invalidSnapshot }
        adding = true
        defer { adding = false }
        let name = trimmedExercise
        let chosenPrimary = primary, source = deviceID
        let ordered = LiftExerciseVocabulary.ordered(secondaries, excluding: chosenPrimary)
        let mode = loadMode
        guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
        let nativeId: String
        do {
            nativeId = try await LiftExerciseVocabulary.remember(name, primary: chosenPrimary, secondaries: ordered,
                known: vocabulary, deviceId: source, in: store, parentExerciseId: parentExerciseId)
        } catch let full as WhoopStore.LiftExerciseVocabularyFull {
            throw LiftExerciseCatalogModel.Failure.full(full.limit)
        }
        guard source == deviceID else { throw LiftExerciseCatalogModel.Failure.changedSource }
        var sourceId = UUID(uuidString: nativeId)
        #if os(iOS)
        if requiresLoadType { sourceId = try WorkoutTrackerClient.shared.sourceExerciseIdentity(nativeId: nativeId, deviceID: source) }
        #endif
        guard onAdd(name, chosenPrimary, ordered, sourceId, mode) else { throw WorkoutTrackerContractError.sessionChanged }
        dismiss()
    }
}
