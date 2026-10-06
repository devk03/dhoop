import XCTest

final class ProteinWebhookTests: XCTestCase {
    private let endpoint = "https://track.kunjadia.dev/api/webhooks/sleep"
    private var summary: ProteinWebhookSummary { .init(day: "2026-10-05", proteinGrams: 85.5, entryCount: 3, timeZone: "America/Los_Angeles") }
    private func ack(_ event: ProteinWebhookEvent, changes: [String:Any] = [:]) throws -> Data {
        var object: [String:Any] = ["schemaVersion":2,"kind":"protein","eventId":event.eventId,"installationId":event.installationId,"revision":event.revision,"day":event.day,"status":"accepted","outcome":"stored"]
        changes.forEach { object[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testOldPendingSleepLoadsUnchangedAndMetricsShareCounter() throws {
        var old = SleepWebhookCheckpoint(); try old.delivery.configure(endpoint: endpoint)
        let sleep = try XCTUnwrap(old.delivery.prepare(.init(wakeDate: "2026-10-05", sleepMinutes: 480, method: "dhoop_estimate", timeZone: "America/Los_Angeles")))
        // Construct the actual v1 shape with no newly introduced keys.
        let encoded = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(SleepWebhookCheckpoint.self, from: encoded)
        XCTAssertNil(decoded.proteinEnabled); XCTAssertNil(decoded.delivery.proteinPending)
        XCTAssertEqual(decoded.delivery.pending?.bytes, sleep.bytes)
        var state = decoded; state.version = 2
        let protein = try XCTUnwrap(state.delivery.prepareProtein(summary))
        XCTAssertEqual(protein.event.revision, sleep.event.revision + 1)
        XCTAssertEqual(protein.event.installationId, sleep.event.installationId)
        try state.validate()
        let reopened = try JSONDecoder().decode(SleepWebhookCheckpoint.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reopened.delivery.proteinPending?.bytes, protein.bytes)
        XCTAssertEqual(reopened.delivery.pending?.bytes, sleep.bytes)
    }
    func testRetractionsUseExplicitNullAndExactAcknowledgements() throws {
        var delivery = SleepWebhookDelivery(); try delivery.configure(endpoint: endpoint)
        let pending = try XCTUnwrap(delivery.prepareProtein(.init(day: summary.day, proteinGrams: nil, entryCount: 0, timeZone: summary.timeZone)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: pending.bytes) as? [String:Any])
        XCTAssertTrue(object["proteinGrams"] is NSNull)
        XCTAssertEqual(object.count, 12)
        for change in [["kind":"sleep"],["schemaVersion":1],["day":"2026-10-04"],["revision":999],["eventId":UUID().uuidString.lowercased()],["installationId":UUID().uuidString.lowercased()],["status":"ok"]] as [[String:Any]] {
            XCTAssertThrowsError(try delivery.acceptProtein(ack(pending.event, changes: change)))
            XCTAssertEqual(delivery.proteinPending?.bytes, pending.bytes)
        }
        try delivery.acceptProtein(ack(pending.event, changes: ["outcome":"cleared"]))
        XCTAssertNil(delivery.proteinPending)
        XCTAssertEqual(delivery.proteinOutcome, "cleared")
        XCTAssertNil(delivery.proteinAcknowledged?[summary.day]?.proteinGrams)
    }
    func testMissingIsNotZeroAndLastEntryRemovalReconcilesPriorDay() throws {
        XCTAssertTrue(try ProteinWebhookProjection.summaries(entries: [], acknowledged: [:], from: "2026-10-01", to: "2026-10-05").isEmpty)
        let entries = [ProteinWebhookProjection.Entry(day: "2026-10-05", grams: 25), .init(day: "2026-10-05", grams: 30.5), .init(day: "2026-10-06", grams: 20)]
        let values = try ProteinWebhookProjection.summaries(entries: entries, acknowledged: [:], from: "2026-10-01", to: "2026-10-05")
        XCTAssertEqual(values.count,1); XCTAssertEqual(values[0].proteinGrams,55.5); XCTAssertEqual(values[0].entryCount,2)
        let cleared = try ProteinWebhookProjection.summaries(entries: [], acknowledged: [summary.day:summary], from: "2026-10-10", to: "2026-10-17")
        XCTAssertEqual(cleared.first?.day, "2026-10-05"); XCTAssertNil(cleared.first?.proteinGrams); XCTAssertEqual(cleared.first?.entryCount,0)
        let explicitZero = try ProteinWebhookProjection.summaries(entries:[.init(day: "2026-10-05", grams:0)], acknowledged:[:],from:"2026-10-01",to:"2026-10-05")
        XCTAssertEqual(explicitZero.first?.proteinGrams,0); XCTAssertEqual(explicitZero.first?.entryCount,1)
    }
    @MainActor func testSavedLogsIncludeFoodProteinAndFailClosedOnCorruption() throws {
        let defaults = UserDefaults(suiteName: "dhoop-protein-webhook-test-" + UUID().uuidString)!
        let store = ProteinLogStore(defaults: defaults)
        store.add(grams: 25, name: "Test", day: "2026-10-05")
        defaults.set(Data(#"{"2026-10-05":[{"protein":30.5},{"protein":null}]}"#.utf8),forKey:"cut.food")
        let values = try ProteinWebhookProjection.savedEntries(defaults: defaults)
        XCTAssertEqual(values.count,2); XCTAssertEqual(values.map(\.grams).reduce(0,+),55.5)
        defaults.set(Data("broken".utf8),forKey:ProteinLogStore.entriesKey)
        XCTAssertThrowsError(try ProteinWebhookProjection.savedEntries(defaults:defaults))
    }
    func testCompletedDayBoundaryUsesLocalCalendarAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        let before = calendar.date(from:DateComponents(year:2026,month:10,day:6,hour:23,minute:59))!
        let after = calendar.date(from:DateComponents(year:2026,month:10,day:7,hour:0,minute:1))!
        XCTAssertEqual(SleepWebhookPolicy.completedDays(now:before,calendar:calendar).through,"2026-10-05")
        XCTAssertEqual(SleepWebhookPolicy.completedDays(now:after,calendar:calendar).through,"2026-10-06")
        let spring = calendar.date(from:DateComponents(year:2026,month:3,day:8,hour:0))!
        let next = SleepWebhookPolicy.nextDailyOpportunity(now:spring,calendar:calendar)
        XCTAssertEqual(next.timeIntervalSince(spring),23*3600+300)
    }
    func testRetryAndBacklogOpportunitiesDoNotWaitUntilNextNight() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        let now = calendar.date(from:DateComponents(year:2026,month:10,day:6,hour:8))!
        var state = SleepWebhookCheckpoint(); state.enabled = true
        XCTAssertEqual(SleepWebhookPolicy.nextOpportunity(state:state,now:now,calendar:calendar),SleepWebhookPolicy.nextDailyOpportunity(now:now,calendar:calendar))
        state.nextAttempt = now.addingTimeInterval(120)
        XCTAssertEqual(SleepWebhookPolicy.nextOpportunity(state:state,now:now,calendar:calendar),now.addingTimeInterval(120))
        state.nextAttempt = nil; state.sleepBacklog = true
        XCTAssertEqual(SleepWebhookPolicy.nextOpportunity(state:state,now:now,calendar:calendar),now.addingTimeInterval(900))
        state.enabled = false; state.proteinEnabled = true; state.proteinNextAttempt = now.addingTimeInterval(60)
        XCTAssertEqual(SleepWebhookPolicy.nextOpportunity(state:state,now:now,calendar:calendar),now.addingTimeInterval(60))
    }

}
