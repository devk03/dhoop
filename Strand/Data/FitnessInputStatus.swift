import Foundation
import WhoopStore
import StrandAnalytics

/// UI evidence from the same bounded, merged rows used by the fitness estimator.
struct FitnessInputStatus: Equatable {
    let restingDays: Int
    let hasAge: Bool
    let hasSex: Bool

    init(days: [DailyMetric], age: Int, sex: String) {
        restingDays = days.compactMap(\.restingHr).filter { $0 > 0 }.count
        hasAge = age > 0
        hasSex = !sex.isEmpty
    }

    var missingDays: Int { max(0, FitnessAgeEngine.minCoverageDays - restingDays) }
    var canEstimate: Bool { hasAge && hasSex && missingDays == 0 }
    var summary: String {
        if !hasAge || !hasSex { return "Add \(!hasAge && !hasSex ? "age and sex" : !hasAge ? "age" : "sex") in Settings" }
        if missingDays > 0 { return "\(restingDays)/\(FitnessAgeEngine.minCoverageDays) resting-HR days ready" }
        return "Resting-HR coverage ready"
    }
    var detail: String {
        let coverage = "\(restingDays) resting-HR days among the latest 7 recorded days within 21 days."
        let next = missingDays > 0 ? " Needs \(missingDays) more qualifying day\(missingDays == 1 ? "" : "s") before a local estimate can be calculated." : " Enough resting-HR coverage for a local estimate."
        return coverage + next + " Age and sex must be set. Weight tracking is not required. Imported measurements and local estimates remain separately labeled."
    }
}
