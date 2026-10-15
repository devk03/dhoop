#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutTrackerSetEditor: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let row: WorkoutTrackerDashboard.SetLog
    let revision: Int
    let system: UnitSystem
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var plannedLoad: String
    @State private var plannedReps: String
    @State private var actualLoad: String
    @State private var actualReps: String
    @State private var rir: String
    @State private var completed: Bool
    private let initial: [String]
    private var massScale: Double { system == .imperial ? 1 : UnitFormatter.poundsPerKilogram }
    private var massUnit: String { system == .imperial ? "lb" : "kg" }

    init(session: WorkoutTrackerDashboard.Session, exercise: WorkoutTrackerDashboard.Exercise,
         row: WorkoutTrackerDashboard.SetLog, revision: Int, system: UnitSystem) {
        self.session = session; self.exercise = exercise; self.row = row; self.revision = revision; self.system = system
        let scale = system == .imperial ? 1 : UnitFormatter.poundsPerKilogram
        func text(_ n: Double?) -> String { n.map { WorkoutFrontendInput.text(.number($0)) } ?? "" }
        let values = [text(row.plannedLoad / scale), String(row.plannedReps), text(row.actualLoad.map { $0 / scale }),
            row.actualReps.map(String.init) ?? "", text(row.rir)]
        initial = values
        _plannedLoad = State(initialValue: values[0]); _plannedReps = State(initialValue: values[1])
        _actualLoad = State(initialValue: values[2]); _actualReps = State(initialValue: values[3])
        _rir = State(initialValue: values[4]); _completed = State(initialValue: row.completed)
    }
    var body: some View {
        ScreenScaffold(title: "Log set", subtitle: LocalizedStringKey("\(exercise.name) · set \(row.setNumber)")) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Performed").font(StrandFont.headline)
                        Text(WorkoutTrackerLoadMode(rawValue: exercise.loadMode)?.explanation ?? exercise.loadMode)
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if WorkoutTrackerLoadMode(rawValue: exercise.loadMode)?.hasMass == true {
                            WorkoutFrontendTextField(title: "Actual load (\(massUnit))", text: $actualLoad, numeric: true)
                        }
                        if exercise.loadMode != "duration" {
                            WorkoutFrontendTextField(title: "Actual repetitions", text: $actualReps, numeric: true)
                            WorkoutFrontendTextField(title: "Repetitions in reserve · optional", text: $rir, numeric: true)
                        }
                        Toggle("Set completed", isOn: $completed).toggleStyle(NoopSwitchStyle())
                        Text("Blank actuals explicitly clear that value. A prescribed target is never entered as performed work.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if exercise.loadMode != "duration" { DisclosureGroup("Edit prescribed targets") {
                    VStack(spacing: NoopMetrics.space3) {
                        if WorkoutTrackerLoadMode(rawValue: exercise.loadMode)?.hasMass == true {
                            WorkoutFrontendTextField(title: "Planned load (\(massUnit))", text: $plannedLoad, numeric: true)
                        }
                        WorkoutFrontendTextField(title: "Planned repetitions", text: $plannedReps, numeric: true)
                    }
                }.font(StrandFont.subhead) }
                WorkoutFrontendSubmitSection(title: "Save set in Life", action: "update_set", revision: revision, command: build) {
                    try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id)
                }
            }
        }
    }
    private func build() throws -> [String: WorkoutTrackerValue] {
        var result: [String: WorkoutTrackerValue] = ["action": .string("update_set"), "mesocycleId": .number(Double(session.mesocycleId)),
            "sessionId": .number(Double(session.id)), "setId": .number(Double(row.id))]
        if plannedLoad != initial[0] { result["plannedLoad"] = try WorkoutFrontendInput.number(plannedLoad, label: "planned load", range: 0...5000, scale: massScale) }
        if plannedReps != initial[1] { result["plannedReps"] = try WorkoutFrontendInput.number(plannedReps, label: "planned repetitions", range: 1...100, integer: true) }
        if actualLoad != initial[2] { result["actualLoad"] = try WorkoutFrontendInput.number(actualLoad, label: "actual load", range: 0...5000, optional: true, scale: massScale) }
        if actualReps != initial[3] { result["actualReps"] = try WorkoutFrontendInput.number(actualReps, label: "actual repetitions", range: 0...100, integer: true, optional: true) }
        if rir != initial[4] { result["rir"] = try WorkoutFrontendInput.number(rir, label: "repetitions in reserve from 0 to 5", range: 0...5, integer: true, optional: true) }
        if completed != row.completed { result["completed"] = .bool(completed) }
        guard result.count > 4 else { throw WorkoutFrontendInput.Invalid(message: "Change a value or mark the set completed first.") }
        return result
    }
}

