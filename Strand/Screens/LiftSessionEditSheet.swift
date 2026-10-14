import SwiftUI
import StrandDesign
import WhoopStore

// Correct a finished session: a number missed or mistyped at the gym, a set added or removed, a warm-up
// not marked, or the session's RPE. Only this session changes — never the program it ran from — and
// every figure on the session screen is recomputed from these rows.
//
// Sets saved at 0 reps (discarded at finish, or skipped) appear here and nowhere else, so a discard
// made by mistake can be filled back in: give such a set its reps and it counts again.
//
// Fields hold plain text and are parsed once, on Save, so a field is never rewritten while it is being
// typed into (the bug that stored 45.5 kg as 455). Only a field whose text changed is written back:
// re-parsing an untouched pound value into kilograms would otherwise nudge it by a rounding error.

struct LiftSessionEditSheet: View {
    let session: LiftSessionRow
    let sets: [LiftSetRow]
    /// Called after the changes are written, so the session screen can reload.
    let onSaved: () async -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Exercises in the order they were first performed, each with its rows in set order — and the same
    /// as the sheet opened, to tell whether anything changed.
    @State private var exercises: [ExerciseRows] = []
    @State private var original: [ExerciseRows] = []
    @State private var sessionRpeText = ""
    @State private var originalSessionRpe = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var showingNotes: Set<String> = []
    /// A weight or reps field whose 0 was emptied when it was focused.
    @State private var clearedZero: Field?

    @FocusState private var focused: Field?
    private enum Field: Hashable { case weight(String), reps(String), rpe(String), notes(String), sessionRpe }

    /// One set's fields, as typed.
    struct SetForm: Equatable {
        var weight: String
        var reps: String
        var rpe: String
        var isWarmup: Bool
        var notes: String = ""
    }

    /// One row on the sheet: a saved set (its row id) or one added here (a new id).
    struct Entry: Equatable {
        let id: String
        var form: SetForm
    }

    /// An exercise and its rows, in set order.
    struct ExerciseRows: Equatable {
        let name: String
        var entries: [Entry]
    }

    private var hasChanges: Bool { exercises != original || sessionRpeText != originalSessionRpe }

    private var weightHeading: LocalizedStringKey {
        unitSystem == .imperial ? "Lb" : "Kg"
    }

