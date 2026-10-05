import SwiftUI
import StrandDesign
import StrandAnalytics

struct CardioDetectionView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var enabled = false
    let localSpans: [(start: Int, end: Int)]
    let sessionActive: Bool
    @State private var candidate: DetectedWorkout?
    @State private var candidateDeviceID: String?
    @State private var saving = false
    @State private var message: String?
    private var loadKey: String {
        "\(repo.deviceId)|\(repo.refreshSeq)|\(enabled)|\(sessionActive)|\(localSpans.map { "\($0.start):\($0.end)" }.joined(separator: ","))"
    }
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Toggle("Auto-detection", isOn: $enabled).font(StrandFont.headline).tint(StrandPalette.metricCyan)
                Text(enabled ? "On · suggests sustained activity after sync. Review before saving." : "Off · start a workout manually or enable suggestions.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if enabled && !sessionActive, let candidate {
                    Divider()
                    Text("Possible workout").font(StrandFont.headline)
                    Text("\(Date(timeIntervalSince1970: Double(candidate.startSec)).formatted(date: .abbreviated, time: .shortened)) · \(candidate.durationMin) min · avg \(candidate.avgBpm) bpm")
                        .font(StrandFont.subhead)
                    HStack(spacing: NoopMetrics.space3) {
                        Button("Save activity") { save(candidate) }.buttonStyle(.borderedProminent).tint(StrandPalette.metricCyan).disabled(saving)
                        Button("Not a workout") { repo.dismissDetectedSuggestion(candidate); self.candidate = nil }.buttonStyle(.bordered).disabled(saving)
                    }.frame(minHeight: NoopMetrics.minimumTouchTarget)
                }
                Text("Short intervals may not meet the detector's 12-minute threshold. Start HIIT or Intervals to record those sessions.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                if let message { Text(message).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            }
        }
        .task(id: loadKey) {
            let deviceID = repo.deviceId
            candidate = nil; candidateDeviceID = nil
            guard enabled, !sessionActive else { return }
            let next = await repo.autoDetectCandidate(excluding: localSpans.map { SavedWorkoutSpan(startSec: $0.start, endSec: $0.end) })
            guard !Task.isCancelled, repo.deviceId == deviceID else { return }
            candidateDeviceID = deviceID; candidate = next
        }
    }
    private func save(_ value: DetectedWorkout) {
        guard candidateDeviceID == repo.deviceId, enabled, !sessionActive else { return }
        let deviceID = repo.deviceId
        saving = true
        Task {
            guard candidateDeviceID == deviceID, repo.deviceId == deviceID else { saving = false; return }
            let success = await repo.saveDetectedWorkout(value)
            await repo.refresh()
            saving = false
            guard deviceID == repo.deviceId else { return }
            if success { candidate = nil; message = "Activity saved. Find it in Cardio history." }
            else { message = "Could not save this activity. Try again." }
        }
    }
}
