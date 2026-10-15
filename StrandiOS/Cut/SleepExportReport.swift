import Foundation

/// Immutable presentation snapshot. No identifiers or credentials are drawn into the shared image.
struct SleepExportReport: Identifiable {
    struct Interval: Identifiable {
        let start: Double
        let end: Double
        let stage: String
        var id: String { "\(start)|\(end)|\(stage)" }
    }
    struct Timeline {
        let start: Double
        let end: Double
        let method: String
        let intervals: [Interval]
    }
    struct Metric: Identifiable {
        let title: String
        var value: Double?
        let unit: String
        var detail: String
        var id: String { title }
        var isReadable: Bool { value.map { $0.isFinite && $0 >= 0 } ?? false }
        var shareQualifier: String? {
            guard isReadable else { return nil }
            if title == "HRV" {
                if detail.localizedCaseInsensitiveContains("method unverified") { return "Method unverified" }
                if detail.localizedCaseInsensitiveContains("rMSSD") { return "rMSSD" }
                if detail.localizedCaseInsensitiveContains("SDNN") { return "SDNN" }
                return detail.isEmpty ? nil : detail
            }
            if title == "Resting HR", detail.contains("Wake-date") { return "Wake date" }
            if title == "Average HR", detail.contains("sleep window") { return "Sleep window" }
            return nil
        }
        var text: String {
            guard let value, value.isFinite, value >= 0 else { return "Unavailable" }
            return value.formatted(.number.precision(.fractionLength(0...1))) + " " + unit
        }
    }
    struct Source: Identifiable {
        let id: String
        let name: String
        let method: String
        let totalMinutes: Double?
        let stages: [Double?] // Deep, REM, Light, Unclassified; absent never means zero.
        let timeline: Timeline?
        var metrics: [Metric]
        var readingSourceID: String? = nil // Internal attribution only; never rendered or shared as metadata.
        var hasMetrics: Bool { metrics.contains { $0.value != nil } }
    }
    let day: String
    let goalMinutes: Double
    let selectedSource: String
    var sources: [Source]
    var id: String { day }
    var hasData: Bool { sources.contains { $0.totalMinutes != nil || $0.timeline != nil } }
    var highlighted: Source? { sources.first { $0.id == selectedSource } ?? sources.first }
    var shareMetricTitles: [String] {
        ["Average HR", "HRV", "Resting HR", "Snoring time"].filter { title in
            sources.contains { source in source.metrics.contains { $0.title == title && $0.isReadable } }
        }
    }
    static func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes >= 0 else { return "Unavailable" }
        let rounded = minutes.rounded()
        let hours = floor(rounded / 60)
        let remainder = rounded.truncatingRemainder(dividingBy: 60)
        return hours > 0 ? "\(hours.formatted(.number.grouping(.never).precision(.fractionLength(0))))h \(remainder.formatted(.number.precision(.fractionLength(0))))m"
            : "\(remainder.formatted(.number.precision(.fractionLength(0))))m"
    }
}
