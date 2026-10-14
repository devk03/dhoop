import XCTest
@testable import DhoopGoalTests

final class VerifiedFileCopyTests: XCTestCase {
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    func testSuccessfulCopyAndReplacementPreservePreparedSource() throws {
        let root = try directory(), source = root.appendingPathComponent("prepared.csv"), target = root.appendingPathComponent("saved.csv")
        let prepared = Data("recorded HR,source A\n".utf8)
        try prepared.write(to: source)
        try VerifiedFileCopy.copy(from: source, to: target)
        XCTAssertEqual(try Data(contentsOf: target), prepared)
        try Data("previous destination".utf8).write(to: target)
        try VerifiedFileCopy.copy(from: source, to: target)
        XCTAssertEqual(try Data(contentsOf: target), prepared)
        XCTAssertEqual(try Data(contentsOf: source), prepared)
        try VerifiedFileCopy.copy(from: source, to: source)
        XCTAssertEqual(try Data(contentsOf: source), prepared)
    }
    func testFailedCopyCannotErasePreviousDestination() throws {
        let root = try directory(), target = root.appendingPathComponent("existing.csv")
        let previous = Data("previous saved data".utf8)
        try previous.write(to: target)
        XCTAssertThrowsError(try VerifiedFileCopy.copy(from: root.appendingPathComponent("missing.csv"), to: target))
        XCTAssertEqual(try Data(contentsOf: target), previous)
    }
    func testDirectoryDestinationIsNotReplacedByAFile() throws {
        let root = try directory(), source = root.appendingPathComponent("prepared.csv")
        let protected = root.appendingPathComponent("folder"), child = protected.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try Data("retained".utf8).write(to: child); try Data("CSV".utf8).write(to: source)
        XCTAssertThrowsError(try VerifiedFileCopy.copy(from: source, to: protected))
        XCTAssertEqual(try Data(contentsOf: child), Data("retained".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("CSV".utf8))
    }
}
