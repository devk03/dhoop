#if os(iOS)
import Foundation
import WhoopStore

/// Reads only the selected wake date. Export never starts a sync or changes sleep records.
@MainActor
enum SleepExportLoader {
    enum Failure: LocalizedError {
        case unavailable, changed
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Sleep data is unavailable for this date. Refresh sleep and try again."
            case .changed: return "The sleep source changed while preparing the image. Open Share sleep again."
            }
        }
    }
    static func load(_ input: SleepExportReport, whoopSourceID: String?, comparisonSourceID: String?, repo: Repository) async -> SleepExportReport {
        var report = input
        let store = await repo.storeHandle()
        for index in report.sources.indices {
            let source = report.sources[index]
            if source.id == "comparison", let id = comparisonSourceID, let timeline = source.timeline {
                do {
                    report.sources[index].metrics = try await SleepComparisonHealthReader.heartMetrics(sourceID: id, timeline: timeline)
                } catch {
                    for metric in report.sources[index].metrics.indices { report.sources[index].metrics[metric].detail = "Health data could not be read" }
                }
                continue
            }
            guard source.id == "whoop", let id = whoopSourceID, let store,
                  let date = HeartDashboardProjection.date(report.day),
                  let end = Calendar.current.date(byAdding: .day, value: 1, to: date) else { continue }
            do {
                let sessions = try await store.sleepSessionsByWake(deviceId: id, from: Int(date.timeIntervalSince1970), to: Int(end.timeIntervalSince1970) - 1)
                let exact = source.timeline.flatMap { timeline in
                    sessions.first { Double($0.effectiveStartTs) == timeline.start && Double($0.endTs) == timeline.end }
                }
                let daily = try await store.dailyMetrics(deviceId: id, from: report.day, to: report.day).first
                let hrvSeries = try await store.metricSeries(deviceId: id, key: "hrv", from: report.day, to: report.day)
                let rhrSeries = try await store.metricSeries(deviceId: id, key: "rhr", from: report.day, to: report.day)
                func positive(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
                report.sources[index].metrics[1].value = positive(exact?.avgHrv) ?? positive(daily?.avgHrv) ?? positive(hrvSeries.last?.value)
                report.sources[index].metrics[1].detail = id.hasSuffix("-noop") ? "Dhoop estimate · HRV method unverified" : "Imported WHOOP · rMSSD"
                report.sources[index].metrics[2].value = positive(exact?.restingHr.map(Double.init)) ?? positive(daily?.restingHr.map(Double.init)) ?? positive(rhrSeries.last?.value)
                report.sources[index].metrics[2].detail = exact?.restingHr != nil ? "Stored sleep-period RHR" : "Wake-date RHR record"
                if let timeline = source.timeline {
                    var owner: String? = id
                    if id.hasSuffix("-noop") {
                        owner = try await store.scoreInputSource(deviceId: id, day: report.day, key: "sleep_performance")
                        let known = await repo.sleepComparisonSourceIds()
                        if !known.contains(owner ?? "") || owner?.hasSuffix("-noop") == true { owner = nil }
                    }
                    if let owner {
                        let windows = SleepExportProjection.asleepWindows(timeline)
                        let stats = try await store.measuredHeartRateStats(deviceId: owner, windows: windows)
                        report.sources[index].metrics[0].value = positive(stats.avg)
                        report.sources[index].metrics[0].detail = "\(stats.n) measured readings · " + (timeline.intervals.isEmpty ? "sleep window" : "recorded asleep intervals")
                    }
                }
            } catch {
                for metric in report.sources[index].metrics.indices where report.sources[index].metrics[metric].value == nil {
                    report.sources[index].metrics[metric].detail = "Local metric could not be read"
                }
            }
        }
        return report
    }
}
#endif
