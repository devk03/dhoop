import XCTest
import Foundation

final class RemoteBuzzPairingLinksTests: XCTestCase {
    private func callback(_ bytes: Data, query: String = "envelope") -> URL {
        URL(string: "dhoop://remote-buzz/pair?\(query)=\(RemoteBuzzPairingLinks.encode(bytes))")!
    }
    func testEncryptedCallbackBoundsAndPinnedDestination() throws {
        let data = Data(#"{"invitation":{},"serverPublicKey":"synthetic","sealed":"ciphertext"}"#.utf8)
        let url = callback(data)
        XCTAssertEqual(try RemoteBuzzPairingLinks.envelope(from: url), data)
        for bad in [URL(string: url.absoluteString.replacingOccurrences(of: "dhoop:", with: "https:"))!,
                    URL(string: url.absoluteString.replacingOccurrences(of: "remote-buzz", with: "other"))!,
                    URL(string: url.absoluteString + "&envelope=duplicate")!,
                    URL(string: url.absoluteString + "#fragment")!, callback(data, query: "command")] {
            XCTAssertThrowsError(try RemoteBuzzPairingLinks.envelope(from: bad))
        }
        XCTAssertThrowsError(try RemoteBuzzPairingLinks.envelope(from: callback(Data(repeating: 32, count: 8193))))
        XCTAssertThrowsError(try RemoteBuzzPairingLinks.envelope(from: callback(Data(#"{"secret":"plaintext"}"#.utf8))))
    }
    func testInvitationOnlyTravelsInFragmentAndExpires() throws {
        let key = "BGsX0fLhLEJH+Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT+NC4v4af5uO5+tKfA+eFivOM1drMV7Oy7ZAaDe/UfU="
        let invitation = RemoteBuzzInvitation(version: 2, setupId: "11111111-1111-4111-8111-111111111111",
            installationId: "22222222-2222-4222-8222-222222222222", publicKey: key, expiresAt: 1791500600,
            topic: RemoteBuzzV2.topic, environment: "sandbox")
        let url = try RemoteBuzzPairingLinks.invitationURL(invitation, now: Date(timeIntervalSince1970: 1791500000))
        XCTAssertEqual(url.scheme, "https"); XCTAssertEqual(url.host, "track.kunjadia.dev")
        XCTAssertEqual(url.path, "/settings"); XCTAssertNil(url.query)
        XCTAssertTrue(url.fragment?.hasPrefix("dhoopBuzzInvitation=") == true)
        XCTAssertThrowsError(try RemoteBuzzPairingLinks.invitationURL(invitation, now: Date(timeIntervalSince1970: 1791500600)))
    }
}