struct WorkoutTrackerExerciseEditor: View {
    let session: WorkoutTrackerDashboard.Session
    let exercise: WorkoutTrackerDashboard.Exercise
    let library: [WorkoutTrackerDashboard.LibraryItem]
    let revision: Int
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var replacement = ""
    @State private var direction = "lighter"
    @State private var oneOffName = ""
    @State private var loadedName = false
    private var base: [String: WorkoutTrackerValue] {
        ["mesocycleId": .number(Double(session.mesocycleId)), "sessionId": .number(Double(session.id))]
    }
    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(exercise.name), subtitle: "Shared program changes") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Adjust progression").font(StrandFont.headline)
                        Picker("Direction", selection: $direction) { Text("Lighter").tag("lighter"); Text("Heavier").tag("heavier") }
                        Text("Life applies the same progression and override rules as the website.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        WorkoutFrontendSubmitSection(title: "Apply adjustment", action: "tune_exercise", revision: revision, command: {
                            base.merging(["action": .string("tune_exercise"), "exerciseKey": .string(exercise.exerciseKey), "direction": .string(direction)]) { _, new in new }
                        }, refresh: refresh)
                    }
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Replace program exercise").font(StrandFont.headline)
                        Picker("Replacement", selection: $replacement) {
                            Text("Choose an exercise").tag("")
                            ForEach(library.filter { $0.movementPattern == exercise.movementPattern && $0.exerciseKey != exercise.exerciseKey }) {
                                Text($0.name).tag($0.exerciseKey)
                            }
                        }
                        Text("Changes the shared program. Life verifies eligibility; completed work remains in history.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        WorkoutFrontendSubmitSection(title: "Replace in Life", action: "substitute_exercise", revision: revision, command: {
                            guard !replacement.isEmpty else { throw WorkoutFrontendInput.Invalid(message: "Choose a replacement first.") }
                            return base.merging(["action": .string("substitute_exercise"), "sessionExerciseId": .number(Double(exercise.id)),
                                "replacementExerciseKey": .string(replacement)]) { _, new in new }
                        }, refresh: refresh)
                    }
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("This workout only").font(StrandFont.headline)
                        WorkoutFrontendTextField(title: "Exercise display name · optional", text: $oneOffName)
                        Text("Does not create a catalog exercise or change the original exercise's progression. Clear the name to restore the original.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        WorkoutFrontendSubmitSection(title: "Save workout-only replacement", action: "update_session", revision: revision, command: {
                            let name = oneOffName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard name.count <= 80 else { throw WorkoutFrontendInput.Invalid(message: "Exercise display name must be at most 80 characters.") }
                            var metrics = session.metrics
                            var substitutions: [String: WorkoutTrackerValue] = [:]
                            if case .object(let existing) = metrics["exerciseSubstitutions"] { substitutions = existing }
                            if name.isEmpty || name.caseInsensitiveCompare(exercise.name) == .orderedSame { substitutions.removeValue(forKey: exercise.exerciseKey) }
                            else { substitutions[exercise.exerciseKey] = .object(["name": .string(name), "originalName": .string(exercise.name)]) }
                            metrics["exerciseSubstitutions"] = .object(substitutions)
                            return base.merging(["action": .string("update_session"), "metrics": .object(metrics)]) { _, new in new }
                        }, refresh: refresh)
                    }
                }
            }
        }
        .onAppear {
            guard !loadedName else { return }; loadedName = true
            if case .object(let all) = session.metrics["exerciseSubstitutions"],
               case .object(let entry) = all[exercise.exerciseKey], case .string(let name) = entry["name"] { oneOffName = name }
        }
    }
    private func refresh() async throws { try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id) }
}

