import Foundation
import Combine
import WhoopStore

enum CardioHistoryPayload {
    case zone(RunningSessionSummary)
    case intervals(URL)
    case recorded(WorkoutRow)
}

@MainActor
final class CardioHistoryModel: ObservableObject {
    @Published private(set) var groups: [CardioHistoryGroup] = []
    @Published private(set) var payloads: [String: CardioHistoryPayload] = [:]
    @Published private(set) var localSpans: [(start: Int, end: Int)] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = 0

    func load(repo: Repository, zones: [RunningSessionSummary], window: MetricDateWindow) async {
        generation += 1
        let current = generation
        loading = true; error = nil
        async let recorded = repo.cardioWorkoutRows(from: Int(window.start.timeIntervalSince1970), to: Int(window.through.timeIntervalSince1970))
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DhoopHIIT", isDirectory: true)
        let files = await Task.detached(priority: .userInitiated) { () -> ([(CardioHistoryItem, URL)], Int) in
            guard FileManager.default.fileExists(atPath: directory.path) else { return ([], 0) }
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("workout-") && $0.pathExtension == "json" }
                var result: [(CardioHistoryItem, URL)] = [], failures = 0
                for url in urls {
                    guard let data = try? Data(contentsOf: url), let run = try? JSONDecoder().decode(HIITSession.self, from: data) else { failures += 1; continue }
                    let effort = run.effort()
                    let kind: CardioHistoryKind = run.kind == .intervals ? .intervals : .hiit
                    let row = CardioHistoryItem(id: "intervals:\(run.id)", kind: kind, title: kind == .hiit ? "HIIT" : "Intervals",
                        source: "WHOOP · recorded in Dhoop", start: run.startedAt, end: run.endedAt ?? run.startedAt.addingTimeInterval(run.elapsed),
                        duration: run.elapsed, averageHR: effort.average, peakHR: effort.peak)
                    result.append((row, url))
                }
                return (result, failures)
            } catch { return ([], 1) }
        }.value
        var items: [CardioHistoryItem] = [], details: [String: CardioHistoryPayload] = [:]
        for run in zones {
            let row = CardioHistoryItem(id: "zone:\(run.id)", kind: .zone, title: "\(run.target.name) run",
                source: "WHOOP · recorded in Dhoop", start: run.startedAt, end: run.endedAt,
                duration: run.elapsedSeconds, averageHR: run.averageBPM, peakHR: run.maximumBPM)
            items.append(row); details[row.id] = .zone(run)
        }
        for (row, url) in files.0 { items.append(row); details[row.id] = .intervals(url) }
        let spans = items.map { (start: Int($0.start.timeIntervalSince1970), end: Int($0.end.timeIntervalSince1970)) }
        for row in await recorded where WorkoutSource.classify(row.source) != .lifting && CardioHistoryProjection.includesSport(row.sport) {
            let id = "stored:\(row.source)|\(row.startTs)|\(row.endTs)|\(row.sport)"
            let item = CardioHistoryItem(id: id, kind: .recorded, title: WorkoutSource.displaySport(row.sport), source: sourceLabel(row),
                start: Date(timeIntervalSince1970: Double(row.startTs)), end: Date(timeIntervalSince1970: Double(row.endTs)),
                duration: row.durationS ?? Double(max(0, row.endTs - row.startTs)), averageHR: row.avgHr.map(Double.init), peakHR: row.maxHr)
            items.append(item); details[id] = .recorded(row)
        }
        guard current == generation, !Task.isCancelled else { return }
        groups = CardioHistoryProjection.groups(items); payloads = details; localSpans = spans; loading = false
        if files.1 > 0 { error = "\(files.1) local workout file(s) could not be read. They remain on this phone." }
    }
    private func sourceLabel(_ row: WorkoutRow) -> String {
        switch WorkoutSource.classify(row.source) {
        case .apple: "Apple Health"
        case .whoop: "WHOOP import"
        case .manual: "Saved activity"
        case .detected: "Detected activity"
        case .lifting: "Imported activity"
        case .activityFile: "Activity file"
        }
    }
}
