#if os(iOS)
import Foundation
import StrandAnalytics

// Local Cardio recordings are not all mirrored into SQLite. Automatic review capture must honor
// their archive and draft spans even when the Cardio screen has never been opened this launch.
enum WorkoutReviewLocalSessions {
    static func spans(defaults: UserDefaults = .standard, directory: URL, now: Date) throws -> [SavedWorkoutSpan] {
        let decoder = JSONDecoder()
        var spans: [SavedWorkoutSpan] = []
        if let data = defaults.data(forKey: RunningSessionStorage.summariesKey) {
            let runs = try decoder.decode([RunningSessionSummary].self, from: data)
            spans += runs.map { SavedWorkoutSpan(startSec: Int($0.startedAt.timeIntervalSince1970),
                                                endSec: Int($0.endedAt.timeIntervalSince1970)) }
        }
        if let data = defaults.data(forKey: RunningSessionStorage.draftKey) {
            let draft = try decoder.decode(RunningSessionStorage.Draft.self, from: data)
            spans.append(SavedWorkoutSpan(startSec: Int(draft.session.startedAt.timeIntervalSince1970),
                                           endSec: Int(now.timeIntervalSince1970)))
        }
        guard FileManager.default.fileExists(atPath: directory.path) else { return spans }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ($0.lastPathComponent.hasPrefix("workout-") && $0.pathExtension == "json") || $0.lastPathComponent == "active.json" }
        for url in urls {
            guard let run = try decoder.decode(HIITSession?.self, from: Data(contentsOf: url)) else { continue }
            let end = run.endedAt ?? (url.lastPathComponent == "active.json" ? now : run.startedAt.addingTimeInterval(run.elapsed))
            spans.append(SavedWorkoutSpan(startSec: Int(run.startedAt.timeIntervalSince1970),
                                         endSec: Int(end.timeIntervalSince1970)))
        }
        return spans
    }
}

#endif