struct WorkoutTrackerSessionEditor: View {
    let session: WorkoutTrackerDashboard.Session
    let revision: Int
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var readiness: String
    @State private var rating: String
    @State private var notes: String
    @State private var metrics: [String: WorkoutTrackerValue]
    @State private var finisher: [String: WorkoutTrackerValue]
    @State private var invalidFields: Set<String> = []
    init(session: WorkoutTrackerDashboard.Session, revision: Int) {
        self.session = session; self.revision = revision
        _readiness = State(initialValue: session.readiness); _rating = State(initialValue: session.rating)
        _notes = State(initialValue: session.notes); _metrics = State(initialValue: session.metrics)
        _finisher = State(initialValue: session.finisher?.metrics ?? [:])
    }
    var body: some View {
        ScreenScaffold(title: "Workout log", subtitle: LocalizedStringKey(session.title)) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Picker("Readiness", selection: $readiness) {
                            Text("Not logged").tag(""); Text("Good").tag("good"); Text("Normal").tag("normal"); Text("Low").tag("low")
                        }
                        Picker("After workout", selection: $rating) {
                            Text("Not logged").tag(""); Text("Great").tag("great"); Text("Good").tag("good"); Text("Hard").tag("hard"); Text("Bad").tag("bad")
                        }
                        Text("Notes").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        TextEditor(text: $notes).font(StrandFont.body).frame(minHeight: NoopMetrics.minimumTouchTarget * 3)
                        Text("\(notes.count) / 2,000 characters").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                WorkoutTrackerMetricsEditor(kind: session.kind, sessionKey: session.sessionKey, metrics: $metrics, invalidFields: $invalidFields)
                if session.finisher != nil {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Cardio finisher").font(StrandFont.headline)
                            Picker("Finisher", selection: Binding(get: {
                                if case .string(let mode) = finisher["mode"] { return mode }; return "airbike"
                            }, set: { finisher["mode"] = .string($0) })) {
                                Text("Air Bike").tag("airbike"); Text("StairMaster").tag("stairmaster")
                            }
                            WorkoutTrackerMetricsEditor(kind: finisher["mode"] == .string("stairmaster") ? "stairmaster" : "airbike",
                                sessionKey: "finisher", metrics: $finisher, invalidFields: $invalidFields)
                        }
                    }
                }
                WorkoutFrontendSubmitSection(title: "Save log in Life", action: "update_session", revision: revision, command: build, refresh: refresh)
                Text("Saving the log does not mark the workout complete. Use the workout's Complete action after reviewing your sets.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private func build() throws -> [String: WorkoutTrackerValue] {
        guard notes.count <= 2000 else { throw WorkoutFrontendInput.Invalid(message: "Notes must be at most 2,000 characters.") }
        guard invalidFields.isEmpty else { throw WorkoutFrontendInput.Invalid(message: "Correct the highlighted metric fields before saving.") }
        var result: [String: WorkoutTrackerValue] = ["action": .string("update_session"), "sessionId": .number(Double(session.id)),
            "mesocycleId": .number(Double(session.mesocycleId)), "readiness": .string(readiness), "rating": .string(rating), "notes": .string(notes), "metrics": .object(metrics)]
        if session.finisher != nil { result["finisherMetrics"] = .object(finisher) }
        return result
    }
    private func refresh() async throws { try await tracker.refreshDashboard(mesocycleId: session.mesocycleId, sessionId: session.id) }
}

