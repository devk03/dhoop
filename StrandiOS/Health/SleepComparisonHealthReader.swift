import Foundation
import HealthKit

/// Read-only provider-preserving query; it does not alter the existing Health sync aggregates.
enum SleepComparisonHealthReader {
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
