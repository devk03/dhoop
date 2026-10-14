import XCTest
import WhoopStore
@testable import DhoopGoalTests

@MainActor
final class LiftSessionDetailModelTests: XCTestCase {
    private func record() -> LiftSessionRow {
        .init(id: "session", deviceId: "recorded-strap", startTs: 1000, endTs: 1200,
              sport: "Strength Training", programId: nil, programName: "Upper", sessionRpe: 7, note: "Old note")
    }
    private func detail(_ row: LiftSessionRow) -> LiftRecordingDetail {
        .init(session: row, sets: [], workout: nil, previousSets: [:])
    }
    func testFailureRetainsConfirmedDetailAndBlocksFreshAuthorityUntilRetry() async {
        let model = LiftSessionDetailModel(), row = record()
        var corrected = row; corrected.sessionRpe = nil; corrected.note = "New note"
        let ticket = await model.load(record: row) { source, id in
            XCTAssertEqual(source, "recorded-strap"); XCTAssertEqual(id, "session")
            return self.detail(corrected)
        }
        XCTAssertNotNil(ticket); XCTAssertTrue(model.isFresh)
        XCTAssertEqual(model.snapshot?.session.note, "New note"); XCTAssertNil(model.snapshot?.session.sessionRpe)
        let retained = model.snapshot, date = model.capturedAt
        await model.load(record: row) { _, _ in throw CocoaError(.fileReadNoPermission) }
        XCTAssertEqual(model.snapshot, retained); XCTAssertEqual(model.capturedAt, date)
        XCTAssertFalse(model.isFresh); XCTAssertNotNil(model.error)
        await model.load(record: row) { _, _ in self.detail(corrected) }
        XCTAssertTrue(model.isFresh); XCTAssertNil(model.error)
    }
    func testConfirmedMissingClearsOldDisplayAndDiffersFromReadFailure() async {
        let model = LiftSessionDetailModel(), row = record()
        await model.load(record: row) { _, _ in self.detail(row) }
        await model.load(record: row) { _, _ in nil }
        XCTAssertNil(model.snapshot); XCTAssertNil(model.capturedAt); XCTAssertNil(model.readID)
        XCTAssertFalse(model.isFresh); XCTAssertNotNil(model.error)
    }
    func testWrongIdentityCannotReplaceConfirmedDetail() async {
        let model = LiftSessionDetailModel(), row = record()
        await model.load(record: row) { _, _ in self.detail(row) }
        var foreign = row; foreign.deviceId = "other"
        await model.load(record: row) { _, _ in self.detail(foreign) }
        XCTAssertEqual(model.snapshot?.session, row); XCTAssertFalse(model.isFresh)
    }
    func testSupersededSuccessOrFailureCannotReplaceNewerRead() async throws {
        for fails in [false, true] {
            let model = LiftSessionDetailModel(), row = record()
            var finish: CheckedContinuation<LiftRecordingDetail?, Error>?
            let old = Task { await model.load(record: row) { _, _ in
                try await withCheckedThrowingContinuation { finish = $0 }
            } }
            for _ in 0..<100 { if finish != nil { break }; await Task.yield() }
            let continuation = try XCTUnwrap(finish)
            var newer = row; newer.note = "Latest read"
            let ticket = await model.load(record: row) { _, _ in self.detail(newer) }
            if fails { continuation.resume(throwing: CocoaError(.fileReadNoPermission)) }
            else { continuation.resume(returning: detail(row)) }
            let stale = await old.value
            XCTAssertNil(stale); XCTAssertEqual(model.readID, ticket)
            XCTAssertEqual(model.snapshot?.session, newer); XCTAssertTrue(model.isFresh); XCTAssertNil(model.error)
        }
    }
}
