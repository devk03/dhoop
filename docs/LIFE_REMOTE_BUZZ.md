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

The owner-authorized private API has no hourly quota or request cooldown on Life
or the phone. Authentication, opt-in, duplicate protection and exercise ownership
still apply. Existing shared BLE overlap protection and Apple's delivery limits
are separate from an API quota. External sharing needs its own reviewed policy.
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

At 5:55 p.m. Pacific, the approved temporary Life client made a permanent MCP
request while CoreDevice reported the iPhone locked. Event
`31b6f8d2-f84b-42ef-8580-1ea219cf34bb` expired with `apnsStatus=uncertain`,
no phone receipts, and the wearer reported no vibration. A second diagnostic
request (`9988dfb2-51e6-4d33-afc3-7e98bb8834ab`) identified `apns_submit` /
`transport_type_error`. The Cloudflare runtime rejected `redirect:error` before
network submission; this was reproduced locally with native workerd. Life was
changed to manual redirect handling while continuing to reject every non-200
response. Native-runtime tests verified synthetic acceptance, no credential
forwarding on redirects, and no resend on idempotent replay. Its production
build and deployment succeeded.

The repaired permanent MCP request at 6:07 p.m. Pacific, event
`df987f94-5d7d-4275-aeac-9b98cdd8b316`, was accepted by Apple. It expired with
no device-reported receipts. CoreDevice reported locked at 6:05:17 p.m. but
unlocked at 6:06:42 p.m., before submission; the lock condition was not maintained
for this test. Wearer confirmation remained pending. The temporary verification
token was revoked and an authenticated read with that token returned HTTP 401;
the permanent phone enrollment and existing agent tokens were preserved. Three
test requests consumed the normal hourly allowance, with no automatic resend or
rate-limit bypass. This proves the repaired MCP-to-APNs path, not phone delivery,
WHOOP vibration, force-quit support or dependable wake-up behavior.

## Owner-authorized private API without quotas

The owner explicitly removed the hourly and request-cooldown policy on October 12.
Life deployed `98a649a` as Worker `5723ee23-b8fb-48eb-ab29-92e6b659e1d6`.
Dhoop build 458 removes the matching phone gate and was installed on the physical
iPhone with the same bundle identifier and development APNs entitlement. Five
targeted Swift receiver-state tests, the signed iOS build, Life's native Workers,
SQLite and Settings tests, and the production build passed. Distinct private
requests remain permitted after persisted/reloaded history; duplicate, expiry,
disabled/revoked, disconnection and exercise-ownership gates remain unchanged.
No database migration or wake-alarm write was performed. This is an iOS-only
personal Life integration; Android has no equivalent remote Life receiver.

A fresh request at 6:25:40 p.m., event
`16a7f652-e3d0-419d-b7f9-077de551d163`, was accepted despite the older three
requests still being inside their former rolling-hour window. The unlocked
phone reported receipt at 6:25:45 p.m., WHOOP command request at the same second,
and a response. Its saved delivery ledger attributed opcode 19 / sequence 4 to
that event and connection, with `SUCCESS(1)` and an empty response payload.
This remains `responseReceived`, not an ACK or wearer confirmation. Replaying
the identical idempotency key returned that original event with no new request.
The human's vibration confirmation and a maintained locked-phone test remain
pending; the Mac's iPhone Mirroring session is locked and is not used as proof
of the phone's foreground view.

The earlier 6:07 p.m. event subsequently appeared in saved phone history and
Life receipts as `expired`, received at 6:11:28 p.m. The original delivery window
had ended at 6:08:01 p.m.; no late WHOOP buzz was dispatched. This demonstrates
why background pushes remain best effort even when private application quotas
are absent. API authorization and expired-command rejection are separate from
Apple's delivery timing.

The session's temporary verification MCP token was revoked and then rejected
with HTTP 401. Existing clients and the enabled phone enrollment were preserved.

At 9:13:31 p.m. Pacific, an explicitly requested fresh remote test produced event
`b1ccb14f-95c0-4d76-8e26-d346b5d32505`. Apple accepted it; Life received
`phone_received:received` and `strap_requested:requested` evidence at 9:13:32 p.m.,
then `strap_response:response_received` at 9:13:33 p.m. The Mac developer
connection was unavailable, so lock state and lock duration could not be
independently inspected. The wearer's vibration and locked-phone confirmation
remain pending. No second buzz was sent to resolve that uncertainty. The test's
temporary client token was revoked; existing clients and phone enrollment remain.

The human-requested repeat at 9:20:50 p.m. Pacific, event
`ba7077b9-75e0-4add-b2b0-cd46ec9ffd09`, completed the permanent path through
physical confirmation. Apple accepted it; the phone reported receipt, strap
request and strap-response evidence at 9:20:54 p.m. A signed device receipt
reported `wearer_confirmed:felt` at 9:21:03 p.m., and the human independently
confirmed feeling it in chat. Life returned `vibrationConfirmed=true`. Phone
lock state/duration were not reported for this specific repeat, so it does not
establish locked, suspended or force-quit guarantees. The test credential was
revoked after verification, preserving existing clients and enrollment.
