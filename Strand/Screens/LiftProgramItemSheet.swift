import SwiftUI
import StrandDesign
import WhoopStore

// Edit ONE exercise line of a program: which exercise, and the targets for it.
//
// NOOP SHIPS NO EXERCISE CATALOGUE — deliberately. The user types whatever they call the movement
// and it is remembered in `liftExercise` with the muscle group they gave it, then offered back next
// time. A shipped mapping of common exercises to muscles would be both a permanent maintenance
// burden and a correctness claim NOOP has no business making about someone else's technique.
//
// Classification is therefore a one-time, few-second action per exercise: pick the primary muscle
// (a direct set) and any secondaries (indirect, counted at half). It is asked once, on first use,
// and remembered thereafter. Leaving it unset is allowed — an unclassified exercise still counts
// toward volume and session load, it simply claims no muscle it was never assigned.

struct LiftProgramItemSheet: View {
    /// The line being edited, or nil to add a new one.
    let item: LiftProgramItemRow?
    var sourceDeviceId: String? = nil
    /// Handed the finished line. The parent owns ordering and persistence.
    let onSave: (LiftProgramItemRow) -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var exercise: String = ""
    @State private var primary: LiftMuscle?
    @State private var secondaries: Set<LiftMuscle> = []

    @State private var setsText: String = ""
    @State private var repsText: String = ""
    @State private var weightText: String = ""
    @State private var restText: String = ""
    @State private var maxRpeText: String = ""
    @State private var note: String = ""

    /// The user's own exercise vocabulary, for suggestions and for adopting a known classification.
    @StateObject private var catalog = LiftExerciseCatalogModel()
    @State private var browsing = false
    @State private var saving = false
    @State private var forgettingBusy = false
    @State private var operationError: String?
    @State private var classificationEdited = false
    private var deviceID: String { sourceDeviceId ?? item?.deviceId ?? repo.deviceId }
    private var vocabulary: [LiftExerciseRow] { catalog.entries(for: deviceID) }
    @State private var loaded = false
    /// The vocabulary entry the user is about to forget (nil = no confirmation showing).
    @State private var forgetting: LiftExerciseRow?

