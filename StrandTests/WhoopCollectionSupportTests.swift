import XCTest
import WhoopProtocol
@testable import Strand

final class WhoopCollectionSupportTests: XCTestCase {
    func testWhoop5ReplyPayloadUsesDeclaredLengthAfterFormatByte() {
        let frame = puffinCommandFrame(cmd: 22, seq: 9, payload: [7, 1, 4, 0, 0], type: 36)
        XCTAssertTrue(verifyFrame(frame, family: .whoop5).ok)
        XCTAssertEqual(FrameRouter.commandResponsePayload(in: frame, family: .whoop5), [4, 0, 0])
        var large = Array(UInt8(0)...UInt8(255)); large += [1, 2, 3]
        let long = puffinCommandFrame(cmd: 34, seq: 10, payload: [8, 1] + large, type: 36)
        XCTAssertTrue(verifyFrame(long, family: .whoop5).ok)
        XCTAssertEqual(FrameRouter.commandResponsePayload(in: long, family: .whoop5), large)
    }
    func testWhoop4PayloadAndMalformedLengthRemainBounded() {
        let frame = frameFromPayload([7, 1, 4, 0, 0], type: 36, seq: 9, cmd: 22)
        XCTAssertTrue(verifyFrame(frame).ok)
        XCTAssertEqual(FrameRouter.commandResponsePayload(in: frame), [4, 0, 0])
        for length in 0..<4 {
            XCTAssertNil(FrameRouter.commandResponsePayload(in: Array(repeating: 0, count: length), family: .whoop5))
        }
        XCTAssertNil(FrameRouter.commandResponsePayload(in: [0xaa, 1, 255, 255], family: .whoop5))
    }
    func testSupportHelloDetailsNeverIncludeIdentityBlocks() {
        var body = [UInt8](repeating: 0, count: 107); body[0] = 1
        let privateText = Array("PRIVATEDEVICEIDENTITY".utf8)
        body.replaceSubrange(14..<(14 + privateText.count), with: privateText)
        body[103] = 0x30
        let detail = FrameRouter.collectionSupportDetail(command: "GET_HELLO(145)", payload: body)
        XCTAssertEqual(detail, "hello candidate revision=1 clockSeconds=0 opaqueState=0 prepBits=48")
        XCTAssertFalse(detail?.contains("PRIVATE") ?? true)
        XCTAssertNil(FrameRouter.collectionSupportDetail(command: "GET_ALARM_TIME(67)", payload: body))
        XCTAssertEqual(FrameRouter.collectionSupportDetail(command: "SEND_HISTORICAL_DATA(22)", payload: [4, 0, 0]),
                       "history response bodyPrefix=040000 bodyBytesIncludingPadding=3")
    }
    func testIsolationExpiresAndNeverBlocksManualOrDurableContinuation() {
        let now = Date(timeIntervalSince1970: 1000)
        for trigger in [BackfillTrigger.connect, .foreground, .periodic, .strap] {
            XCTAssertTrue(BLEManager.deferAutomaticSyncForSupport(trigger: trigger, now: now, until: now.addingTimeInterval(1)))
            XCTAssertFalse(BLEManager.deferAutomaticSyncForSupport(trigger: trigger, now: now, until: now))
            XCTAssertFalse(BLEManager.deferAutomaticSyncForSupport(trigger: trigger, now: now, until: nil))
        }
        for trigger in [BackfillTrigger.manual, .autoContinue] {
            XCTAssertFalse(BLEManager.deferAutomaticSyncForSupport(trigger: trigger, now: now, until: now.addingTimeInterval(360)))
        }
    }
}
