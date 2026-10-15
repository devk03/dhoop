import Foundation
import HealthKit

/// Read-only provider-preserving query; it does not alter the existing Health sync aggregates.
enum SleepComparisonHealthReader {
    static func heartMetrics(sourceID: String, timeline: SleepExportReport.Timeline) async throws -> [SleepExportReport.Metric] {
        var result = [
            SleepExportReport.Metric(title: "Average HR", value: nil, unit: "bpm", detail: "No readable provider samples"),
            .init(title: "HRV", value: nil, unit: "ms", detail: "SDNN · no readable provider samples"),
            .init(title: "Resting HR", value: nil, unit: "bpm", detail: "No readable provider samples")]
        guard HKHealthStore.isHealthDataAvailable(), HealthKitBridge.hasHealthKitEntitlement else { return result }
        let store = HKHealthStore()
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .heartRateVariabilitySDNN, .restingHeartRate]
        for (index, identifier) in identifiers.enumerated() {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let unit = identifier == .heartRateVariabilitySDNN ? HKUnit.secondUnit(with: .milli) : HKUnit.count().unitDivided(by: .minute())
            let predicate = HKQuery.predicateForSamples(withStart: Date(timeIntervalSince1970: timeline.start),
                end: Date(timeIntervalSince1970: timeline.end), options: [.strictStartDate, .strictEndDate])
            let values: [SleepExportProjection.Reading] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    let values = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> SleepExportProjection.Reading? in
                        guard sample.sourceRevision.source.bundleIdentifier == sourceID,
                              !SleepComparisonProjection.isAppWriteback(sourceID: sourceID, ownBundleID: Bundle.main.bundleIdentifier,
                                syncID: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                                externalID: sample.metadata?[HKMetadataKeyExternalUUID] as? String)
                        else { return nil }
                        let value = sample.quantity.doubleValue(for: unit)
                        return .init(sourceID: sourceID, start: sample.startDate.timeIntervalSince1970, end: sample.endDate.timeIntervalSince1970, value: value)
                    }
                    continuation.resume(returning: values)
                }
                store.execute(query)
            }
            let summary = SleepExportProjection.mean(values, sourceID: sourceID, timeline: timeline)
            result[index].value = summary.value
            result[index].detail = "\(summary.count) provider readings · " + (identifier == .heartRateVariabilitySDNN ? "SDNN · sleep period" : "sleep period")
        }
        return result
    }

    static func read(window: MetricDateWindow) async throws -> [SleepComparisonProvider] {
        guard HKHealthStore.isHealthDataAvailable(), HealthKitBridge.hasHealthKitEntitlement,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let observedThrough = Date()
        let queryEnd = min(observedThrough, window.through.addingTimeInterval(36 * 3600))
        let store = HKHealthStore()
        let ownBundleID = Bundle.main.bundleIdentifier
        let predicate = HKQuery.predicateForSamples(withStart: window.start.addingTimeInterval(-36 * 3600), end: queryEnd, options: [])
        let samples: [SleepComparisonSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, values, error in
                if let error { continuation.resume(throwing: error); return }
                let rows = (values as? [HKCategorySample] ?? []).compactMap { sample -> SleepComparisonSample? in
                    let stage: SleepComparisonSample.Stage
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: stage = .deep
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: stage = .rem
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue: stage = .core
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: stage = .unspecified
                    case HKCategoryValueSleepAnalysis.awake.rawValue: stage = .awake
                    default: return nil
                    }
                    let source = sample.sourceRevision.source
                    // HealthKitBridge writes ExternalUUID; retain SyncIdentifier support for other versions.
                    guard !SleepComparisonProjection.isAppWriteback(sourceID: source.bundleIdentifier, ownBundleID: ownBundleID,
                        syncID: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                        externalID: sample.metadata?[HKMetadataKeyExternalUUID] as? String) else { return nil }
                    return SleepComparisonSample(sourceID: source.bundleIdentifier, sourceName: source.name,
                        start: sample.startDate.timeIntervalSince1970, end: sample.endDate.timeIntervalSince1970, stage: stage)
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
        return await Task.detached(priority: .userInitiated) {
            SleepComparisonProjection.healthProviders(samples, window: window, observedThrough: observedThrough)
        }.value
    }
}
