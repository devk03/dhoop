import XCTest

final class RunningSessionStorageTests: XCTestCase {
    private var target: RunningZoneTarget { RunningZoneTarget(name: "Zone", lowerBPM: 120, upperBPM: 150, method: "Manual") }
    private func summary() -> RunningSessionSummary {
        RunningSessionSummary(id: UUID(), deviceId: "test", target: target, startedAt: Date(), endedAt: Date(),
            elapsedSeconds: 10, inZoneSeconds: 0, goalSeconds: 600, observedSeconds: 0,
            readableSamples: 0, averageBPM: nil, maximumBPM: nil, goalMet: false)
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "dhoop-delete-test-\(UUID().uuidString)")! }

    private func storage(_ defaults: UserDefaults) -> RunningSessionStorage {
        RunningSessionStorage(defaults: defaults, directory: FileManager.default.temporaryDirectory.appendingPathComponent("zone-save-test-\(UUID().uuidString)"))
    }
    func testSaveRecoversBufferedPreferenceLossAndDeleteDoesNotResurrectArchive() throws {
        let defaults = defaults(), a = summary(), originalDraft = Data("draft retained".utf8)
        let storage = storage(defaults)
        defaults.set(originalDraft, forKey: RunningSessionStorage.draftKey)
        XCTAssertEqual(try storage.saveSummary(a).map(\.id), [a.id])
        XCTAssertEqual(defaults.data(forKey: RunningSessionStorage.draftKey), originalDraft)
        // Model a process exit before buffered summary preferences reached disk.
        defaults.removeObject(forKey: RunningSessionStorage.summariesKey)
        XCTAssertEqual(try storage.loadSummaries().map(\.id), [a.id])
        XCTAssertEqual(try storage.saveSummary(a).count, 1)
        XCTAssertTrue(try storage.deleteSummary(id: a.id).isEmpty)
        XCTAssertTrue(try storage.loadSummaries().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.directory.appendingPathComponent("workout-\(a.id.uuidString).json").path))
    }
    func testFailedSavePreservesHistoryAndDraft() throws {
        let defaults = defaults(), bytes = Data("unreadable original history".utf8), draft = Data("draft".utf8)
        defaults.set(bytes, forKey: RunningSessionStorage.summariesKey)
        defaults.set(draft, forKey: RunningSessionStorage.draftKey)
        XCTAssertThrowsError(try storage(defaults).saveSummary(summary()))
        XCTAssertEqual(defaults.data(forKey: RunningSessionStorage.summariesKey), bytes)
        XCTAssertEqual(defaults.data(forKey: RunningSessionStorage.draftKey), draft)
    }
    func testDeleteOneSummaryPreservesOtherRecordsAndDraftAcrossReload() throws {
        let defaults = defaults(), a = summary(), b = summary()
        let draft = Data("unrelated draft bytes".utf8)
        defaults.set(try JSONEncoder().encode([a, b]), forKey: RunningSessionStorage.summariesKey)
        defaults.set(draft, forKey: RunningSessionStorage.draftKey)
        let remaining = try storage(defaults).deleteSummary(id: a.id)
        XCTAssertEqual(remaining.map(\.id), [b.id])
        let reloaded = try JSONDecoder().decode([RunningSessionSummary].self, from: XCTUnwrap(defaults.data(forKey: RunningSessionStorage.summariesKey)))
        XCTAssertEqual(reloaded.map(\.id), [b.id])
        XCTAssertEqual(defaults.data(forKey: RunningSessionStorage.draftKey), draft)
    }
    func testCorruptSummariesCannotBeOverwrittenByDelete() throws {
        let defaults = defaults(), bytes = Data("corrupt but retained".utf8)
        defaults.set(bytes, forKey: RunningSessionStorage.summariesKey)
        XCTAssertThrowsError(try storage(defaults).deleteSummary(id: UUID()))
        XCTAssertEqual(defaults.data(forKey: RunningSessionStorage.summariesKey), bytes)
    }
    func testDiscardIsScopedToConfirmedDraftUUID() throws {
        let defaults = defaults()
        let run = RunningZoneSession(deviceId: "test", target: target, goalSeconds: 600)!
        let data = try JSONEncoder().encode(RunningSessionStorage.Draft(session: run, elapsedSeconds: 10))
        defaults.set(data, forKey: RunningSessionStorage.draftKey)
        let storage = storage(defaults)
        XCTAssertThrowsError(try storage.discardDraft(id: UUID()))
        XCTAssertEqual(defaults.data(forKey: RunningSessionStorage.draftKey), data)
        try storage.discardDraft(id: run.id)
        XCTAssertNil(defaults.data(forKey: RunningSessionStorage.draftKey))
    }
}
