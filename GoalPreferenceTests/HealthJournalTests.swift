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
    func testVerifiedSnapshotRestoresOfflineWithoutChangingDraftsOrConnectionScope() async throws {
        let store = archive(), config = configuration
        let first = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { _,_ in try self.document() })
        await first.refresh(); let id = try first.createEntry(topicId: topicID)
        var mutation = try XCTUnwrap(first.draft(id)?.mutation); mutation.notes = "Retained offline note"; first.edit(id, mutation: mutation)
        let before = try Data(contentsOf: store.folder.appendingPathComponent("drafts.json"))
        let offline = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { _,_ in throw URLError(.notConnectedToInternet) })
        XCTAssertTrue(offline.loaded); XCTAssertNotNil(offline.savedCopyReadAt)
        XCTAssertEqual(offline.document.observations.first?.notes, "Original")
        await offline.refresh()
        XCTAssertEqual(offline.document.observations.first?.notes, "Original"); XCTAssertNotNil(offline.error)
        XCTAssertEqual(offline.draft(id)?.mutation.notes, "Retained offline note")
        XCTAssertEqual(try Data(contentsOf: store.folder.appendingPathComponent("drafts.json")), before)
        let other = configuration
        let separate = HealthJournalClient(archive: store, read: { other }, save: { _ in })
        XCTAssertFalse(separate.loaded); XCTAssertTrue(separate.document.observations.isEmpty)
    }
    func testSnapshotWriteFailureDoesNotDisableDraftStorage() async throws {
        let store = archive(), config = configuration; try store.prepare()
        try FileManager.default.createDirectory(at: store.folder.appendingPathComponent("snapshot.json"), withIntermediateDirectories: true)
        let client = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { _,_ in try self.document() })
        await client.refresh(); XCTAssertTrue(client.loaded); XCTAssertFalse(client.storageError)
        let id = try client.createEntry(topicId: topicID)
        XCTAssertNotNil(client.draft(id)); XCTAssertFalse(client.storageError)
    }
    func testSnapshotKeepsExactFirstPageCursorInsteadOfSkippingOlderEntries() async throws {
        let store = archive(), config = configuration
        let client = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { request,_ in
            let offset = Int(request.query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: self.document()) as? [String: Any])
            let row = try XCTUnwrap((object["observations"] as? [[String: Any]])?.first)
            object["observations"] = (offset..<(offset + 20)).map { i -> [String: Any] in
                var value = row; value["id"] = String(format: "00000000-0000-4000-8000-%012d", i + 10); return value
            }
            object["nextOffset"] = offset == 0 ? 20 : NSNull()
            return try JSONSerialization.data(withJSONObject: object)
        })
        await client.refresh(); await client.refresh(more: true)
        XCTAssertEqual(client.document.observations.count, 40)
        let restored = HealthJournalClient(archive: store, read: { config }, save: { _ in })
        XCTAssertEqual(restored.document.observations.count, 20); XCTAssertEqual(restored.document.nextOffset, 20)
    }
    func testUploadedOriginalIsVerifiedAndReusedWithoutRedownloading() async throws {
        let store = archive(), config = configuration; var imageGets = 0
        let png = Data([137,80,78,71,13,10,26,10] + Array(repeating: 0, count: 24))
        let client = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { request,_ in
            if let photo = request.image { return try self.photoReceipt(photo) }
            if request.expectedImage != nil { imageGets += 1; return png }
            if let body = request.body { return self.receipt(try JSONDecoder().decode(HealthJournalMutation.self, from: body)) }
            return self.empty
        })
        let id = try client.create(.entry(topicId: topicID)); try await client.addPhoto(png, draftId: id); await client.send(id)
        let photo = try XCTUnwrap(client.draft(id)?.photos.first)
        let image = HealthJournalImage(id: photo.id, observationId: photo.observationId, contentType: photo.contentType,
            bytes: photo.bytes, sha256: photo.sha256, filename: photo.filename, recordedAt: "2026-10-30T13:00:00Z", source: "dhoop", url: "/api/integrations/dhoop/health/images/" + photo.id)
        let original = try await client.image(image); XCTAssertEqual(original, png); XCTAssertEqual(imageGets, 0)
        try Data("corrupt test fixture".utf8).write(to: store.photoURL(photo))
        let fallback = try await client.image(image); XCTAssertEqual(fallback, png); XCTAssertEqual(imageGets, 1)
    }
    func testCapabilityReadsCoalesceAndCacheWithoutBlockingEntryCreation() async throws {
        let config = configuration; var reads = 0
        let client = HealthJournalClient(archive: archive(), read: { config }, save: { _ in }, send: { _,_ in
            reads += 1; try await Task.sleep(nanoseconds: 30_000_000); return self.inlineCapabilities(true)
        })
        async let first: Void = client.refreshCapabilities()
        async let second: Void = client.refreshCapabilities()
        let id = try client.createEntry(); XCTAssertNotNil(client.draft(id))
        _ = await (first, second); XCTAssertEqual(reads, 1)
        await client.refreshCapabilities(); XCTAssertEqual(reads, 1)
        XCTAssertTrue(client.capabilities?.inlineTopicCreation == true)
    }

    func testCancellingQueuedPhotoReadDoesNotConsumeOrLeakAnActivePermit() async throws {
        let reads = HealthJournalPhotoReads()
        try await reads.acquire(); try await reads.acquire()
        let cancelled = Task { try await reads.acquire() }
        await Task.yield(); cancelled.cancel()
        do { try await cancelled.value; XCTFail("A cancelled queued preview must not start") }
        catch is CancellationError { }
        reads.release()
        try await reads.acquire()
        reads.release(); reads.release()
        try await reads.acquire(); try await reads.acquire()
        reads.release(); reads.release()
    }
    func testPhotoReadsTransferOnlyOnePermitAtATime() async throws {
        let reads = HealthJournalPhotoReads(); try await reads.acquire(); try await reads.acquire()
        var started = 0
        let queued = Task { try await reads.acquire(); started += 1 }
        await Task.yield(); XCTAssertEqual(started, 0)
        reads.release(); try await queued.value; XCTAssertEqual(started, 1)
        reads.release(); reads.release()
    }

    private func inlineCapabilities(_ supported: Bool) -> Data {
        Data("{\"schemaVersion\":1,\"read\":true,\"write\":true,\"imagesOptional\":true,\"correctionHistory\":true,\"inlineTopicCreation\":\(supported)}".utf8)
    }
    func testNewEntryWithoutTopicsOpensDurableComposerWithoutNetworkOrTopicScreen() throws {
        let store = archive(); var requests = 0
        let client = HealthJournalClient(archive: store, read: { nil }, save: { _ in }, send: { _,_ in requests += 1; return self.empty })
        let id = try client.createEntry()
        let draft = try XCTUnwrap(client.draft(id))
        XCTAssertEqual(requests, 0); XCTAssertEqual(draft.mutation.action, "observe")
        XCTAssertEqual(draft.mutation.newTopic?.title, "General")
        XCTAssertEqual(draft.mutation.newTopic?.bodyArea, "Unspecified")
        XCTAssertNotEqual(draft.mutation.topicId, draft.mutation.id)
        let reloaded = HealthJournalClient(archive: store, read: { nil }, save: { _ in })
        XCTAssertEqual(reloaded.draft(id)?.mutation, draft.mutation)
        XCTAssertTrue(try XCTUnwrap(reloaded.draft(id)).editable)
    }
    func testInlineTopicSaveNormalizesOnlyDefinitionAndUsesOneEntryPost() async throws {
        let config = configuration; var posts: [HealthJournalMutation] = []; var paths: [String] = []
        let client = HealthJournalClient(archive: archive(), read: { config }, save: { _ in }, send: { request,_ in
            paths.append(request.path)
            if request.path == "capabilities" { return self.inlineCapabilities(true) }
            if let body = request.body {
                let mutation = try JSONDecoder().decode(HealthJournalMutation.self, from: body)
                posts.append(mutation); return self.receipt(mutation)
            }
            return self.empty
        })
        let id = try client.createEntry(); var mutation = try XCTUnwrap(client.draft(id)?.mutation)
        mutation.newTopic?.title = "  Left arm  "; mutation.newTopic?.bodyArea = "  Forearm  "
        mutation.notes = "  Keep this note exactly.\n"; client.edit(id, mutation: mutation)
        await client.send(id)
        XCTAssertTrue(try XCTUnwrap(client.draft(id)).completed)
        XCTAssertEqual(posts.count, 1); XCTAssertEqual(posts[0].topicId, mutation.topicId)
        XCTAssertEqual(posts[0].newTopic?.title, "Left arm"); XCTAssertEqual(posts[0].newTopic?.bodyArea, "Forearm")
        XCTAssertEqual(posts[0].notes, mutation.notes); XCTAssertEqual(posts[0].observedAt, mutation.observedAt)
        XCTAssertEqual(paths, ["capabilities", "entries", "entries"])
    }
    func testInlineTopicUncertainReceiptReplaysExactBodyAndIdentityAfterRelaunch() async throws {
        let config = configuration, store = archive(); var sent: [Data] = []
        let first = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { request,_ in
            if request.path == "capabilities" { return self.inlineCapabilities(true) }
            if let body = request.body { sent.append(body); throw URLError(.networkConnectionLost) }
            return self.empty
        })
        let id = try first.createEntry(); await first.send(id)
        XCTAssertFalse(try XCTUnwrap(first.draft(id)).bodyAccepted)
        let replay = HealthJournalClient(archive: store, read: { config }, save: { _ in }, send: { request,_ in
            if let body = request.body {
                sent.append(body); return self.receipt(try JSONDecoder().decode(HealthJournalMutation.self, from: body))
            }
            XCTAssertEqual(request.path, "entries", "A frozen replay must not change based on a newer capability read")
            return self.empty
        })
        await replay.send(id)
        XCTAssertTrue(try XCTUnwrap(replay.draft(id)).completed)
        XCTAssertEqual(sent.count, 2); XCTAssertEqual(sent[0], sent[1])
    }
    func testUnsupportedInlineTopicRetainsEditableDraftAndRetryChecksNewCapability() async throws {
        let config = configuration; var supported = false; var posts = 0
        let client = HealthJournalClient(archive: archive(), read: { config }, save: { _ in }, send: { request,_ in
            if request.path == "capabilities" { return self.inlineCapabilities(supported) }
            if let body = request.body { posts += 1; return self.receipt(try JSONDecoder().decode(HealthJournalMutation.self, from: body)) }
            return self.empty
        })
        let id = try client.createEntry(); await client.send(id)
        XCTAssertEqual(posts, 0); XCTAssertTrue(try XCTUnwrap(client.draft(id)).editable)
        XCTAssertNil(client.draft(id)?.body); XCTAssertNotNil(client.draft(id)?.lastError)
        supported = true; await client.send(id)
        XCTAssertEqual(posts, 1); XCTAssertTrue(try XCTUnwrap(client.draft(id)).completed)
    }
    func testFailedCapabilityReadDoesNotClaimInlineTopicIsUnsupported() async throws {
        let config = configuration
        let client = HealthJournalClient(archive: archive(), read: { config }, save: { _ in }, send: { _,_ in throw URLError(.notConnectedToInternet) })
        let id = try client.createEntry(); await client.send(id)
        XCTAssertTrue(try XCTUnwrap(client.draft(id)).editable)
        XCTAssertEqual(client.draft(id)?.lastError, HealthJournalClient.message(URLError(.notConnectedToInternet)))
        XCTAssertNotEqual(client.draft(id)?.lastError, HealthJournalFailure.inlineTopicUnavailable.localizedDescription)
    }

    func testInlineTopicIsObserveOnlyAndExistingTopicEntryDoesNotAddDefinition() async throws {
        var mutation = HealthJournalMutation.newEntry(); try mutation.validate()
        mutation.action = "correct"; mutation.topicId = nil; mutation.expectedVersion = 1
        XCTAssertThrowsError(try mutation.validate())
        mutation = .newEntry(); mutation.newTopic?.side = "invalid"
        XCTAssertThrowsError(try mutation.validate())
        mutation = .newEntry(); mutation.newTopic?.title = String(repeating: "😀", count: 61)
        XCTAssertThrowsError(try mutation.validate())
        let config = configuration
        let client = HealthJournalClient(archive: archive(), read: { config }, save: { _ in }, send: { _,_ in try self.document() })
        await client.refresh(); let id = try client.createEntry(topicId: topicID)
        XCTAssertEqual(client.draft(id)?.mutation.topicId, topicID)
        XCTAssertNil(client.draft(id)?.mutation.newTopic)
    }

    func testRepeatedDSTHourHasDifferentVisibleTimestampForEachActualInstant() {
        let first = HealthJournalDates.display("2026-11-01T01:30:00-04:00", zone: "America/New_York")
        let second = HealthJournalDates.display("2026-11-01T01:30:00-05:00", zone: "America/New_York")
        XCTAssertNotEqual(first, second, "Two different health observations must not have identical ambiguous timestamps")
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
    func testForegroundRecoveryPersistsRetainedDraftAfterTransientWriteFailure() throws {
        let store=archive()
        let client=HealthJournalClient(archive:store,read:{nil},save:{_ in},send:{_,_ in self.empty})
        let id=try client.create(.entry(topicId:topicID))
        let file=store.folder.appendingPathComponent("drafts.json"),preserved=store.folder.appendingPathComponent("preserved-state.json")
        try FileManager.default.moveItem(at:file,to:preserved)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        var mutation=try XCTUnwrap(client.draft(id)).mutation;mutation.notes="Retained after a temporary storage failure"
        client.edit(id,mutation:mutation)
        XCTAssertTrue(client.storageError)
        XCTAssertEqual(client.draft(id)?.mutation.notes,mutation.notes)
        try FileManager.default.moveItem(at:file,to:store.folder.appendingPathComponent("retained-obstruction"))
        try FileManager.default.moveItem(at:preserved,to:file)
        client.reloadWhenAccessible()
        XCTAssertFalse(client.storageError,"Available storage must restore the Save action after foreground recovery")
        XCTAssertEqual(try store.read().drafts.first?.mutation.notes,mutation.notes)
        XCTAssertNil(client.error)
    }
    func testCorruptArchiveFailsClosedWithoutOverwriting() throws {
        let store=archive();try store.prepare();let file=store.folder.appendingPathComponent("drafts.json"),bad=Data("broken".utf8)
        try bad.write(to:file)
        let client=HealthJournalClient(archive:store,read:{nil},save:{_ in},send:{_,_ in self.empty})
        XCTAssertThrowsError(try client.create(.entry(topicId:topicID)))
        client.reloadWhenAccessible()
        XCTAssertTrue(client.storageError)
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
