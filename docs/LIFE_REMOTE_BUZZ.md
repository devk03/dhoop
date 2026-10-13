# Permanent Life MCP → Dhoop → WHOOP cues

The permanent integration uses `tracker.read_buzz` and `tracker.send_buzz` on
`https://track.kunjadia.dev/mcp`. `/api/dhoop/buzz` is the retired-from-normal-use
v1 experiment described in REMOTE_BUZZ_TEST.md; its two-hour credentials are not
permanent enrollment credentials. The server/crypto contract is maintained in
`/Users/devkunjadia/Developer/life/docs/DHOOP_REMOTE_BUZZ_V2.md`.

## Setup and verification

1. Dhoop Settings → WHOOP alerts → Create pairing invitation.
2. Open pairing in Life. Review the public invitation and explicitly approve owner pairing.
3. Create encrypted pairing, then Open in Dhoop before the ten-minute invitation expires.
4. Enable Remote alerts in Dhoop. Wait for Life to confirm device registration and enablement.
5. Read `tracker.read_buzz {}`. Only an enabled, registered, unrevoked enrollment is ready.
6. Call `tracker.send_buzz` with that enrollmentId and a fresh idempotencyKey. Reuse
   the same key after an uncertain result. Do not automatically resend.
7. Read `tracker.read_buzz {eventId}` to distinguish Apple acceptance, phone receipt,
   strap request/response, and explicit wearer confirmation. A response is not a felt buzz.

At most three requests per hour and at least thirty seconds between requests apply.
Commands expire after sixty seconds. Test foreground first, then a phone locked for
at least one minute. Background delivery is best effort and requires a usable strap
connection; force-quit behavior must not be inferred from a short lock test.

## One-shot development diagnostics

Debug builds support `--life-buzz-diagnostics` to export a protected, backup-excluded
`Documents/dhoop-life-buzz-diagnostics.json`. The snapshot contains public pairing
identity, permission/registration statuses, counts, and capture time. It never contains
an APNs token, device bearer, HMAC secret, private key, or Access credential.

`--life-buzz-prepare` additionally creates a fresh public invitation through the same
app method as the Settings button. It cannot replace an active phone enrollment or
enable alerts. Both actions require an explicit developer launch; Release ignores them.
The snapshot is refreshed by real state/registration changes, without a polling job.

A paired Mac can launch the installed Debug app with these flags and copy only the
public diagnostic file with `devicectl`. Restarting an app can interrupt an active
workout; use these diagnostics while no workout is running. A Wi-Fi developer
connection is sufficient after the phone has been unlocked to mount developer services.

## October 12 investigation

Live Life Settings exposed the permanent buzz tools and existing MCP clients, but
showed no active Dhoop pairing. The unlocked phone's state-v2 file showed enabled=false,
revoked=false, deviceRevision=0, receiptSequence=0 and zero events/receipts. This is an
incomplete enrollment, not proof of an Apple or WHOOP delivery failure. No data migration,
strap alarm change or server credential change was required by that read.

At 5:37 p.m. Pacific, after the human approved pairing, Life created a fresh encrypted
enrollment for the same installation. Build 457 imported it successfully. The phone
reported paired=true, enabled=true, deviceRevision=2 and "Life received device update";
owner Settings independently displayed "Enabled · sandbox". The switch was enabled
through the phone UI, not a debug flag. Event and receipt counts were still zero: an
authenticated permanent API request and wearer-confirmed vibration remained pending.
The debug snapshot was checked for its public-only field whitelist, and the installed
app retained the stable bundle identifier and development APNs entitlement.
