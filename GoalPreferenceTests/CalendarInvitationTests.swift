import Foundation
import XCTest

@MainActor
final class CalendarInvitationTests: XCTestCase {
    private let day = "2026-10-24"
    private func config() -> CalendarRSVPConfiguration {
        .init(origin: "https://track.kunjadia.dev", installationId: UUID(), acceptToken: String(repeating: "a", count: 43), accessClientId: nil, accessClientSecret: nil)
    }
    private func event(status: String = "needsAction", eligible: Bool = true, etag: String? = "\"v1\"") throws -> CalendarReaderEvent {
        let value: [String: Any] = ["eventId": "occurrence+opaque/?", "title": "Synthetic invitation", "startAt": "2026-10-24T17:00:00Z", "endAt": "2026-10-24T18:00:00Z",
            "startDate": NSNull(), "endDate": NSNull(), "allDay": false, "source": "google", "status": "confirmed", "linkedTaskRefs": [], "etag": etag ?? NSNull() as Any,
            "invitation": ["organizer": ["email": "host@example.test", "displayName": "Host", "self": false],
                "creator": ["email": "creator@example.test", "displayName": "Creator", "self": false],
                "self": ["email": "owner@example.test", "displayName": NSNull(), "self": true], "responseStatus": status,
                "isInvitation": true, "pending": status == "needsAction", "canAccept": eligible, "acceptBlockedReason": NSNull(), "scope": "occurrence",
                "recurringEventId": "series", "originalStartTime": ["dateTime": "2026-10-24T17:00:00Z"]]]
        return try JSONDecoder().decode(CalendarReaderEvent.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func response(_ event: CalendarReaderEvent, status: String = "accepted", id: String? = nil) throws -> Data {
        var value: [String: Any] = ["eventId": id ?? event.id, "title": event.title, "startAt": event.startAt!, "endAt": event.endAt!, "allDay": false,
            "source": "google", "status": "confirmed", "linkedTaskRefs": [], "etag": "\"v2\""]
        value["invitation"] = ["organizer": ["email": "host@example.test", "displayName": "Host", "self": false],
            "creator": NSNull(), "self": ["email": "owner@example.test", "displayName": NSNull(), "self": true],
            "responseStatus": status, "isInvitation": true, "pending": false, "canAccept": false, "acceptBlockedReason": "already_accepted", "scope": "occurrence"]
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "date": day, "readAt": "2026-10-24T16:00:00Z", "outcome": "accepted", "event": value])
    }
    func testInvitationIdentityAndEligibilityAreConservativeAndBodyOnlyHasThreeFields() throws {
        let event = try event(); XCTAssertNotEqual(event.invitation?.organizer, event.invitation?.creator)
        let request = try CalendarAcceptRequest(date: day, event: event)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String])
        XCTAssertEqual(Set(body.keys), ["date", "eventId", "expectedEtag"]); XCTAssertEqual(body["eventId"], "occurrence+opaque/?")
        for status in ["accepted", "unknown"] { XCTAssertThrowsError(try CalendarAcceptRequest(date: day, event: self.event(status: status))) }
        XCTAssertThrowsError(try CalendarAcceptRequest(date: day, event: self.event(eligible: false)))
        for tag in [nil, "*", "W/\"v1\"", "\"v1\n\""] { XCTAssertThrowsError(try CalendarAcceptRequest(date: day, event: self.event(etag: tag))) }
    }
    func testAcceptRequiresIndependentEnrollmentAndNeverAutoRetriesConflict() async throws {
        let event = try event(), value = config(); var calls = 0
        let disabled = CalendarRSVPClient(read: { nil }, save: { _ in XCTFail() }, send: { _, _ in calls += 1; throw CalendarRSVPFailure.conflict })
        do { _ = try await disabled.accept(date: day, event: event); XCTFail() } catch { }
        XCTAssertEqual(calls, 0)
        let client = CalendarRSVPClient(read: { value }, save: { _ in XCTFail() }, send: { _, request in
            XCTAssertNotNil(request); calls += 1; throw CalendarRSVPFailure.conflict
        })
        do { _ = try await client.accept(date: day, event: event); XCTFail() } catch { }
        XCTAssertEqual(calls, 1); XCTAssertNil(client.busyEventID)
    }
    func testResponseCannotClaimAcceptanceForAnotherEventOrUnconfirmedStatus() async throws {
        let event = try event(), value = config()
        for data in [try response(event, status: "needsAction"), try response(event, id: "other")] {
            let client = CalendarRSVPClient(read: { value }, save: { _ in }, send: { _, _ in data })
            do { _ = try await client.accept(date: day, event: event); XCTFail() } catch { }
        }
        let client = CalendarRSVPClient(read: { value }, save: { _ in }, send: { _, _ in try self.response(event) })
        let accepted = try await client.accept(date: day, event: event)
        XCTAssertEqual(accepted.invitation?.responseStatus, "accepted")
    }
    func testEnrollmentChecksCapabilitiesBeforeSavingAndRejectsCrudScope() async throws {
        let value = config(); var saved: CalendarRSVPConfiguration?
        func bytes(_ crud: Bool) throws -> Data { try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "installationId": value.installationId.uuidString, "acceptOnly": true, "eventCrud": crud]) }
        let bad = CalendarRSVPClient(read: { saved }, save: { saved = $0 }, send: { _, request in XCTAssertNil(request); return try bytes(true) })
        do { try await bad.install(value); XCTFail() } catch { }; XCTAssertNil(saved)
        let good = CalendarRSVPClient(read: { saved }, save: { saved = $0 }, send: { _, request in XCTAssertNil(request); return try bytes(false) })
        try await good.install(value); XCTAssertEqual(saved, value); XCTAssertTrue(good.enabled)
    }
    func testWidgetLinksCannotTriggerAcceptanceOrEscapeCalendarScope() throws {
        let id = "opaque /?&=+"; let link = try XCTUnwrap(CalendarWidgetSnapshot.link(day: day, eventID: id))
        XCTAssertEqual(CalendarNavigationRequest(url: link)?.eventID, id)
        for url in ["dhoop://calendar?date=2026-10-24&action=accept", "dhoop://calendar?date=2026-10-24&date=2026-10-23", "https://calendar?date=2026-10-24", "dhoop://calendar?date=invalid"] {
            XCTAssertNil(CalendarNavigationRequest(url: URL(string: url)!))
        }
    }
    func testWidgetMissingDayStaleDayAndIncompleteDataNeverPretendEmptyToday() {
        let now = CalendarReaderDates.instant("2026-10-24T18:00:00Z")!
        let old = CalendarWidgetSnapshot.Day(date: "2026-10-23", readAt: now.addingTimeInterval(-86400), complete: true, events: [])
        XCTAssertNil(CalendarWidgetSnapshot(days: [old]).current(at: now))
        let today = CalendarWidgetSnapshot.Day(date: day, readAt: now.addingTimeInterval(-1800), complete: false, events: [])
        XCTAssertEqual(CalendarWidgetSnapshot(days: [today]).current(at: now)?.complete, false)
        XCTAssertNil(CalendarWidgetSnapshot(days: [today, today]).current(at: now))
    }
}
