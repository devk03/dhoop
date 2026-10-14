import XCTest
import AppKit
import StrandDesign
@testable import DhoopGoalTests

@MainActor
final class ImageSelectionTests: XCTestCase {
    private enum ReadFailure: Error { case unavailable }
    private func png() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 4, bitsPerPixel: 32))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        pixels[0] = 64; pixels[1] = 128; pixels[2] = 192; pixels[3] = 255
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
    private func truncatedPNG() throws -> Data { Data(try png().prefix(33)) }
    private func defaults() throws -> UserDefaults { try XCTUnwrap(UserDefaults(suiteName: "image-tests-\(UUID().uuidString)")) }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSupersededReadOrFailureCannotReplaceNewerSelection() async throws {
        for fails in [false, true] {
            let operation = ImageSelectionController(), started = expectation(description: "Old transfer started")
            var oldRead: CheckedContinuation<Data?, Error>?, stored = Data("existing".utf8)
            let old = operation.select(read: {
                try await withCheckedThrowingContinuation { oldRead = $0; started.fulfill() }
            }, commit: { stored = $0 })
            let task = Task { await operation.load(old) }
            await fulfillment(of: [started], timeout: 2)
            let latest = operation.select(read: { Data("new".utf8) }, commit: { stored = $0 })
            let committed = await operation.load(latest)
            XCTAssertTrue(committed)
            if fails { oldRead?.resume(throwing: ReadFailure.unavailable) }
            else { oldRead?.resume(returning: Data("old".utf8)) }
            let stale = await task.value
            XCTAssertFalse(stale); XCTAssertEqual(stored, Data("new".utf8))
            XCTAssertEqual(operation.state, .succeeded); XCTAssertNil(operation.error)
        }
    }

    func testFailedReadAndFailedCommitRetainInputForExplicitRetry() async throws {
        for failsRead in [false, true] {
            let operation = ImageSelectionController()
            var retry = false, stored = Data("existing".utf8), reads = 0
            let token = operation.select(read: {
                reads += 1
                if failsRead && !retry { throw ReadFailure.unavailable }
                return Data("chosen".utf8)
            }, commit: {
                if !failsRead && !retry { throw ReadFailure.unavailable }
                stored = $0
            })
            let initial = await operation.load(token)
            XCTAssertFalse(initial); XCTAssertTrue(operation.hasInput); XCTAssertNotNil(operation.error)
            XCTAssertEqual(stored, Data("existing".utf8))
            retry = true
            let saved = await operation.retry()
            XCTAssertTrue(saved); XCTAssertEqual(reads, 2); XCTAssertFalse(operation.hasInput)
            XCTAssertEqual(stored, Data("chosen".utf8))
        }
    }

    func testDuplicateLoadAndExplicitCancelCannotCommitLater() async {
        let operation = ImageSelectionController(), started = expectation(description: "Transfer started")
        var read: CheckedContinuation<Data?, Never>?, writes = 0
        let token = operation.select(read: {
            await withCheckedContinuation { read = $0; started.fulfill() }
        }, commit: { _ in writes += 1 })
        let task = Task { await operation.load(token) }
        await fulfillment(of: [started], timeout: 2)
        let duplicate = await operation.load(token)
        XCTAssertFalse(duplicate)
        operation.cancel(); read?.resume(returning: Data("chosen".utf8))
        let committed = await task.value
        XCTAssertFalse(committed); XCTAssertEqual(writes, 0)
        XCTAssertEqual(operation.state, .idle); XCTAssertFalse(operation.hasInput)
    }

    func testInvalidAvatarRetainsDecodableAvatarAndPreferences() throws {
        let suite = try defaults(), profile = ProfileStore(defaults: suite)
        XCTAssertTrue(profile.setAvatar(try png()))
        let before = try XCTUnwrap(profile.avatarImageData)
        XCTAssertFalse(profile.setAvatar(Data("not an image".utf8)))
        XCTAssertFalse(profile.setAvatar(try truncatedPNG()), "A recognized PNG header is not proof that its pixels can be decoded")
        XCTAssertEqual(profile.avatarImageData, before)
        XCTAssertEqual(suite.data(forKey: "profile.avatarImageData"), before)
    }

    func testInvalidOrUnwritableBackgroundKeepsCurrentImageAndPreferences() throws {
        let suite = try defaults(), root = try directory()
        let background = BackgroundImageStore(defaults: suite, directory: root)
        try background.setImage(from: try png())
        let recents = background.recents, before = suite.dictionaryRepresentation()
        XCTAssertThrowsError(try background.setImage(from: Data("not an image".utf8)))
        XCTAssertThrowsError(try background.setImage(from: try truncatedPNG()))
        XCTAssertEqual(background.recents, recents); XCTAssertNotNil(background.image)
        XCTAssertTrue(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: before))
        let preserved = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: root, to: preserved)
        try Data("directory unavailable".utf8).write(to: root)
        XCTAssertThrowsError(try background.setImage(from: try png()))
        XCTAssertEqual(background.recents, recents); XCTAssertNotNil(background.image)
        XCTAssertTrue(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: before))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.appendingPathComponent(recents[0].id).path))
    }

    func testUnreadableRecentDoesNotReplaceActiveImageAndImportsHaveDistinctFiles() throws {
        let root = try directory(), suite = try defaults()
        let background = BackgroundImageStore(defaults: suite, directory: root)
        try background.setImage(from: try png()); try background.setImage(from: try png())
        XCTAssertEqual(Set(background.recents.map(\.id)).count, 2)
        let prior = background.recents, prefs = suite.dictionaryRepresentation()
        let oldFile = root.appendingPathComponent(prior[1].id)
        let retained = root.appendingPathComponent("retained-image.jpg")
        try FileManager.default.moveItem(at: oldFile, to: retained)
        XCTAssertThrowsError(try background.applyRecent(1))
        XCTAssertEqual(background.recents, prior); XCTAssertNotNil(background.image)
        XCTAssertTrue(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: prefs))
    }
}
