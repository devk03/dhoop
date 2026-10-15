import SwiftUI
import StrandDesign
import StrandAnalytics

struct CardioDetectionView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var enabled = false
    let localSpans: [(start: Int, end: Int)]
    let sessionActive: Bool
    @State private var reviews: [WorkoutReview] = []
    @State private var saving = false
    @State private var loading = false
    @State private var message: String?
    @State private var showReviewed = false
    @State private var loadedDeviceID: String?
    @State private var activityLabels: [String: String] = [:]

    private var loadKey: String {
        "\(repo.deviceId)|\(repo.refreshSeq)|\(enabled)|\(sessionActive)|\(saving)|\(localSpans.map { "\($0.start):\($0.end)" }.joined(separator: ","))"
    }
    private var spans: [SavedWorkoutSpan] {
        localSpans.map { SavedWorkoutSpan(startSec: $0.start, endSec: $0.end) }
    }
    private var displayedReviews: [WorkoutReview] { loadedDeviceID == repo.deviceId ? reviews : [] }
    private var pending: [WorkoutReview] { displayedReviews.filter { $0.decision == .pending } }
    private var reviewed: [WorkoutReview] { displayedReviews.filter { $0.decision != .pending } }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Toggle("Auto-detection", isOn: $enabled)
                    .font(StrandFont.headline).tint(StrandPalette.accent)
                Text(enabled ? "On · suggests sustained activity after sync. Review before saving." : "Off · start a workout manually or enable suggestions.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if loading { ProgressView("Checking activity…").font(StrandFont.caption) }
                if sessionActive {
                    Text("Review is available after session and history checks finish.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if !pending.isEmpty {
                    Divider()
                    Text("To review · \(pending.count)").font(StrandFont.headline)
                    ForEach(pending) { reviewRow($0) }
                } else if enabled && !loading && !sessionActive {
                    Text("No new suggestions. Synced sustained activity will appear here.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if !reviewed.isEmpty {
                    DisclosureGroup(isExpanded: $showReviewed) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                            ForEach(reviewed) { reviewRow($0) }
                        }
                    } label: {
                        Text("Reviewed · \(reviewed.count)").font(StrandFont.headline)
                    }
                    .tint(StrandPalette.accent)
                }
                DisclosureGroup("How detection works") {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("Unreviewed suggestions expire 48 hours after the activity ends. Confirmed workouts and raw sensor history are kept.")
                        Text("Short intervals may not meet the 12-minute threshold. Start HIIT or Intervals to record those sessions.")
                        Text("Expired suggestions stay suppressed. Activity types are suggestions; heart rate alone cannot identify the sport. Review labels stay on this device.")
                    }.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }.font(StrandFont.subhead).tint(StrandPalette.accent)
                if let message {
                    Text(message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityIdentifier("workoutReviewMessage")
                }
            }
        }
        .task(id: loadKey) { if !saving { await load() } }
    }

    private func reviewRow(_ review: WorkoutReview) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(Date(timeIntervalSince1970: Double(review.startSec)).formatted(date: .abbreviated, time: .shortened))
                .font(StrandFont.subhead)
            Text("\(review.durationMin) min · avg \(review.avgBpm) bpm")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(review.recordingRemoved ? "Workout · recording removed from history" : label(review.decision))
                .font(StrandFont.caption).foregroundStyle(review.decision == .workout ? StrandPalette.statusPositive : StrandPalette.textSecondary)
                .padding(.horizontal, NoopMetrics.space2).padding(.vertical, NoopMetrics.space1)
                .background(StrandPalette.surfaceInset, in: Capsule())
            if review.decision == .pending || review.decision == .notWorkout {
                Text("Suggested · \(review.suggestedActivity)").font(StrandFont.subhead)
            }
            Picker("Activity type", selection: Binding(get: { activityLabels[review.id] ?? review.activityLabel ?? "Workout" }, set: { activityLabels[review.id] = $0 })) {
                    ForEach(WorkoutReview.activityLabels, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).disabled(saving || sessionActive)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoopMetrics.space3) { actions(review) }
                VStack(alignment: .leading, spacing: NoopMetrics.space2) { actions(review) }
            }
            .font(StrandFont.subhead).disabled(saving || sessionActive)
        }
        .padding(.vertical, NoopMetrics.space2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ review: WorkoutReview) -> some View {
        if review.decision == .workout, !review.recordingRemoved,
           let chosen = activityLabels[review.id], chosen != (review.activityLabel ?? review.linkedWorkout?.sport ?? "Workout") {
            NoopAsyncButton("Save activity type") { try await decide(review, .workout) }
        }
        if review.decision != .workout || review.recordingRemoved {
            NoopAsyncButton(review.recordingRemoved ? "Save workout again" : (review.decision == .pending ? "Is a workout" : "Change to workout")) {
                try await decide(review, .workout)
            }
        }
        if review.decision != .notWorkout {
            NoopAsyncButton(review.decision == .pending ? "Not a workout" : "Change to not a workout", kind: .secondary) {
                try await decide(review, .notWorkout)
            }
        }
    }

    private func label(_ decision: WorkoutReview.Decision) -> String {
        switch decision {
        case .pending: return "Pending"
        case .workout: return "Workout"
        case .notWorkout: return "Not a workout"
        }
    }

    @MainActor private func load() async {
        let deviceID = repo.deviceId
        if loadedDeviceID != deviceID { reviews = [] }
        loading = true
        defer { loading = false }
        do {
            let next = try await repo.workoutReviews(discover: enabled && !sessionActive, excluding: spans)
            guard !Task.isCancelled, repo.deviceId == deviceID else { return }
            reviews = next; loadedDeviceID = deviceID
        } catch {
            guard !Task.isCancelled, repo.deviceId == deviceID else { return }
            message = "Could not load review history. \(error.localizedDescription)"
        }
    }

    private struct ReadAfterSaveFailure: LocalizedError {
        var errorDescription: String? { "The decision was saved, but review history could not be refreshed. Your label is retained; try refreshing before changing it again." }
    }
    @MainActor private func decide(_ review: WorkoutReview, _ decision: WorkoutReview.Decision) async throws {
        guard review.deviceID == repo.deviceId, !sessionActive else { throw WorkoutReviewError.unavailable }
        guard !saving else { throw WorkoutReviewError.busy }
        saving = true
        message = nil
        defer { saving = false }
        try await repo.setWorkoutReview(review.id, deviceID: review.deviceID, decision: decision, excluding: spans, activityLabel: activityLabels[review.id] ?? review.activityLabel)
        await repo.refresh()
        guard repo.deviceId == review.deviceID else { throw WorkoutReviewError.unavailable }
        do {
            let next = try await repo.workoutReviews(discover: false, excluding: spans)
            try Task.checkCancellation()
            guard repo.deviceId == review.deviceID else { throw WorkoutReviewError.unavailable }
            reviews = next; loadedDeviceID = review.deviceID
        } catch is CancellationError { throw CancellationError() }
        catch {
            if repo.deviceId == review.deviceID, let index = reviews.firstIndex(where: { $0.id == review.id }) {
                // The write returned successfully; do not keep presenting a committed decision as pending.
                reviews[index].decision = decision
                reviews[index].recordingRemoved = false
                message = ReadAfterSaveFailure().localizedDescription
            }
            throw ReadAfterSaveFailure()
        }
        message = decision == .workout ? "Workout saved. You can change this label under Reviewed."
            : "Marked not a workout. You can change this label under Reviewed."
    }
}
