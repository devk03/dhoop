#if os(iOS)
import SwiftUI
import StrandDesign

/// Opt-in actual native renders with isolated synthetic clients. No owner credentials, photos or network.
@MainActor
enum HealthJournalRenderProof {
    static let topic = "00000000-0000-4000-8000-000000000001"
    static let observation = "00000000-0000-4000-8000-000000000002"
    static func fixture(empty: Bool = false) throws -> Data {
        let row: [String: Any] = ["id":observation,"topicId":topic,"observedAt":"2026-10-30T09:00:00-04:00","timeZone":"America/New_York",
            "recordedAt":"2026-10-30T13:00:00Z","notes":"Slight dryness after shower.","symptoms":"A little tightness.","source":"web","version":1,"updatedAt":"2026-10-30T13:00:00Z","images":[]]
        return try JSONSerialization.data(withJSONObject:["topics":[["id":topic,"title":"Face","bodyArea":"Face","side":"unspecified","status":"open","version":1,"createdAt":"2026-10-30T13:00:00Z","updatedAt":"2026-10-30T13:00:00Z"]],
            "observations":empty ? []:[row],"nextOffset":NSNull(),"revisions":[["version":1,"snapshot":row,"recordedAt":"2026-10-30T13:00:00Z","source":"web"]],"nextBeforeVersion":NSNull()])
    }
    static func client(empty: Bool = false, connected: Bool = true, failure: Bool = false) -> HealthJournalClient {
        let connection = HealthJournalConnection(endpoint:HealthJournalConnection.endpoint,bearerToken:String(repeating:"d",count:43),installationId:UUID(),accessClientId:"synthetic",accessClientSecret:"synthetic")
        return .init(archive:.init(folder:FileManager.default.temporaryDirectory.appendingPathComponent("health-synthetic-"+UUID().uuidString)),
                     read:{connected ? connection:nil},save:{_ in},send:{_,_ in if failure {throw HealthJournalFailure.http(503)};return try fixture(empty:empty)})
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
