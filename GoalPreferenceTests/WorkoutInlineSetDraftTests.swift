import XCTest

final class WorkoutInlineSetDraftTests: XCTestCase {
    private func row(load: Double? = nil, reps: Int? = nil, completed: Bool = false) -> WorkoutTrackerDashboard.SetLog {
        .init(id: 20, setNumber: 1, setType: "work", plannedLoad: 190, plannedReps: 6,
            actualLoad: load, actualReps: reps, rir: nil, completed: completed)
    }
    func testCheckingBlankSetNeverConvertsTargetsToPerformedWork() throws {
        let draft = WorkoutInlineSetDraft(row: row(), massScale: 1)
        XCTAssertEqual(draft.load, ""); XCTAssertEqual(draft.reps, ""); XCTAssertFalse(draft.isDirty)
        let command = try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: true)
        XCTAssertEqual(command["completed"], .bool(true))
        XCTAssertNil(command["actualLoad"]); XCTAssertNil(command["actualReps"])
        XCTAssertNil(command["plannedLoad"]); XCTAssertNil(command["plannedReps"])
    }
    func testInlineEditsConvertMetricLoadAndPreserveUnchangedActuals() throws {
        var draft = WorkoutInlineSetDraft(row: row(load: 220, reps: 6), massScale: 2.2046226218)
        draft.load = "100"; draft.rir = "2"
        let command = try draft.command(sessionID: 10, programID: 1, mode: .dumbbellEach, completed: true)
        guard case .number(let weight) = command["actualLoad"] else { return XCTFail("Actual mass missing") }
        XCTAssertEqual(weight, 220.46226218, accuracy: 0.000001)
        XCTAssertEqual(command["rir"], .number(2)); XCTAssertNil(command["actualReps"])
        XCTAssertEqual(command["setId"], .number(20)); XCTAssertEqual(command["sessionId"], .number(10))
    }
    func testClearAndUncheckAreExplicitAndBodyweightNeverWritesMass() throws {
        var draft = WorkoutInlineSetDraft(row: row(load: 190, reps: 6, completed: true), massScale: 1)
        draft.load = ""; draft.reps = ""
        let cleared = try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: false)
        XCTAssertEqual(cleared["actualLoad"], .null); XCTAssertEqual(cleared["actualReps"], .null)
        XCTAssertEqual(cleared["completed"], .bool(false))
        let bodyweight = try draft.command(sessionID: 10, programID: 1, mode: .bodyweight, completed: false)
        XCTAssertNil(bodyweight["actualLoad"])
        let timed = try draft.command(sessionID: 10, programID: 1, mode: .duration, completed: false)
        XCTAssertNil(timed["actualReps"]); XCTAssertNil(timed["actualLoad"])
    }
    func testInvalidInputAndConcurrentChangeCannotBeSilentlySaved() throws {
        var draft = WorkoutInlineSetDraft(row: row(), massScale: 1)
        for input in ["NaN", "-1", "5001", "infinite", "bad"] {
            draft.load = input
            XCTAssertThrowsError(try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: true))
        }
        draft.load = "190"
        for input in ["6.5", "101", "-1"] {
            draft.reps = input
            XCTAssertThrowsError(try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: true))
        }
        draft.reps = "6"
        XCTAssertTrue(draft.conflicts(with: row(load: 195, reps: 7)))
        XCTAssertFalse(draft.conflicts(with: row()))
        XCTAssertEqual(draft.load, "190")
    }
    func testRIRZeroIsRecordedAndBlankExplicitlyClearsRatherThanBecomingZero() throws {
        var source = row(load: 190, reps: 6, completed: true); source.rir = 2
        var draft = WorkoutInlineSetDraft(row: source, massScale: 1)
        draft.rir = "0"
        let zero = try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: true)
        XCTAssertEqual(zero["rir"], .number(0)); XCTAssertNil(zero["actualLoad"]); XCTAssertNil(zero["actualReps"])
        draft.rir = ""
        XCTAssertEqual(try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: true)["rir"], .null)
        for invalid in ["-1", "6", "2.5", "NaN"] {
            draft.rir = invalid
            XCTAssertThrowsError(try draft.command(sessionID: 10, programID: 1, mode: .barbell, completed: true))
        }
        XCTAssertEqual(WorkoutInlineSetDraft(row: row(), massScale: 1).rir, "")
    }
}