/// Only performed metric fields are edited; untouched prescription and unknown keys survive.
struct WorkoutTrackerMetricsEditor: View {
    let kind: String
    let sessionKey: String
    @Binding var metrics: [String: WorkoutTrackerValue]
    @Binding var invalidFields: Set<String>
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            if kind == "run" {
                if sessionKey == "quality_or_soccer" {
                    Picker("Activity", selection: Binding(get: {
                        if case .string(let type) = metrics["activityType"] { return type }; return "quality_run"
                    }, set: { metrics["activityType"] = .string($0) })) {
                        Text("Quality run").tag("quality_run"); Text("Soccer").tag("soccer")
                    }
                }
                if metrics["activityType"] == .string("soccer") { number("Minutes played", key: "durationMinutes") }
                else if case .array(let values) = metrics["splits"] {
                    ForEach(values.indices, id: \.self) { index in
                        WorkoutTrackerMetricNumber(title: "Mile \(index + 1) time · seconds", fieldId: "\(sessionKey)-split-\(index)", invalidFields: $invalidFields, value: Binding(get: {
                            if case .array(let current) = metrics["splits"], current.indices.contains(index) { return current[index] }; return .null
                        }, set: { value in
                            if case .array(var current) = metrics["splits"], current.indices.contains(index) { current[index] = value; metrics["splits"] = .array(current) }
                        }))
                    }
                } else { number("Elapsed time · seconds", key: "timeSeconds") }
                if sessionKey == "four_mile" { number("Distance · miles", key: "distanceMiles") }
            } else if kind == "yoga" { number("Minutes completed", key: "durationMinutes") }
            else if kind == "airbike" { number("Rounds completed", key: "completedRounds") }
            else if kind == "stairmaster" {
                number("Minutes", key: "durationMinutes"); number("Level · optional", key: "stairmasterLevel"); number("Floors · optional", key: "floors")
            }
            if case .object = metrics["attachedRun"] {
                Text("Attached easy run").font(StrandFont.headline)
                number("Run time · seconds", key: "timeSeconds", parent: "attachedRun")
            }
            if case .object = metrics["airbike"] {
                Text("Attached Air Bike").font(StrandFont.headline)
                number("Rounds completed", key: "completedRounds", parent: "airbike")
            }
        }.font(StrandFont.subhead)
    }
    private func number(_ title: String, key: String, parent: String? = nil) -> some View {
        WorkoutTrackerMetricNumber(title: title, fieldId: "\(sessionKey)-\(parent ?? "session")-\(key)", invalidFields: $invalidFields, value: Binding(get: {
            if let parent, case .object(let nested) = metrics[parent] { return nested[key] ?? .null }
            return metrics[key] ?? .null
        }, set: { value in
            if let parent, case .object(var nested) = metrics[parent] { nested[key] = value; metrics[parent] = .object(nested) }
            else { metrics[key] = value }
        }))
    }
}

private struct WorkoutTrackerMetricNumber: View {
    let title: String
    let fieldId: String
    @Binding var invalidFields: Set<String>
    @Binding var value: WorkoutTrackerValue
    @State private var text = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            WorkoutFrontendTextField(title: title, text: $text, numeric: true)
                .onAppear { text = WorkoutFrontendInput.text(value) }
                .onChange(of: text) { _, input in
                    do {
                        value = try WorkoutFrontendInput.number(input, label: title, range: 0...1_000_000, optional: true)
                        invalid = false; invalidFields.remove(fieldId)
                    } catch { invalid = true; invalidFields.insert(fieldId) }
                }
            if invalid { Text("Enter a nonnegative number or clear the field.").font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical) }
        }
        .onDisappear { invalidFields.remove(fieldId) }
    }
}
#endif
