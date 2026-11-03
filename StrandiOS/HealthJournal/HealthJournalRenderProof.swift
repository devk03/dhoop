#if os(iOS)
import SwiftUI
import StrandDesign

/// Opt-in actual native renders with isolated synthetic clients. No owner credentials, photos or network.
@MainActor
enum HealthJournalRenderProof {
    static let topic = "00000000-0000-4000-8000-000000000001"
    static let observation = "00000000-0000-4000-8000-000000000002"
    static let photoID = "00000000-0000-4000-8000-000000000003"
    static var photoBytes: Data? {
        guard let data = try? Data(contentsOf: FileManager.default.temporaryDirectory.appendingPathComponent("health-journal-demo.png")),
              HealthJournalMedia.digest(data) == "00510a9d51f35799304c12da9d7179032e28ae789d6146add4d9b8ab79348157" else { return nil }
        return data
    }
    static func fixture(empty: Bool = false) throws -> Data {
        var row: [String: Any] = ["id":observation,"topicId":topic,"observedAt":"2026-10-30T09:00:00-04:00","timeZone":"America/New_York",
            "recordedAt":"2026-10-30T13:00:00Z","notes":"Slight dryness after shower.","symptoms":"A little tightness.","source":"web","version":1,"updatedAt":"2026-10-30T13:00:00Z","images":[]]
        if let bytes = photoBytes {
            row["images"] = [["id": photoID, "observationId": observation, "contentType": "image/png", "bytes": bytes.count,
                "sha256": HealthJournalMedia.digest(bytes), "filename": "generated-demo.png", "recordedAt": "2026-10-30T13:00:00Z",
                "source": "web", "url": "/api/integrations/dhoop/health/images/" + photoID]]
        }
        return try JSONSerialization.data(withJSONObject:["topics":empty ? []:[["id":topic,"title":"Skin","bodyArea":"Forearm","side":"left","status":"open","version":1,"createdAt":"2026-10-30T13:00:00Z","updatedAt":"2026-10-30T13:00:00Z"]],
            "observations":empty ? []:[row],"nextOffset":NSNull(),"revisions":[["version":1,"snapshot":row,"recordedAt":"2026-10-30T13:00:00Z","source":"web"]],"nextBeforeVersion":NSNull()])
    }
    static func client(empty: Bool = false, connected: Bool = true, failure: Bool = false, folder: URL? = nil) -> HealthJournalClient {
        let connection = HealthJournalConnection(endpoint: HealthJournalConnection.endpoint, bearerToken: String(repeating: "d", count: 43),
            installationId: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, accessClientId: "synthetic", accessClientSecret: "synthetic")
        let root = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent("health-synthetic-" + UUID().uuidString)
        let server = HealthJournalDemoServer(empty: empty, folder: root, failure: failure)
        return .init(archive: .init(folder: root.appendingPathComponent("drafts")), read: { connected ? connection : nil }, save: { _ in }, send: { request,_ in
            try await server.respond(request)
        })
    }
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--health-journal-render-proof") else { return }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-health-ui-v1")
        let run=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--health-render-run=")}).flatMap{UUID(uuidString:String($0.dropFirst("--health-render-run=".count)))}?.uuidString ?? "manual"
        var rendered=false
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let demo=client();await demo.refresh()
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:demo)},name:"timeline-dark-390",width:390,folder:folder)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:demo)},name:"timeline-light-390",width:390,scheme:.light,folder:folder)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:demo)},name:"timeline-narrow-320",width:320,folder:folder)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:demo)},name:"timeline-accessibility",width:390,height:1400,type:.accessibility3,folder:folder)
            var mutation=HealthJournalMutation.entry(topicId:topic,now:HealthJournalDates.instant("2026-10-30T13:00:00Z")!,zone:"America/New_York")
            mutation.notes="Slight dryness after shower.";let draft=try demo.create(mutation)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalEditor(client:demo,draftId:draft)},name:"editor-390",width:390,height:1100,folder:folder)
            let newTopic=try demo.create(.topic())
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalEditor(client:demo,draftId:newTopic)},name:"topic-validation-320",width:320,folder:folder)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalDetail(client:demo,observationId:observation)},name:"detail-390",width:390,height:1100,folder:folder)
            let empty=client(empty:true);await empty.refresh()
            let firstEntry = try empty.createEntry()
            try await CalendarReaderRenderProof.capture(NavigationStack { HealthJournalEditor(client: empty, draftId: firstEntry) }, name: "first-entry-390", width: 390, height: 1200, folder: folder)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:empty)},name:"empty-390",width:390,folder:folder)
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:client(connected:false))},name:"connection-390",width:390,folder:folder)
            let failed=client(failure:true);await failed.refresh()
            try await CalendarReaderRenderProof.capture(NavigationStack{HealthJournalView(client:failed)},name:"error-390",width:390,folder:folder)
            rendered=true
        }catch { }
        let result:[String:Any]=["schemaVersion":1,"rendered":rendered,"syntheticOnly":true,"networkUsed":false,"runId":run,
            "build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"]
        if let data=try? JSONSerialization.data(withJSONObject:result) {try? data.write(to:folder.appendingPathComponent("result.json"),options:.atomic)}
    }
}
#endif

