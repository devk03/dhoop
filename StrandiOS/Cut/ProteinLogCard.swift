import SwiftUI
import StrandDesign

struct ProteinLogCard: View {
    @StateObject private var protein = ProteinLogStore()
    @ObservedObject private var food = CutPlanStore.shared
    @State private var showEditor = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let day = Repository.localDayKey(context.date)
            let grams = protein.total(day: day, foodProtein: food.protein(day: day))
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack {
                        Label("Protein", systemImage: "fish.fill").font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.metricPurple)
                        Spacer()
                        Button { showEditor = true } label: { Label("Log", systemImage: "plus") }
                            .buttonStyle(.bordered).tint(StrandPalette.metricPurple)
                    }
                    Text(protein.targetGrams.map { "\(grams.formatted(.number.precision(.fractionLength(0)))) / \($0.formatted(.number.precision(.fractionLength(0)))) g" }
                         ?? "\(grams.formatted(.number.precision(.fractionLength(0)))) g today")
                        .font(StrandFont.number(32, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                    if let target = protein.targetGrams {
                        ProgressView(value: min(grams, target), total: target).tint(StrandPalette.metricPurple)
                    }
                    Text("Log grams of protein without calories or a weight goal.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    let existing = food.protein(day: day)
                    if existing > 0 {
                        Text("Includes \(existing.formatted(.number.precision(.fractionLength(0)))) g from your food log.")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    ForEach(protein.entries.filter { $0.day == day }) { entry in
                        HStack {
                            Text(entry.name).font(StrandFont.body)
                            Spacer()
                            Text("\(entry.grams.formatted(.number.precision(.fractionLength(1)))) g").font(StrandFont.bodyNumber)
                            Button { protein.remove(entry.id) } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("Remove \(entry.name)").tint(StrandPalette.textSecondary)
                        }
                        .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) { ProteinEntrySheet(store: protein) }
    }
}

private struct ProteinEntrySheet: View {
    @ObservedObject var store: ProteinLogStore
    @Environment(\.dismiss) private var dismiss
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
