import XCTest

@MainActor
final class HealthJournalTests: XCTestCase {
    private let topicID = "00000000-0000-4000-8000-000000000001"
    private let entryID = "00000000-0000-4000-8000-000000000002"
    private var configuration: HealthJournalConnection {
        .init(endpoint: HealthJournalConnection.endpoint, bearerToken: String(repeating: "a", count: 43), installationId: UUID(), accessClientId: "health.access", accessClientSecret: "health-secret")
    }
    private func archive() -> HealthJournalArchive { .init(folder: FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-health-tests-" + UUID().uuidString)) }
    private func receipt(_ mutation: HealthJournalMutation) -> Data { Data("{\"id\":\"\(mutation.id)\",\"version\":1}".utf8) }
    private var empty: Data { Data("{\"topics\":[],\"observations\":[],\"nextOffset\":null}".utf8) }
    private func document(version: Int = 1, notes: String = "Original") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["topics": [["id":topicID,"title":"Face","bodyArea":"face","side":"unspecified","status":"open","version":1,"createdAt":"2026-10-30T13:00:00Z","updatedAt":"2026-10-30T13:00:00Z"]],
            "observations": [["id":entryID,"topicId":topicID,"observedAt":"2026-10-30T09:00:00-04:00","timeZone":"America/New_York","recordedAt":"2026-10-30T13:00:00Z","notes":notes,"symptoms":"","source":"agent","version":version,"updatedAt":"2026-10-30T13:00:00Z","images":[]]],"nextOffset":NSNull(),"revisions":[],"nextBeforeVersion":NSNull()])
    }
    func testTimeZoneAndDSTOffsetArePreservedAndValidated() throws {
        XCTAssertTrue(HealthJournalDates.valid("2026-11-01T01:30:00-04:00", zone:"America/New_York"))
        XCTAssertTrue(HealthJournalDates.valid("2026-11-01T01:30:00-05:00", zone:"America/New_York"))
        XCTAssertFalse(HealthJournalDates.valid("2026-03-08T02:30:00-05:00", zone:"America/New_York"))
        XCTAssertFalse(HealthJournalDates.valid("2026-10-30T09:00:00Z", zone:"America/New_York"))
        XCTAssertFalse(HealthJournalDates.validDay("2026-02-30"))
        let mutation = HealthJournalMutation.entry(topicId:topicID,now:HealthJournalDates.instant("2026-10-30T13:00:00Z")!,zone:"America/New_York")
        XCTAssertEqual(mutation.observedAt,"2026-10-30T09:00:00-04:00")
        try mutation.validate()
    }
    func testStrictMutationKeysTextOnlyAndUTF16Limits() throws {
        var mutation = HealthJournalMutation.entry(topicId:topicID)
        try mutation.validate()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(mutation)) as? [String:Any])
        XCTAssertNil(json["expectedVersion"]); XCTAssertNil(json["title"]); XCTAssertNil(json["images"])
        XCTAssertEqual(json["symptoms"] as? String,"")
        mutation.notes = String(repeating:"🧑",count:10001)
        XCTAssertThrowsError(try mutation.validate())
        var topic = HealthJournalMutation.topic(); topic.title=String(repeating:"😀",count:61);topic.bodyArea="face"
        XCTAssertThrowsError(try topic.validate())
    }
    func testDedicatedConnectionRejectsAlternateOriginsAndHeaderInjection() throws {
        var config = configuration
        XCTAssertTrue(config.valid)
        config.endpoint = "https://tracker.kunjadia.dev/api/integrations/dhoop/health"; XCTAssertFalse(config.valid)
        config = configuration; config.bearerToken += "\n"; XCTAssertFalse(config.valid)
        config = configuration; config.bearerToken="Bearer token"; XCTAssertFalse(config.valid)
        XCTAssertThrowsError(try HealthJournalRequest(path:"https://other.example/image").url(configuration))
        XCTAssertThrowsError(try HealthJournalRequest.entries(.init(from:"2026-11-01",through:"2026-10-01")))
    }
    func testLostReceiptRetriesExactPersistedBodyAfterRestartWithoutChangingDate() async throws {
        let store=archive(), config=configuration
        var sent:[Data]=[]
        let client=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{ request,_ in
            if let body=request.body { sent.append(body); throw URLError(.networkConnectionLost) }
            return self.empty
        })
        let mutation=HealthJournalMutation.entry(topicId:topicID,now:HealthJournalDates.instant("2026-10-30T13:00:00Z")!,zone:"America/New_York")
        let id=try client.create(mutation); await client.send(id)
        XCTAssertFalse(try XCTUnwrap(client.draft(id)).bodyAccepted)
        let replay=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{request,_ in
            if let body=request.body { sent.append(body);return self.receipt(mutation) };return self.empty
        })
        await replay.send(id)
        XCTAssertEqual(sent.count,2);XCTAssertEqual(sent[0],sent[1])
        XCTAssertTrue(try XCTUnwrap(replay.draft(id)).completed)
        XCTAssertEqual(replay.draft(id)?.mutation.observedAt,"2026-10-30T09:00:00-04:00")
    }
    func testAcceptedTextAndPhotoNotResentAfterSecondPhotoFailureAndRestart() async throws {
        let store=archive(),config=configuration,mutation=HealthJournalMutation.entry(topicId:topicID)
        var requests:[String]=[];var photoAttempts=0
        let client=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{request,_ in
            requests.append(request.path)
            if let photo=request.image {
                photoAttempts += 1
                if photoAttempts==2 { throw URLError(.notConnectedToInternet) }
                return try self.photoReceipt(photo)
            }
            return request.body == nil ? self.empty : self.receipt(mutation)
        })
        let id=try client.create(mutation),png=Data([137,80,78,71,13,10,26,10]+Array(repeating:0,count:24))
        try await client.addPhoto(png,draftId:id);try await client.addPhoto(png,draftId:id)
        await client.send(id)
        XCTAssertEqual(client.draft(id)?.status,"Entry saved; photo pending")
        let first=try XCTUnwrap(client.draft(id)?.photos.first),last=try XCTUnwrap(client.draft(id)?.photos.last)
        XCTAssertTrue(first.accepted);XCTAssertFalse(last.accepted)
        requests=[]
        let replay=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{request,_ in
            requests.append(request.path)
            if let photo=request.image {return try self.photoReceipt(photo)};return self.empty
        })
        await replay.send(id)
        XCTAssertEqual(requests.filter{$0.hasPrefix("images/")},["images/"+last.id])
        XCTAssertFalse(requests.contains("images/"+first.id));XCTAssertTrue(try XCTUnwrap(replay.draft(id)).completed)
        XCTAssertEqual(try store.photo(first),png)
    }
    private func photoReceipt(_ photo:HealthJournalPendingPhoto) throws -> Data {
        try JSONSerialization.data(withJSONObject:["id":photo.id,"observationId":photo.observationId,"contentType":photo.contentType,"bytes":photo.bytes,"sha256":photo.sha256,"filename":photo.filename,"recordedAt":"2026-10-30T13:00:00Z","source":"dhoop","url":"/api/integrations/dhoop/health/images/"+photo.id])
    }
    func testConflictRequiresExplicitReviewAndRetainsDraft() async throws {
        let config=configuration,store=archive()
        let entry=try JSONDecoder().decode(HealthJournalDocument.self,from:document()).observations[0]
        var posts=0
        let client=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{request,_ in
            if request.body != nil {posts += 1;throw HealthJournalFailure.conflict}
            return try self.document(version:3,notes:"New website note")
        })
        var mutation=HealthJournalMutation.correction(entry);mutation.notes="My retained note"
        let id=try client.create(mutation);await client.send(id);await client.send(id)
        XCTAssertEqual(posts,1);XCTAssertTrue(try XCTUnwrap(client.draft(id)).conflict)
        try await client.review(id,reviewedVersion:3)
        let reviewed=try XCTUnwrap(client.draft(id));XCTAssertTrue(reviewed.editable)
        XCTAssertEqual(reviewed.mutation.expectedVersion,3);XCTAssertEqual(reviewed.mutation.notes,"My retained note")
        XCTAssertNotEqual(reviewed.mutation.requestId,mutation.requestId)
        XCTAssertEqual(reviewed.mutation.observedAt,entry.observedAt)
    }
    func testReviewedVersionCannotAdvanceSilentlyPastWhatOwnerSaw() async throws {
        let config=configuration
        let entry=try JSONDecoder().decode(HealthJournalDocument.self,from:document()).observations[0]
        let client=HealthJournalClient(archive:archive(),read:{config},save:{_ in},send:{request,_ in
            if request.body != nil {throw HealthJournalFailure.conflict};return try self.document(version:4)
        })
        let id=try client.create(.correction(entry));await client.send(id)
        do {try await client.review(id,reviewedVersion:3);XCTFail("A newer unseen version cannot be rebased")}
        catch {XCTAssertEqual(error as? HealthJournalFailure,.conflict)}
        XCTAssertTrue(try XCTUnwrap(client.draft(id)).conflict)
        XCTAssertEqual(client.draft(id)?.mutation.expectedVersion,1)
    }
    func testCredentialRotationSameInstallationPreservesQueuedBody() async throws {
        let store=archive();var saved=configuration;let initial=saved
        let client=HealthJournalClient(archive:store,read:{saved},save:{saved=$0},send:{request,_ in
            if request.path == "capabilities" {return Data("{\"schemaVersion\":1,\"read\":true,\"write\":true,\"imagesOptional\":true,\"correctionHistory\":true}".utf8)}
            if request.body != nil {throw URLError(.networkConnectionLost)};return self.empty
        })
        let id=try client.create(.entry(topicId:topicID));await client.send(id)
        let before=try XCTUnwrap(client.draft(id)?.body)
        var replacement=initial;replacement.bearerToken=String(repeating:"b",count:43);replacement.accessClientSecret="new-secret"
        try await client.install(replacement)
        XCTAssertEqual(saved,replacement);XCTAssertEqual(client.draft(id)?.body,before)
        XCTAssertEqual(client.draft(id)?.installationId,initial.installationId)
        var different=replacement;different.installationId=UUID()
        do {try await client.install(different);XCTFail("Cross-installation replay must fail")}
        catch {XCTAssertEqual(error as? HealthJournalFailure,.configuration)}
        XCTAssertEqual(saved,replacement)
    }
    func testLiveOffsetPagesDeduplicateAndRefreshDropsOlderPagingState() async throws {
        let config=configuration;var calls=0
        let client=HealthJournalClient(archive:archive(),read:{config},save:{_ in},send:{request,_ in
            calls += 1
            var json=try XCTUnwrap(JSONSerialization.jsonObject(with:self.document()) as? [String:Any])
            json["nextOffset"]=calls == 1 ? 20:NSNull()
            return try JSONSerialization.data(withJSONObject:json)
        })
        await client.refresh();XCTAssertEqual(client.document.nextOffset,20)
        await client.refresh(more:true);XCTAssertEqual(client.document.observations.count,1)
        await client.refresh();XCTAssertNil(client.document.nextOffset)
        XCTAssertEqual(calls,3)
    }
    func testRefreshFailureNotEmptyAndFilterFailureCannotShowOtherTopic() async throws {
        let config=configuration;var fail=false
        let client=HealthJournalClient(archive:archive(),read:{config},save:{_ in},send:{_,_ in
            if fail {throw URLError(.notConnectedToInternet)};return try self.document()
        })
        await client.refresh();XCTAssertTrue(client.loaded);XCTAssertEqual(client.document.observations.count,1)
        fail=true;await client.refresh();XCTAssertEqual(client.document.observations.count,1);XCTAssertNotNil(client.error)
        await client.refresh(.init(topicId:UUID().uuidString.lowercased()))
        XCTAssertFalse(client.loaded);XCTAssertTrue(client.document.observations.isEmpty);XCTAssertNotNil(client.error)
    }
    func testWrongWriteReceiptCannotMarkDraftSaved() async throws {
        let config=configuration
        let client=HealthJournalClient(archive:archive(),read:{config},save:{_ in},send:{request,_ in
            if request.body != nil {return Data("{\"id\":\"00000000-0000-4000-8000-000000000099\",\"version\":1}".utf8)}
            return self.empty
        })
        let id=try client.create(.entry(topicId:topicID));await client.send(id)
        XCTAssertFalse(try XCTUnwrap(client.draft(id)).bodyAccepted)
        XCTAssertFalse(try XCTUnwrap(client.draft(id)).completed)
    }
    func testOriginalRetrievalChecksDigestAndRejectsForeignImageRoute() async throws {
        let config=configuration,bytes=Data("original".utf8)
        let metadata=HealthJournalImage(id:entryID,observationId:entryID,contentType:"image/jpeg",bytes:bytes.count,
            sha256:HealthJournalMedia.digest(bytes),filename:"photo.jpg",recordedAt:"2026-10-30T13:00:00Z",source:"web",
            url:"/api/integrations/dhoop/health/images/"+entryID)
        let client=HealthJournalClient(archive:archive(),read:{config},save:{_ in},send:{_,_ in Data("changed!".utf8)})
        do {_ = try await client.image(metadata);XCTFail("A mismatched original must never be accepted")}
        catch {XCTAssertEqual(error as? HealthJournalFailure,.invalidResponse)}
        let foreign=HealthJournalImage(id:entryID,observationId:entryID,contentType:"image/jpeg",bytes:bytes.count,
            sha256:metadata.sha256,filename:"photo.jpg",recordedAt:metadata.recordedAt,source:"web",url:"https://other.example/photo.jpg")
        XCTAssertFalse(foreign.valid)
    }
    func testCorruptArchiveFailsClosedWithoutOverwriting() throws {
        let store=archive();try store.prepare();let file=store.folder.appendingPathComponent("drafts.json"),bad=Data("broken".utf8)
        try bad.write(to:file)
        let client=HealthJournalClient(archive:store,read:{nil},save:{_ in},send:{_,_ in self.empty})
        XCTAssertThrowsError(try client.create(.entry(topicId:topicID)))
        XCTAssertEqual(try Data(contentsOf:file),bad)
    }
    func testPhotoIntegrityAndCredentialInstallationMismatchFailClosed() async throws {
        let store=archive(),config=configuration
        let client=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{_,_ in self.empty})
        let id=try client.create(.entry(topicId:topicID)),png=Data([137,80,78,71,13,10,26,10]+Array(repeating:0,count:24))
        try await client.addPhoto(png,draftId:id)
        let photo=try XCTUnwrap(client.draft(id)?.photos.first);try Data("changed".utf8).write(to:store.photoURL(photo))
        XCTAssertThrowsError(try store.photo(photo))
        var state=try store.read();state.drafts[0].installationId=UUID();try store.save(state)
        var called=false
        let replay=HealthJournalClient(archive:store,read:{config},save:{_ in},send:{_,_ in called=true;return self.empty})
        await replay.send(id);XCTAssertFalse(called)
    }
}
