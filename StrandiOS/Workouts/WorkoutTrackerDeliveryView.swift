#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

struct WorkoutTrackerDeliveryView: View {
    let deliveryId: UUID
    @ObservedObject private var client = WorkoutTrackerClient.shared
    @EnvironmentObject private var repo: Repository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var localVerified: Bool?
    @State private var localError: String?
    @State private var localCheckedAt: Date?
    @State private var remote: WorkoutTrackerCaptureSnapshot?
    @State private var remoteCheckedAt: Date?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var delivery: WorkoutTrackerDelivery? { client.state.deliveries.first { $0.id == deliveryId } }

    var body: some View {
        ScreenScaffold(title: "Workout delivery", subtitle: LocalizedStringKey(delivery?.record.programName ?? "Strength workout")) {
            if let delivery {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text(statusTitle(delivery)).font(StrandFont.caption).foregroundStyle(statusColor(delivery))
                            .padding(.horizontal, NoopMetrics.space3).padding(.vertical, NoopMetrics.space2)
                            .background(StrandPalette.surfaceInset, in: Capsule())
                        Text(delivery.message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Label(delivery.operation == .delete ? "Local deletion" : "Local workout", systemImage: "doc.text").font(StrandFont.headline)
                            Text(localDescription(delivery)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            if let localCheckedAt { Text("Checked \(localCheckedAt.formatted(date: .abbreviated, time: .shortened))").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                            Text("\(delivery.sets.count) stored set entries · \(Date(timeIntervalSince1970: Double(delivery.record.startTs)).formatted(date: .abbreviated, time: .shortened))")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            NoopAsyncButton("Check local storage", systemImage: "internaldrive", kind: .secondary) { try await checkLocal(delivery) }
                        }
                    }
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            Text("Tracker receipt").font(StrandFont.headline)
                            Text("A local save, a received capture, and applied website values are separate states.")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            NoopAsyncButton("Recover original receipt", systemImage: "arrow.clockwise") {
                                guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                                try await client.synchronize(store: store, deliveryId: delivery.id)
                                try await checkLocal(delivery)
                            }.disabled(!client.state.enabled || client.busy || delivery.bytes == nil || localVerified != true)
                            NoopAsyncButton("Compare tracker data", systemImage: "rectangle.split.2x1", kind: .secondary) {
                                let snapshot = try await client.captureSnapshot(deliveryId: delivery.id)
                                remote = snapshot; remoteCheckedAt = Date()
                            }.disabled(!client.state.enabled || client.busy)
                            NoopAsyncButton("Keep locally", systemImage: "pause.circle", kind: .tertiary) {
                                try client.keepLocally(deliveryId: delivery.id)
                            }.disabled(client.busy || delivery.paused == true)
                            Text("Keep locally pauses automatic delivery for this capture. Previously accepted website data is retained. Recover original receipt sends only that reviewed event.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            if !client.state.enabled {
                                Text("Connection is off. Nothing is sent by opening this screen.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            } else if delivery.bytes == nil || localVerified == false {
                                Text("This intent cannot be replayed safely. Compare the tracker before reviewing changed bindings or local corrections.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                    if let remote {
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                Text("Tracker comparison").font(StrandFont.headline)
                                Text(remote.tombstone ? "Capture is tombstoned" : remote.projectionPolicy == "capture_only" ? "History-only observations · no canonical update" : "Source observations and current website values")
                                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                                if let remoteCheckedAt { Text("Checked \(remoteCheckedAt.formatted(date: .abbreviated, time: .shortened))").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                                if remote.projectionState == "retired" {
                                    Text("The original program targets have retired. Replacement IDs will not be guessed.").font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber)
                                }
                                Text("\(remote.ownership.values.filter { $0.origin == "manual" }.count) fields have manual ownership")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                ForEach(remote.sets) { observed in comparison(observed, delivery: delivery) }
                            }
                        }
                    }
                    NoopCard {
                        DisclosureGroup("Technical details") {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                Text("Source workout: \(delivery.sourceWorkoutId.uuidString.lowercased())")
                                Text("Event: \(delivery.id.uuidString.lowercased())")
                                Text("Source revision: \(delivery.revision)")
                                Text("Life target: cycle \(delivery.binding.manifest.cycleId), session \(delivery.binding.manifest.sessionId)")
                                Text("Recorded source device: \(delivery.record.deviceId)")
                                Text("Mappings identify references; they do not prove every observed field was applied.")
                            }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).textSelection(.enabled)
                        }.font(StrandFont.subhead).tint(StrandPalette.accent)
                    }
                }
            } else {
                Text("This delivery is unavailable. Local workout history remains separate.").font(StrandFont.subhead)
            }
        }
        .task { if let delivery { try? await checkLocal(delivery) } }
    }

    private func checkLocal(_ delivery: WorkoutTrackerDelivery) async throws {
        guard let store = await repo.storeHandle() else { localError = "Local storage is unavailable"; throw WorkoutTrackerContractError.invalidSnapshot }
        do { localVerified = try await delivery.matches(store: store); localCheckedAt = Date(); localError = nil }
        catch { localVerified = nil; localError = "Local storage could not be checked"; throw error }
    }
    private func localDescription(_ delivery: WorkoutTrackerDelivery) -> String {
        if let localError { return localError }
        guard let localVerified else { return "Local persistence has not been checked" }
        if localVerified { return delivery.operation == .delete ? "Deletion is verified locally; source intent is retained." : "This exact recording is verified in local storage." }
        return "Local storage differs from this delivery. It will not be replayed automatically."
    }
    private func statusColor(_ delivery: WorkoutTrackerDelivery) -> Color {
        if delivery.paused == true { return StrandPalette.textSecondary }
        switch delivery.status { case .accepted: return StrandPalette.metricSteps; case .review: return StrandPalette.metricHRV; case .failed: return StrandPalette.statusCritical; default: return StrandPalette.textPrimary }
    }
    private func statusTitle(_ delivery: WorkoutTrackerDelivery) -> String {
        if delivery.paused == true { return "Kept locally" }
        switch delivery.status {
        case .accepted: return delivery.needsReconciliation ? "Progress pending" : "Receipt verified"
        case .review: return "Review needed"
        case .failed: return "Receipt not verified"
        case .prepared: return "Awaiting local confirmation"
        case .ready: return "Ready to send"
        }
    }
    private func comparison(_ observed: WorkoutTrackerCaptureSnapshot.SetObservation, delivery: WorkoutTrackerDelivery) -> some View {
        let local = delivery.sets.first { UUID(uuidString: $0.id) == observed.sourceSetId }
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2)) : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space4))
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Divider()
            Text(local.map { "\($0.exercise) · set \($0.setIndex)" } ?? observed.raw.occurrence?.name ?? "Tracker set \(observed.sourceSetId.uuidString.prefix(8))").font(StrandFont.subhead)
            if let basis = observed.raw.loadBasis {
                Text(basis == "per_hand" ? "Load per hand" : basis == "added" ? "Added load" : basis == "none" ? "No mass load" : "Total load")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if observed.raw.deleted == true { Text("Source set is tombstoned").font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber) }
            layout {
                column("Local intent", weightKg: local?.weightKg, reps: local?.reps)
                column("Tracker source", weightKg: observed.raw.loadKg, reps: observed.raw.reps)
                column("Website", weightKg: observed.projection?.loadLb.map { $0 * 0.45359237 }, reps: observed.projection?.reps)
            }
            if let note = observed.raw.notes, !note.isEmpty { Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            if observed.projection == nil { Text("No canonical set projection · source history may still be present").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
        }
    }
    private func column(_ title: String, weightKg: Double?, reps: Int?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(weightKg.map { LiftFormat.weight($0, system: unitSystem) } ?? "—").font(StrandFont.subhead)
            Text(reps.map { "\($0) reps" } ?? "Reps unavailable").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