    var body: some View {
        ScreenScaffold(title: "Edit sets",
                       subtitle: "Fix numbers, or add and remove sets. Sets left at 0 reps stay out of the figures, and only this session changes — not the program.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                sessionRpeCard
                ForEach(exercises.indices, id: \.self) { exerciseCard($0) }
                footer
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 560, height: 780)
        #endif
        .background(StrandPalette.surfaceBase)
        .keyboardDoneToolbar($focused)
        .dismissesKeyboardOnTap($focused)
        // A field holding 0 (a discarded set) empties when focused, so typing replaces the 0 instead of
        // appending to it ("0" then "60" read "600" in the simulator); left empty, it goes back to 0. The
        // single-argument form on purpose: the two-argument `onChange` is macOS 14+.
        .onChange(of: focused) { now in
            restoreClearedZero()
            if swapText(now, "0", "") { clearedZero = now }
        }
        .onAppear(perform: fill)
        .alert("Changes were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "Your edits are still available. Please try again.") }
    }

    private var sessionRpeCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text("How hard was the whole session? (1–10)").strandOverline()
                field(.sessionRpe, text: Binding(
                    get: { sessionRpeText },
                    set: { sessionRpeText = $0.replacingOccurrences(of: ",", with: ".") }))
            }
        }
    }

    private func exerciseCard(_ index: Int) -> some View {
        let group = exercises[index]
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                Text(group.name)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                HStack(spacing: 8) {
                    Text("Set").strandOverline()
                        .frame(width: LiftSessionView.setColumnWidth, alignment: .center)
                    Text(weightHeading).strandOverline().frame(maxWidth: .infinity, alignment: .leading)
                    Text("Reps").strandOverline().frame(maxWidth: .infinity, alignment: .leading)
                    Text("RPE").strandOverline().frame(maxWidth: .infinity, alignment: .leading)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                    setRow(exercise: index, position: position, entry: entry)
                    if showingNotes.contains(group.name) {
                        TextField("Set \(position + 1) notes", text: Binding(get: { self.entry(index, entry.id)?.form.notes ?? "" }, set: { text in
                            update(index, entry.id) { $0.form.notes = text }
                        }), axis: .vertical)
                        .textFieldStyle(.plain).font(StrandFont.subhead).lineLimit(2...6)
                        .focused($focused, equals: .notes(entry.id))
                        .frame(minHeight: NoopMetrics.minimumTouchTarget)
                        .accessibilityLabel("Notes for set \(position + 1), \(group.name)")
                    }
                }
                NoopButton("Set notes", systemImage: "text.bubble", kind: .tertiary) {
                    if showingNotes.contains(group.name) { showingNotes.remove(group.name) } else { showingNotes.insert(group.name) }
                }
                setCountRow(index)
            }
        }
    }

    /// The set number toggles a warm-up, as on the session sheet. Numbers follow the rows, so removing a
    /// set renumbers the ones after it.
    private func setRow(exercise: Int, position: Int, entry: Entry) -> some View {
        let warmup = entry.form.isWarmup
        return HStack(spacing: 8) {
            Button { update(exercise, entry.id) { $0.form.isWarmup.toggle() } } label: {
                Text(warmup ? String(localized: "W") : "\(position + 1)")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(warmup ? StrandPalette.metricAmber : StrandPalette.textSecondary)
                    .frame(width: LiftSessionView.setColumnWidth, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .accessibilityLabel(warmup
                                ? String(localized: "Warm-up set — tap to make it a working set")
                                : String(localized: "Set \(position + 1) — tap to mark it a warm-up"))
            field(.weight(entry.id), text: binding(exercise, entry.id, \.weight))
            field(.reps(entry.id), text: binding(exercise, entry.id, \.reps))
            field(.rpe(entry.id), text: binding(exercise, entry.id, \.rpe))
        }
        .padding(.vertical, 6)
    }

    /// Add a set at the end of an exercise, or drop its last one — the same control as the session
    /// sheet. An exercise keeps at least one row: set it to 0 reps to take it out of the figures.
    private func setCountRow(_ index: Int) -> some View {
        let group = exercises[index]
        let canAdd = group.entries.count < LiftSessionEngine.maxSetsPerExercise
        let canRemove = group.entries.count > 1
        return HStack(spacing: 8) {
            Button { addSet(index) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Add set").font(StrandFont.caption)
                }
                .foregroundStyle(canAdd ? StrandPalette.effortColor : StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .disabled(!canAdd)
            .accessibilityLabel(String(localized: "Add a set to \(group.name)"))

            Button { removeSet(index) } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canRemove ? StrandPalette.textSecondary
                                               : StrandPalette.textTertiary.opacity(0.4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .disabled(!canRemove)
            .accessibilityLabel(String(localized: "Remove the last set from \(group.name)"))
        }
        .padding(.top, 2)
    }

    private func field(_ target: Field, text: Binding<String>) -> some View {
        TextField(Self.empty, text: text)
            .textFieldStyle(.plain)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(StrandPalette.textPrimary)
            .numericKeyboard()
            .focused($focused, equals: target)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A typed comma becomes a point, as on the session sheet: iOS labels the decimal key from the
    /// device's region, and the field reads back in the notation the app displays.
    private func binding(_ exercise: Int, _ id: String,
                         _ key: WritableKeyPath<SetForm, String>) -> Binding<String> {
        Binding(get: { entry(exercise, id)?.form[keyPath: key] ?? "" },
                set: { text in
                    update(exercise, id) { $0.form[keyPath: key] = text.replacingOccurrences(of: ",", with: ".") }
                })
    }

    private func entry(_ exercise: Int, _ id: String) -> Entry? {
        guard exercises.indices.contains(exercise) else { return nil }
        return exercises[exercise].entries.first { $0.id == id }
    }

    private func update(_ exercise: Int, _ id: String, _ change: (inout Entry) -> Void) {
        guard exercises.indices.contains(exercise),
              let i = exercises[exercise].entries.firstIndex(where: { $0.id == id }) else { return }
        change(&exercises[exercise].entries[i])
    }

    /// Replace a weight or reps field's text with `new` if it is `old`. RPE never holds 0.
    @discardableResult
    private func swapText(_ field: Field?, _ old: String, _ new: String) -> Bool {
        let target: (id: String, key: WritableKeyPath<SetForm, String>)
        switch field {
        case .weight(let id)?: target = (id, \.weight)
        case .reps(let id)?: target = (id, \.reps)
        default: return false
        }
        guard let exercise = exercises.firstIndex(where: { $0.entries.contains { $0.id == target.id } }),
              entry(exercise, target.id)?.form[keyPath: target.key] == old else { return false }
        update(exercise, target.id) { $0.form[keyPath: target.key] = new }
        return true
    }

    /// Put back a 0 that was emptied on focus and left empty, before anything reads the fields: an empty
    /// reps field saves as nil, which counts as a performed set.
    private func restoreClearedZero() {
        swapText(clearedZero, "", "0")
        clearedZero = nil
    }

    /// A new set starts from the exercise's last one — usually what the extra set was — without its RPE.
    private func addSet(_ exercise: Int) {
        restoreClearedZero()
        guard let last = exercises[exercise].entries.last,
              exercises[exercise].entries.count < LiftSessionEngine.maxSetsPerExercise else { return }
        exercises[exercise].entries.append(Entry(
            id: UUID().uuidString,
            form: SetForm(weight: last.form.weight, reps: last.form.reps, rpe: "", isWarmup: false)))
    }

    private func removeSet(_ exercise: Int) {
        guard exercises[exercise].entries.count > 1 else { return }
        exercises[exercise].entries.removeLast()
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(NoopFeedbackButtonStyle())
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            NoopActionButton("Save changes", state: saving ? .working : .idle) { Task { await save() } }
                .disabled(saving || !hasChanges)
        }
    }

    private func fill() {
        guard exercises.isEmpty else { return }
        var order: [String] = []
        for row in sets.sorted(by: { $0.ord < $1.ord }) where !order.contains(row.exercise) {
            order.append(row.exercise)
        }
        exercises = order.map { name in
            ExerciseRows(name: name, entries: sets
                .filter { $0.exercise == name }
                .sorted { ($0.setIndex, $0.ord) < ($1.setIndex, $1.ord) }
                .map { Entry(id: $0.id, form: Self.form(for: $0, system: unitSystem)) })
        }
        original = exercises
        sessionRpeText = session.sessionRpe.map { LiftFormat.trim($0) } ?? ""
        originalSessionRpe = sessionRpeText
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        guard let store = await repo.storeHandle() else {
            saveError = "Storage is unavailable. Your changes are still open."
            return
        }

        restoreClearedZero()
        let change = Self.changes(from: sets, to: exercises, system: unitSystem)
        var row = session
        if sessionRpeText != originalSessionRpe {
            row.sessionRpe = LiftFormat.number(sessionRpeText)
        }
        do {
            #if os(iOS)
            let candidate = sets.filter { old in !change.deletedIds.contains(old.id) && !change.upserts.contains(where: { $0.id == old.id }) } + change.upserts
            let trackerEvent = try await WorkoutTrackerClient.shared.prepareHistoryChange(record: row, sets: candidate, store: store)
            #endif
            try await store.editLiftRecording(session: row, upserts: change.upserts, deletedSetIDs: change.deletedIds)
            #if os(iOS)
            if let trackerEvent {
                do { try await WorkoutTrackerClient.shared.confirmPersistence(trackerEvent, store: store) }
                catch { saveError = "Your changes are saved locally. Tracker delivery state needs recovery; your edits are retained."; return }
            }
            #endif
        }
        catch { saveError = error.localizedDescription; return }
        await onSaved()
        dismiss()
    }

    /// A set's fields as the sheet opens, in the unit the app displays.
    static func form(for row: LiftSetRow, system: UnitSystem) -> SetForm {
        SetForm(weight: row.weightKg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: system)) } ?? "",
                reps: row.reps.map(String.init) ?? "",
                rpe: row.rpe.map { LiftFormat.trim($0) } ?? "",
                isWarmup: row.isWarmup, notes: row.note ?? "")
    }

    /// `row` with every field that differs between `before` and `after` parsed back in. A blank field
    /// clears its value.
    static func applying(_ after: SetForm, over before: SetForm, to row: LiftSetRow,
                         system: UnitSystem) -> LiftSetRow {
        var edited = row
        if after.weight != before.weight { edited.weightKg = kilograms(after.weight, system) }
        if after.reps != before.reps { edited.reps = repCount(after.reps) }
        if after.rpe != before.rpe { edited.rpe = LiftFormat.number(after.rpe) }
        edited.isWarmup = after.isWarmup
        if after.notes != before.notes { edited.note = after.notes.isEmpty ? nil : after.notes }
        return edited
    }

    /// What saving writes: every row that changed or was added, and the ids of rows no longer on the
    /// sheet. Rows are numbered 1… per exercise in sheet order. A saved row has only its edited fields
    /// parsed back in; an added row takes its muscles from the exercise's other sets, has no timing, and
    /// is ordered after every set the session already had.
    static func changes(from rows: [LiftSetRow], to exercises: [ExerciseRows],
                        system: UnitSystem) -> (upserts: [LiftSetRow], deletedIds: [String]) {
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var nextOrd = (rows.map(\.ord).max() ?? -1) + 1
        var upserts: [LiftSetRow] = []
        var kept = Set<String>()
        for group in exercises {
            guard let template = rows.first(where: { $0.exercise == group.name }) else { continue }
            for (position, entry) in group.entries.enumerated() {
                if let row = byId[entry.id] {
                    kept.insert(row.id)
                    var edited = applying(entry.form, over: form(for: row, system: system), to: row, system: system)
                    edited.setIndex = position + 1
                    if edited != row { upserts.append(edited) }
                } else {
                    upserts.append(LiftSetRow(
                        id: entry.id, deviceId: template.deviceId, sessionId: template.sessionId,
                        ord: nextOrd, exercise: group.name, primaryMuscle: template.primaryMuscle,
                        secondaryMuscles: template.secondaryMuscles, setIndex: position + 1,
                        weightKg: kilograms(entry.form.weight, system), reps: repCount(entry.form.reps),
                        rpe: LiftFormat.number(entry.form.rpe), isWarmup: entry.form.isWarmup,
                        startTs: nil, endTs: nil, restSec: nil, note: entry.form.notes.isEmpty ? nil : entry.form.notes))
                    nextOrd += 1
                }
            }
        }
        return (upserts, rows.map(\.id).filter { !kept.contains($0) })
    }

    private static func kilograms(_ text: String, _ system: UnitSystem) -> Double? {
        LiftFormat.number(text).map { LiftFormat.kilograms(fromDisplay: $0, system: system) }
    }

    private static func repCount(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    private static let empty = "—"
}
