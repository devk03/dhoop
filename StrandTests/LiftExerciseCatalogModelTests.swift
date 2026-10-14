import XCTest
import WhoopStore
@testable import Strand

@MainActor
final class LiftExerciseCatalogModelTests: XCTestCase {
    private func row(_ source: String, name: String = "Bench") -> LiftExerciseRow {
        LiftExerciseRow(id: UUID().uuidString, deviceId: source, name: name, primaryMuscle: nil,
                        secondaryMuscles: [], createdAt: 1, lastUsedTs: nil)
    }
    func testFailureKeepsKnownRowsButDoesNotAuthorizeWritesAsIfCatalogWereEmpty() async throws {
        let model = LiftExerciseCatalogModel(), known = row("strap")
        try await model.load(deviceID: "strap") { _ in [known] }
        XCTAssertTrue(model.isReady(for: "strap"))
        do {
            try await model.load(deviceID: "strap") { _ in throw NSError(domain: "catalog", code: 1) }
            XCTFail("A failed read must remain unavailable")
        } catch LiftExerciseCatalogModel.Failure.unreadable {}
        XCTAssertEqual(model.entries(for: "strap"), [known])
        XCTAssertFalse(model.isReady(for: "strap"))
        XCTAssertNotNil(model.error)
        try await model.load(deviceID: "strap") { _ in [] }
        XCTAssertTrue(model.isReady(for: "strap"), "An actual empty catalog permits adding the first exercise")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.error)
    }
    func testLateReadCannotReplaceTheNewSelectedSourcesCatalog() async throws {
        let model = LiftExerciseCatalogModel(), old = row("old"), new = row("new")
        let entered = expectation(description: "Old read started")
        var release: CheckedContinuation<[LiftExerciseRow], Never>?
        let pending = Task { @MainActor in
            do {
                try await model.load(deviceID: "old") { _ in
                    entered.fulfill()
                    return await withCheckedContinuation { release = $0 }
                }
                XCTFail("A superseded read must not publish old rows")
            } catch LiftExerciseCatalogModel.Failure.changedSource {}
        }
        await fulfillment(of: [entered], timeout: 2)
        try await model.load(deviceID: "new") { _ in [new] }
        release?.resume(returning: [old])
        try await pending.value
        XCTAssertEqual(model.entries(for: "new"), [new])
        XCTAssertTrue(model.entries(for: "old").isEmpty)
        XCTAssertTrue(model.isReady(for: "new"))
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
    }
    func testForeignRowsAndDuplicateIdentitiesCannotBecomeReadableCatalogs() async {
        let model = LiftExerciseCatalogModel(), foreign = row("other"), duplicate = row("strap")
        for rows in [[foreign], [duplicate, duplicate]] {
            do { try await model.load(deviceID: "strap") { _ in rows }; XCTFail("Unattributed or ambiguous rows must fail") }
            catch LiftExerciseCatalogModel.Failure.unreadable {}
            catch { XCTFail("Unexpected failure: \(error)") }
            XCTAssertFalse(model.isReady(for: "strap"))
            XCTAssertTrue(model.entries(for: "strap").isEmpty)
        }
    }
}