#if os(iOS)
/// In-memory response fixture for native UI verification, not a hosted service or production client.
@MainActor
final class HealthJournalDemoServer {
    private var document: HealthJournalDocument
    private let folder: URL
    private let failure: Bool
    private var receipts: [String: Data] = [:]
    init(empty: Bool, folder: URL, failure: Bool) {
        self.folder = folder; self.failure = failure
        document = (try? Data(contentsOf: folder.appendingPathComponent("server.json")))
            .flatMap { try? JSONDecoder().decode(HealthJournalDocument.self, from: $0) }
            ?? (try? JSONDecoder().decode(HealthJournalDocument.self, from: HealthJournalRenderProof.fixture(empty: empty))) ?? .empty
    }
    func respond(_ request: HealthJournalRequest) async throws -> Data {
        if failure { throw HealthJournalFailure.http(503) }
        if ProcessInfo.processInfo.arguments.contains("--health-ui-slow") { try await Task.sleep(nanoseconds: 2_000_000_000) }
        if request.path == "capabilities" {
            return Data("{\"schemaVersion\":1,\"read\":true,\"write\":true,\"imagesOptional\":true,\"correctionHistory\":true,\"inlineTopicCreation\":true}".utf8)
        }
        if let image = request.expectedImage {
            guard image.id == HealthJournalRenderProof.photoID, let bytes = HealthJournalRenderProof.photoBytes else { throw HealthJournalFailure.media }
            return bytes
        }
        if let photo = request.image {
            let image = HealthJournalImage(id: photo.id, observationId: photo.observationId, contentType: photo.contentType, bytes: photo.bytes,
                sha256: photo.sha256, filename: photo.filename, recordedAt: ISO8601DateFormatter().string(from: Date()), source: "dhoop", url: "/api/integrations/dhoop/health/images/" + photo.id)
            if let i = document.observations.firstIndex(where: { $0.id == photo.observationId }) {
                document.observations[i].images = (document.observations[i].images ?? []).filter { $0.id != photo.id } + [image]
            }
            try persist(); return try JSONEncoder().encode(image)
        }
        if let body = request.body {
            let mutation = try JSONDecoder().decode(HealthJournalMutation.self, from: body)
            if let receipt = receipts[mutation.requestId] { return receipt }
            let now = ISO8601DateFormatter().string(from: Date())
            if mutation.action == "topic" {
                let topic = HealthJournalTopic(id: mutation.id, title: mutation.title ?? "", bodyArea: mutation.bodyArea ?? "", side: mutation.side ?? "unspecified",
                    status: mutation.status ?? "open", version: (mutation.expectedVersion ?? 0) + 1, createdAt: now, updatedAt: now)
                document.topics.removeAll { $0.id == topic.id }; document.topics.append(topic)
            } else {
                if let topic = mutation.newTopic, let id = mutation.topicId {
                    document.topics.append(.init(id: id, title: topic.title, bodyArea: topic.bodyArea, side: topic.side, status: topic.status, version: 1, createdAt: now, updatedAt: now))
                }
                let previous = document.observations.first { $0.id == mutation.id }
                let row = HealthJournalObservation(id: mutation.id, topicId: mutation.topicId ?? previous?.topicId ?? HealthJournalRenderProof.topic,
                    observedAt: mutation.observedAt ?? now, timeZone: mutation.timeZone ?? "UTC", recordedAt: previous?.recordedAt ?? now,
                    notes: mutation.notes ?? "", symptoms: mutation.symptoms ?? "", source: "dhoop", version: (mutation.expectedVersion ?? 0) + 1,
                    updatedAt: now, images: previous?.images ?? [])
                document.observations.removeAll { $0.id == row.id }; document.observations.insert(row, at: 0)
            }
            let receipt = try JSONSerialization.data(withJSONObject: ["id": mutation.id, "version": (mutation.expectedVersion ?? 0) + 1])
            receipts[mutation.requestId] = receipt; try persist(); return receipt
        }
        var page = document
        if let id = request.query.first(where: { $0.name == "observationId" })?.value { page.observations = page.observations.filter { $0.id == id } }
        if let topic = request.query.first(where: { $0.name == "topicId" })?.value { page.observations = page.observations.filter { $0.topicId == topic } }
        return try JSONEncoder().encode(page)
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("server.json"), options: .atomic)
    }
}
#endif
