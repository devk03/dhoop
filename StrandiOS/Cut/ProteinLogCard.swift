import SwiftUI
import StrandDesign

struct ProteinLogCard: View {
    let day: String
    @State private var logDay: String
    init(day: String) { self.day = day; _logDay = State(initialValue: day) }
    @StateObject private var protein = ProteinLogStore()
    @ObservedObject private var food = CutPlanStore.shared
    @State private var showEditor = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber

    var body: some View {
        let grams = protein.total(day: logDay, foodProtein: food.protein(day: logDay))
        let loggedDate = HeartDashboardProjection.date(logDay)?.formatted(.dateTime.month(.abbreviated).day()) ?? logDay
        NoopCard {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space3))
                : AnyLayout(HStackLayout(spacing: NoopMetrics.space3))
            layout {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Label("Protein", systemImage: "fork.knife").font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.statusPositive)
                    Text("\(grams.formatted(.number.precision(.fractionLength(0)))) g")
                        .font(StrandFont.number(numberSize, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
            Text(protein.targetGrams.map { "Logged \(loggedDate) · target \($0.formatted(.number.precision(.fractionLength(0)))) g" } ?? "Logged \(loggedDate)")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if let target = protein.targetGrams {
                        ProgressView(value: min(grams, target), total: target).tint(StrandPalette.statusPositive)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button { logDay = Repository.localDayKey(Date()); showEditor = true } label: { Label("Log protein", systemImage: "plus") }
                    .font(StrandFont.subhead).buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .tint(StrandPalette.statusPositive).frame(minHeight: NoopMetrics.minimumTouchTarget)
            }
        }
        .onChange(of: day) { _, value in logDay = value }
        .sheet(isPresented: $showEditor, onDismiss: { logDay = Repository.localDayKey(Date()) }) { ProteinEntrySheet(store: protein) }
    }
}

private struct ProteinEntrySheet: View {
    @ObservedObject var store: ProteinLogStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var food = CutPlanStore.shared
    @State private var grams = ""
    @State private var name = ""
    @State private var target = ""

    private func parsed(_ value: String) -> Double? {
        guard let value = Double(value.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Logged today") {
                    let day = Repository.localDayKey(Date())
                    if food.protein(day: day) > 0 {
                        Text("Includes \(food.protein(day: day).formatted()) g from your food log.")
                    }
                    ForEach(store.entries.filter { $0.day == day }) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text("\(entry.grams.formatted()) g").font(StrandFont.bodyNumber)
                            Button { store.remove(entry.id) } label: { Image(systemName: "minus.circle") }
                                .frame(minWidth: NoopMetrics.minimumTouchTarget, minHeight: NoopMetrics.minimumTouchTarget)
                                .accessibilityLabel("Remove \(entry.name)")
                        }
                    }
                }
                Section("Log protein") {
                    TextField("Food or meal (optional)", text: $name)
                    TextField("Protein, grams", text: $grams).keyboardType(.decimalPad)
                    Button("Add protein") {
                        guard let value = parsed(grams) else { return }
                        store.add(grams: value, name: name, day: Repository.localDayKey(Date()))
                        dismiss()
                    }
                    .disabled(parsed(grams) == nil)
                }
                Section {
                    TextField("Daily target, grams (optional)", text: $target).keyboardType(.decimalPad)
                    Button("Save target") { store.targetGrams = parsed(target); dismiss() }
                        .disabled(!target.isEmpty && parsed(target) == nil)
                } header: {
                    Text("Your protein target")
                } footer: {
                    Text("Choose a fixed number of grams, or leave blank to track without a target. This is independent of your weight.")
                }
            }
            .navigationTitle("Protein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { target = store.targetGrams.map { String($0) } ?? "" }
        }
    }
}
