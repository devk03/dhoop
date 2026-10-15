import Foundation
import Combine

/// Canonical manual commands use a dedicated credential and a durable, immutable operation queue.
/// WHOOP source observations retain their separate transport, identities and ownership policy.
@MainActor
final class WorkoutFrontendClient: ObservableObject {
    enum Failure: LocalizedError {
        case disabled, unresolved, unavailable, needsRecovery, rejected
        var errorDescription: String? {
            switch self {
            case .disabled:return "Website editing is off or has not been verified. Your input is retained."
            case .unresolved:return "An earlier website change needs receipt recovery or review. No replacement change was sent."
            case .unavailable:return "The command queue could not be read. Existing data is retained; editing is paused."
            case .needsRecovery:return "Website acceptance is unresolved. Recover this exact operation's receipt before retrying. Your input is retained."
            case .rejected:return "The website rejected this change without applying its primary effects. Refresh and review your retained input."
            }
        }
    }
    static let shared: WorkoutFrontendClient = {
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        return WorkoutFrontendClient(store:.init(url:root.appendingPathComponent("Dhoop/WorkoutFrontend/state.json")))
    }()
    @Published private(set) var state=WorkoutFrontendState()
    @Published private(set) var busy=false
    @Published private(set) var storageUnavailable=false
    private let store: WorkoutFrontendFileStore
    private let send: @MainActor (WorkoutSyncEndpoint,Data?,WorkoutSyncConfiguration) async throws -> Data
    private let readCredential: () throws -> WorkoutSyncConfiguration?
    private let saveCredential: (WorkoutSyncConfiguration) throws -> Void
    private var generation=0
    init(store:WorkoutFrontendFileStore,
         send:@escaping @MainActor (WorkoutSyncEndpoint,Data?,WorkoutSyncConfiguration) async throws -> Data = { endpoint,body,config in try await WorkoutSyncTransport().send(to:endpoint,body:body,credentials:config) },
         readCredential:@escaping () throws -> WorkoutSyncConfiguration? = WorkoutTrackerKeychain.readFrontend,
         saveCredential:@escaping (WorkoutSyncConfiguration) throws -> Void = WorkoutTrackerKeychain.saveFrontend) {
        self.store=store;self.send=send;self.readCredential=readCredential;self.saveCredential=saveCredential
        do { state=try store.load() } catch { storageUnavailable=true }
    }
    var unresolved: WorkoutFrontendOperation? { state.operations.first { $0.unresolved } }
    var configured: Bool { (try? credentials()) != nil }
    func supports(_ action:String, lifecycle:Bool=false) -> Bool {
        state.enabled && !storageUnavailable && !busy && state.capabilities?.manualCommands == true &&
        state.capabilities?.actions.contains(action) == true && (!lifecycle || state.capabilities?.frontendStart == true) && unresolved == nil
    }
    private func credentials() throws -> WorkoutSyncConfiguration {
        guard var config=try readCredential(),config.valid,config.origin==state.origin,config.installationId==state.installationId else { throw Failure.disabled }
        config.enabled=state.enabled;return config
    }
    private func commit(_ next:WorkoutFrontendState) throws { try store.save(next);state=next }
    func configure(origin:String,installationId:UUID,token:String,accessClientId:String? = nil,accessClientSecret:String? = nil) throws {
        guard !busy,!storageUnavailable,unresolved==nil else { throw Failure.unresolved }
        let config=WorkoutSyncConfiguration(enabled:false,origin:origin,installationId:installationId,credential:token.trimmingCharacters(in:.whitespacesAndNewlines),accessClientId:accessClientId,accessClientSecret:accessClientSecret)
        guard config.valid else { throw Failure.disabled }
        var next=state;next.enabled=false;next.origin=origin;next.installationId=installationId;next.capabilities=nil;next.checkedAt=nil
        try saveCredential(config);try commit(next);generation+=1
    }
    func setEnabled(_ value:Bool) throws {
        guard !busy,!storageUnavailable else { throw Failure.unavailable }
        if value { _=try credentials() }
        var next=state;next.enabled=value;if !value { next.capabilities=nil;next.checkedAt=nil }
        try commit(next);generation+=1
    }
    func checkCapabilities() async throws {
        guard !busy,!storageUnavailable,state.enabled else { throw Failure.disabled }
        let config=try credentials(),ticket=generation
        busy=true;defer{busy=false}
        let data=try await send(.frontendCapabilities,nil,config)
        let result=try JSONDecoder().decode(WorkoutFrontendCapabilities.self,from:data);try result.validate()
        guard ticket==generation,!Task.isCancelled,state.enabled else { throw Failure.disabled }
        var next=state;next.capabilities=result;next.checkedAt=Date();try commit(next)
    }
    @discardableResult
    func prepare(command:[String:WorkoutTrackerValue],revision:Int) throws -> UUID {
        guard !storageUnavailable,!busy,unresolved==nil else { throw Failure.unresolved }
        guard case .string(let action)=command["action"], revision >= 0 else { throw Failure.disabled }
        let manualCompletion = action == "update_session" && state.capabilities?.sessionCompletion == true &&
            [WorkoutTrackerValue.string("completed"), .string("planned")].contains(command["status"] ?? .null)
        if manualCompletion && command["date"] != nil { throw Failure.disabled }
        let lifecycle = action == "start_session" || (action == "update_session" && command["status"] != nil && !manualCompletion)
        guard supports(action, lifecycle: lifecycle) else { throw Failure.disabled }
        if action == "update_session", command["date"] != nil, state.capabilities?.sessionDateScheduling != true { throw Failure.disabled }
        let config=try credentials()
        // Match the service's documented name normalization before freezing receipt identity.
        var normalized = command
        if ["create_mesocycle", "create_four_lift_program", "restart_half_marathon_program"].contains(action),
           case .string(let name) = normalized["name"] {
            normalized["name"] = .string(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let intent=WorkoutFrontendIntent(operationId:UUID(),expectedLifeRevision:revision,command:normalized)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let bytes=try encoder.encode(intent)
        var next=state
        next.operations.append(.init(intent:intent,bytes:bytes,origin:config.origin,installationId:config.installationId,
            createdAt:Date(),state:.prepared,receipt:nil,attemptedAt:nil))
        try commit(next);return intent.operationId
    }
    func submit(_ id:UUID) async throws {
        guard !busy,!storageUnavailable,state.enabled,
              let index=state.operations.firstIndex(where:{$0.id==id}) else { throw Failure.disabled }
        let item=state.operations[index]
        guard item.state == .prepared || item.state == .notObserved else { throw Failure.needsRecovery }
        let config=try credentials()
        guard config.origin==item.origin,config.installationId==item.installationId else { throw Failure.disabled }
        busy=true;defer{busy=false}
        var next=state;next.operations[index].state = .sending;next.operations[index].attemptedAt=Date();try commit(next)
        do {
            let data=try await send(.frontendCommand,item.bytes,config)
            try accept(data,for:id)
        } catch {
            if state.operations[index].state == .sending {
                var failed=state;failed.operations[index].state = .uncertain;try commit(failed)
            }
            throw error
        }
        switch state.operations[index].state {
        case .committed:return
        case .rejected:throw Failure.rejected
        default:throw Failure.needsRecovery
        }
    }
    func recover(_ id:UUID) async throws {
        guard !busy,!storageUnavailable,state.enabled,let item=state.operations.first(where:{$0.id==id}),
              item.attemptedAt != nil else { throw Failure.disabled }
        let config=try credentials()
        guard config.origin==item.origin,config.installationId==item.installationId else { throw Failure.disabled }
        busy=true;defer{busy=false}
        let data=try await send(.frontendReceipt(id),nil,config)
        try accept(data,for:id)
    }
    private func accept(_ data:Data,for id:UUID) throws {
        guard let index=state.operations.firstIndex(where:{$0.id==id}) else { throw Failure.unavailable }
        let item=state.operations[index]
        let receipt=try JSONDecoder().decode(WorkoutFrontendReceipt.self,from:data)
        try receipt.validate(for:item.intent,prior:item.receipt)
        // A later negative lookup cannot erase a previously verified success.
        if item.state == .committed && receipt.state != .committed { return }
        if receipt.state == .notObserved, let prior=item.receipt, prior.state != .notObserved { return }
        var next=state
        next.operations[index].receipt=receipt
        switch receipt.state {
        case .committed:next.operations[index].state = .committed
        case .rejected:next.operations[index].state = .rejected
        case .running,.uncertain:next.operations[index].state = .uncertain
        case .notObserved:next.operations[index].state = .notObserved
        }
        try commit(next)
    }
    func cancelUnsent(_ id:UUID) throws {
        guard !busy,let index=state.operations.firstIndex(where:{$0.id==id}),state.operations[index].state == .prepared,
              state.operations[index].attemptedAt==nil else { throw Failure.needsRecovery }
        var next=state;next.operations[index].state = .cancelled;try commit(next)
    }
}
