import XCTest

final class LifeSyncStatusTests: XCTestCase {
    func testReceiptDoesNotHideNewPendingFailureOrProcessingAndOffRetainsEvidence() throws {
        var checkpoint = SleepWebhookCheckpoint()
        checkpoint.enabled = true
        try checkpoint.delivery.configure(endpoint: "https://owner.example/api/webhooks/sleep")
        let first = try XCTUnwrap(checkpoint.delivery.prepare(.init(wakeDate: "2026-10-17", sleepMinutes: 460,
            method: "dhoop_estimate", timeZone: "America/Los_Angeles")))
        let event = first.event
        let ack = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "eventId": event.eventId,
            "installationId": event.installationId, "revision": event.revision, "wakeDate": event.wakeDate,
            "status": "accepted", "outcome": "manual_preserved"])
        try checkpoint.delivery.accept(ack, now: Date(timeIntervalSince1970: 1000))
        var view = LifeSyncStatus(checkpoint: checkpoint, protein: false, checking: false, storageUnavailable: false)
        XCTAssertEqual(view.phase, .receipt); XCTAssertEqual(view.receiptDay, "2026-10-17")
        XCTAssertEqual(view.outcome, "manual_preserved")
        checkpoint.message = "Waiting for sleep processing"
        view = LifeSyncStatus(checkpoint: checkpoint, protein: false, checking: false, storageUnavailable: false)
        XCTAssertEqual(view.phase, .processing); XCTAssertEqual(view.receiptDay, "2026-10-17")
        _ = try checkpoint.delivery.prepare(.init(wakeDate: "2026-10-18", sleepMinutes: 470, method: "dhoop_estimate", timeZone: "America/Los_Angeles"))
        view = LifeSyncStatus(checkpoint: checkpoint, protein: false, checking: false, storageUnavailable: false)
        XCTAssertEqual(view.phase, .queued); XCTAssertEqual(view.pendingDay, "2026-10-18")
        checkpoint.failures = 1; checkpoint.message = "Life access was denied. Review connection settings."
        view = LifeSyncStatus(checkpoint: checkpoint, protein: false, checking: false, storageUnavailable: false)
        XCTAssertEqual(view.phase, .failed); XCTAssertEqual(view.detail, checkpoint.message)
        XCTAssertEqual(view.receiptDay, "2026-10-17"); XCTAssertEqual(view.pendingDay, "2026-10-18")
        XCTAssertEqual(LifeSyncStatus(checkpoint: checkpoint, protein: false, checking: true, storageUnavailable: false).phase, .checking)
        checkpoint.enabled = false
        view = LifeSyncStatus(checkpoint: checkpoint, protein: false, checking: false, storageUnavailable: false)
        XCTAssertEqual(view.phase, .off); XCTAssertEqual(view.pendingDay, "2026-10-18")
    }
    func testNoReceiptNeverImpliesWebsiteSuccessAndStorageErrorIsActionableForEitherMetric() {
        var checkpoint = SleepWebhookCheckpoint(); checkpoint.enabled = true; checkpoint.proteinEnabled = true
        for protein in [false, true] {
            let idle = LifeSyncStatus(checkpoint: checkpoint, protein: protein, checking: false, storageUnavailable: false)
            XCTAssertEqual(idle.phase, .idle); XCTAssertNil(idle.receiptDay); XCTAssertNil(idle.receivedAt)
            let failed = LifeSyncStatus(checkpoint: checkpoint, protein: protein, checking: false, storageUnavailable: true)
            XCTAssertEqual(failed.phase, .failed)
            XCTAssertEqual(failed.detail, "Delivery state could not be read or saved. Export is paused.")
        }
    }
}
