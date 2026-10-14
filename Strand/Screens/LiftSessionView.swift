import SwiftUI
import StrandDesign
import WhoopStore

// The workout sheet: every exercise and every set of the session, on one scrollable page.
//
// WHY A SHEET AND NOT A WIZARD. The first version showed one set at a time and walked the plan in
// order. In a real gym that fails twice over: you cannot see what is coming, and you cannot move on
// when a machine is occupied. So every set is a row, any pending row can be started, and finished
// rows stay on screen with what you lifted.
//
// COLOUR CARRIES STATE, so you can find your place at a glance from arm's length:
//   green   the set you are working now
//   amber   the rest that follows it
//   done    a completed set, with a check; numbers nobody typed stay grey
//
// The session itself lives in `LiftSessionController`, ABOVE this view. Swiping this sheet away
// minimises it to the bottom bar; the clock, the strap gesture and the buzzes all keep running,
// because a workout outlives the screen you happen to be looking at.

struct LiftSessionView: View {
    // Only what the sheet draws from. The live heart rate and the running clocks are their own small views
    // (`LiftLiveReadouts.swift`): watched from here, every beat, log line and tick redrew the whole sheet.
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Called once the session has been written, so the hub can reload.
    let onFinished: () async -> Void

    @State private var showingFinish = false
    @State private var confirmingDiscard = false
    @State private var sessionRpeText = ""
    @State private var saving = false
    @State private var saveError: String?
    /// The two questions finishing can ask. Nil until answered: saving waits for an answer rather than
    /// deciding for the user.
    @State private var unfinishedChoice: UnfinishedChoice?
    @State private var programChoice: ProgramChoice?
    /// Program lines whose set count this session changed, read when the finish sheet opens.
    @State private var setCountChanges: [LiftSessionController.SetCountChange] = []
    @State private var addingExercise = false
    /// The card to bring into view once an exercise has been added — the new one, at the end.
    @State private var scrollTarget: Int?

    private enum UnfinishedChoice: Hashable { case complete, discard }
    private enum ProgramChoice: Hashable { case update, keep }

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @FocusState private var focused: FocusTarget?
    private enum FocusTarget: Hashable {
        case weight(LiftSlot), reps(LiftSlot), rpe(LiftSlot), sessionRpe
    }

    /// What the user has TYPED into a field, held until they leave it.
    ///
    /// Without this a numeric field cannot accept a decimal at all. Each binding read its text back
    /// out of the engine, so every keystroke round-tripped through `LiftFormat` and was replaced by
    /// the canonical rendering of the parsed value. Typing "45." parsed to 45, re-rendered as "45",
    /// and the point vanished as it was typed — then the next keystroke made "455". A user entering
    /// 45.5 kg silently got 455 kg, which is the shape of bug this feature has to stop having.
    ///
    /// So while a field is focused it shows exactly what was typed; the parsed value still goes to
    /// the engine and to disk on every keystroke, so nothing about durability changes. The draft is
    /// dropped when focus leaves and the row goes back to the canonical formatting.
    @State private var draft: [FocusTarget: String] = [:]

    private var engine: LiftSessionEngine? { session.engine }

    var body: some View {
        Group {
            if let engine {
                if dynamicTypeSize.isAccessibilitySize {
                    sheet(engine)
                } else { VStack(spacing: 0) {
                    sheet(engine)
                    // The control bar never scrolls away: at the rack the clock and the one action have to
                    // be where your thumb already is.
                    controlBar(engine)
                } }
            } else {
                ComingSoon(what: "No session running", symbol: "dumbbell")
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 560, height: 800)
        #endif
        .background(StrandPalette.surfaceBase)
        .disabled(session.isSaving)
        .keyboardDoneToolbar($focused)
        .dismissesKeyboardOnTap($focused)
        // Re-read whenever the session's exercises change, so an exercise added mid-session that was
        // done before shows last time's numbers in grey, like every other line.
        .task(id: engine?.plan.map(\.exercise)) { await loadLastTime() }
        // Release a field's draft once the user leaves it, so the row returns to the canonical
        // formatting ("45.50" typed becomes "45.5"). The single-argument form on purpose: the
        // two-argument `onChange` is macOS 14+ and this file also builds for macOS 13.
        .onChange(of: focused) { now in
            draft = draft.filter { $0.key == now }
        }
        .sheet(isPresented: $showingFinish) { finishSheet }
        .alert("Session needs attention", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "Your session is still available. Please try again.") }
    }

    // MARK: - The scrollable sheet

