// Compile with the app's Foundation/CryptoKit delivery + secure-setup files. Paths only on argv.
// No credential values are printed, passed as arguments, or included in the resulting executable.
import Foundation

let args = CommandLine.arguments
if args.count != 5 && args.count != 6 {
    print("Usage: sleep-webhook-setup <phone-public.json> <bearer-file> <access-json> <sealed-output.json> [protein-bearer-file]")
    exit(2)
}
do {
    let invitation = try JSONDecoder().decode(SleepWebhookSecureSetup.Invitation.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let bearer = try String(contentsOfFile: args[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    struct Access: Decodable { let clientId: String; let clientSecret: String }
    let access = try JSONDecoder().decode(Access.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
    let proteinBearer = args.count == 6 ? try String(contentsOfFile: args[5], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) : nil
    let value = SleepWebhookCredentials(endpoint: "https://track.kunjadia.dev/api/webhooks/sleep", bearer: bearer,
        clientId: access.clientId, clientSecret: access.clientSecret, proteinBearer: proteinBearer)
    let sealed = try SleepWebhookSecureSetup.seal(value, invitation: invitation)
    let output = URL(fileURLWithPath: args[4])
    try JSONEncoder().encode(sealed).write(to: output, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    print("Encrypted setup file created. No credentials displayed.")
} catch {
    print("Secure setup failed. Check the invitation expiry and private input files; values were not displayed.")
    exit(1)
}
