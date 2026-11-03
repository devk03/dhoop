#if os(iOS)
import SwiftUI
import StrandDesign

/// One replacement editor for the inline workout and program options. Only explicit Save submits.
struct WorkoutExerciseReplacementEditor: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let library: [WorkoutTrackerDashboard.LibraryItem]
    let revision: Int
    let scope: WorkoutFrontendScope
    var enabled = true
    let refresh: () async throws -> Void
    @ObservedObject var client: WorkoutFrontendClient
    @State private var draft: WorkoutReplacementDraft
    @State private var query = ""
    @State private var storageError = false
    @FocusState private var focused: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private let store: WorkoutReplacementDraftStore
    init(session: WorkoutTrackerDashboard.Session, exercise: WorkoutTrackerDashboard.Exercise,
         library: [WorkoutTrackerDashboard.LibraryItem], revision: Int, scope: WorkoutFrontendScope,
         enabled: Bool = true, refresh: @escaping () async throws -> Void, client: WorkoutFrontendClient) {
        self.session = session; self.exercise = exercise; self.library = library; self.revision = revision
        self.scope = scope; self.enabled = enabled; self.refresh = refresh; self.client = client
        let identity = WorkoutReplacementDraftScope(origin: scope.origin, installationID: scope.installationId,
            programID: session.mesocycleId, sessionID: session.id, exerciseID: exercise.id)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = .init(url: root.appendingPathComponent("Dhoop/WorkoutReplacementDrafts/" + scope.installationId.uuidString.lowercased())
            .appendingPathComponent("\(session.id)-\(exercise.id).json"))
        var initial = WorkoutReplacementDraft(scope: identity, exercise: exercise, library: library)
        var failed = false
        do {
            if let retained = try store.load(scope: identity), !retained.applied {
                let command = try? retained.command(exercise: exercise, library: library)
                let accepted = command.map { command in client.state.operations.contains {
                    $0.state == .committed && $0.origin == scope.origin && $0.installationId == scope.installationId && $0.intent.command == command
                } } ?? false
                if !accepted { initial = retained }
            }
        }
        catch { failed = true }
        _draft = State(initialValue: initial); _storageError = State(initialValue: failed)
    }
    private var alternatives: [WorkoutTrackerDashboard.LibraryItem] {
        library.filter { $0.movementPattern == exercise.movementPattern && $0.exerciseKey != exercise.exerciseKey &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
    private var pending: Bool {
        client.unresolved?.intent.command["sessionExerciseId"] == .number(Double(exercise.id)) &&
        client.unresolved?.intent.command["sessionId"] == .number(Double(session.id))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Picker("Replace with", selection: $draft.custom) {
                Text("Exercise library").tag(false)
                if client.state.capabilities?.customExerciseSubstitution == true { Text("New exercise").tag(true) }
            }.pickerStyle(.menu).disabled(pending)
            Group {
                if draft.custom {
                    WorkoutFrontendTextField(title: "Exercise name", text: $draft.name).focused($focused, equals: "name")
                    Picker("Load type", selection: $draft.loadMode) {
                        ForEach(WorkoutTrackerLoadMode.allCases, id: \.rawValue) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
                    }
                    WorkoutFrontendTextField(title: "Increment (lb)", text: $draft.increment, numeric: true).focused($focused, equals: "increment")
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space2))
                    layout { definitionNumbers }
                    TextField("Exercise notes · Optional", text: $draft.notes, axis: .vertical)
                        .font(StrandFont.body).focused($focused, equals: "notes")
                    Text("Adds this exercise to your Life library for future workouts.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    TextField("Find exercise", text: $query).font(StrandFont.body).focused($focused, equals: "search")
                        .autocorrectionDisabled()
                    Picker("Exercise", selection: $draft.replacement) {
                        Text("Choose exercise").tag("")
                        ForEach(alternatives) { Text(verbatim: $0.name).tag($0.exerciseKey) }
                        if !alternatives.contains(where: { $0.exerciseKey == draft.replacement }),
                           let retained = library.first(where: { $0.exerciseKey == draft.replacement }) {
                            Text(verbatim: retained.name).tag(retained.exerciseKey)
                        }
                    }.pickerStyle(.menu)
                    if alternatives.isEmpty { Text("No replacements are available for this movement.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                }
            }.disabled(pending || storageError)
            if storageError {
                Text("Exercise input could not be saved on this phone. Existing input is retained; reopen when storage is available.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
            }
            WorkoutFrontendSubmitSection(title: draft.custom ? "Save & use exercise" : "Save replacement", action: "substitute_exercise",
                revision: revision, command: {
                    focused = nil
                    guard !storageError, enabled else { throw WorkoutTrackerContractError.invalidSnapshot }
                    try store.save(draft)
                    return try draft.command(exercise: exercise, library: library)
                }, refresh: {
                    var saved = draft; saved.applied = true; try store.save(saved)
                    try await refresh()
                }, client: client, scope: scope)
                .disabled(storageError || !enabled || (draft.custom && client.state.capabilities?.customExerciseSubstitution != true))
        }
        .onChange(of: draft) { _, value in
            guard !storageError else { return }
            do { try store.save(value) } catch { storageError = true }
        }
        .keyboardDoneToolbar($focused)
    }
    @ViewBuilder private var definitionNumbers: some View {
        WorkoutFrontendTextField(title: "Min reps", text: $draft.repMin, numeric: true).focused($focused, equals: "repMin")
        WorkoutFrontendTextField(title: "Max reps", text: $draft.repMax, numeric: true).focused($focused, equals: "repMax")
    }
}
#endif
