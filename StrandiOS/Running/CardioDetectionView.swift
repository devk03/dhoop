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

    private var loadKey: String {
        "\(repo.deviceId)|\(repo.refreshSeq)|\(enabled)|\(sessionActive)|\(localSpans.map { "\($0.start):\($0.end)" }.joined(separator: ","))"
    }
    private var spans: [SavedWorkoutSpan] {
        localSpans.map { SavedWorkoutSpan(startSec: $0.start, endSec: $0.end) }
    }
    private var pending: [WorkoutReview] { reviews.filter { $0.decision == .pending } }
    private var reviewed: [WorkoutReview] { reviews.filter { $0.decision != .pending } }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Toggle("Auto-detection", isOn: $enabled)
                    .font(StrandFont.headline).tint(StrandPalette.metricCyan)
                Text(enabled ? "On · suggests sustained activity after sync. Review before saving." : "Off · start a workout manually or enable suggestions.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if loading { ProgressView("Checking activity…").font(StrandFont.caption) }
                if sessionActive {
                    Text("Finish your active session before reviewing suggestions.")
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
                    .tint(StrandPalette.metricCyan)
                }
                Text("Suggestions from the last 48 hours are kept here once found. You can change either label later, even with auto-detection off.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("Short intervals may not meet the detector's 12-minute threshold. Start HIIT or Intervals to record those sessions.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                Text("Older dismissed suggestions are available only when their original activity can be detected again.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                if let message {
                    Text(message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityIdentifier("workoutReviewMessage")
                }
            }
        }
        .task(id: loadKey) { await load() }
    }

    private func reviewRow(_ review: WorkoutReview) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(Date(timeIntervalSince1970: Double(review.startSec)).formatted(date: .abbreviated, time: .shortened))
                .font(StrandFont.subhead)
            Text("\(review.durationMin) min · avg \(review.avgBpm) bpm")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(review.recordingRemoved ? "Workout · recording removed from history" : label(review.decision)).font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoopMetrics.space3) { actions(review) }
                VStack(alignment: .leading, spacing: NoopMetrics.space2) { actions(review) }
            }
            .disabled(saving || sessionActive)
        }
        .padding(.vertical, NoopMetrics.space2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ review: WorkoutReview) -> some View {
        if review.decision != .workout || review.recordingRemoved {
            Button(review.recordingRemoved ? "Save workout again" : (review.decision == .pending ? "Is a workout" : "Change to workout")) {
                decide(review, .workout)
            }
            .buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan)
            .frame(minHeight: NoopMetrics.minimumTouchTarget)
        }
        if review.decision != .notWorkout {
            Button(review.decision == .pending ? "Not a workout" : "Change to not a workout") {
                decide(review, .notWorkout)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: NoopMetrics.minimumTouchTarget)
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
        reviews = []
        loading = true
        defer { loading = false }
        do {
            let next = try await repo.workoutReviews(discover: enabled && !sessionActive, excluding: spans)
            guard !Task.isCancelled, repo.deviceId == deviceID else { return }
            reviews = next
        } catch {
            guard !Task.isCancelled, repo.deviceId == deviceID else { return }
            message = "Could not load review history. \(error.localizedDescription)"
        }
    }

    private func decide(_ review: WorkoutReview, _ decision: WorkoutReview.Decision) {
        guard review.deviceID == repo.deviceId, !sessionActive, !saving else { return }
        saving = true
        message = nil
        Task { @MainActor in
            defer { saving = false }
            do {
                try await repo.setWorkoutReview(review.id, deviceID: review.deviceID, decision: decision, excluding: spans)
                await repo.refresh()
                guard repo.deviceId == review.deviceID else { return }
                await load()
                message = decision == .workout ? "Workout saved. You can change this label under Reviewed."
                    : "Marked not a workout. You can change this label under Reviewed."
            } catch {
                guard repo.deviceId == review.deviceID else { return }
                message = error.localizedDescription
            }
        }
    }
}
