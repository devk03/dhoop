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
    @State private var recoveryReview: WorkoutTrackerRecoveryReview?
    @State private var historyReview: WorkoutTrackerHistoryReview?
    @State private var deletionReview: WorkoutTrackerDeletionReview?
    @State private var preparedDeliveryId: UUID?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var delivery: WorkoutTrackerDelivery? { try? client.delivery(deliveryId) }

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
                            NoopAsyncButton("Find original receipt", systemImage: "doc.text.magnifyingglass", kind: .secondary) {
                                _ = try await client.lookupReceipt(deliveryId: delivery.id)
                            }.disabled(!client.state.enabled || client.busy || delivery.bytes == nil)
                            Text("Reads an existing receipt without replaying the workout. Local edits and deletions do not prevent this check. A missing result remains unknown.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            if let lookup = delivery.receiptLookup {
                                Label(lookup.status == .recorded ? "Original event receipt found" : "No receipt observed · outcome unknown",
                                      systemImage: lookup.status == .recorded ? "doc.badge.checkmark" : "questionmark.circle")
                                    .font(StrandFont.subhead)
                                if let checkedAt = delivery.receiptLookupCheckedAt {
                                    Text("Receipt checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                if lookup.current?.sourcePresent == false {
                                    Text("Current source metadata is unavailable. The original receipt is retained independently.")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                if lookup.receipt?.outcome == "stale" {
                                    Text("That event was processed without applying its older observations.")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber)
                                }
                                Text("This check does not verify derived progress or replay any event.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            if let replacement = try? client.reviewedReplacement(for: delivery.id) {
                                NavigationLink { WorkoutTrackerDeliveryView(deliveryId: replacement.id) } label: {
                                    Label(replacement.operation == .delete ? "Open reviewed deletion" : "Open history-only correction", systemImage: replacement.operation == .delete ? "trash" : "clock.arrow.circlepath")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(NoopSecondaryButtonStyle())
                                Text("This original intent is retained. Sending it is disabled because you prepared a reviewed replacement.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            NoopAsyncButton(LocalizedStringKey(sendTitle(delivery)), systemImage: delivery.operation == .delete ? "trash" : "arrow.clockwise", kind: delivery.operation == .delete ? .destructive : .primary) {
                                guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                                try await client.synchronize(store: store, deliveryId: delivery.id)
                                try await checkLocal(delivery)
                            }.disabled(!client.state.enabled || client.busy || delivery.bytes == nil || localVerified != true ||
                                (try? client.reviewedReplacement(for: delivery.id)) != nil)
                            if let originalId = delivery.recoveryOf {
                                let original = try? client.delivery(originalId)
                                Text(original?.sourceWorkoutId == delivery.sourceWorkoutId ? "Original event retained" : "Original event retention could not be verified")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Text("Sending uses this exact reviewed event. It does not create another workout.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            NoopAsyncButton("Compare tracker data", systemImage: "rectangle.split.2x1", kind: .secondary) {
                                let snapshot = try await client.captureSnapshot(deliveryId: delivery.id)
                                remote = snapshot; remoteCheckedAt = Date()
                            }.disabled(!client.state.enabled || client.busy)
                            if [.lifeRevisionConflict, .manifestConflict].contains(delivery.rejection), delivery.acknowledgement == nil, delivery.operation != .delete {
                                NoopAsyncButton("Review a new delivery", systemImage: "doc.text.magnifyingglass", kind: .secondary) {
                                    recoveryReview = nil; preparedDeliveryId = nil
                                    historyReview = nil
                                    deletionReview = nil
                                    let review = try await client.reviewRecovery(deliveryId: delivery.id)
                                    remote = review.comparison.capture; remoteCheckedAt = review.comparison.checkedAt
                                    recoveryReview = review
                                }.disabled(!client.state.enabled || client.busy || localVerified != true)
                                Text("Review is available only for a definite revision rejection. Uncertain receipts must be recovered with the original event first.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            if delivery.operation != .delete {
                                NoopAsyncButton("Review history-only correction", systemImage: "clock.arrow.circlepath", kind: .secondary) {
                                    historyReview = nil; recoveryReview = nil; deletionReview = nil; preparedDeliveryId = nil
                                    let review = try await client.reviewHistoryOnly(deliveryId: delivery.id)
                                    remote = review.capture; remoteCheckedAt = review.checkedAt
                                    historyReview = review
                                }.disabled(!client.state.enabled || client.busy || localVerified != true)
                                Text("Requires a previously accepted workout and resolved earlier receipts. Saves source history only; website sets, manual edits and progression are not changed.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            if delivery.operation == .delete {
                                NoopAsyncButton("Review tracker deletion", systemImage: "doc.text.magnifyingglass", kind: .secondary) {
                                    deletionReview = nil; historyReview = nil; recoveryReview = nil; preparedDeliveryId = nil
                                    let review = try await client.reviewDeletion(deliveryId: delivery.id)
                                    remote = review.capture; remoteCheckedAt = review.checkedAt
                                    deletionReview = review
                                }.disabled(!client.state.enabled || client.busy || localVerified != true)
                                Text("Full deletion can retain its original IDs after a routine retires. Review current source observations and manual ownership before preparing a new event.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            NoopAsyncButton("Keep locally", systemImage: "pause.circle", kind: .tertiary) {
                                try client.keepLocally(deliveryId: delivery.id)
                            }.disabled(client.busy || delivery.paused == true)
                            Text("Keep locally pauses automatic delivery. Retry sends the exact stored event and may apply unchanged, locally verified observations if it was not already accepted.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            if !client.state.enabled {
                                Text("Connection is off. Nothing is sent by opening this screen.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            } else if delivery.bytes == nil || localVerified == false {
                                Text("This intent cannot be replayed safely. Compare the tracker before reviewing changed bindings or local corrections.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                    if let recoveryReview {
                        recoveryCard(recoveryReview)
                    }
                    if let historyReview {
                        historyCard(historyReview)
                    }
                    if let deletionReview {
                        deletionCard(deletionReview)
                    }
                    if let preparedDeliveryId {
                        NavigationLink {
                            WorkoutTrackerDeliveryView(deliveryId: preparedDeliveryId)
                        } label: {
                            Label("Open prepared delivery", systemImage: "doc.badge.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(NoopSecondaryButtonStyle())
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
        if delivery.receiptLookup?.status == .notObserved, delivery.acknowledgement == nil {
            return "Outcome unknown · replay paused"
        }
        if delivery.status == .accepted, delivery.operation == .delete {
            return delivery.hasVerifiedDeletionReceipt ? (delivery.reconciliationUnknown ? "Deletion verified · progress unverified" : delivery.needsReconciliation ? "Deletion verified · progress pending" : "Tracker deletion verified") : "Receipt received · deletion state unverified"
        }
        if delivery.status == .accepted, delivery.reconciliationUnknown { return delivery.isHistoryOnly ? "History receipt verified · progress unverified" : "Receipt verified · progress unverified" }
        if delivery.status == .accepted { return delivery.isHistoryOnly ? "History saved · website unchanged" : delivery.needsReconciliation ? "Progress pending" : "Receipt verified" }
        if delivery.recoveryOf != nil, delivery.paused == true, delivery.status == .ready { return "Prepared · not sent" }
        if delivery.paused == true { return "Kept locally" }
        switch delivery.status {
        case .accepted: return delivery.needsReconciliation ? "Progress pending" : "Receipt verified"
        case .review: return "Review needed"
        case .failed: return "Receipt not verified"
        case .prepared: return "Awaiting local confirmation"
        case .ready: return "Ready to send"
        }
    }
    private func sendTitle(_ delivery: WorkoutTrackerDelivery) -> String {
        if delivery.operation == .delete {
            return delivery.recoveryOf != nil && delivery.status == .ready ? "Send prepared deletion" : delivery.submissionAttempted == false ? "Send stored deletion" : "Retry exact deletion"
        }
        return delivery.recoveryOf != nil && delivery.status == .ready ? "Send prepared delivery" : delivery.submissionAttempted == false ? "Send stored delivery" : "Retry exact stored event"
    }
    private func deletionCard(_ review: WorkoutTrackerDeletionReview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label("Review full tracker deletion", systemImage: "trash").font(StrandFont.headline)
                Text(review.capture.tombstone ? "The tracker source is already tombstoned. No new deletion will be prepared; this read is separate from the original event's receipt." : "Delete this same physical capture. Manual website values and prescriptions stay protected; raw sensor readings and recorded provenance are retained.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                if review.capture.projectionState == "retired" {
                    Text("Original targets retired · replacement IDs are not required")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber)
                }
                if review.includesNewerSource {
                    Text("The tracker holds newer source observations than the retained accepted event. Preparing explicitly targets the current capture shown below, with a higher revision.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.metricAmber).fixedSize(horizontal: false, vertical: true)
                }
                Text("\(review.capture.ownership.values.filter { $0.origin == "manual" }.count) manually owned fields stay protected")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Current tracker note: \(review.capture.session.notes ?? "None")")
                    .font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true)
                ForEach(review.capture.sets) { observed in comparison(observed, delivery: review.original) }
                if review.canPrepare {
                    Text("Preparing retains the original event and creates a paused deletion. Sending is separate. The patch omits recorded values and original start provenance so they are not replaced by an older copy.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    NoopAsyncButton(review.includesNewerSource ? "Prepare deletion of current tracker data" : "Prepare reviewed deletion", systemImage: "trash", kind: .destructive) {
                        guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                        preparedDeliveryId = try await client.prepareReviewedDeletion(reviewId: review.id, store: store)
                        deletionReview = nil
                    }.disabled(!client.state.enabled || client.busy)
                }
            }
        }
    }
    private func historyCard(_ review: WorkoutTrackerHistoryReview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label("Review source history", systemImage: "clock.arrow.circlepath").font(StrandFont.headline)
                Text("Your recorded correction stays attached to the same physical workout. This action does not change website sets or request progression.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                if review.capture.projectionState == "retired" {
                    Text("Original routine retired · accepted history remains eligible")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber)
                }
                Text("\(review.capture.ownership.values.filter { $0.origin == "manual" }.count) manually owned fields remain unchanged")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Session note: \(review.original.record.note ?? "None")")
                    .font(StrandFont.subhead).fixedSize(horizontal: false, vertical: true)
                Text(review.original.record.sessionRpe.map { "Session effort: \($0.formatted()) / 10" } ?? "Session effort: not recorded")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                ForEach(review.capture.sets) { observed in comparison(observed, delivery: review.original) }
                DisclosureGroup("All proposed set details") {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        ForEach(review.original.sets, id: \.id) { row in
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text("\(row.exercise) · set \(row.setIndex) · \(row.isWarmup ? "Warm-up" : "Working set")").font(StrandFont.subhead)
                                Text("\(row.weightKg.map { LiftFormat.weight($0, system: unitSystem) } ?? "No mass load") · \(row.reps.map { "\($0) reps" } ?? "Reps unavailable")")
                                    .font(StrandFont.caption)
                                Text(row.rpe.map { "Effort: \($0.formatted()) / 10" } ?? "Effort: not recorded").font(StrandFont.caption)
                                Text("Note: \(row.note ?? "None")").font(StrandFont.caption)
                                Text(row.startTs.flatMap { start in row.endTs.map { end in
                                    "Recorded: \(Date(timeIntervalSince1970: Double(start)).formatted(date: .abbreviated, time: .standard)) – \(Date(timeIntervalSince1970: Double(end)).formatted(date: .abbreviated, time: .standard))"
                                }} ?? "Timing unavailable")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.font(StrandFont.subhead).tint(StrandPalette.accent)
                Text("Preparing retains the original event and start plan. The new correction is paused; sending is a separate action.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Prepare history-only correction", systemImage: "doc.badge.plus") {
                    guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                    preparedDeliveryId = try await client.prepareHistoryOnly(reviewId: review.id, store: store)
                    historyReview = nil
                }.disabled(!client.state.enabled || client.busy)
            }
        }
    }
    private func recoveryCard(_ review: WorkoutTrackerRecoveryReview) -> some View {
        let manualCount = review.comparison.manifest.ownership?.values.filter { $0.origin == "manual" }.count
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label("Review changed tracker data", systemImage: "arrow.triangle.branch").font(StrandFont.headline)
                Text(review.prescriptionChanged ? "The prescription changed. Your recorded sets and original start plan will be retained." : "The tracker revision changed. Your recorded sets and prescription are unchanged.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Text("Current status: \(review.comparison.manifest.status.replacingOccurrences(of: "_", with: " "))")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Scheduled: \(review.comparison.manifest.scheduledDate ?? "Not scheduled")")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if review.comparison.capture == nil {
                    Text("No readable capture for this installation. This is not proof of global absence; Life still checks ownership when receiving the delivery.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.metricAmber)
                }
                Text(manualCount.map { "\($0) manually owned fields" } ?? "Manual ownership unavailable")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Group {
                    ForEach(review.priorManifest.exerciseOccurrences, id: \.sessionExerciseId) { old in
                        if let current = review.comparison.manifest.exerciseOccurrences.first(where: { $0.sessionExerciseId == old.sessionExerciseId }) {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                Divider()
                                Text(current.name).font(StrandFont.subhead)
                                if old.name != current.name { Text("Originally: \(old.name)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                                Text("\(current.loadMode.title) · targets only").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                ForEach(old.sets, id: \.lifeSetId) { oldSet in
                                    if let newSet = current.sets.first(where: { $0.lifeSetId == oldSet.lifeSetId }) {
                                        Text("Set \(oldSet.setNumber)").font(StrandFont.subhead)
                                        if review.prescriptionChanged {
                                            Text("Target: \(targetDescription(oldSet, occurrence: old)) → \(targetDescription(newSet, occurrence: current))")
                                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                                        }
                                        canonicalComparison(newSet, occurrence: old, delivery: review.original)
                                        Text(newSet.completed ? "Website: completed" : "Website: not completed")
                                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                        if let rir = newSet.rir { Text("Website RIR: \(rir)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                                    }
                                }
                                if review.prescriptionChanged {
                                    Text("Rest target: \(old.restTargetSeconds.map { "\($0)s" } ?? "—") → \(current.restTargetSeconds.map { "\($0)s" } ?? "—")")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    Text("Target RIR: \(old.targetRir.map(String.init) ?? "—") → \(current.targetRir.map(String.init) ?? "—")")
                                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                            }
                        }
                    }
                }
                Text("Manual website edits stay authoritative. Preparing retains the original rejected event and creates a separate, paused delivery. Nothing is sent by this action.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                NoopAsyncButton("Prepare reviewed delivery", systemImage: "doc.badge.plus") {
                    guard let store = await repo.storeHandle() else { throw WorkoutTrackerContractError.invalidSnapshot }
                    let id = try await client.prepareReviewedRecovery(reviewId: review.id, store: store)
                    preparedDeliveryId = id; recoveryReview = nil
                }.disabled(!client.state.enabled || client.busy)
            }
        }
    }
    private func canonicalComparison(_ target: WorkoutTrackerManifest.PlannedSet, occurrence: WorkoutTrackerManifest.Occurrence,
                                     delivery: WorkoutTrackerDelivery) -> some View {
        let identity = delivery.binding.occurrences.first { $0.sessionExerciseId == occurrence.sessionExerciseId }?.sets.first { $0.lifeSetId == target.lifeSetId }
        let row = delivery.sets.first { UUID(uuidString: $0.id) == identity?.sourceSetId }
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2)) : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space4))
        return layout {
            column("Recorded", weightKg: row?.weightKg, reps: row?.reps)
            // Life canonical actual loads are pounds even when prescription display units differ.
            column("Website", weightKg: target.actualLoad.map { $0 * 0.45359237 }, reps: target.actualReps)
        }
    }
    private func targetDescription(_ set: WorkoutTrackerManifest.PlannedSet, occurrence: WorkoutTrackerManifest.Occurrence) -> String {
        let kg = try? occurrence.kilograms(for: set)
        let weight = kg.map { LiftFormat.weight($0, system: unitSystem) } ?? "—"
        return "\(weight) × \(set.plannedReps.map(String.init) ?? "—") reps\(set.loadOverride || set.repsOverride ? " · override" : "")"
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
