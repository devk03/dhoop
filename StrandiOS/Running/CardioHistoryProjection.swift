import Foundation

enum CardioHistoryKind: String, CaseIterable, Identifiable, Sendable {
    case zone, hiit, intervals, recorded
    var id: String { rawValue }
    var title: String {
        switch self { case .zone: "Zone runs"; case .hiit: "HIIT"; case .intervals: "Intervals"; case .recorded: "Other activity" }
    }
}
struct CardioHistoryItem: Identifiable, Sendable {
    let id: String
    let kind: CardioHistoryKind
    let title: String
    let source: String
    let start: Date
    let end: Date
    let duration: Double
    let averageHR: Double?
    let peakHR: Int?
    var isLocal: Bool { kind != .recorded }
}
struct CardioHistoryGroup: Identifiable {
    let primary: CardioHistoryItem
    var recordings: [CardioHistoryItem]
    var id: String { primary.id }
}

/// A read-only history index. Related recordings remain accessible and are never deleted or merged on disk.
enum CardioHistoryProjection {
    static func includesSport(_ sport: String) -> Bool {
        let value = sport.lowercased().filter { $0.isLetter || $0.isNumber }
        // Unknown/generic activities remain browsable without claiming a diagnosed sport.
        return !["strength", "strengthtraining", "traditionalstrengthtraining", "functionalstrengthtraining", "bodybuilding", "weightlifting", "powerlifting", "yoga", "pilates", "meditation", "gaming", "motorracing", "motocross", "skydiving", "archery", "fishing", "hunting", "billiards", "darts"].contains(value)
    }
    static func groups(_ items: [CardioHistoryItem]) -> [CardioHistoryGroup] {
        var result: [CardioHistoryGroup] = []
        var seen = Set<String>()
        let locals = items.filter(\.isLocal).sorted { $0.start > $1.start }
        let imported = items.filter { !$0.isLocal }.sorted { $0.start > $1.start }
        for item in locals where seen.insert(item.id).inserted { result.append(CardioHistoryGroup(primary: item, recordings: [item])) }
        for item in imported where seen.insert(item.id).inserted {
            // Only effectively identical wall-clock boundaries can link a recorded representation
            // to an explicitly tracked local session. Overlap alone is not enough.
            let matches = result.indices.filter {
                result[$0].primary.isLocal && abs(result[$0].primary.start.timeIntervalSince(item.start)) <= 2
                    && abs(result[$0].primary.end.timeIntervalSince(item.end)) <= 2
            }
            if matches.count == 1 { result[matches[0]].recordings.append(item) }
            else { result.append(CardioHistoryGroup(primary: item, recordings: [item])) }
        }
        return result.sorted { $0.primary.start > $1.primary.start }
    }
    static func filtered(_ groups: [CardioHistoryGroup], window: MetricDateWindow, kind: CardioHistoryKind?, search: String) -> [CardioHistoryGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.filter { group in
            let p = group.primary
            return p.start >= window.start && p.start <= window.through
                && (kind == nil || group.recordings.contains { $0.kind == kind })
                && (query.isEmpty || group.recordings.contains { "\($0.title) \($0.source)".localizedCaseInsensitiveContains(query) })
        }
    }
}
