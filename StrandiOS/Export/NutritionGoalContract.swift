import Foundation

struct NutritionGoalConnection: Equatable {
    let credentials: SleepWebhookCredentials
    let installationId: String
    var valid: Bool { credentials.isValid && credentials.hasProteinBearer && UUID(uuidString: installationId) != nil }
}
struct NutritionGoalDocument: Codable, Equatable {
    let schemaVersion: Int
    let kind: String
    let installationId: String
    let version: Int
    let periods: [CalorieGoalPeriod]
    func validate(installation: String) throws {
        guard schemaVersion == 1, kind == "nutrition_goals", installationId == installation,
              version >= 0, version <= 2_147_483_647, periods.count <= 200,
              Set(periods.map(\.id)).count == periods.count, periods.allSatisfy(\.valid) else { throw NutritionGoalFailure.invalid }
        let sorted = periods.sorted { $0.startDate < $1.startDate }
        for pair in zip(sorted, sorted.dropFirst()) where pair.0.endDate >= pair.1.startDate { throw NutritionGoalFailure.invalid }
    }
}
struct NutritionGoalWrite: Encodable {
    let schemaVersion = 1
    let kind = "nutrition_goal"
    let installationId: String
    let expectedVersion: Int
    let action: String
    let goal: CalorieGoalPeriod?
    let id: String?
    enum CodingKeys: CodingKey { case schemaVersion, kind, installationId, expectedVersion, action, goal, id }
    func encode(to encoder: Encoder) throws {
        guard expectedVersion >= 0, expectedVersion <= 2_147_483_647,
              UUID(uuidString: installationId) != nil,
              (action == "upsert" && goal?.valid == true && id == nil)
                || (action == "remove" && goal == nil && id.flatMap(UUID.init(uuidString:)) != nil) else { throw NutritionGoalFailure.invalid }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(kind, forKey: .kind)
        try c.encode(installationId, forKey: .installationId); try c.encode(expectedVersion, forKey: .expectedVersion)
        try c.encode(action, forKey: .action); try c.encodeIfPresent(goal, forKey: .goal); try c.encodeIfPresent(id, forKey: .id)
    }
}
enum NutritionGoalFailure: LocalizedError {
    case unavailable, invalid, changed, unconfirmed, storage
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Life calorie ranges are not connected yet. Your food log still works."
        case .invalid: return "Choose valid dates and a daily calorie range. Your input is kept."
        case .changed: return "Calorie ranges changed. Refresh and review before saving again."
        case .unconfirmed: return "Life has not confirmed this change. Your draft is kept; refresh before retrying."
        case .storage: return "The saved calorie-range cache could not be read. Refresh from Life."
        }
    }
}
