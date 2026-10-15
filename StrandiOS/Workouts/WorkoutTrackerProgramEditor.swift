#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutTrackerProgramEditor: View {
    let page: WorkoutTrackerDashboard
    @ObservedObject private var tracker = WorkoutTrackerClient.shared
    @State private var action = "update_athlete_profile"
    @State private var name = ""
    @State private var start = Date()
    @State private var race = Date()
    @State private var includeRace = false
    @State private var bodyweight = ""
    @State private var age = ""
    @State private var benchmarkValues: [String: String] = [:]
    @State private var reviewedReset = false
    @State private var initialized = false
    @State private var entryImperial = false
    @AppStorage(UnitPrefs.systemKey) private var units = UnitSystem.metric.rawValue
    private var imperial: Bool { entryImperial }
    private var scale: Double { imperial ? 1 : UnitFormatter.poundsPerKilogram }
    private var unit: String { imperial ? "lb" : "kg" }
    private var primary: [WorkoutTrackerDashboard.Benchmark] { page.dashboard.benchmarks.filter(\.isPrimary) }
    private let actions: [(String, String)] = [
        ("update_athlete_profile", "Athlete profile"), ("update_benchmarks", "Strength benchmarks"),
        ("recalculate_half_marathon_weights", "Recalculate remaining workouts"),
        ("create_four_lift_program", "Create four-lift program"), ("restart_half_marathon_program", "Restart half-marathon program"),
        ("create_mesocycle", "Create training cycle"), ("reset_mesocycle", "Reset this cycle")]

    var body: some View {
        ScreenScaffold(title: "Program settings", subtitle: LocalizedStringKey(page.dashboard.activeMesocycle?.name ?? "Life workout tracker")) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Picker("Change", selection: $action) {
                            ForEach(actions, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Text("Life applies the same validation, progression and schedule rules used by the website and MCP.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        if ["create_mesocycle", "create_four_lift_program", "restart_half_marathon_program"].contains(action) {
                            WorkoutFrontendTextField(title: "Program name · optional", text: $name)
                            DatePicker("Start date", selection: $start, displayedComponents: .date)
                        }
                        if action == "restart_half_marathon_program" {
                            Toggle("Set race date", isOn: $includeRace).toggleStyle(NoopSwitchStyle())
                            if includeRace { DatePicker("Race date", selection: $race, displayedComponents: .date) }
                        }
                        if action != "create_mesocycle" && action != "reset_mesocycle" && action != "recalculate_half_marathon_weights" {
                            WorkoutFrontendTextField(title: "Bodyweight (\(unit))", text: $bodyweight, numeric: true)
                        }
                        if ["update_athlete_profile", "create_four_lift_program", "restart_half_marathon_program"].contains(action) {
                            WorkoutFrontendTextField(title: "Age", text: $age, numeric: true)
                        }
                        if action == "update_benchmarks" {
                            ForEach(primary) { benchmark in
                                WorkoutFrontendTextField(title: "\(benchmark.name) · effective maximum (\(unit))",
                                    text: Binding(get: { benchmarkValues[benchmark.exerciseKey] ?? "" }, set: { benchmarkValues[benchmark.exerciseKey] = $0 }), numeric: true)
                            }
                            Text("Weighted pull-up uses total system load: bodyweight plus added weight. These are effective maximums, not set loads.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        if action == "reset_mesocycle" {
                            Text("Resetting changes this shared Life cycle and can clear its recorded results. Review its history and backup first.")
                                .font(StrandFont.body).foregroundStyle(StrandPalette.statusCritical)
                            Toggle("I intend to reset this cycle", isOn: $reviewedReset).toggleStyle(NoopSwitchStyle())
                        }
                        if action == "recalculate_half_marathon_weights" {
                            Text("Recalculate remaining prescriptions using Life's current benchmarks. Completed history and manual override rules are handled by Life.")
                                .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                WorkoutFrontendSubmitSection(title: "Apply in Life", action: action, revision: page.lifeRevision, command: build) {
                    try await tracker.refreshDashboard()
                }.id(action)
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true; entryImperial = units == UnitSystem.imperial.rawValue
            let config = page.dashboard.activeMesocycle?.config ?? [:]
            if case .number(let pounds) = config["bodyweight"] { bodyweight = WorkoutFrontendInput.text(.number(pounds / scale)) }
            age = WorkoutFrontendInput.text(config["age"])
            for benchmark in primary { benchmarkValues[benchmark.exerciseKey] = WorkoutFrontendInput.text(.number(benchmark.effectiveMax / scale)) }
        }
    }
    private func build() throws -> [String: WorkoutTrackerValue] {
        var result: [String: WorkoutTrackerValue] = ["action": .string(action)]
        let creating = ["create_mesocycle", "create_four_lift_program", "restart_half_marathon_program"].contains(action)
        if creating {
            guard name.count <= 200 else { throw WorkoutFrontendInput.Invalid(message: "Program name must be at most 200 characters.") }
            result["startDate"] = .string(date(start))
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result["name"] = .string(name) }
            if action == "restart_half_marathon_program", includeRace { result["raceDate"] = .string(date(race)) }
        } else {
            guard let cycle = page.dashboard.activeMesocycle else { throw WorkoutFrontendInput.Invalid(message: "Choose a Life training cycle first.") }
            result["mesocycleId"] = .number(Double(cycle.id))
        }
        if ["update_athlete_profile", "update_benchmarks"].contains(action) || (creating && action != "create_mesocycle" && !bodyweight.isEmpty) {
            result["bodyweight"] = try WorkoutFrontendInput.number(bodyweight, label: "bodyweight", range: 75...700, scale: scale)
        }
        if action == "update_athlete_profile" || (creating && action != "create_mesocycle" && !age.isEmpty) {
            result["age"] = try WorkoutFrontendInput.number(age, label: "age from 13 to 100", range: 13...100, integer: true)
        }
        if action == "update_benchmarks" {
            var values: [String: WorkoutTrackerValue] = [:]
            for benchmark in primary {
                values[benchmark.exerciseKey] = try WorkoutFrontendInput.number(benchmarkValues[benchmark.exerciseKey] ?? "", label: benchmark.name + " maximum", range: 0...5000, scale: scale)
            }
            result["values"] = .object(values)
        }
        if action == "reset_mesocycle" && !reviewedReset { throw WorkoutFrontendInput.Invalid(message: "Review and confirm the cycle reset first.") }
        return result
    }
    private func date(_ value: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }
}
#endif
