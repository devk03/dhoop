import Foundation
import Combine

/// App-side delivery ledger. No firmware alarm writes; a schedule is not proof of strap delivery.
@MainActor
final class BuzzDeliveryCoordinator: ObservableObject {
    enum Status: String, Codable {
        case scheduled, awaitingOwner, requested, responseReceived, acknowledged, rejected, confirmed, missed, cancelled, unavailable, suppressed
    }
    struct Cue: Codable, Identifiable {
        let id: String
        let owner: String
        let deviceId: String
        let due: Date
        let expires: Date
        let loops: UInt8
        let gate: String?
        let sampleAt: Date?
        var status: Status = .scheduled
        var detail = "Scheduled in Dhoop; not armed on the strap"
        var requestedAt: Date?
        var sequence: Int?
        var opcode: Int?
        var connection: UUID?
    }
    struct Link {
        let deviceId: String
        let connection: UUID
        let ready: Bool
    }
    struct Transmission { let sequence: Int; let opcode: Int }
    @Published private(set) var cues: [Cue] = []
    @Published private(set) var storageError: String?
    @Published private(set) var exclusiveOwner: String?
    @Published var alarmReadback: [String] = []
    var link: () -> Link = { Link(deviceId: "", connection: UUID(), ready: false) }
    var transmit: (Cue) -> Transmission? = { _ in nil }
    var gateEnabled: (String) -> Bool = { HapticPrefs.enabled($0) }
    var log: (String) -> Void = { _ in }
    private let file: URL
    private var timer: Task<Void, Never>?
    private var processing = false
    private var lastRequestAt = Date.distantPast
    private var loaded = true

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dhoop/Buzz/delivery-v1.json")) {
        self.file = file
        do {
            cues = try JSONDecoder().decode([Cue].self, from: Data(contentsOf: file))
            // Only an owning feature can revalidate a future schedule after relaunch.
            for i in cues.indices where cues[i].status == .scheduled { cues[i].status = .awaitingOwner }
        } catch CocoaError.fileReadNoSuchFile { }
        catch { loaded = false; storageError = "Buzz history could not be read. Alerts are disabled until storage is available." }
    }

    @discardableResult func claim(_ owner: String) -> Bool {
        guard loaded, storageError == nil else { return false }
        guard exclusiveOwner == nil || exclusiveOwner == owner else { return false }
        exclusiveOwner = owner
        return true
    }
    func release(_ owner: String) {
        cancel(owner: owner)
        if exclusiveOwner == owner { exclusiveOwner = nil }
    }

    @discardableResult func schedule(owner: String, id: String = UUID().uuidString, deviceId: String,
                                     due: Date = Date(), grace: TimeInterval = 2, loops: UInt8 = 1,
                                     gate: String? = nil, sampleAt: Date? = nil, now: Date = Date()) -> String {
        guard loaded else { return id }
        var next = cues
        if let index = next.firstIndex(where: { $0.id == id }) {
            if next[index].status == .scheduled { service(now: now); return id }
            guard next[index].status == .awaitingOwner, next[index].owner == owner,
                  next[index].deviceId == deviceId, next[index].due == due else { return id }
            next[index].status = .scheduled
        } else {
            next.append(Cue(id: id, owner: owner, deviceId: deviceId, due: due,
                            expires: due.addingTimeInterval(max(0, grace)), loops: min(max(loops, 1), 8), gate: gate, sampleAt: sampleAt))
        }
        guard commit(next) else { return id }
        service(now: now)
        return id
    }

    func connectionLost() {
        var next = cues
        for i in next.indices where next[i].status == .scheduled {
            next[i].status = .unavailable
            next[i].detail = "Connection lost; timed cue cancelled. Resume the feature to schedule again."
        }
        if !commit(next) { cues = next }
        armTimer()
    }

    func willUseSequence(_ sequence: Int, connection: UUID) {
        var next = cues
        var changed = false
        for i in next.indices where next[i].sequence == sequence && next[i].connection == connection
            && [.requested, .responseReceived].contains(next[i].status) {
            next[i].sequence = nil
            next[i].detail = "Command requested; sequence reused before a conclusive response. Delivery unconfirmed."
            changed = true
        }
        if changed { _ = commit(next) }
    }

    func cancel(owner: String) {
        var next = cues
        for i in next.indices where next[i].owner == owner && [.scheduled, .awaitingOwner].contains(next[i].status) {
            next[i].status = .cancelled; next[i].detail = "Cancelled in Dhoop; no strap alarm was armed"
        }
        // Cancel memory even if disk fails. Relaunch never executes an unvalidated schedule.
        if !commit(next) { cues = next }
        armTimer()
    }

    /// Call from genuine BLE events as well as the foreground timer. Neither guarantees future execution.
    func service(now: Date = Date()) {
        guard loaded, !processing else { return }
        processing = true
        defer { processing = false; armTimer() }
        let readyIDs = cues.filter { $0.status == .scheduled && $0.due <= now }.sorted { $0.due < $1.due }.map(\.id)
        for id in readyIDs {
            guard let i = cues.firstIndex(where: { $0.id == id }) else { continue }
            var next = cues
            let cue = next[i]
            let context = link()
            if now > cue.expires {
                next[i].status = .missed; next[i].detail = "Deadline missed; no late buzz replayed"
            } else if let sample = cue.sampleAt, now < sample || now.timeIntervalSince(sample) > 2 {
                next[i].status = .missed; next[i].detail = "Heart-rate sample stale; no buzz requested"
            } else if let gate = cue.gate, !gateEnabled(gate) {
                next[i].status = .cancelled; next[i].detail = "Alert preference is off"
            } else if let owner = exclusiveOwner, cue.owner != owner && cue.owner != "manual-test" {
                next[i].status = .suppressed; next[i].detail = "Another exercise owns WHOOP cues"
            } else if !context.ready || context.deviceId != cue.deviceId {
                next[i].status = .unavailable; next[i].detail = "WHOOP unavailable at deadline; not queued for reconnect"
            } else if now.timeIntervalSince(lastRequestAt) < 0.25 {
                next[i].status = .suppressed; next[i].detail = "Overlapping cue suppressed"
            } else {
                next[i].status = .requested; next[i].requestedAt = now; next[i].connection = context.connection
                next[i].detail = "Command requested; acknowledgment and vibration unconfirmed"
                // Persist before the effect. Relaunch cannot replay an already requested cue.
                guard commit(next) else { continue }
                lastRequestAt = now
                if let sent = transmit(cue), let index = cues.firstIndex(where: { $0.id == id }) {
                    next = cues; next[index].sequence = sent.sequence; next[index].opcode = sent.opcode
                    _ = commit(next)
                } else if let index = cues.firstIndex(where: { $0.id == id }) {
                    next = cues; next[index].status = .unavailable; next[index].detail = "Command was not submitted"
                    _ = commit(next)
                }
                log("\(cue.owner): requested; vibration unconfirmed")
                continue
            }
            _ = commit(next)
            log("\(cue.owner): \(next[i].detail)")
        }
    }

    func acknowledge(sequence: Int, opcode: Int, result: String, payload: [UInt8] = [], deviceId: String, connection: UUID, now: Date = Date()) {
        // Sequence is only eight bits: also require opcode, device, connection and a short receipt window.
        guard let i = cues.lastIndex(where: { [Status.requested, .responseReceived].contains($0.status) && $0.sequence == sequence && $0.opcode == opcode
            && $0.deviceId == deviceId && $0.connection == connection
            && $0.requestedAt.map { now >= $0 && now.timeIntervalSince($0) <= 5 } == true }) else { return }
        var next = cues
        let success = opcode == 19 && result.hasPrefix("SUCCESS") && payload.count >= 2 && payload[0] == 1 && payload[1] == 5
        let rejected = result.hasPrefix("FAIL") || result.hasPrefix("INVALID") || result.hasPrefix("ERROR") || result.hasPrefix("UNSUPPORTED")
        next[i].status = success ? .acknowledged : rejected ? .rejected : .responseReceived
        next[i].detail = "Command response: \(result); payload \(payload.map(String.init).joined(separator: ",")). Physical vibration unconfirmed."
        _ = commit(next)
        log("\(next[i].owner): command response \(result); vibration unconfirmed")
    }
    func confirm(id: String) {
        guard let i = cues.firstIndex(where: { $0.id == id && [.requested, .responseReceived, .acknowledged].contains($0.status) }) else { return }
        var next = cues; next[i].status = .confirmed; next[i].detail = "Vibration confirmed by the wearer"
        _ = commit(next)
    }
    func retryStorage() {
        do {
            var saved = try JSONDecoder().decode([Cue].self, from: Data(contentsOf: file))
            for i in saved.indices where saved[i].status == .scheduled { saved[i].status = .awaitingOwner }
            cues = saved; loaded = true; storageError = nil
        } catch { storageError = "Buzz history is still unreadable. No data was replaced." }
    }

    private func commit(_ next: [Cue]) -> Bool {
        guard loaded else { return false }
        do {
            let retained = next.filter { [.scheduled, .awaitingOwner].contains($0.status) }
                + next.filter { ![.scheduled, .awaitingOwner].contains($0.status) }.suffix(128)
            var directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let data = try JSONEncoder().encode(retained)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            cues = retained; storageError = nil
            return true
        } catch { storageError = "Buzz state could not be saved. No new command was sent."; return false }
    }
    private func armTimer() {
        timer?.cancel()
        guard let next = cues.filter({ $0.status == .scheduled }).map(\.due).min() else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.05, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.service()
        }
    }
}
