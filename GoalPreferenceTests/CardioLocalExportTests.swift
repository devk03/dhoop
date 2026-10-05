import XCTest

final class CardioLocalExportTests: XCTestCase {
    func testRoundTripPreservesEveryLocalRecordWithoutRewritingOriginals() throws {
        let defaults = UserDefaults(suiteName: "cardio-export-\(UUID().uuidString)")!
        let summary = Data("saved zone summaries".utf8), draft = Data("paused zone draft".utf8)
        defaults.set(summary, forKey: "dhoop.running.summaries.v1")
        defaults.set(draft, forKey: "dhoop.running.activeDraft.v1")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cardio-export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originals = ["workout-one.json": Data("raw interval record".utf8), "workout-damaged.json": Data([0xff, 0x00]), "active.json": Data("paused HIIT".utf8)]
        for (name, data) in originals { try data.write(to: directory.appendingPathComponent(name)) }
        try Data("unrelated".utf8).write(to: directory.appendingPathComponent("other.txt"))
        let archive = try CardioLocalExport.capture(defaults: defaults, directory: directory)
        let restored = try JSONDecoder().decode(CardioLocalExport.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.formatVersion, 1)
        XCTAssertEqual(restored.runningSummaries, summary)
        XCTAssertEqual(restored.runningDraft, draft)
        XCTAssertEqual(restored.intervalFiles, originals)
        for (name, data) in originals { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), data) }
    }
}
