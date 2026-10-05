import XCTest

final class HIITWorkoutFilesTests: XCTestCase {
    private func fixture() -> HIITSession {
        var run = HIITSession(deviceId: "test-strap", plan: HIITPlan(), zones: [RunningZoneTarget(name: "Test", lowerBPM: 120, upperBPM: 150, method: "Manual")])!
        run.finish()
        return run
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-hiit-save-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testSuccessfulSaveArchivesFullSessionAndClearsDraft() throws {
        let url = try directory(), run = fixture()
        try JSONEncoder().encode(run).write(to: url.appendingPathComponent("active.json"))
        XCTAssertNil(try HIITWorkoutFiles(directory: url).save(run))
        XCTAssertEqual(try String(contentsOf: url.appendingPathComponent("active.json")), "null")
        let saved = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("workout-") }!
        XCTAssertEqual(try JSONDecoder().decode(HIITSession.self, from: Data(contentsOf: saved)), run)
    }
    func testDraftCleanupFailureStillReturnsCommittedWorkout() throws {
        let url = try directory(), run = fixture()
        // A directory at this path makes the second atomic file write fail independently of the first.
        try FileManager.default.createDirectory(at: url.appendingPathComponent("active.json"), withIntermediateDirectories: true)
        XCTAssertNotNil(try HIITWorkoutFiles(directory: url).save(run))
        let saved = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("workout-") }!
        XCTAssertEqual(try JSONDecoder().decode(HIITSession.self, from: Data(contentsOf: saved)), run)
    }
    func testArchiveFailureThrowsAndPreservesDraft() throws {
        let url = try directory(), run = fixture()
        let draft = Data("existing recoverable draft".utf8)
        try draft.write(to: url.appendingPathComponent("active.json"))
        let name = "workout-\(Int(run.startedAt.timeIntervalSince1970))-\(run.id.uuidString).json"
        try FileManager.default.createDirectory(at: url.appendingPathComponent(name), withIntermediateDirectories: true)
        XCTAssertThrowsError(try HIITWorkoutFiles(directory: url).save(run))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("active.json")), draft)
    }
}
