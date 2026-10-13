import XCTest
import WhoopProtocol
import StrandAnalytics

@MainActor
final class DhoopAlarmManagerTests: XCTestCase {
    private func setup() -> (DhoopAlarmManager, DhoopAlarmManager.Link, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-alarm-test-\(UUID().uuidString).json")
        let manager = DhoopAlarmManager(file: .init(url: url))
        let link = DhoopAlarmManager.Link(deviceID: "test", connection: UUID(), ready: true, whoop5: true, experimental: true)
        manager.link = { link }
        return (manager, link, url)
    }
    private func alarm() -> DhoopAlarmDefinition {
        var value = DhoopAlarmDefinition()
        value.rule = .init(minute: 0, oneTimeEpoch: Int(Date().timeIntervalSince1970) + 300)
        return value
    }
    private func settle(_ manager: DhoopAlarmManager) async {
        for _ in 0..<100 {
            await Task.yield()
            if !manager.busy { await Task.yield(); if !manager.busy { return } }
        }
        XCTFail("Coordinator did not settle")
    }
    func testNoImplicitOwnershipAndReadbackAfterSave() async throws {
        let (manager, link, url) = setup()
        var records = Dictionary(uniqueKeysWithValues: (1...6).map {
            ($0, Whoop5AlarmRecord(payload: [4,UInt8($0)] + Array(repeating:0,count:19), slot:$0)!)
        })
        var writes: [Int] = []
        manager.exchange = { opcode, payload in
            let slot = Int(payload[1])
            if opcode == 66 { writes.append(slot); records[slot] = Whoop5AlarmRecord(payload:payload,slot:slot)! }
            return .init(deviceID:link.deviceID,connection:link.connection,opcode:opcode,result:"SUCCESS(1)",
                payload:opcode == 67 ? records[slot]!.bytes : [4,1])
        }
        let value = alarm(); manager.save(value); await settle(manager)
        XCTAssertTrue(writes.isEmpty,"zeros do not authorize slot allocation")
        XCTAssertEqual(manager.status(value,now:Date()),"Pending sync")
        manager.approveSlot(6,expected:records[6]!); await settle(manager)
        XCTAssertEqual(writes,[6]); XCTAssertEqual(manager.status(value,now:Date()),"Stored on WHOOP")
        let restored = try DhoopAlarmFile(url:url).read()
        XCTAssertEqual(restored.slots.first?.expected.epoch,Int64(value.rule.oneTimeEpoch!))
        XCTAssertEqual(restored.slots.first?.originalRecord?.epoch,0)
    }
    func testACKWithoutMatchingReadbackNeverBecomesStored() async throws {
        let (manager, link, _) = setup()
        let zero = Whoop5AlarmRecord(payload:[4,6] + Array(repeating:0,count:19),slot:6)!
        var writes = 0
        manager.exchange = { opcode, payload in
            if opcode == 66 { writes += 1 }
            let record = Whoop5AlarmRecord(payload:[4,payload[1]] + Array(repeating:0,count:19),slot:Int(payload[1]))!
            return .init(deviceID:link.deviceID,connection:link.connection,opcode:opcode,result:"SUCCESS(1)",payload:record.bytes)
        }
        let value=alarm(); manager.save(value); await settle(manager)
        manager.approveSlot(6,expected:zero); await settle(manager)
        XCTAssertEqual(writes,1)
        XCTAssertNotEqual(manager.status(value,now:Date()),"Stored on WHOOP")
        XCTAssertNotNil(manager.state.slots.first?.pendingRecord)
    }
    func testCancellationTargetsOnlyOwnedSlotAndPreservesOthers() async throws {
        let (manager, link, _) = setup()
        var records = Dictionary(uniqueKeysWithValues:(1...6).map {
            ($0, Whoop5AlarmRecord(payload:[4,UInt8($0)] + Array(repeating:0,count:19),slot:$0)!)
        })
        records[1] = Whoop5AlarmRecord.standard(slot:1,epoch:Int64(Date().timeIntervalSince1970)+7200)!
        let original=records[1]!
        var clears: [[UInt8]]=[]
        manager.exchange = { opcode,payload in
            let slot=Int(payload[1])
            if opcode==66 { records[slot]=Whoop5AlarmRecord(payload:payload,slot:slot)! }
            if opcode==69 { clears.append(payload); records[slot]=Whoop5AlarmRecord(payload:[4,UInt8(slot)]+Array(repeating:0,count:19),slot:slot)! }
            return .init(deviceID:link.deviceID,connection:link.connection,opcode:opcode,result:"SUCCESS(1)",payload:opcode==67 ? records[slot]!.bytes : [2])
        }
        let value=alarm();manager.save(value);await settle(manager)
        manager.approveSlot(6,expected:records[6]!);await settle(manager)
        manager.delete(value.id);await settle(manager)
        XCTAssertEqual(clears,[[2,6]])
        XCTAssertEqual(records[1],original)
        XCTAssertTrue(manager.definitions.isEmpty)
    }
    func testForeignChangeBlocksAnyReplacement() async throws {
        let (manager, link, _) = setup()
        var records = Dictionary(uniqueKeysWithValues:(1...6).map {
            ($0, Whoop5AlarmRecord(payload:[4,UInt8($0)] + Array(repeating:0,count:19),slot:$0)!)
        })
        var writes = 0
        manager.exchange = { opcode,payload in
            let slot=Int(payload[1])
            if opcode==66 || opcode==69 { writes += 1 }
            if opcode==66 { records[slot]=Whoop5AlarmRecord(payload:payload,slot:slot)! }
            return .init(deviceID:link.deviceID,connection:link.connection,opcode:opcode,result:"SUCCESS(1)",payload:records[slot]!.bytes)
        }
        let value=alarm();manager.save(value);await settle(manager)
        manager.approveSlot(6,expected:records[6]!);await settle(manager)
        records[6]=Whoop5AlarmRecord.standard(slot:6,epoch:Int64(value.rule.oneTimeEpoch!+3600))!
        let foreign=records[6]!, count=writes
        manager.delete(value.id);await settle(manager)
        XCTAssertEqual(writes,count)
        XCTAssertEqual(records[6],foreign)
        XCTAssertNotNil(manager.error)
    }
    func testCorruptStateIsPreservedAndFailsClosed() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("dhoop-alarm-corrupt-\(UUID().uuidString).json")
        let original=Data("not-json".utf8);try original.write(to:url)
        let manager=DhoopAlarmManager(file:.init(url:url))
        XCTAssertNotNil(manager.storageError)
        manager.save(alarm())
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    func testClearRecoveryAfterRelaunchDoesNotResendAlarm() async throws {
        let (_, link, url) = setup()
        var value = alarm(); value.deleted = true; value.enabled = false
        let expected = Whoop5AlarmRecord.standard(slot: 6, epoch: Int64(value.rule.oneTimeEpoch!))!
        var owned = DhoopAlarmSlot(deviceID: link.deviceID, slot: 6, expected: expected)
        owned.definitionIDs = [value.id]; owned.removalRequested = true
        var saved = DhoopAlarmState(); saved.definitions = [value]; saved.slots = [owned]
        try DhoopAlarmFile(url: url).save(saved)
        let manager = DhoopAlarmManager(file: .init(url: url)); manager.link = { link }
        var mutations: [(Int, [UInt8])] = []
        manager.exchange = { opcode, payload in
            if opcode != 67 { mutations.append((opcode, payload)) }
            return .init(deviceID: link.deviceID, connection: link.connection, opcode: opcode, result: "SUCCESS(1)",
                payload: [4, payload[1]] + Array(repeating: 0, count: 19))
        }
        manager.requestSync(); await settle(manager)
        XCTAssertEqual(mutations.map(\.0), [69])
        XCTAssertEqual(mutations.first?.1, [2, 6])
        XCTAssertFalse(manager.state.slots[0].removalRequested)
        XCTAssertEqual(manager.state.slots[0].expected.epoch, 0)
    }
    func testEveryDefinitionGetsCoverageBeforeFillingOneRepeatRule() async throws {
        let (manager, link, _) = setup()
        var records = Dictionary(uniqueKeysWithValues: (1...6).map {
            ($0, Whoop5AlarmRecord(payload: [4, UInt8($0)] + Array(repeating: 0, count: 19), slot: $0)!)
        })
        manager.exchange = { opcode, payload in
            let slot = Int(payload[1])
            if opcode == 66 { records[slot] = Whoop5AlarmRecord(payload: payload, slot: slot)! }
            return .init(deviceID: link.deviceID, connection: link.connection, opcode: opcode, result: "SUCCESS(1)", payload: records[slot]!.bytes)
        }
        var early = alarm(); early.rule = .init(minute: 7 * 60, weekdays: Set(1...7))
        var late = alarm(); late.rule = .init(minute: 9 * 60, weekdays: Set(1...7))
        manager.save(early); await settle(manager); manager.save(late); await settle(manager)
        manager.approveSlot(5, expected: records[5]!); await settle(manager)
        manager.approveSlot(6, expected: records[6]!); await settle(manager)
        XCTAssertEqual(Set(manager.state.slots.flatMap(\.definitionIDs)), [early.id, late.id])
        XCTAssertEqual(manager.verifiedOccurrences(now: Date()).count, 2)
    }
    func testUnattributedWriteACKDoesNotCertifyTheRequest() async throws {
        let (manager, link, _) = setup()
        var records = Dictionary(uniqueKeysWithValues: (1...6).map {
            ($0, Whoop5AlarmRecord(payload: [4, UInt8($0)] + Array(repeating: 0, count: 19), slot: $0)!)
        })
        manager.exchange = { opcode, payload in
            let slot = Int(payload[1])
            if opcode == 66 { records[slot] = Whoop5AlarmRecord(payload: payload, slot: slot)! }
            return .init(deviceID: opcode == 66 ? "another device" : link.deviceID, connection: link.connection,
                opcode: opcode, result: "SUCCESS(1)", payload: records[slot]!.bytes)
        }
        let value = alarm(); manager.save(value); await settle(manager)
        manager.approveSlot(6, expected: records[6]!); await settle(manager)
        XCTAssertNotNil(manager.state.slots[0].pendingRecord)
        XCTAssertNotEqual(manager.status(value, now: Date()), "Stored on WHOOP")
    }
}
