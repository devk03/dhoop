import Foundation
import Combine
import StrandAnalytics
import WhoopProtocol

@MainActor
final class DhoopAlarmManager: ObservableObject {
    struct Link: Equatable {
        var deviceID = ""
        var connection = UUID()
        var ready = false
        var whoop5 = false
        var experimental = false
        var firmware = "Unknown firmware"
        var battery: Double?
    }
    struct Reply {
        let deviceID: String
        let connection: UUID
        let opcode: Int
        let result: String
        let payload: [UInt8]
        var success: Bool { result == "SUCCESS(1)" }
    }
    struct Reading: Identifiable {
        var id: Int { slot }
        let slot: Int
        let record: Whoop5AlarmRecord?
        let raw: [UInt8]
        let detail: String
        let at: Date
        let deviceID: String
        let connection: UUID
    }
    enum Failure: LocalizedError {
        case unavailable, timeout, stale, invalidRecord, rejected, conflict, storage, busy
        case verificationFailed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Connect the paired WHOOP 5 to synchronize alarms."
            case .timeout: return "WHOOP did not answer. Storage remains unverified."
            case .stale: return "The device or connection changed. Check WHOOP again."
            case .invalidRecord: return "WHOOP's response could not verify alarm storage."
            case .rejected: return "WHOOP did not accept the operation. Existing storage needs checking."
            case .conflict: return "This slot changed on WHOOP. Dhoop preserved it."
            case .storage: return "Alarm state could not be saved. No new write was requested."
            case .busy: return "Another WHOOP alarm check is in progress. Wait for it to finish."
            case .verificationFailed(let message): return message
            }
        }
    }
    @Published private(set) var state = DhoopAlarmState()
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var context = Link()
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var storageError: String?
    @Published private(set) var phoneStatus = "Phone backup off"
    var link: () -> Link = { Link() }
    var exchange: (Int, [UInt8]) async throws -> Reply = { _, _ in throw Failure.unavailable }
    var backup: ([DhoopAlarmDefinition], Date) async -> String = { _, _ in "Phone backup unavailable on this platform" }
    var authorizeBackup: () async -> Bool = { false }
    private let file: DhoopAlarmFile
    private var queued = false

    init(file: DhoopAlarmFile = DhoopAlarmFile()) {
        self.file = file
        do { state = try file.read() }
        catch { storageError = "Alarm history could not be read. The original file is preserved; strap writes are disabled." }
    }
    var definitions: [DhoopAlarmDefinition] { state.definitions.filter { !$0.deleted } }
    var currentSlots: [DhoopAlarmSlot] { state.slots.filter { $0.deviceID == context.deviceID } }
    var exportURL: URL { file.url }
    func importLegacy(enabled: Bool, minute: Int, weekdays: Set<Int>, overrides: [Int: Int], now: Date = Date()) {
        guard !state.legacyImported, storageError == nil else { return }
        var next = state; next.legacyImported = true
        if enabled {
            let days = weekdays.isEmpty ? Set(1...7) : weekdays
            let groups = Dictionary(grouping: days, by: { overrides[$0] ?? minute })
            for value in groups.keys.sorted() {
                var alarm = DhoopAlarmDefinition(); alarm.label = "Wake up"
                alarm.rule = .init(minute: value, weekdays: Set(groups[value]!))
                next.definitions.append(alarm)
            }
            append("Existing wake preferences imported. Strap slots remain protected until explicitly adopted.", to: &next, now: now)
        }
        _ = commit(next)
    }
    @discardableResult func save(_ definition: DhoopAlarmDefinition, now: Date = Date()) -> Bool {
        guard definition.valid else { error = "Choose a valid time and label."; return false }
        var next = state, value = definition
        if let i = next.definitions.firstIndex(where: { $0.id == value.id }) {
            value.revision = next.definitions[i].revision + 1; next.definitions[i] = value
        } else { next.definitions.append(value) }
        append("Saved \(value.label); automatic WHOOP verification pending.", to: &next, now: now)
        guard commit(next) else { return false }
        requestSync()
        return true
    }
    func toggle(_ id: String, enabled: Bool) {
        guard var definition = state.definitions.first(where: { $0.id == id && !$0.deleted }) else { return }
        definition.enabled = enabled
        if enabled && definition.rule.weekdays.isEmpty,
           (definition.rule.oneTimeEpoch ?? 0) <= Int(Date().timeIntervalSince1970) {
            var calendar = Calendar.current
            if let id = definition.rule.timeZoneID, let zone = TimeZone(identifier: id) { calendar.timeZone = zone }
            definition.rule.oneTimeEpoch = AlarmOccurrencePlanner.nextWallTime(minute: definition.rule.minute, after: Date(), calendar: calendar)
        }
        save(definition)
    }
    func delete(_ id: String) {
        guard var definition = state.definitions.first(where: { $0.id == id }) else { return }
        definition.deleted = true; definition.enabled = false; save(definition)
    }
    func skipNext(_ id: String, now: Date = Date()) {
        guard var definition = state.definitions.first(where: { $0.id == id }),
              let next = AlarmOccurrencePlanner.dates(rule: definition.rule, after: now, limit: 1).first else { return }
        definition.rule.skippedEpochs.insert(next); save(definition, now: now)
    }
    func plan(now: Date = Date()) -> [PlannedAlarmOccurrence] {
        AlarmOccurrencePlanner.plan(rules: Dictionary(uniqueKeysWithValues:
            definitions.filter(\.enabled).map { ($0.id, $0.rule) }), after: now)
    }
    func nextEpoch(_ alarm: DhoopAlarmDefinition, now: Date) -> Int? {
        alarm.enabled ? AlarmOccurrencePlanner.dates(rule: alarm.rule, after: now, limit: 1).first : nil
    }
    func verifiedOccurrences(now: Date) -> [DhoopAlarmSlot] {
        guard context.ready else { return [] }
        let desired = Set(plan(now: now).map(\.epoch))
        return currentSlots.filter { slot in
            slot.pendingRecord == nil && !slot.removalRequested && desired.contains(Int(slot.expected.epoch))
                && slot.expected == Whoop5AlarmRecord.standard(slot: slot.slot, epoch: slot.expected.epoch)
                && readings.contains { reading in reading.slot == slot.slot && reading.record == slot.expected
                    && reading.deviceID == context.deviceID && reading.connection == context.connection }
        }
    }
    struct RemovalRisk: Identifiable {
        let id: String
        let slot: Int
        let epochs: [Int64]
    }
    func pendingRemovalRisks(now: Date) -> [RemovalRisk] {
        let desired = Set(plan(now: now).map { Int64($0.epoch) })
        return currentSlots.compactMap { slot in
            // A merely reserved external slot is not a cancellation request.
            guard !slot.definitionIDs.isEmpty || !slot.pendingDefinitionIDs.isEmpty || slot.removalRequested else { return nil }
            let records = [slot.expected, slot.pendingRecord].compactMap { $0 }
            let epochs = Set(records.map(\.epoch).filter {
                $0 > Int64(now.timeIntervalSince1970) && (slot.removalRequested || !desired.contains($0))
            }).sorted()
            return epochs.isEmpty ? nil : RemovalRisk(id: slot.id, slot: slot.slot, epochs: epochs)
        }
    }
    func status(_ alarm: DhoopAlarmDefinition, now: Date) -> String {
        let associated = currentSlots.filter { $0.definitionIDs.contains(alarm.id) || $0.pendingDefinitionIDs.contains(alarm.id) }
        if !alarm.enabled || alarm.deleted {
            return associated.contains { !$0.expected.isZeroTime || $0.pendingRecord != nil } ? "Pending removal" : "Off"
        }
        guard let epoch = nextEpoch(alarm, now: now) else {
            return alarm.rule.oneTimeEpoch.map { $0 <= Int(now.timeIntervalSince1970) } == true
                ? "Due · delivery unconfirmed" : "No future occurrence"
        }
        if let slot = associated.first(where: { $0.expected.epoch == epoch && $0.pendingRecord == nil && !$0.removalRequested }) {
            if let read = readings.first(where: { $0.slot == slot.slot && $0.deviceID == context.deviceID && $0.connection == context.connection }),
               let record = read.record, record != slot.expected { return "Changed on WHOOP · Review slot" }
            return verifiedOccurrences(now: now).contains(where: { $0.id == slot.id })
                ? "Stored on WHOOP" : "Previously stored · Check WHOOP"
        }
        return associated.first(where: { $0.pendingRecord != nil })?.detail ?? "Pending sync"
    }
    func approveSlot(_ slot: Int, expected: Whoop5AlarmRecord, now: Date = Date()) {
        let current = link()
        guard !busy, current.ready, current.whoop5,
              let reading = readings.first(where: { $0.slot == slot }), reading.record == expected,
              reading.deviceID == current.deviceID, reading.connection == current.connection,
              now.timeIntervalSince(reading.at) <= 60 else { error = Failure.stale.localizedDescription; return }
        var next = state
        guard !next.slots.contains(where: { $0.deviceID == current.deviceID && $0.slot == slot }) else { return }
        // This explicit UI approval is necessary even for zeros, which can represent a failed read.
        next.slots.append(.init(deviceID: current.deviceID, slot: slot, expected: expected, originalRecord: expected))
        append("Owner approved use of slot \(slot). Its previous full record was retained.", to: &next, now: now)
        if commit(next) { requestSync() }
    }
    func requestSync() {
        queued = true
        guard !busy else { return }
        Task { await synchronize() }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true; defer { busy = false; if queued { requestSync() } }
        context = link(); error = nil
        guard context.ready && context.whoop5 else { error = Failure.unavailable.localizedDescription; return }
        let captured = context
        readings = []
        for slot in 1...6 {
            do { let reading = try await read(slot, context: captured); readings.append(reading) }
            catch { readings.append(.init(slot: slot, record: nil, raw: [], detail: error.localizedDescription,
                                          at: Date(), deviceID: captured.deviceID, connection: captured.connection)) }
            if link().connection != captured.connection { break }
        }
        if same(captured) { context = link() }
        exportDiagnostics()
    }
    /// Explicit read completion means six attributed, decodable records, not an empty or partial list.
    func readSlotsReviewed() async throws {
        guard !busy else { throw Failure.busy }
        let captured = link()
        guard captured.ready && captured.whoop5 else { throw Failure.unavailable }
        await refresh()
        try Task.checkCancellation()
        guard same(captured) else { throw Failure.stale }
        guard readings.count == 6, Set(readings.map(\.slot)) == Set(1...6), readings.allSatisfy({
            $0.record != nil && $0.deviceID == captured.deviceID && $0.connection == captured.connection
        }) else { throw Failure.invalidRecord }
    }
    /// The explicit retry awaits the existing owned-slot reconciler; it grants no new ownership.
    func synchronizeReviewed() async throws {
        guard !busy else { throw Failure.busy }
        guard storageError == nil else { throw Failure.storage }
        await synchronize()
        try Task.checkCancellation()
        guard storageError == nil else { throw Failure.storage }
        if let error { throw Failure.verificationFailed(error) }
    }
    func connectionChanged() {
        context = link(); readings = []
        var next = state
        for i in next.slots.indices where next.slots[i].deviceID == context.deviceID { next.slots[i].verifiedAt = nil }
        _ = commit(next)
        if context.ready && context.whoop5 { requestSync() }
    }
    func executionReported(now: Date = Date()) {
        var next = state
        append("WHOOP reported alarm execution (event 57); slot and felt vibration are unconfirmed.", to: &next, now: now)
        if commit(next) { requestSync() }
    }
    func confirmFelt(slot: Int, epoch: Int, felt: Bool, now: Date = Date()) {
        guard epoch <= Int(now.timeIntervalSince1970),
              state.history.contains(where: { $0.deviceID == context.deviceID && $0.slot == slot && $0.epoch == epoch }) else { return }
        var next = state
        append(felt ? "Wearer confirmed feeling the alarm." : "Wearer reported no alarm vibration.",
               slot: slot, epoch: epoch, to: &next, now: now)
        _ = commit(next)
    }
    func blocksMotor(now: Date) -> Bool {
        // Conservatively protect every known nonzero slot, including external schedules.
        let epochs = readings.compactMap { $0.record?.epoch }.filter { $0 > 0 }
            + currentSlots.compactMap { $0.expected.epoch > 0 ? $0.expected.epoch : nil }
        return epochs.contains { abs(Double($0) - now.timeIntervalSince1970) <= 60 }
    }
    private func synchronize() async {
        guard !busy else { return }
        busy = true; queued = false
        defer { busy = false; exportDiagnostics(); if queued { requestSync() } }
        context = link(); error = nil
        guard storageError == nil else { return }
        // Backup reflects explicit user intent independently of strap availability.
        phoneStatus = await backup(definitions, Date())
        guard context.ready && context.whoop5 else { error = Failure.unavailable.localizedDescription; return }
        let captured = context
        // A read-only inventory is useful even when no alarm slots have been authorized.
        readings = []
        for slot in 1...6 {
            do { readings.append(try await read(slot, context: captured)) }
            catch { self.error = error.localizedDescription }
            guard same(captured) else { self.error = Failure.stale.localizedDescription; return }
        }
        context = link()
        let ids = currentSlots.map(\.id)
        for id in ids {
            guard same(captured), let index = state.slots.firstIndex(where: { $0.id == id }) else { return }
            do { try await reconcile(index: index, context: captured) }
            catch { self.error = error.localizedDescription; setDetail(id, error.localizedDescription) }
        }
    }
    private func reconcile(index: Int, context: Link) async throws {
        let owned = state.slots[index]
        let reading = try await read(owned.slot, context: context)
        guard let current = reading.record else { throw Failure.invalidRecord }
        // Recover a partial write by readback. Neither success nor failure ACK guarantees atomicity.
        if let pending = owned.pendingRecord, current == pending {
            var next = state; next.slots[index].expected = pending
            next.slots[index].definitionIDs = owned.pendingDefinitionIDs
            next.slots[index].pendingRecord = nil; next.slots[index].pendingDefinitionIDs = []
            next.slots[index].verifiedAt = reading.at; next.slots[index].detail = "Stored on WHOOP"
            guard commit(next) else { throw Failure.storage }
        } else if owned.pendingRecord != nil && current != owned.expected {
            throw Failure.conflict
        } else if owned.pendingRecord != nil {
            // Original record remains. Clear the unresolved intent only after this physical read.
            var next = state; next.slots[index].pendingRecord = nil; next.slots[index].pendingDefinitionIDs = []
            guard commit(next) else { throw Failure.storage }
        }
        let now = Date(), slot = state.slots[index]
        let consumed = current.isClearedCandidate && slot.expected.epoch > 0
            && slot.expected.epoch <= Int64(now.timeIntervalSince1970)
        let pendingClear = slot.removalRequested && current.isClearedCandidate
        guard current == slot.expected || consumed || pendingClear else { throw Failure.conflict }
        let plans = plan(now: now)
        // Merely reserving a populated slot does not clear it without an intended replacement.
        if slot.definitionIDs.isEmpty && slot.pendingRecord == nil && !current.isZeroTime && plans.isEmpty { return }
        let keep = plans.first { $0.epoch == Int(slot.expected.epoch) }
        if let keep, current == slot.expected, !slot.removalRequested,
           current == Whoop5AlarmRecord.standard(slot: slot.slot, epoch: current.epoch) {
            var next = state; next.slots[index].definitionIDs = keep.definitionIDs
            next.slots[index].verifiedAt = reading.at; next.slots[index].detail = "Stored on WHOOP"
            guard commit(next) else { throw Failure.storage }; return
        }
        // A replaced/disabled occurrence is cancelled before any new occurrence is assigned.
        if !current.isClearedCandidate || pendingClear {
            guard context.experimental else { throw Failure.unavailable }
            var next = state; next.slots[index].removalRequested = true
            next.slots[index].detail = "Pending removal"
            guard commit(next) else { throw Failure.storage }
            guard let payload = Whoop5AlarmRecord.clearPayload(slot: owned.slot) else { throw Failure.invalidRecord }
            let response = try await exchange(69, payload)
            guard same(context), attributed(response, opcode: 69, context: context), response.success else { throw Failure.rejected }
            let cleared = try await read(owned.slot, context: context)
            guard let record = cleared.record, record.isClearedCandidate else { throw Failure.invalidRecord }
            var final = state; final.slots[index].expected = record
            final.slots[index].definitionIDs = []; final.slots[index].removalRequested = false
            final.slots[index].verifiedAt = nil; final.slots[index].detail = "Removal reported by WHOOP; physical cancellation unverified"
            append("Selected slot read back as zero after a targeted clear; physical cancellation remains unverified.",
                slot: owned.slot, epoch: Int(current.epoch > 0 ? current.epoch : slot.expected.epoch), to: &final)
            guard commit(final) else { throw Failure.storage }
        } else if consumed {
            var next = state; next.slots[index].expected = current; next.slots[index].definitionIDs = []
            next.slots[index].verifiedAt = nil; next.slots[index].detail = "Due occurrence cleared; felt vibration unconfirmed"
            append("WHOOP reports the due record cleared; this is not proof of a felt alarm.", slot: owned.slot,
                   epoch: Int(slot.expected.epoch), to: &next)
            guard commit(next) else { throw Failure.storage }
        }
        guard context.experimental else { return }
        // Recompute after every await: UI edits may have changed intent during verification.
        let allocated = Set(state.slots.filter { $0.deviceID == context.deviceID && !$0.removalRequested }
            .compactMap { $0.pendingRecord?.epoch ?? ($0.expected.epoch > Int64(Date().timeIntervalSince1970) ? $0.expected.epoch : nil) })
        let ordered = plan()
        let covered = Set(state.slots.filter { $0.deviceID == context.deviceID && $0.expected.epoch > Int64(Date().timeIntervalSince1970) }
            .flatMap(\.definitionIDs))
        let primary = ordered.first { !allocated.contains(Int64($0.epoch)) && !$0.definitionIDs.allSatisfy(covered.contains) }
        guard let candidate = primary ?? ordered.first(where: { !allocated.contains(Int64($0.epoch)) }),
              candidate.epoch > Int(Date().timeIntervalSince1970) + 10,
              let record = Whoop5AlarmRecord.standard(slot: owned.slot, epoch: Int64(candidate.epoch)) else { return }
        // Leave near-overlap unresolved; never silently retime a user's requested alarm.
        let others = readings.filter { $0.slot != owned.slot }.compactMap { $0.record?.epoch }
        guard !others.contains(where: { $0 > 0 && abs($0 - record.epoch) < 60 }) else {
            throw Failure.conflict
        }
        let beforeWrite = try await read(owned.slot, context: context)
        guard beforeWrite.record == state.slots[index].expected else { throw Failure.conflict }
        let currentPlan = plan().first { $0.epoch == candidate.epoch }
        guard let currentPlan, candidate.epoch > Int(Date().timeIntervalSince1970) + 10 else { queued = true; return }
        var next = state; next.slots[index].pendingRecord = record
        next.slots[index].pendingDefinitionIDs = currentPlan.definitionIDs
        next.slots[index].detail = "Write requested; storage unverified"
        guard commit(next) else { throw Failure.storage }
        let response = try await exchange(66, record.bytes)
        guard same(context) else { throw Failure.stale }
        // Even a failure may have stored part of the record: always read it before judging.
        let afterWrite = try await read(owned.slot, context: context)
        guard attributed(response, opcode: 66, context: context), response.success,
              afterWrite.record == record else { throw Failure.invalidRecord }
        var final = state; final.slots[index].expected = record
        final.slots[index].definitionIDs = currentPlan.definitionIDs
        final.slots[index].pendingRecord = nil; final.slots[index].pendingDefinitionIDs = []
        final.slots[index].verifiedAt = afterWrite.at; final.slots[index].detail = "Stored on WHOOP"
        append("Full alarm record read back; scheduled physical firing remains unverified.", slot: owned.slot,
               epoch: candidate.epoch, to: &final)
        guard commit(final) else { throw Failure.storage }
        if !plan().contains(where: { $0.epoch == candidate.epoch }) { queued = true }
    }
    private func read(_ slot: Int, context: Link) async throws -> Reading {
        guard same(context), let payload = AlarmPayload.getAlarmRev4(alarmId: UInt8(slot)) else { throw Failure.stale }
        let response = try await exchange(67, payload)
        guard same(context), response.deviceID == context.deviceID, response.connection == context.connection,
              response.opcode == 67 else { throw Failure.stale }
        let record = response.success ? Whoop5AlarmRecord(payload: response.payload, slot: slot) : nil
        let reading = Reading(slot: slot, record: record, raw: response.payload,
            detail: record.map { $0.isZeroTime ? "Zero time reported; availability unverified" : "Stored time reported" }
                ?? "\(response.result); record unverified", at: Date(), deviceID: context.deviceID, connection: context.connection)
        if let i = readings.firstIndex(where: { $0.slot == slot }) { readings[i] = reading }
        return reading
    }
    private func same(_ context: Link) -> Bool {
        let current = link(); return current.ready && current.deviceID == context.deviceID && current.connection == context.connection
    }
    private func attributed(_ response: Reply, opcode: Int, context: Link) -> Bool {
        response.deviceID == context.deviceID && response.connection == context.connection && response.opcode == opcode
    }
    private func setDetail(_ id: String, _ detail: String) {
        var next = state
        guard let i = next.slots.firstIndex(where: { $0.id == id }) else { return }
        next.slots[i].detail = detail; next.slots[i].verifiedAt = nil
        _ = commit(next)
    }
    private func append(_ message: String, slot: Int? = nil, epoch: Int? = nil,
                        to state: inout DhoopAlarmState, now: Date = Date()) {
        state.history.append(.init(at: now, deviceID: context.deviceID, slot: slot, epoch: epoch, message: message))
        state.history = Array(state.history.suffix(512))
    }
    @discardableResult private func commit(_ next: DhoopAlarmState) -> Bool {
        guard storageError == nil else { return false }
        do { try file.save(next); state = next; return true }
        catch { storageError = "Could not save alarm state. Further strap writes are disabled; original state is preserved."; return false }
    }
    private func exportDiagnostics() {
        #if DEBUG
        guard CommandLine.arguments.contains("--alarm-diagnostics") else { return }
        let rows: [[String: Any]] = readings.map { row in
            ["slot": row.slot, "raw": row.raw.map(Int.init), "detail": row.detail,
             "epoch": row.record.map { Int($0.epoch) } ?? -1, "checkedAt": row.at.timeIntervalSince1970]
        }
        let body: [String: Any] = ["capturedAt": Date().timeIntervalSince1970, "deviceID": context.deviceID,
            "firmware": context.firmware, "ready": context.ready, "readings": rows,
            "error": error ?? "", "ownedSlots": currentSlots.map(\.slot)]
        if let bytes = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]) {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dhoop-alarm-diagnostics.json")
            try? bytes.write(to: url, options: .atomic)
        }
        #endif
    }
}
