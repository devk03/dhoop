import Foundation
import XCTest

final class WorkoutProgressionPreferenceTests: XCTestCase {
    private func exercise() -> WorkoutTrackerDashboard.Exercise {
        .init(id: 11, exerciseKey: "bench", name: "Bench press", orderIndex: 1, loadMode: "barbell",
            progressionType: "double", plannedSets: 3, plannedReps: 8, plannedLoad: 135, targetRir: 2,
            notes: "", slotKey: "press", movementPattern: "push", originalExerciseKey: "", originalExerciseName: "", isPriming: false, sets: [])
    }
    func testLegacyDTOIsReadableAndSlotPreferenceOverridesCatalogRange() throws {
        var row = exercise()
        XCTAssertNil(try JSONDecoder().decode(WorkoutTrackerDashboard.Exercise.self, from: JSONEncoder().encode(row)).progressionPreference)
        row.repMin = 6; row.repMax = 10
        row.progressionPreference = .init(mode: .manual, repMin: 8, repMax: 12, targetRir: 1)
        let draft = WorkoutProgressionPreferenceDraft(exercise: row)
        XCTAssertFalse(draft.automatic); XCTAssertEqual(draft.minimum, 8); XCTAssertEqual(draft.maximum, 12); XCTAssertEqual(draft.targetRIR, 1)
        let command = try draft.command(mesocycleId: 4, sessionExerciseId: 11)
        XCTAssertEqual(command, ["action": .string("update_progression_preferences"), "mesocycleId": .number(4),
            "sessionExerciseId": .number(11), "mode": .string("manual"), "repMin": .number(8), "repMax": .number(12), "targetRir": .number(1)])
    }
    func testAutomaticClearsPinnedRangeWithoutInventingLoggedWorkOrVolume() throws {
        var draft = WorkoutProgressionPreferenceDraft(exercise: exercise())
        draft.automatic = true; draft.minimum = 8; draft.maximum = 12; draft.targetRIR = 0
        let command = try draft.command(mesocycleId: 4, sessionExerciseId: 21)
        XCTAssertEqual(command["mode"], .string("auto")); XCTAssertEqual(command["targetRir"], .number(0))
        XCTAssertNil(command["repMin"]); XCTAssertNil(command["repMax"])
        XCTAssertNil(command["sets"]); XCTAssertNil(command["actualLoad"]); XCTAssertNil(command["weeklySets"])
        XCTAssertNil(command["exerciseKey"], "Exercise occurrence IDs keep repeated exercise keys independent")
    }
    func testLegacyAutomaticMetadataDoesNotApplyManualWriteRangeToHistory() throws {
        var row = exercise()
        row.repMin = 30; row.repMax = 60
        row.progressionPreference = .init(mode: .auto, repMin: 30, repMax: 60, targetRir: 2)
        let decoded = try JSONDecoder().decode(WorkoutTrackerDashboard.Exercise.self, from: JSONEncoder().encode(row))
        XCTAssertEqual(decoded.repMax, 60)
        XCTAssertEqual(decoded.progressionPreference?.repMax, 60)
        let draft = WorkoutProgressionPreferenceDraft(exercise: decoded)
        XCTAssertTrue(draft.automatic)
        XCTAssertTrue((1...30).contains(draft.maximum))
        XCTAssertNil(try draft.command(mesocycleId: 1, sessionExerciseId: 11)["repMax"])
    }
    func testInvalidManualRangesTargetsAndIdentitiesCannotBecomeCommands() throws {
        for (low, high, rir) in [(0, 8, 2), (8, 31, 2), (12, 8, 2), (8, 12, -1), (8, 12, 6)] {
            var draft = WorkoutProgressionPreferenceDraft(exercise: exercise()); draft.automatic = false
            draft.minimum = low; draft.maximum = high; draft.targetRIR = rir
            XCTAssertThrowsError(try draft.command(mesocycleId: 1, sessionExerciseId: 11))
        }
        let draft = WorkoutProgressionPreferenceDraft(exercise: exercise())
        XCTAssertThrowsError(try draft.command(mesocycleId: 0, sessionExerciseId: 11))
        XCTAssertThrowsError(try draft.command(mesocycleId: 1, sessionExerciseId: 0))
        XCTAssertThrowsError(try WorkoutProgressionPreference(mode: .manual, repMin: nil, repMax: nil, targetRir: 2).validate())
    }
}
