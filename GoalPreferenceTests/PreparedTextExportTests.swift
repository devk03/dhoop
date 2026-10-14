import XCTest
@testable import DhoopGoalTests

final class PreparedTextExportTests: XCTestCase {
    func testSuccessivePreparationsRetainExactTextAndFriendlyName() throws {
        let first = try PreparedTextExport.write("First source · 72 bpm\n", suggestedName: "strap.txt")
        let second = try PreparedTextExport.write("Second source · unavailable\n", suggestedName: "strap.txt")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "strap.txt")
        XCTAssertEqual(second.lastPathComponent, "strap.txt")
        XCTAssertEqual(try Data(contentsOf: first), Data("First source · 72 bpm\n".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("Second source · unavailable\n".utf8))
    }

    func testFailedPreparationPreservesEarlierExportAndBlockingFile() throws {
        let first = try PreparedTextExport.write("Retained log\n", suggestedName: "strap.txt")
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("Retained blocker".utf8).write(to: blocker)
        XCTAssertThrowsError(try PreparedTextExport.write("New log", suggestedName: "strap.txt", directory: blocker))
        XCTAssertEqual(try Data(contentsOf: first), Data("Retained log\n".utf8))
        XCTAssertEqual(try Data(contentsOf: blocker), Data("Retained blocker".utf8))
    }

    func testFilenameCannotEscapePreparationDirectory() throws {
        for name in ["", ".", "..", "../strap.txt", "/strap.txt", "nested/strap.txt"] {
            XCTAssertThrowsError(try PreparedTextExport.write("Log", suggestedName: name))
        }
    }
}