    private func sheet(_ engine: LiftSessionEngine) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    header(engine)
                    LiftCollectionReadout(fromTs: engine.startTs, deviceId: session.sourceDeviceId)
                    ForEach(Array(engine.plan.enumerated()), id: \.offset) { index, item in
                        exerciseCard(engine, index: index, item: item)
                    }
                    addExerciseRow(engine)
                    if dynamicTypeSize.isAccessibilitySize { controlBar(engine) }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, NoopMetrics.screenPadding)
                .padding(.top, 18)
            }
            .onChange(of: engine.currentSlot) { slot in
                // Follow the session down the sheet, but only when it moves on its own — scrolling
                // back to read an earlier exercise must not be yanked away from.
                guard let slot else { return }
                withAnimation { proxy.scrollTo(slot.exerciseIndex, anchor: .top) }
            }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
            .sheet(isPresented: $addingExercise) {
                LiftSessionExerciseSheet { name, primary, secondaries in
                    guard session.addExercise(name, primaryMuscle: primary,
                                              secondaryMuscles: secondaries) else { return }
                    scrollTarget = (session.engine?.plan.count ?? 1) - 1
                }
            }
        }
    }

    /// Add an exercise the program does not have — at the END of the sheet, after everything planned,
    /// because that is where it goes: the program's lines keep their order, and the new one is tapped to
    /// start whenever the lifter gets to it (Utku, 21 Sep 2026). Finishing asks whether the program keeps
    /// it; until then it changes this session only, like ⊕/⊖.
    private func addExerciseRow(_ engine: LiftSessionEngine) -> some View {
        let canAdd = engine.plan.count < LiftSessionEngine.maxExercises
        return Button {
            addingExercise = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(StrandFont.headline.weight(.semibold))
                Text("Add exercise").font(StrandFont.body)
            }
            .foregroundStyle(canAdd ? StrandPalette.effortColor : StrandPalette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .strokeBorder(StrandPalette.textTertiary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(NoopFeedbackButtonStyle())
        .disabled(!canAdd)
    }

    private func header(_ engine: LiftSessionEngine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.programName ?? String(localized: "Session"))
                .font(StrandFont.title1)
                .foregroundStyle(StrandPalette.textPrimary)
            Text(String(localized: "\(engine.completedWorkingSets) of \(engine.plannedWorkingSets) sets done"))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One exercise, with all its sets

    private func exerciseCard(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.exercise)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(LiftMuscleSummary.line(primary: item.primaryMuscle,
                                                secondaries: item.secondaryMuscles))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // Belt and braces with the entry cap: the sets are what this screen is for,
                        // and a note must never be able to push them off it.
                        .lineLimit(4)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StrandPalette.metricAmber.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                columnHeadings

                ForEach(engine.slots(forExercise: index), id: \.self) { slot in
                    setRow(engine, slot: slot)
                    // The rest belongs BETWEEN two sets, because that is where it happens.
                    if isRestingAfter(engine, slot: slot) { restBand(engine) }
                }

                setCountRow(engine, index: index, item: item)
            }
        }
        .id(index)
    }

    /// Add one more set, or drop the last planned one — at the END of the exercise, because that is
    /// where the question comes up: you have done what was written down and have one more in you, or
    /// you have not. Until this existed the sheet drew exactly `1...targetSets` and the extra set was
    /// performed and then lost.
    ///
    /// The geometry mirrors a set row: the minus sits in the tick column, under the checks it undoes.
    ///
    /// **Both buttons change this session only.** Whether the program keeps the new count is asked
    /// when the session is finished: a program is a plan for next time, and one extra set on a good
    /// day is not always a new plan.
    private func setCountRow(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        let canAdd = item.targetSets < LiftSessionEngine.maxSetsPerExercise
        let canRemove = engine.canRemoveSet(fromExercise: index)

        return HStack(spacing: 8) {
            Button {
                session.addSet(toExercise: index)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(StrandFont.headline.weight(.semibold))
                    Text("Add set").font(StrandFont.caption)
                }
                .foregroundStyle(canAdd ? StrandPalette.effortColor : StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .disabled(!canAdd)
            .accessibilityLabel(String(localized: "Add a set to \(item.exercise)"))

            Button {
                session.removeSet(fromExercise: index)
            } label: {
                Image(systemName: "minus.circle")
                    .font(StrandFont.headline.weight(.semibold))
                    // Dimmed rather than gone: the pair reads as one control, and a minus that
                    // disappears once the last set is done looks like a feature that broke.
                    .foregroundStyle(canRemove ? StrandPalette.textSecondary
                                               : StrandPalette.textTertiary.opacity(0.4))
                    .frame(width: Self.tickColumnWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .disabled(!canRemove)
            .accessibilityLabel(String(localized: "Remove the last set from \(item.exercise)"))
        }
        .padding(.top, 2)
        .padding(.horizontal, 8)
    }

    /// Width of the set-number column, shared by the heading and every row so the number sits
    /// directly under its label.
    ///
    /// Matches the warm-up button's minimum touch target. Accessibility sizes use labeled inputs
    /// instead of squeezing the table's headings and fields into these columns.
    static let setColumnWidth: CGFloat = NoopMetrics.minimumTouchTarget

    /// Width of the trailing tick column. Mirrored by a clear spacer in the heading row so the four
    /// labels sit over the four things they name.
    private static let tickColumnWidth: CGFloat = NoopMetrics.minimumTouchTarget

    private var columnHeadings: some View {
        Group { if !dynamicTypeSize.isAccessibilitySize { HStack(spacing: NoopMetrics.space2) {
            Text("Set").strandOverline()
                .frame(width: Self.setColumnWidth, alignment: .center)
            Text(weightHeading).strandOverline().frame(maxWidth: .infinity, alignment: .leading)
            Text("Reps").strandOverline().frame(maxWidth: .infinity, alignment: .leading)
            Text("RPE").strandOverline().frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Self.tickColumnWidth)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        } }
    }

    private var weightHeading: LocalizedStringKey {
        unitSystem == .imperial ? "Lb" : "Kg"
    }

    // MARK: - One set row

    private func setRow(_ engine: LiftSessionEngine, slot: LiftSlot) -> some View {
        let recorded = engine.recordedSet(for: slot)
        let isWorking = engine.stage == .working(slot)

        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
            : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
        return rowLayout {
            // The set number IS the warm-up toggle. Warm-ups are excluded from volume and from the
            // per-muscle counts, so being unable to mark one silently inflates the single figure the
            // whole feature rests on — it has to be reachable in one tap, without leaving the row.
            Button {
                toggleWarmup(slot)
            } label: {
                Text(isWarmup(slot) ? String(localized: "W") : "\(slot.setIndex)")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(isWarmup(slot)
                                     ? StrandPalette.metricAmber
                                     : (isWorking ? StrandPalette.textPrimary
                                                  : StrandPalette.textSecondary))
                    .frame(width: Self.setColumnWidth, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .accessibilityLabel(isWarmup(slot)
                                ? String(localized: "Warm-up set — tap to make it a working set")
                                : String(localized: "Set \(slot.setIndex) — tap to mark it a warm-up"))

            setInput(weightHeading, slot: slot, field: .weight(slot), text: weightBinding(slot), ghost: ghostWeight(slot))
            setInput("Reps", slot: slot, field: .reps(slot), text: repsBinding(slot), ghost: ghostReps(slot))
            setInput("RPE", slot: slot, field: .rpe(slot), text: rpeBinding(slot), ghost: ghostRpe(engine, slot: slot))

            // The tick both REPORTS and ACTS: filled when the set is done, and tappable to start
            // this set when it is not — which is how you jump to a different exercise.
            Button {
                session.start(slot)
            } label: {
                Image(systemName: recorded == nil ? "circle" : "checkmark.circle.fill")
                    .font(StrandFont.headline.weight(.semibold))
                    .foregroundStyle(recorded == nil
                                     ? StrandPalette.textTertiary
                                     : StrandPalette.statusPositive)
            }
            .buttonStyle(NoopFeedbackButtonStyle())
            .frame(width: Self.tickColumnWidth)
            .accessibilityLabel(recorded == nil
                                ? String(localized: "Start this set")
                                : String(localized: "Redo this set"))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(rowBackground(isWorking: isWorking, done: recorded != nil),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private func setInput(_ title: LocalizedStringKey, slot: LiftSlot, field: FocusTarget,
                                      text: Binding<String>, ghost: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                numberField(slot: slot, field: field, text: text, ghost: ghost)
            }
        } else {
            numberField(slot: slot, field: field, text: text, ghost: ghost)
        }
    }

    /// Warm-up state lives in the controller, so a mark survives the sheet being minimised and
    /// applies however the set was closed out — button, strap, or the minimised bar.
    private func isWarmup(_ slot: LiftSlot) -> Bool { session.isWarmup(slot) }

    private func toggleWarmup(_ slot: LiftSlot) {
        session.setWarmup(slot, !session.isWarmup(slot))
    }

    /// Green = working now, faint = done, clear = still to come.
    ///
    /// Deliberately no amber case. Tinting the just-finished SET amber said the wrong thing: the set
    /// is over, and what is running is the gap after it. The rest is drawn as its own band between
    /// the two set rows instead — see `restBand`.
    private func rowBackground(isWorking: Bool, done: Bool) -> Color {
        if isWorking { return StrandPalette.statusPositive.opacity(0.20) }
        if done { return StrandPalette.surfaceRaised.opacity(0.5) }
        return .clear
    }

    private func isRestingAfter(_ engine: LiftSessionEngine, slot: LiftSlot) -> Bool {
        if case .resting(let s, _) = engine.stage { return s == slot }
        return false
    }

    /// The running rest, drawn as an amber band sitting BETWEEN the set that ended and the set that
    /// follows — which is literally where a rest is.
    ///
    /// It replaces tinting the finished set's row amber. That read as "this set is amber" when the
    /// set was already done, and from across a gym floor it was not obvious which gap was running.
    /// A band in the gap is unambiguous at a glance, which is the whole requirement: you are looking
    /// at this from a bench, not reading it.
    ///
    /// It carries the countdown as well as the colour. The control bar has the same number, but the
    /// control bar is pinned to the bottom and this is where your eyes already are — and once the
    /// sheet is scrolled to a later exercise, the band is the only thing that says which rest.
    private func restBand(_ engine: LiftSessionEngine) -> some View {
        HStack(spacing: 8) {
            Text("Rest period").strandOverline()
                .foregroundStyle(StrandPalette.metricAmber)
            Spacer(minLength: 0)
            LiftRunningClock { engine.restRemaining(now: $0) ?? 0 }
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.metricAmber)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(StrandPalette.metricAmber.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private func numberField(slot: LiftSlot, field: FocusTarget,
                             text: Binding<String>, ghost: String) -> some View {
        TextField(ghost, text: text)
            .textFieldStyle(.plain)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(StrandPalette.textPrimary)
            .numericKeyboard()
            .focused($focused, equals: field)
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget, alignment: .leading)
            .accessibilityLabel(inputLabel(field))
    }

    private func inputLabel(_ field: FocusTarget) -> Text {
        switch field {
        case .weight(let slot): return Text("Weight for set \(slot.setIndex), \(unitSystem == .imperial ? "pounds" : "kilograms")")
        case .reps(let slot): return Text("Repetitions for set \(slot.setIndex)")
        case .rpe(let slot): return Text("RPE for set \(slot.setIndex)")
        case .sessionRpe: return Text("Session RPE")
        }
    }

    // MARK: - Ghost values
    //
    // The grey numbers come from ONE chain, `LiftSessionController.carry(for:)`: this exercise earlier
    // in the session (set 2 almost always mirrors set 1), then the same set last session, then the
    // program's target. The minimised bar and the Lock Screen read the same chain.
    //
    // A set keeps its grey numbers after it is done, until something is typed over them — grey means
    // "not entered". What they are worth is decided when the session is finished: every set without
    // typed numbers is completed with them, or discarded, in one choice.

    private func ghostWeight(_ slot: LiftSlot) -> String {
        session.carry(for: slot).weightKg.map { display($0) } ?? "—"
    }

    private func ghostReps(_ slot: LiftSlot) -> String {
        session.carry(for: slot).reps.map(String.init) ?? "—"
    }

    /// Grey RPE is the line's max RPE when the program sets one — and, like every other grey number, it is
    /// what the set saves if nothing is typed over it (RULES 34). A previous set's own rating is shown as a
    /// reminder when the plan sets no maximum, and that one is never saved: it belongs to another set.
    private func ghostRpe(_ engine: LiftSessionEngine, slot: LiftSlot) -> String {
        if let planned = engine.planItem(for: slot)?.targetRpe { return LiftFormat.trim(planned) }
        return engine.previousSetInSession(for: slot)?.rpe.map { LiftFormat.trim($0) } ?? "—"
    }

    private func display(_ kg: Double) -> String {
        LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: unitSystem))
    }

    // MARK: - Field bindings
    //
    // Each field reads and writes THROUGH the controller, so a keystroke lands in the engine and on
    // disk immediately.
    //
    // TYPING INTO ANY SET, AT ANY TIME. A set that has already been performed is edited in place; one
    // that has not is held in `LiftSessionController.pendingValues` and applied the moment it is
    // recorded. The two are indistinguishable from the row, which is the requirement: being mid-set
    // on one machine is no reason to refuse a correction to another row you are looking at.
    //
    // This used to be a claim rather than a behaviour — the comment here said the value was "held
    // until the set is recorded" while `write` silently dropped it — and a real session found it:
    // "when I type something during an active set to other sets it refreshes to the empty".

    /// A text binding that does not fight the user while they type: reads the draft if there is one,
    /// otherwise the canonical rendering of what is stored.
    ///
    /// A typed comma becomes a point on the way in. iOS's `.decimalPad` labels its separator key
    /// from the DEVICE's region — a German or French phone offers "," and the app cannot relabel it
    /// — so the two would otherwise disagree with the "." this screen displays everywhere else.
    /// Normalising here means the field always reads back in the notation it shows, whichever key
    /// the keyboard happened to offer.
    private func fieldBinding(_ field: FocusTarget,
                              formatted: @escaping () -> String,
                              store: @escaping (String) -> Void) -> Binding<String> {
        Binding(
            get: { draft[field] ?? formatted() },
            set: { typed in
                let text = typed.replacingOccurrences(of: ",", with: ".")
                draft[field] = text
                store(text)
            })
    }

    private func weightBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.weight(slot),
                     formatted: { session.enteredValues(for: slot).weightKg.map { display($0) } ?? "" },
                     store: { text in
                         let kg = LiftFormat.number(text).map {
                             LiftFormat.kilograms(fromDisplay: $0, system: unitSystem)
                         }
                         write(slot) { $0.weightKg = kg }
                     })
    }

    private func repsBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.reps(slot),
                     formatted: { session.enteredValues(for: slot).reps.map(String.init) ?? "" },
                     store: { text in
                         write(slot) { $0.reps = Int(text.trimmingCharacters(in: .whitespaces)) }
                     })
    }

    private func rpeBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.rpe(slot),
                     formatted: { session.enteredValues(for: slot).rpe.map { LiftFormat.trim($0) } ?? "" },
                     store: { text in write(slot) { $0.rpe = LiftFormat.number(text) } })
    }

    /// Apply one field change to a set, leaving its other fields as they were.
    ///
    /// Works whether or not the set has been performed — the controller decides where the value
    /// lands. It reads the CURRENT entered values first, so editing the reps cannot blank a weight
    /// that was typed a moment ago into the same pending row.
    private func write(_ slot: LiftSlot, _ mutate: (inout LiftRecordedSet) -> Void) {
        let entered = session.enteredValues(for: slot)
        var row = LiftRecordedSet(exerciseIndex: slot.exerciseIndex, setIndex: slot.setIndex,
                                  weightKg: entered.weightKg, reps: entered.reps, rpe: entered.rpe,
                                  isWarmup: session.isWarmup(slot), startTs: 0, endTs: 0, restSec: nil)
        mutate(&row)
        session.updateSet(slot, weightKg: row.weightKg, reps: row.reps,
                          rpe: row.rpe, isWarmup: row.isWarmup)
    }

    // MARK: - The control bar

    private func controlBar(_ engine: LiftSessionEngine) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space3))
            : AnyLayout(HStackLayout(spacing: NoopMetrics.space3))
        return VStack(spacing: NoopMetrics.rowSpacing) {
            layout {
                clock(String(localized: "Session"), tint: StrandPalette.textPrimary) { $0 - engine.startTs }
                stageClock(engine)
                heartRate()
                Spacer(minLength: 0)
                Button { session.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(StrandFont.subhead.weight(.semibold))
                }
                .buttonStyle(NoopFeedbackButtonStyle())
                .foregroundStyle(engine.canUndo ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                .disabled(!engine.canUndo)
                .accessibilityLabel("Undo")
            }

            layout {
                Button { session.advance() } label: {
                    Text(actionLabel(engine)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.noopPrimary)

                Button {
                    unfinishedChoice = nil
                    programChoice = nil
                    setCountChanges = []
                    showingFinish = true
                } label: {
                    Text("Finish")
                }
                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: dynamicTypeSize.isAccessibilitySize))
            }
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, NoopMetrics.space2)
        .padding(.bottom, NoopMetrics.space3)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(StrandPalette.textTertiary.opacity(0.15)).frame(height: 0.5)
        }
    }

    /// Live heart rate, beside the clocks that are already pinned above the action button.
    ///
    /// It belongs here and not in the scrolling sheet: this strip is the part that never scrolls
    /// away, and a glance mid-set is the whole use — you are holding a bar, not browsing. Asked for
    /// after a real session. Always shown, dash included, and display only (`LiftHeartRate`).
    private func heartRate() -> some View {
        labelled(String(localized: "HR")) { LiftHeartRate(style: .plain) }
    }

    /// A running clock under its label. `seconds` turns the current unix second into what it reads.
    private func clock(_ label: String, tint: Color, seconds: @escaping (Int) -> Int) -> some View {
        labelled(label) {
            LiftRunningClock(seconds: seconds)
                .font(StrandFont.bodyNumber)
                .foregroundStyle(tint)
        }
    }

    private func labelled<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(label).strandOverline()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
            value()
        }
    }

    @ViewBuilder
    private func stageClock(_ engine: LiftSessionEngine) -> some View {
        switch engine.stage {
        case .working:
            clock(String(localized: "This set"), tint: StrandPalette.statusPositive) {
                $0 - engine.stageStartedAt
            }
        case .resting:
            // "Rest period", never "Rest": the catalog's "Rest" key is NOOP's SLEEP metric, so this
            // label rendered as "Erholung" (recovery) in German — the exact collision CLAUDE.md and
            // the handover brief both warn about. Reintroduced by the workout-sheet rewrite.
            clock(String(localized: "Rest period"), tint: StrandPalette.metricAmber) {
                engine.restRemaining(now: $0) ?? 0
            }
        case .warmup, .finished:
            clock(String(localized: "Warm-up"), tint: StrandPalette.textSecondary) {
                $0 - engine.stageStartedAt
            }
        }
    }

    private func actionLabel(_ engine: LiftSessionEngine) -> LocalizedStringKey {
        switch engine.stage {
        case .warmup:   return "Start first set"
        case .working:  return "Set done"
        case .resting:  return engine.allCompleted ? "All sets done" : "Start next set"
        case .finished: return "Saving…"
        }
    }

    // MARK: - Finish

    private var finishSheet: some View {
        let unfinished = session.unfinishedSlots.count
        let asksAboutProgram = !setCountChanges.isEmpty || !addedExercises.isEmpty
        let answered = (unfinished == 0 || unfinishedChoice != nil)
            && (!asksAboutProgram || programChoice != nil)
        return ScreenScaffold(title: "Finish session",
                              subtitle: "One number for the whole session, so a leg day can be compared with a run.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        Text("How hard was the whole session? (1–10)").strandOverline()
                        TextField("7", text: $sessionRpeText)
                            .textFieldStyle(.plain)
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .numericKeyboard()
                            .focused($focused, equals: .sessionRpe)
                        Text("This is session RPE. Multiplied by the session's length it gives session load — the one figure that compares across completely different training.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if unfinished > 0 { unfinishedCard(count: unfinished) }
                if asksAboutProgram { programCard }

                // One way to save. Session RPE above is optional, so an empty field is simply no rating;
                // a separate "Skip" saved exactly the same way and read as a second choice.
                NoopActionButton("Save session", fullWidth: true, state: saving ? .working : .idle) { Task { await save() } }
                    .disabled(saving || !answered)
                if !answered {
                    Text("Choose an option above to save.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }

                // A way OUT that records nothing. Until this existed, the only route off this screen
                // saved. A session started by a mis-tap, or to try something out, had to be saved and
                // then lived in the history and in that day's Effort for good.
                Button(role: .destructive) {
                    confirmingDiscard = true
                } label: {
                    Label("Discard session", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NoopFeedbackButtonStyle())
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.statusCritical)
                .padding(.top, 4)
                .disabled(saving)
                .confirmationDialog("Discard this session?",
                                    isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) {
                        session.discard()
                        showingFinish = false
                    }
                    Button("Keep going", role: .cancel) { }
                } message: {
                    Text("\(engine?.completedWorkingSets ?? 0) recorded sets will be thrown away. Nothing is saved and no workout is created.")
                }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 460, height: 420)
        #endif
        .background(StrandPalette.surfaceBase)
        .keyboardDoneToolbar($focused)
        .task { await loadSetCountChanges() }
    }

    /// Sets never started. One choice covers all of them, because what matters at the end of a session
    /// is simply whether they happened: complete them with the numbers the sheet showed, or discard them
    /// to zeros that every figure leaves out and Edit sets can still fill in. A set that was done is never
    /// asked about — it is complete (`LiftSessionController.setsToSave`).
    private func unfinishedCard(count: Int) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text("Unfinished sets").strandOverline()
                Text("Sets not started: \(count)")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Unfinished sets", selection: $unfinishedChoice) {
                    Text("Complete them").tag(UnfinishedChoice?.some(.complete))
                    Text("Discard them").tag(UnfinishedChoice?.some(.discard))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Completing saves them with the grey numbers shown. Discarding keeps them out of every figure; they stay under Edit sets as zeros you can fill in later.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // Said before Save rather than after: `save` files nothing when no set counts.
                if unfinishedChoice == .discard,
                   !LiftSessionController.anyPerformed(session.setsToSave(completingUnfinished: false)) {
                    Text("Every set would be a zero, so discarding saves no session and no workout.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Exercises added during the session, which the program does not have yet.
    private var addedExercises: [LiftPlanItem] {
        session.engine?.plan.filter(\.addedInSession) ?? []
    }

    /// Set counts changed with ⊕/⊖, and exercises added, during the session. The program keeps them only
    /// if asked to — one answer for all of them, listed so the lifter sees what "update" would write.
    private var programCard: some View {
        let added = addedExercises
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text("Program").strandOverline()
                Text(programQuestion(countsChanged: !setCountChanges.isEmpty, exercisesAdded: !added.isEmpty))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(setCountChanges, id: \.itemId) { change in
                    Text("\(change.exercise): \(change.from) → \(change.to) sets")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(Array(added.enumerated()), id: \.offset) { _, line in
                    Text("New: \(line.exercise) · sets: \(line.targetSets)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Picker("Program", selection: $programChoice) {
                    Text("Update program").tag(ProgramChoice?.some(.update))
                    Text("Keep as it was").tag(ProgramChoice?.some(.keep))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    /// The program question, worded for what actually changed.
    private func programQuestion(countsChanged: Bool, exercisesAdded: Bool) -> LocalizedStringKey {
        switch (countsChanged, exercisesAdded) {
        case (true, true):  return "You added exercises and changed the number of sets. Keep these changes in the program for next time?"
        case (false, true): return "You added exercises. Add them to the program for next time?"
        default:            return "You changed the number of sets. Keep the new counts in the program for next time?"
        }
    }

    // MARK: - Loading and saving

    /// What was lifted for each of this session's exercises LAST time, by set number — the middle
    /// layer of the grey numbers, handed to the controller that owns the chain.
    private func loadLastTime() async {
        guard let engine, let store = await repo.storeHandle() else { return }
        var out: [String: [Int: LiftSetCarry]] = [:]
        // One query per DISTINCT exercise, not per plan line. A program that programs the same
        // movement twice — or an imported one with many lines — would otherwise re-ask the store the
        // same question, and this runs when the sheet opens.
        for exercise in NSOrderedSet(array: engine.plan.map(\.exercise)).compactMap({ $0 as? String }) {
            let rows = (try? await store.lastLiftSets(deviceId: repo.deviceId,
                                                      exercise: exercise,
                                                      before: engine.startTs)) ?? []
            var bySet: [Int: LiftSetCarry] = [:]
            for r in rows where !r.isWarmup {
                bySet[r.setIndex] = LiftSetCarry(weightKg: r.weightKg, reps: r.reps)
            }
            out[exercise] = bySet
        }
        session.setLastSession(out)
    }

    private func save() async {
        guard !saving, session.beginSaving() else { return }
        saving = true
        defer { saving = false; session.endSaving() }
        guard let store = await repo.storeHandle() else {
            saveError = "Storage is unavailable. Your workout and entries are still open."
            return
        }
        do { try await save(to: store) }
        catch { saveError = error.localizedDescription }
    }

    private func save(to store: WhoopStore) async throws {
        guard let engine = session.engine else { return }
        let endTs = Int(Date().timeIntervalSince1970)
        let sessionId = (session.recordingId ?? UUID()).uuidString.lowercased()
        // After `finish`, which closes out the running rest: that set's measured rest belongs to it.
        let finished = session.setsToSave(completingUnfinished: unfinishedChoice == .complete, finishingAt: endTs)

        // Nothing to file, so file nothing. With no set done, "Discard them" turns every set into a zero.
        // Filing that anyway wrote a session with nothing in it AND a manual workout, and the engine fills
        // that workout's strain from the heart rate the strap measured — so an hour that recorded nothing
        // still read back as a workout. The finish sheet says so before Save. The program's set counts
        // are a separate thing the user chose explicitly, so those still apply.
        guard LiftSessionController.anyPerformed(finished) else {
            try await writeProgram(store: store, plan: engine.plan, sets: finished)
            await finishAndDismiss()
            return
        }

        let row = LiftSessionRow(
            id: sessionId, deviceId: session.sourceDeviceId ?? repo.deviceId,
            startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport,
            programId: session.programId,
            // Snapshot the name: renaming or deleting the program never rewrites this session.
            programName: session.programName,
            sessionRpe: LiftFormat.number(sessionRpeText),
            note: session.programName)

        // `ord` is COMPLETION order, which with out-of-order work is not the plan's order — and it
        // is the order that actually happened, which is what a session should read back as. Sets
        // completed at finish without being started come last.
        let rows = finished.enumerated().map { ord, s -> LiftSetRow in
            let item = engine.planItem(for: s.slot)
            return LiftSetRow(
                id: session.identity(for: s.slot).uuidString.lowercased(), deviceId: row.deviceId, sessionId: sessionId,
                ord: ord, exercise: item?.exercise ?? "",
                // Snapshot the classification AS IT WAS, so reclassifying later never rewrites what
                // past weeks were counted as.
                primaryMuscle: item?.primaryMuscle,
                secondaryMuscles: item?.secondaryMuscles ?? [],
                setIndex: s.slot.setIndex, weightKg: s.weightKg, reps: s.reps, rpe: s.rpe,
                isWarmup: s.isWarmup, startTs: s.startTs, endTs: s.endTs,
                restSec: s.restSec, note: nil)
        }
        // Through the SAME path a manual workout takes, so it inherits overlap dedup, the engine's
        // HR-derived strain fill and delete/merge. `strain` stays nil deliberately: the engine fills
        // it from the heart rate the strap MEASURED, never from typed sets and reps.
        let workout = WorkoutRow(
            startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport,
            source: "manual", durationS: Double(max(0, endTs - engine.startTs)),
            energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
            distanceM: nil, zonesJSON: nil, notes: session.programName, steps: nil)
        let updatedProgramItems = try await programChanges(store: store, plan: engine.plan, sets: finished)
        #if os(iOS)
        let trackerEvent = try session.trackerBinding.map { try WorkoutTrackerClient.shared.prepare(record: row, sets: rows, binding: $0) }
        #endif
        try await store.saveLiftRecording(session: row, sets: rows, workout: workout, updatedProgramItems: updatedProgramItems)
        #if os(iOS)
        if let trackerEvent {
            do { try await WorkoutTrackerClient.shared.confirmPersistence(trackerEvent, store: store) }
            catch {
                saveError = "The workout is saved locally, but delivery state could not be finalized. Your active session is retained for recovery."
                return
            }
        }
        #endif

        await finishAndDismiss()
        #if os(iOS)
        if trackerEvent != nil, WorkoutTrackerClient.shared.state.enabled {
            Task { try? await WorkoutTrackerClient.shared.synchronize(store: store) }
        }
        #endif
    }

    /// Close the session down and leave the sheet. Shared by the normal save and the nothing-to-file
    /// path above, so the two cannot drift about what ending a session means.
    private func finishAndDismiss() async {
        session.finishedSaving()
        await repo.refresh()
        await onFinished()
        showingFinish = false
        dismiss()
    }

    /// The program lines whose set count this session changed, for the finish sheet to ask about.
    private func loadSetCountChanges() async {
        guard let programId = session.programId, let plan = session.engine?.plan,
              let store = await repo.storeHandle(),
              let rows = try? await store.liftProgramItems(programId: programId) else { return }
        setCountChanges = LiftSessionController.setCountChanges(plan: plan, program: rows)
    }

    /// Carry this session onto its program (`LiftSessionController.programAfterSession`): each line's
    /// heaviest done set becomes its weight and reps (always, Utku 21 Sep 2026); changed set counts and
    /// exercises added during the session reach it only when the user chose to keep them.
    ///
    /// Re-reads the lines, so a program edited elsewhere while the session ran keeps every other change
    /// and a line deleted since is not resurrected. The store call replaces the lines wholesale, so
    /// nothing is written when no line differs.
    private func writeProgram(store: WhoopStore, plan: [LiftPlanItem],
                              sets: [LiftSessionController.FinishedSet]) async throws {
        guard let programId = session.programId,
              let edited = try await programChanges(store: store, plan: plan, sets: sets) else { return }
        _ = try await store.replaceLiftProgramItems(programId: programId, items: edited)
    }

    private func programChanges(store: WhoopStore, plan: [LiftPlanItem],
                                sets: [LiftSessionController.FinishedSet]) async throws -> [LiftProgramItemRow]? {
        guard let programId = session.programId else { return nil }
        let rows = try await store.liftProgramItems(programId: programId)
        let edited = LiftSessionController.programAfterSession(
            sets, plan: plan, program: rows, keepingChanges: programChoice == .update,
            programId: programId, deviceId: session.sourceDeviceId ?? repo.deviceId)
        return edited != rows ? edited : nil
    }

    /// The sport every logged session is filed under — the same token the Hevy/Liftosaur importer
    /// uses, so a typed session and an imported one land in one bucket with one icon.
    static let sport = "Strength Training"
}
