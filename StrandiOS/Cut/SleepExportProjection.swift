import Foundation

/// One wake date and one provider own each export field; no latest-value carry or provider fallback.
enum SleepExportProjection {
    struct Reading {
        let sourceID: String
        let start: Double
        let end: Double
        let value: Double
    }
    static func mean(_ readings: [Reading], sourceID: String, timeline: SleepExportReport.Timeline) -> (value: Double?, count: Int) {
        let spans = asleepSpans(timeline)
        let values = readings.filter { reading in
            reading.sourceID == sourceID && reading.start.isFinite && reading.end.isFinite && reading.end >= reading.start &&
                reading.value.isFinite && reading.value > 0 && spans.contains {
                    reading.start >= $0.lowerBound && reading.start < $0.upperBound && reading.end <= $0.upperBound
                }
        }.map(\.value)
        return (values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.count)
    }
    static func source(day: String, id: String, name: String, reading: SleepComparisonDay?,
                       timelines: [SleepComparisonTimeline], selectedEpisodeID: String? = nil) -> SleepExportReport.Source {
        let row = reading.flatMap { $0.day == day && $0.total.isFinite && $0.total >= 0 ? $0 : nil }
        let candidates = timelines.filter { episode in
            episode.day == day && (row.map { $0.sourceID == episode.sourceID } ?? true) &&
                episode.start.isFinite && episode.end.isFinite && episode.end > episode.start
        }.sorted {
            if $0.intervals.isEmpty != $1.intervals.isEmpty { return !$0.intervals.isEmpty }
            return $0.end - $0.start > $1.end - $1.start
        }
        let episode = candidates.first { $0.id == selectedEpisodeID } ?? candidates.first
        let timeline = episode.map { value in
            SleepExportReport.Timeline(start: value.start, end: value.end, method: value.method,
                intervals: value.intervals.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= value.start && $0.end <= value.end && $0.end > $0.start }
                    .map { .init(start: $0.start, end: $0.end, stage: $0.stage.rawValue) })
        }
        let stages: [Double?] = [row?.deep, row?.rem, row?.light, row?.unspecified].map { raw in
            raw.flatMap { value in value.isFinite && value >= 0 && row.map({ value <= $0.total }) == true ? value : nil }
        }
        let method = row.map { id == "comparison" ? "\($0.method) · via Apple Health" : $0.method } ?? "No daily total for this date"
        return .init(id: id, name: name, method: method,
            totalMinutes: row?.total, stages: stages, timeline: timeline, metrics: [
                .init(title: "Average HR", value: nil, unit: "bpm", detail: "No readable sleep-period samples"),
                .init(title: "HRV", value: nil, unit: "ms", detail: "No readable record for this date"),
                .init(title: "Resting HR", value: nil, unit: "bpm", detail: "No readable record for this date")])
    }
    static func asleepSpans(_ timeline: SleepExportReport.Timeline) -> [Range<Double>] {
        let spans = timeline.intervals.isEmpty ? [(timeline.start, timeline.end)]
            : timeline.intervals.filter { $0.stage != "awake" }.map { ($0.start, $0.end) }
        return spans.compactMap { start, end in
            guard start.isFinite, end.isFinite, end > start else { return nil }
            return start..<end
        }
    }
    static func asleepWindows(_ timeline: SleepExportReport.Timeline) -> [Range<Int>] {
        asleepSpans(timeline).compactMap { span in
            let start = span.lowerBound, end = span.upperBound
            guard start.isFinite, end.isFinite, start > Double(Int.min), end < Double(Int.max) else { return nil }
            let lower = Int(ceil(start)), upper = Int(ceil(end))
            return lower < upper ? lower..<upper : nil
        }
    }
}
