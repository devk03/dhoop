import SwiftUI
import StrandDesign

struct FoodInlineEntry: View {
    @ObservedObject var store: ProteinLogStore
    let day: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, protein, calories, target }
    @State private var name = ""
    @State private var grams = ""
    @State private var calories = ""
    @State private var target = ""
    @State private var message: String?
    @State private var failed = false
    private func number(_ value: String) -> Double? {
        NutritionInputNumber.parse(value)
    }
    private var canSave: Bool {
        let protein = grams.isEmpty ? 0 : number(grams)
        return protein.map { $0 <= 1000 && ($0 > 0 || !calories.isEmpty) } == true
            && (calories.isEmpty || number(calories).map { $0 <= 20000 } == true) && !store.storageUnavailable
    }
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text(verbatim: day).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                TextField("Food name", text: $name).focused($focused, equals: .name).textInputAutocapitalization(.sentences)
                    .font(StrandFont.body).padding(NoopMetrics.space3)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius))
                let layout = typeSize >= .xxxLarge ? AnyLayout(VStackLayout(spacing: NoopMetrics.space3)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: NoopMetrics.space2))
                layout {
                    input("Protein", text: $grams, unit: "g", field: .protein)
                    input("Calories", text: $calories, unit: "kcal", field: .calories)
                    NoopAsyncButton("", systemImage: "plus", fullWidth: typeSize >= .xxxLarge) { try save() }
                        .accessibilityLabel("Add food").disabled(!canSave)
                }
                Text(LocalizedStringKey(message ?? "Calories are optional. Blank estimates stay unknown."))
                    .font(StrandFont.caption).foregroundStyle(failed ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = store.storageError {
                    Text(LocalizedStringKey(error)).font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical)
                    NoopAsyncButton("Retry reading the log", systemImage: "arrow.clockwise", kind: .secondary) { try store.reload() }
                }
                DisclosureGroup("Daily protein target (optional)") {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        TextField("Target in grams", text: $target).keyboardType(.decimalPad).focused($focused, equals: .target)
                            .font(StrandFont.bodyNumber).frame(minHeight: NoopMetrics.minimumTouchTarget)
                        NoopAsyncButton("Save target", kind: .secondary) {
                            try store.setTarget(target.isEmpty ? nil : number(target)); focused = nil; failed = false; message = store.targetGrams == nil ? "Target removed" : "Protein target saved"
                        }.disabled(!target.isEmpty && (number(target) ?? 0) <= 0)
                    }
                }.font(StrandFont.subhead).tint(StrandPalette.metricProtein)
            }
        }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { if focused != nil { Spacer(); Button("Done") { focused = nil } } } }
        .onAppear { target = store.targetGrams.map { $0.formatted(.number.grouping(.never)) } ?? "" }
        .onChange(of: [name, grams, calories]) { _, values in
            if values.contains(where: { !$0.isEmpty }) { message = nil; failed = false }
        }
    }
    private func input(_ title: LocalizedStringKey, text: Binding<String>, unit: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: NoopMetrics.space1) {
                TextField("Optional", text: text).keyboardType(.decimalPad).focused($focused, equals: field)
                    .accessibilityLabel(title).font(StrandFont.bodyNumber)
                Text(verbatim: unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }.padding(NoopMetrics.space3).frame(minHeight: NoopMetrics.controlHeight)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius))
        }.frame(maxWidth: .infinity)
    }
    private func save() throws {
        do {
            guard canSave else { throw ProteinLogStore.Failure.invalidEntry }
            try store.add(grams: grams.isEmpty ? 0 : number(grams)!, name: name, day: day, calories: calories.isEmpty ? nil : number(calories))
            grams = ""; calories = ""; name = ""; focused = nil; failed = false; message = "Saved on this phone"
        } catch { failed = true; message = error.localizedDescription; throw error }
    }
}

struct FoodCalorieSummaryCard: View {
    let estimates: [Double?]
    let dayTotals: [Double]
    let singleDay: Bool
    var proteinGrams: Double? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardTileNumber
    var body: some View {
        let summary = NutritionCalorieSummary(estimates: estimates)
        let average = dayTotals.isEmpty ? nil : dayTotals.reduce(0, +) / Double(dayTotals.count)
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                let layout = typeSize >= .xxxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space3)) : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space4))
                layout {
                    if singleDay { metric("Protein", value: proteinGrams, unit: "g logged", tint: StrandPalette.metricProtein) }
                    metric(singleDay ? "Estimated calories" : "Average estimated calories", value: singleDay ? summary.calories : average,
                        unit: singleDay ? "kcal logged" : "kcal/day on estimated days", tint: StrandPalette.metricPurple)
                }
                Text("\(summary.estimatedEntryCount) of \(summary.entryCount) entries estimated")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Logged subtotal, not complete daily intake.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
    private func metric(_ title: LocalizedStringKey, value: Double?, unit: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                .font(StrandFont.number(numberSize, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
            Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
