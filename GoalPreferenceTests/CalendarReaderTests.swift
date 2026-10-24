import Foundation
import XCTest

@MainActor
final class CalendarReaderTests: XCTestCase {
    private let date = "2026-10-23"
    private func config(_ enabled: Bool = true) -> CalendarReaderConfiguration {
        .init(enabled: enabled, origin: "https://track.kunjadia.dev", installationId: UUID(), readToken: String(repeating: "c", count: 43), accessClientId: nil, accessClientSecret: nil)
    }
    private func bytes(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func event(_ id: String = "event1", refs: [String] = ["task:abc"], allDay: Bool = false) -> [String: Any] {
        ["eventId": id, "title": "Owner's task", "startAt": allDay ? NSNull() : "2026-10-23T20:00:00Z",
         "endAt": allDay ? NSNull() : "2026-10-23T21:00:00Z", "startDate": allDay ? "2026-10-23" : NSNull(),
         "endDate": allDay ? "2026-10-24" : NSNull(), "allDay": allDay, "source": "google", "status": "confirmed",
         "displayContext": NSNull(), "entityKey": refs.first ?? NSNull() as Any, "linkedTaskRefs": refs]
    }
    private func day(_ ids: [String] = ["event1"], snapshot: String = "snapshot1", cursor: String? = nil, date: String = "2026-10-23") throws -> Data {
        try bytes(["schemaVersion": 1, "date": date, "timeZone": "America/Los_Angeles", "readAt": "2026-10-23T20:00:00.000Z", "readOnly": true,
            "snapshot": snapshot, "events": ids.map { event($0) }, "page": ["hasMore": cursor != nil, "nextCursor": cursor ?? NSNull() as Any]])
    }
    private func entry(_ version: Int) -> [String: Any] {
        ["id": "entry\(version)", "version": version, "workDate": date, "fromDate": date, "toDate": "2026-10-24", "category": "work",
         "accomplished": "Actual progress \(version)", "nextStep": "Next step \(version)", "createdAt": "2026-10-23T20:00:00Z"]
    }
    private func history(_ versions: [Int], version: Int = 34, cursor: Int? = nil) throws -> CalendarReaderProgress {
        try JSONDecoder().decode(CalendarReaderProgress.self, from: bytes(["version": version, "latest": entry(version), "entries": versions.map(entry),
            "total": version, "nextBeforeVersion": cursor ?? NSNull() as Any]))
    }
    private func detail(human: String, author: Any = "human", available: Bool = true) throws -> Data {
        let result: [String: Any] = available ? ["ref": "task:abc", "available": true, "url": "https://track.kunjadia.dev/tasks/task:abc",
            "task": ["title": "Owner's task", "note": human, "description": "Original detailed description", "done": false, "status": "backlog", "date": date],
            "brief": ["humanDescription": human, "humanDescriptionAuthor": author, "agentDescription": "Full agent working context", "instructions": "Reference only", "acceptanceCriteria": "Check the real result", "repoUrl": "https://github.com/example/repo", "version": 4]] :
            ["ref": "task:abc", "available": false, "error": ["code": "TASK_CONTEXT_UNAVAILABLE", "message": "Try again"]]
        return try bytes(["schemaVersion": 1, "date": date, "timeZone": "America/Los_Angeles", "readAt": "2026-10-23T20:00:00Z", "readOnly": true,
            "event": event(), "tasks": [result]])
    }
    func testEndpointPinningDatesAndOpaqueQueriesCannotBroadenCalendarScope() throws {
        let cursor = "opaque+/= &?", id = "event/1?taskRef=other"
        let url = try CalendarReaderEndpoint.event(date, id, "task:abc", 4).url(origin: config().origin)
        XCTAssertEqual(url.path, "/api/integrations/dhoop/calendar/event")
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(q, ["date": date, "eventId": id, "taskRef": "task:abc", "beforeVersion": "4"])
        let u = try CalendarReaderEndpoint.day(date, cursor).url(origin: config().origin)
        XCTAssertEqual(URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!.last?.value, cursor)
        for origin in ["http://track.kunjadia.dev", "https://evil.test", "https://track.kunjadia.dev/api/webhooks", "https://owner@track.kunjadia.dev"] {
            XCTAssertThrowsError(try CalendarReaderEndpoint.day(date, nil).url(origin: origin))
        }
        XCTAssertThrowsError(try CalendarReaderEndpoint.day("2026-02-30", nil).url(origin: config().origin))
        XCTAssertThrowsError(try CalendarReaderEndpoint.event(date, id, nil, 1).url(origin: config().origin))
        XCTAssertEqual(CalendarReaderDates.shifted("2026-03-08", by: 1), "2026-03-09")
        XCTAssertEqual(CalendarReaderDates.shifted("2026-11-01", by: -1), "2026-10-31")
        for link in ["javascript:alert(1)", "file:///tmp/private", "https://secret@evil.test", "codex://threads/not-a-uuid"] { XCTAssertNil(CalendarReaderDates.safeLink(link)) }
        XCTAssertNotNil(CalendarReaderDates.safeLink("https://github.com/example/repo"))
    }
    func testAllDayAndTimedEventsRetainDifferentRepresentations() throws {
        let value = try JSONDecoder().decode(CalendarReaderEvent.self, from: bytes(event(allDay: true)))
        try value.validate(); XCTAssertNil(value.startAt); XCTAssertEqual(value.endDate, "2026-10-24")
        var invalid = event(allDay: true); invalid["startAt"] = "2026-10-23T00:00:00Z"
        XCTAssertThrowsError(try JSONDecoder().decode(CalendarReaderEvent.self, from: bytes(invalid)).validate())
        var projection = event(); projection["source"] = "local_projection"
        XCTAssertEqual(try JSONDecoder().decode(CalendarReaderEvent.self, from: bytes(projection)).source, "local_projection")
    }
    func testSnapshotPagingRejectsMixedDaysDuplicatesAndChangedSnapshotsAtomically() throws {
        var chain = CalendarReaderDayChain()
        try chain.accept(JSONDecoder().decode(CalendarReaderDay.self, from: day(["one"], cursor: "next")), date: date, requestedCursor: nil)
        let before = chain
        XCTAssertThrowsError(try chain.accept(JSONDecoder().decode(CalendarReaderDay.self, from: day(["two"], snapshot: "changed")), date: date, requestedCursor: "next"))
        XCTAssertEqual(chain, before)
        XCTAssertThrowsError(try chain.accept(JSONDecoder().decode(CalendarReaderDay.self, from: day(["one"])), date: date, requestedCursor: "next"))
        XCTAssertEqual(chain, before)
        try chain.accept(JSONDecoder().decode(CalendarReaderDay.self, from: day(["two"])), date: date, requestedCursor: "next")
        XCTAssertEqual(chain.events.map(\.id), ["one", "two"]); XCTAssertNil(chain.cursor)
    }
    func testLongOwnerDescriptionsAndProtectedEmptyDescriptionsAreNotRewritten() throws {
        let long = String(repeating: "Owner writes as much detail as needed.\n", count: 500)
        for text in [long, ""] {
            let value = try JSONDecoder().decode(CalendarReaderDetail.self, from: detail(human: text))
            try value.validate(date: date, eventId: "event1")
            XCTAssertEqual(value.tasks.first?.brief?.humanDescription, text)
            XCTAssertEqual(value.tasks.first?.brief?.humanDescriptionAuthor, "human")
            XCTAssertEqual(value.tasks.first?.task?.note, text)
        }
        let unavailable = try JSONDecoder().decode(CalendarReaderDetail.self, from: detail(human: "", available: false))
        try unavailable.validate(date: date, eventId: "event1")
        XCTAssertEqual(unavailable.tasks.count, 1); XCTAssertFalse(unavailable.tasks[0].available)
        XCTAssertThrowsError(try unavailable.validate(date: date, eventId: "event1", taskRef: "task:unrelated"))
    }
    func testProgressPaginationPreservesLatestAndRefusesNewHistoryVersion() throws {
        var ledger = try history(Array((5...34).reversed()), cursor: 5)
        try ledger.validate()
        try ledger.append(history(Array((1...4).reversed())), before: 5)
        XCTAssertEqual(ledger.entries.map(\.version), Array((1...34).reversed())); XCTAssertEqual(ledger.latest?.version, 34)
        XCTAssertNil(ledger.nextBeforeVersion)
        var original = try history(Array((5...34).reversed()), cursor: 5)
        let retained = original
        XCTAssertThrowsError(try original.append(history([4,3,2,1], version: 35), before: 5))
        XCTAssertEqual(original, retained)
        XCTAssertThrowsError(try history([]).validate(), "A nonempty ledger must not look like no progress exists")
    }
    func testFailedRefreshKeepsOnlyTheMatchingDayVisible() async throws {
        let c = config(); var offline = false
        let client = CalendarReaderClient(read: { c }, save: { _ in }, send: { _, _ in
            if offline { throw URLError(.notConnectedToInternet) }; return try self.day()
        })
        await client.loadDay(date); XCTAssertNotNil(client.snapshot(for: date)); XCTAssertNil(client.error)
        offline = true; await client.loadDay(date)
        XCTAssertTrue(client.stale); XCTAssertNotNil(client.error); XCTAssertNotNil(client.snapshot(for: date))
        await client.loadDay("2026-10-24"); XCTAssertNil(client.snapshot(for: "2026-10-24")); XCTAssertNotNil(client.snapshot(for: date))
    }
    func testSnapshotConflictRestartsFromPageOneWithoutCombiningOldEvents() async throws {
        let c = config(); var calls = 0
        let client = CalendarReaderClient(read: { c }, save: { _ in }, send: { endpoint, _ in
            calls += 1
            if calls == 1 { return try self.day(["old"], cursor: "next") }
            if calls == 2 { XCTAssertEqual(endpoint, .day(self.date, "next")); throw CalendarReaderFailure.snapshotChanged }
            XCTAssertEqual(endpoint, .day(self.date, nil)); return try self.day(["new"], snapshot: "new-snapshot")
        })
        await client.loadDay(date); await client.loadDay(date, more: true)
        XCTAssertEqual(client.day.events.map(\.id), ["new"]); XCTAssertEqual(calls, 3)
    }
    func testConnectionDisabledDuringReadCannotPublishOldCalendarData() async throws {
        var saved = config(); var disable: () throws -> Void = {}
        let client = CalendarReaderClient(read: { saved }, save: { saved = $0 }, send: { _, _ in try disable(); return try self.day() })
        disable = { try client.setEnabled(false) }
        await client.loadDay(date)
        XCTAssertFalse(client.enabled); XCTAssertNil(client.day.first); XCTAssertNil(client.snapshot(for: date))
    }
    func testUnlockRecoversCalendarCredentialsWithoutReconfiguringOrWritingThem() async throws {
        let configuration = config(); var unlocked = false; var writes = 0; var calls = 0
        let client = CalendarReaderClient(read: {
            guard unlocked else { throw CalendarReaderFailure.configuration }; return configuration
        }, save: { _ in writes += 1 }, send: { _, _ in calls += 1; return try self.day() })
        XCTAssertFalse(client.enabled)
        unlocked = true; await client.loadDay(date)
        XCTAssertTrue(client.enabled); XCTAssertNotNil(client.snapshot(for: date)); XCTAssertEqual(writes, 0); XCTAssertEqual(calls, 1)
    }
    func testProvisioningVerifiesReadAndKeychainBeforeRetiringTransfer() async throws {
        var saved: CalendarReaderConfiguration?
        let c = config(); var succeeds = false
        let client = CalendarReaderClient(read: { saved }, save: { saved = $0 }, send: { endpoint, _ in
            if !succeeds { throw CalendarReaderFailure.http(403) }
            guard case .day(let requestedDay, _) = endpoint else { throw CalendarReaderFailure.invalidResponse }
            return try self.day([], date: requestedDay)
        })
        let envelope: [String: Any] = ["schemaVersion": 1, "baseURL": c.origin, "installationId": c.installationId.uuidString, "readToken": c.readToken]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-setup-" + UUID().uuidString + ".json")
        let transfer = try bytes(envelope); try transfer.write(to: url)
        do { try await CalendarReaderProvisioner.consume(url, client: client); XCTFail("Denied read must not enable") } catch { }
        XCTAssertNil(saved); XCTAssertEqual(try Data(contentsOf: url), transfer)
        succeeds = true; try await CalendarReaderProvisioner.consume(url, client: client)
        XCTAssertEqual(saved, c); XCTAssertTrue(client.enabled)
        let retired = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(retired["consumed"] as? Bool, true); XCTAssertNil(retired["readToken"])
    }
}
