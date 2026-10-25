import SwiftUI
import StrandDesign

struct NutritionGoalEditor: View {
    let day: String
    @ObservedObject var client: NutritionGoalClient = .shared
    @Environment(\.dynamicTypeSize) private var typeSize
    var initiallyExpanded = false
    var automaticallyConnect = true
    @State private var expanded = false
    @AppStorage("dhoop.food.goalDraft.id") private var id = ""
    @AppStorage("dhoop.food.goalDraft.from") private var from = ""
    @AppStorage("dhoop.food.goalDraft.through") private var through = ""
    @AppStorage("dhoop.food.goalDraft.minimum") private var minimum = ""
    @AppStorage("dhoop.food.goalDraft.maximum") private var maximum = ""
    @State private var saved = false
    @FocusState private var focused: Bool
    private var goal: CalorieGoalPeriod? { client.goal(for: day) }
    private var draft: CalorieGoalPeriod? {
        guard let min = Double(minimum.replacingOccurrences(of: ",", with: ".")),
              let max = Double(maximum.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let value = CalorieGoalPeriod(id: id, startDate: from, endDate: through, minCalories: min, maxCalories: max)
        return value.valid ? value : nil
    }
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                DisclosureGroup("Daily calorie range", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        DatePicker("From", selection: date($from), displayedComponents: .date)
                        DatePicker("Through", selection: date($through), displayedComponents: .date)
                        let layout = typeSize >= .xxxLarge ? AnyLayout(VStackLayout(spacing: NoopMetrics.space2)) : AnyLayout(HStackLayout(spacing: NoopMetrics.space2))
                        layout {
                            input("Minimum kcal", value: $minimum)
                            input("Maximum kcal", value: $maximum)
                        }
                        NoopAsyncButton("Save range", fullWidth: true) {
                            guard let draft else { throw NutritionGoalFailure.invalid }
                            try await client.save(draft); focused = false; saved = true
                        }.disabled(draft == nil || client.busy || client.requiresRefresh || !client.enabled)
                        Button("New range") { load(nil) }.buttonStyle(NoopButtonStyle(.tertiary))
                        ForEach(client.periods) { period in
                            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                                Button { load(period) } label: {
                                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                        Text(verbatim: band(period)).font(StrandFont.subhead)
                                        Text(verbatim: period.startDate + " – " + period.endDate)
                                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    }.frame(maxWidth: .infinity, minHeight: NoopMetrics.minimumTouchTarget, alignment: .leading)
                                }.buttonStyle(NoopFeedbackButtonStyle()).accessibilityHint("Edit calorie range")
                                NoopAsyncButton("", systemImage: "minus.circle", kind: .tertiary) {
                                    try await client.remove(period.id); if id == period.id { load(nil) }
                                }.disabled(client.busy || client.requiresRefresh).accessibilityLabel("Remove calorie range")
                            }
                        }
                    }.padding(.top, NoopMetrics.space3).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                }.font(StrandFont.subhead).tint(StrandPalette.metricPurple)
                if let goal {
                    Text(verbatim: band(goal)).font(StrandFont.headline)
                    Text(verbatim: goal.startDate + " – " + goal.endDate).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                } else if client.cached == nil { Text("Calorie ranges not loaded").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                } else { Text("No calorie range for this date").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                if client.busy { ProgressView().accessibilityLabel("Daily calorie range") }
                if saved { Text("Saved on Life").font(StrandFont.caption).foregroundStyle(StrandPalette.metricPurple) }
                if let error = client.error {
                    Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                }
                if client.enabled {
                    NoopAsyncButton("Refresh ranges", systemImage: "arrow.clockwise", kind: .tertiary) { _ = await client.refresh() }.disabled(client.busy)
                    if client.requiresRefresh { Text("Showing the last confirmed ranges. Refresh before editing.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                } else { Text("Shared ranges are waiting for the Life connection.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            }
        }
        .onAppear { if id.isEmpty { load(nil) }; if initiallyExpanded { expanded = true } }
        .task {
            if automaticallyConnect { await NutritionGoalSetup.connectForFoodScreen() }
            else if client.enabled { _ = await client.refresh() }
        }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { if focused { Spacer(); Button("Done") { focused = false } } } }
    }
    private func band(_ period: CalorieGoalPeriod) -> String {
        let minimum = period.minCalories.formatted(.number.precision(.fractionLength(0)))
        let maximum = period.maxCalories.formatted(.number.precision(.fractionLength(0)))
        return (period.minCalories == period.maxCalories ? minimum : minimum + "–" + maximum) + " " + String(localized: "kcal/day")
    }
    private func input(_ title: LocalizedStringKey, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            TextField("Optional", text: value).keyboardType(.decimalPad).focused($focused)
                .font(StrandFont.bodyNumber).padding(NoopMetrics.space3)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius))
        }
    }
    private func date(_ key: Binding<String>) -> Binding<Date> {
        Binding(get: { CalorieGoalPeriod.date(key.wrappedValue) ?? CalorieGoalPeriod.date(day) ?? Date() }, set: {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; key.wrappedValue = formatter.string(from: $0)
        })
    }
    private func load(_ period: CalorieGoalPeriod?) {
        id = period?.id ?? UUID().uuidString.lowercased(); from = period?.startDate ?? day; through = period?.endDate ?? day
        minimum = period.map { $0.minCalories.formatted(.number.grouping(.never)) } ?? ""
        maximum = period.map { $0.maxCalories.formatted(.number.grouping(.never)) } ?? ""; saved = false
    }
}