    /// The app's existing metric/imperial preference — the Lift Log never adds a second weight unit
    /// setting of its own, so the plan is typed in the same unit the session records in.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var weightLabel: LocalizedStringKey {
        unitSystem == .imperial ? "Weight (lb)" : "Weight (kg)"
    }

    @FocusState private var focused: Field?
    private enum Field: Hashable { case exercise, sets, reps, weight, rest, maxRpe, note }

    private var trimmedExercise: String {
        exercise.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// The ceiling as typed, when it is one: 1 to 10. A blank field is no ceiling.
    private var maxRpe: Double? {
        LiftFormat.number(maxRpeText).flatMap { (1...10).contains($0) ? $0 : nil }
    }
    private var maxRpeInvalid: Bool {
        !maxRpeText.trimmingCharacters(in: .whitespaces).isEmpty && maxRpe == nil
    }
    private var targetsInvalid: Bool {
        func invalidInteger(_ text: String, minimum: Int) -> Bool {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && (Int(value).map { $0 < minimum } ?? true)
        }
        let weight = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        return invalidInteger(setsText, minimum: 1) || invalidInteger(repsText, minimum: 0) || invalidInteger(restText, minimum: 0)
            || (!weight.isEmpty && (LiftFormat.number(weight).map { $0 < 0 } ?? true))
    }
    private var canSave: Bool { catalog.isReady(for: deviceID) && !saving && !forgettingBusy && !trimmedExercise.isEmpty && !maxRpeInvalid && !targetsInvalid }

    private var suggestions: [LiftExerciseRow] {
        LiftExerciseVocabulary.suggestions(vocabulary, matching: exercise)
    }

    var body: some View {
        ScreenScaffold(
            title: item == nil ? "Add exercise" : "Edit exercise",
            subtitle: "Type any name you like. Dhoop remembers it, with the muscles you give it."
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                exerciseSection.disabled(saving || forgettingBusy)
                LiftMusclePicker(primary: Binding(get: { primary }, set: { primary = $0; classificationEdited = true }),
                                 secondaries: Binding(get: { secondaries }, set: { secondaries = $0; classificationEdited = true }))
                    .disabled(saving || forgettingBusy)
                targetsSection.disabled(saving || forgettingBusy)
                noteSection.disabled(saving || forgettingBusy)
                if targetsInvalid { Text("Use whole positive set counts and non-negative repetitions, rest and weight. Leave optional targets blank.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical) }
                if let operationError { Text(operationError).font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical) }
                footer
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: NoopMetrics.detailSheetMinWidth, minHeight: NoopMetrics.detailSheetMinHeight)
        #endif
        .background(StrandPalette.surfaceBase)
        .keyboardDoneToolbar($focused)
        .dismissesKeyboardOnTap($focused)
        .interactiveDismissDisabled(saving || forgettingBusy)
        .task { await loadIfNeeded() }
        .sheet(isPresented: $browsing) { LiftExerciseCatalogBrowser(catalog: catalog, deviceID: deviceID, onPick: adopt) }
        .confirmationDialog(
            forgetting.map { Text(String(localized: "Forget \($0.name)?")) } ?? Text(""),
            isPresented: Binding(get: { forgetting != nil },
                                 set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) { Task { await forget() } }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: {
            Text("It stops being offered here. Sessions you already logged with it are kept exactly as they are.")
        }
    }

    /// Forget an exercise. The logged sets keep their own copy of the name and muscles, so this
    /// removes it from the picker WITHOUT touching a single recorded session.
    private func forget() async {
        guard let row = forgetting else { return }
        guard let store = await repo.storeHandle() else { operationError = LiftExerciseCatalogModel.Failure.unavailable.localizedDescription; return }
        forgettingBusy = true; operationError = nil
        defer { forgettingBusy = false }
        do {
            _ = try await store.deleteLiftExercise(id: row.id)
            try await loadCatalog()
            forgetting = nil
        } catch { operationError = "The exercise could not be forgotten or the catalog refreshed. Your routine draft is retained." }
    }

    // MARK: - Exercise name + suggestions

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
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
                        NoopAsyncButton("Retry reading exercises", systemImage: "arrow.clockwise", kind: .secondary) { try await loadCatalog() }
                    }
                    NoopButton("Browse all exercises", systemImage: "list.bullet", kind: .secondary) { browsing = true }
                        .disabled(!catalog.isReady(for: deviceID))

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Text("Used before").strandOverline()
                            ForEach(suggestions, id: \.id) { row in
                                HStack(spacing: NoopMetrics.space2) {
                                    Button {
                                        adopt(row)
                                    } label: {
                                        LiftExerciseSuggestionLabel(row: row)
                                    }
                                    .buttonStyle(NoopFeedbackButtonStyle())

                                    // A typo becomes a permanent picker entry otherwise. Forgetting a
                                    // name is safe by construction: every logged set SNAPSHOTS its
                                    // exercise name and classification, so history is untouched.
                                    Button(role: .destructive) {
                                        forgetting = row
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(StrandFont.caption)
                                            .foregroundStyle(StrandPalette.textTertiary)
                                            .frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                                    }
                                    .buttonStyle(NoopFeedbackButtonStyle())
                                    .accessibilityLabel("Forget this exercise")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Targets

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Targets", overline: "What you're aiming for")
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack(spacing: NoopMetrics.gap) {
                        field("Working sets") {
                            numberInput("4", text: $setsText, field: .sets)
                        }
                        field("Reps") {
                            numberInput("8", text: $repsText, field: .reps)
                        }
                    }
                    HStack(spacing: NoopMetrics.gap) {
                        field(weightLabel) {
                            numberInput("60", text: $weightText, field: .weight)
                        }
                        field("Rest (seconds)") {
                            numberInput("120", text: $restText, field: .rest)
                        }
                    }
                    // Max RPE is a CEILING, not effort planned in advance (Utku, 15 Sep 2026): the
                    // hardest a set should feel, so a lifter knows where to hold back. It is shown grey in
                    // the session and, like every other grey number, a set left unrated saves it
                    // (Utku, 16 Sep 2026; RULES 34) — typing a rating always wins.
                    HStack(spacing: NoopMetrics.gap) {
                        field("Max RPE (1–10)") {
                            numberInput("8", text: $maxRpeText, field: .maxRpe)
                        }
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                    if maxRpeInvalid {
                        Text("Max RPE must be between 1 and 10.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusWarning)
                    }
                    Text("Max RPE is a ceiling: the hardest a set should feel, where 10 means nothing left. It shows grey during the session, and a set you leave unrated saves it as its rating.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Every target is optional — this is the plan, not the record. What you actually lift is entered set by set during the session.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Technique note", overline: "In your words")
            NoopCard {
                TextField("Slow eccentric, pause at the bottom", text: $note, axis: .vertical)
                    // A cue read between sets, and it renders directly above the set rows — every
                    // line pushes them down the screen.
                    .onChange(of: note) { new in
                        if new.count > WhoopStore.maxExerciseNoteLength {
                            note = String(new.prefix(WhoopStore.maxExerciseNoteLength))
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1...4)
                    .focused($focused, equals: .note)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.disabled(saving || forgettingBusy)
                .buttonStyle(NoopFeedbackButtonStyle())
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            NoopAsyncButton(item == nil ? "Add to routine draft" : "Apply to routine draft", systemImage: "checkmark") { try await save() }
                .disabled(!canSave)
                .accessibilityLabel("Apply exercise changes to routine draft")
        }
    }

    // MARK: - Field helpers (the house form idiom)

    private func field<Content: View>(_ label: LocalizedStringKey,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(label).strandOverline()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberInput(_ placeholder: LocalizedStringKey,
                             text: Binding<String>,
                             field: Field) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(StrandPalette.textPrimary)
            .numericKeyboard()
            .focused($focused, equals: field)
    }

    // MARK: - Behaviour

    /// Take a known exercise from the vocabulary, including the classification it already carries —
    /// so a movement is classified once and never asked about again.
    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name
        primary = row.primaryMuscle
        secondaries = Set(row.secondaryMuscles)
        classificationEdited = true
        focused = nil
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        if let item {
            exercise = item.exercise
            setsText = item.targetSets.map(String.init) ?? ""
            repsText = item.targetRepsLow.map(String.init) ?? ""
            weightText = item.targetWeightKg.map {
                LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: unitSystem))
            } ?? ""
            restText = item.restSec.map(String.init) ?? ""
            maxRpeText = item.targetRpe.map { LiftFormat.trim($0) } ?? ""
            note = item.note ?? ""
        }
        try? await loadCatalog()
    }

    @MainActor private func loadCatalog() async throws {
        try await catalog.load(deviceID: deviceID) { source in
            guard let store = await repo.storeHandle() else { throw LiftExerciseCatalogModel.Failure.unavailable }
            return try await store.liftExercises(deviceId: source)
        }
        // An existing line adopts whatever classification its exercise already carries, so editing a
        // line shows the muscles the exercise is known by rather than an empty picker.
        if !classificationEdited, let known = vocabulary.first(where: { $0.name == trimmedExercise }) {
            primary = known.primaryMuscle
            secondaries = Set(known.secondaryMuscles)
        }
    }

    @MainActor private func save() async throws {
        guard canSave else { throw LiftExerciseCatalogModel.Failure.unavailable }
        saving = true; operationError = nil
        defer { saving = false }
        let name = trimmedExercise
        let source = deviceID

        // Remember the exercise (and its classification) in the vocabulary, so it is offered back
        // next time.
        guard let store = await repo.storeHandle() else { throw LiftExerciseCatalogModel.Failure.unavailable }
        do {
            try await LiftExerciseVocabulary.remember(
                    name, primary: primary,
                    secondaries: LiftExerciseVocabulary.ordered(secondaries, excluding: primary),
                    known: vocabulary, deviceId: source, in: store)
        } catch let full as WhoopStore.LiftExerciseVocabularyFull {
                // Refused rather than silently dropped: the user typed a name and deserves to know
                // it was not remembered.
                throw LiftExerciseCatalogModel.Failure.full(full.limit)
        } catch {
            throw error
        }

        guard source == deviceID else { throw LiftExerciseCatalogModel.Failure.changedSource }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(LiftProgramItemRow(
            id: item?.id ?? UUID().uuidString,
            deviceId: source,
            // Assigned properly by the parent on save; a placeholder here would be a second source
            // of truth for ordering.
            programId: item?.programId ?? "",
            ord: item?.ord ?? 0,
            exercise: name,
            targetSets: Int(setsText.trimmingCharacters(in: .whitespaces)),
            // ONE rep count: `targetRepsHigh` stays nil, a schema column the editor no longer fills.
            targetRepsLow: Int(repsText.trimmingCharacters(in: .whitespaces)),
            targetRepsHigh: nil,
            targetRpe: maxRpe,
            targetWeightKg: LiftFormat.number(weightText).map {
                LiftFormat.kilograms(fromDisplay: $0, system: unitSystem)
            },
            restSec: Int(restText.trimmingCharacters(in: .whitespaces)),
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ))
        dismiss()
    }
}
