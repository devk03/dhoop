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

    func testDeleteRetiresOnlyChosenArchiveAndClearsMatchingStaleDraft() throws {
        let url = try directory(), a = fixture(), b = fixture()
        let store = HIITWorkoutFiles(directory: url)
        try store.save(a); try store.save(b)
        let archives = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let chosen = try XCTUnwrap(archives.first { $0.lastPathComponent.hasSuffix("\(a.id).json") })
        let other = try XCTUnwrap(archives.first { $0.lastPathComponent.hasSuffix("\(b.id).json") })
        try JSONEncoder().encode(a).write(to: url.appendingPathComponent("active.json"))
        try store.deleteWorkout(at: chosen, id: a.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chosen.path))
        XCTAssertEqual(try JSONDecoder().decode(HIITSession.self, from: Data(contentsOf: other)), b)
        XCTAssertEqual(try String(contentsOf: url.appendingPathComponent("active.json")), "null")
        let retired = try FileManager.default.contentsOfDirectory(at: url.appendingPathComponent("Deleted"), includingPropertiesForKeys: nil)
        XCTAssertEqual(try JSONDecoder().decode(HIITSession.self, from: Data(contentsOf: XCTUnwrap(retired.first))), a)
    }
    func testDeletePreservesDifferentActiveDraftAndRejectsWrongIdentity() throws {
        let url = try directory(), a = fixture(), b = fixture(), store = HIITWorkoutFiles(directory: url)
        try store.save(a)
        let chosen = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("workout-") })
        let draft = try JSONEncoder().encode(b)
        try draft.write(to: url.appendingPathComponent("active.json"))
        XCTAssertThrowsError(try store.deleteWorkout(at: chosen, id: b.id))
        try store.deleteWorkout(at: chosen, id: a.id)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("active.json")), draft)
    }
    func testUnreadableDraftPreventsArchiveRetirement() throws {
        let url = try directory(), run = fixture(), store = HIITWorkoutFiles(directory: url)
        try store.save(run)
        let chosen = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("workout-") })
        try Data("unreadable draft".utf8).write(to: url.appendingPathComponent("active.json"))
        XCTAssertThrowsError(try store.deleteWorkout(at: chosen, id: run.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: chosen.path))
    }
    func testDiscardClearsOnlyTheConfirmedDraftAndKeepsSavedArchive() throws {
        let url = try directory(), saved = fixture(), draft = fixture(), store = HIITWorkoutFiles(directory: url)
        try store.save(saved)
        let bytes = try JSONEncoder().encode(draft)
        try bytes.write(to: url.appendingPathComponent("active.json"))
        XCTAssertThrowsError(try store.discardDraft(id: saved.id))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("active.json")), bytes)
        try store.discardDraft(id: draft.id)
        XCTAssertEqual(try String(contentsOf: url.appendingPathComponent("active.json")), "null")
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        XCTAssertTrue(names.contains { $0.hasSuffix("\(saved.id).json") })
    }
}
