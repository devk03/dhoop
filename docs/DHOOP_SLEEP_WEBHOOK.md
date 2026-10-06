# Dhoop → Life sleep summary contract, version 1

Status: Life receiver deployed; Dhoop sender implemented in build 438. Activation requires on-device credentials and explicit enablement.
This is the personal fork's narrow,
default-off Experimental sleep export, separate from the upstream raw-stream `PUSH_PROTOCOL.md`.
The receiver belongs in `/Users/devkunjadia/Developer/life`, not in Dhoop.

## Transport

- `POST https://track.kunjadia.dev/api/webhooks/sleep`
- `Authorization: Bearer <dedicated sleep-only token>`
- `CF-Access-Client-Id: <dedicated service token client ID>`
- `CF-Access-Client-Secret: <dedicated service token secret>`
- `Content-Type: application/json`; no content compression.
- HTTPS only. The client never follows redirects or logs tokens, bodies, or raw server errors.
- Maximum request and response size: 16 KiB each; enforce the streamed body limit, not only Content-Length.
- Reject unsupported methods/content types. Do not enable cross-origin browser access.
- Receiver must explicitly restrict hosts to `track.kunjadia.dev` and `tracker.kunjadia.dev`.
  The shared public photo host must not accept this endpoint.
- Server secret: `SLEEP_WEBHOOK_TOKEN`, at least 32 random bytes encoded as base64url or hex.
  Fail closed if missing. Do not reuse MCP tokens, login cookies, or the site's password.
- Optional `SLEEP_WEBHOOK_INSTALLATION_ID` pins the authorized installation UUID.
- Store the bearer and both Access credential fields in the iPhone Keychain. Never compile credentials
  into app defaults or include them in health backups. Missing Access credentials must fail closed.
- Send Access credentials only to their configured exact HTTPS webhook destination. Never forward them
  to redirects or reuse them for other tracker routes. Rotating credentials preserves pending bytes and revisions.
- Never paste real credentials into source, chat, logs, documentation, or committed configuration.

## Request

Example values below are illustrative, not personal health data.

```json
{
  "schemaVersion": 1,
  "eventId": "8121824e-16d4-4d1a-a21c-2a49675913ec",
  "installationId": "34927a8c-d5ae-44bc-b8f5-9e307e455d58",
  "revision": 1,
  "wakeDate": "2026-10-05",
  "sleepMinutes": 455.5,
  "source": "whoop",
  "method": "dhoop_estimate",
  "timeZone": "America/Los_Angeles",
  "generationDate": "2026-10-05T15:30:00Z"
}
```

All fields are required. UUIDs are lowercase canonical UUID strings. `revision` is a positive
JavaScript-safe integer, monotonically increasing for an installation and persisted before sending.
It orders revisions; `generationDate` must never be used to decide which delivery wins.
`eventId` identifies one immutable event. Retries retain the exact event ID, revision and request bytes.
`generationDate` is an ISO 8601 UTC timestamp when the export event was created, not the sleep end.

`sleepMinutes` is finite, greater than zero, and at most 1440. It includes fractional minutes.
`source` is exactly `whoop`. `method` is `dhoop_estimate` or `whoop_import`:

- `dhoop_estimate`: locally computed sleep with verified WHOOP input provenance. It is not an official
  WHOOP sleep score or a clinically validated measurement.
- `whoop_import`: an imported WHOOP sleep record.

Do not relabel Dhoop estimates as official WHOOP values or combine them with Apple Health values.
Apple/Eight Sleep is not part of this first contract; add it only through an agreed extension.
No raw HR, R–R, sleep-stage traces, serial numbers, MAC addresses, weight or protein are sent.

`wakeDate` is a strictly validated Gregorian calendar date (`YYYY-MM-DD`). In this first integration
`timeZone` must be exactly `America/Los_Angeles`; return 422 otherwise. Dhoop must pause export when its
local calendar is in another timezone instead of pretending its persisted day keys can be converted.
Do not reinterpret a day key as UTC midnight or derive it from the request's arrival time.

## Life date and value mapping

Life's existing morning check-in writes sleep to the **previous calendar day's row**. Therefore:

- Dhoop wake date `2026-10-05` → Life `rows.date = 2026-10-04`.
- Reuse `previousCheckInDate`; preserve month/year/DST boundaries.
- Keep exact minutes, source, method, timezone and wake date in the receipt/provenance metadata.
- The site's existing sleep field uses hours rounded to 15-minute increments. Reuse `roundSleepHours`
  for that display field; never overwrite the exact incoming minutes with the rounded value.
- Do not mark the full morning check-in complete, fabricate other fields, or rewrite notes/journal data.

## Acceptance

Acknowledge only after the row and receipt transaction is durable:

```json
{
  "schemaVersion": 1,
  "eventId": "8121824e-16d4-4d1a-a21c-2a49675913ec",
  "installationId": "34927a8c-d5ae-44bc-b8f5-9e307e455d58",
  "revision": 1,
  "wakeDate": "2026-10-05",
  "status": "accepted",
  "outcome": "stored"
}
```

Return HTTP 200 with JSON and `Cache-Control: no-store`. All identity fields must exactly echo the
request, including for a stale request. `status` must be `accepted`. Optional diagnostic `outcome` is
one of `stored`, `duplicate`, `stale`, `manual_preserved`. It is not a remote instruction to the app.
The sender advances its local checkpoint only after validating this acknowledgement. HTML login pages,
redirects, empty 2xx responses and mismatched identities are failures, not successful delivery.

Use bounded machine-readable error codes, never arbitrary diagnostic text: 400 invalid input,
401 invalid token, 409 conflicting event/revision/installation, 413 excessive body, 415 unsupported
content type, 422 unsupported version/source/method/timezone, 503 missing configuration/storage.
Network failures, 408, 429 and 5xx retain the pending event for bounded later retries. Other failures
remain visible and retain the pending event; no tight retry loops. No hourly delivery guarantee on iOS.

## Idempotency, corrections and manual ownership

Use existing `rows` and `settings` tables; no migration is authorized. Existing receiver helpers must
not invoke runtime `CREATE`/`ALTER` schema paths. Fail clearly if required tables are absent.

Maintain durable receipt/ownership metadata by target row date. It must retain installation ID,
latest accepted revision, event ID, canonical payload hash, exact minutes, method/source and the last
value written automatically. Apply row and receipt updates atomically with compare-and-swap guards.
Retry a concurrent-state conflict only with a fresh read. Never acknowledge a partial commit.

- New blank cell: fill it and establish automatic ownership.
- Existing nonblank unowned cell: preserve it as manual.
- Automatically owned cell: a newer event from its owning installation may correct its value.
- Manual cell, including an intentionally blank one: preserve it and durably consume the receipt.
- Identical retry: acknowledge without another mutation.
- Older revision: acknowledge as stale without overwriting newer data.
- Same revision/event identity with conflicting content: reject with 409.
- Different installation attempting to claim an owned date: reject with 409; require an explicit
  operator reconciliation rather than silent takeover.

Every deliberate manual sleep write must atomically mark ownership manual, even if the value is
unchanged or cleared. Audit `updateCell`, `saveMorningCheckIn`, MCP sleep writes and `addItemToDay`.
Do not infer that an unchanged string proves no manual edit occurred.

Enqueue changed dates through the existing consistency job mechanism in the same transaction, so
historical consistency scores are refreshed. Respect that pipeline's existing historical horizon.

## Morning check-in experience

Prefill sleep from the prior row and show its honest source (for example, “Dhoop estimate”). An untouched
automatic prefill must carry its expected receipt event ID/revision into submission and retain
automatic ownership. A deliberate edit marks it manual. If an automatic correction arrives while the
form is open, do not overwrite that newer value with the old prefill. Preserve all other check-in fields.
Existing manual values should also prefill, while remaining manual.

## Verification and activation

Test the production route with a real in-memory SQLite-backed D1 adapter: narrow auth, missing secrets,
wrong host, size/content limits, invalid dates/numbers, timezone rejection, previous-day mapping,
duplicates, reordered revisions, conflicting content, different installations, transaction rollback,
concurrent manual edits, blank/same-value edits, rescoring and unchanged-prefill races. Assert that the
receiver executes no schema DDL. Run the morning-check-in/consistency suites and the production build.

Cloudflare Access Service Auth requires the two headers above in addition to the sleep bearer. The
Life agent reports the policy is scoped to the two exact webhook destinations, with the rest of the
tracker still protected. Never broadly exempt `/api/*` or disable tracker protection. Service credentials
expire after one year; an edge rejection is a visible delivery failure, not a reason to follow login
redirects. Credential rotation must not discard the durable pending event.

Keep credentials and production activation separate from code review. Report endpoint, deployment SHA,
required secret names and a verified response. Do not claim end-to-end delivery until the iPhone has
received a compatible build and a real delivery was acknowledged. Do not run DB migrations without
permission. Never run `rm`.

## Coordinated receiver status — October 5, 2026

The Life agent reports receiver deployment `9d05d89d4e54941b5fb6698426fc614ddb37a9b3`, Cloudflare
version `25d2a422-2407-4b5a-b7dc-c78efdf4abad`, and finalized server documentation at `44be597`.
The documentation is available in `/Users/devkunjadia/Developer/life/docs/DHOOP_SLEEP_WEBHOOK.md`.

Its non-mutating live checks returned:

- Correct Access credentials and sleep bearer with `{}`: 400 JSON `invalid_payload`, no-store,
  no redirect, on both tracker hosts.
- Access credentials without the sleep bearer: 401 unauthorized.
- Sleep bearer without Access credentials: 403 from the edge.
- The service credentials at `/api/row`: normal tracker login remains required.

These are receiver-agent reports, not an independently repeated iPhone delivery check. No test health
record was written. The original isolated receiver draft is superseded by Life main. Dhoop build 438 includes the durable outbox, bounded network transport, background job, current-timezone
gate and Keychain setup. A matching 200 `accepted` response for a real phone event is required before
claiming end-to-end delivery. Deployment status must be reported separately from that receipt.


## iPhone implementation and operation

Settings → Sleep webhook provides the default-off toggle, connection setup, pending/accepted status,
and Send now. The one-week source scan uses `verifiedWhoopSleepTotals`, which resolves each stored
sleep total and computed input provenance in one database snapshot. Imported WHOOP records take
priority; computed estimates must have WHOOP input provenance. Apple Health is never a fallback.
This is an iOS-specific personal-fork export; Android retains its independent upstream raw-stream push.
No analytics formula, stored health value or database schema is changed by this feature.

A backup-excluded, atomically replaced checkpoint stores the installation ID, revision, exact pending
bytes, bounded receipts and retry deadline. A malformed or unreadable checkpoint pauses delivery instead
of inventing a new identity. Credential rotation retains the pending event; changing destinations clears
the destination receipt ledger while keeping the installation revision counter. Already pending events
can retry without waiting for a fresh health-store read or rescore. New events wait for rescore completion.

Each invocation sends at most two events, newest dates first. Automatic retries back off from one minute
to six hours. Post-processing and foreground hooks enqueue independent work; the BGProcessingTask has
an earliest start of one hour and requires network access. iOS controls actual execution. Force-quitting
the app, unavailable data, network failure and system background limits can delay updates. Opening
Dhoop or choosing Send now provides a retry opportunity; this is not a guaranteed hourly service.

## Secure setup from the paired Mac

Only explicit setup actions generate a 30-minute invitation. The phone stores its P256 agreement key
in WhenUnlockedThisDeviceOnly Keychain and exports the public invitation. The Mac helper reads private
credential files directly and seals their contents with ephemeral P256 ECDH, HKDF-SHA256 and AES-GCM.
Only ciphertext crosses into the app container. Import requires the full local invitation to match and
be unexpired. The app consumes the invitation and discards the private key before saving credentials;
a failed import requires a new invitation. Consumed ciphertext is quarantined non-destructively under
the backup-excluded checkpoint directory. Credentials use AfterFirstUnlockThisDeviceOnly Keychain so
an explicitly enabled background send can run while the phone is locked after first unlock.

Compile the helper with `swiftc StrandiOS/Export/SleepWebhookDelivery.swift
StrandiOS/Export/SleepWebhookSecureSetup.swift Tools/SleepWebhookSetup/main.swift -o <helper-path>`.
Run it with four paths: public invitation, private sleep bearer file, private Access JSON (clientId and
clientSecret keys), and sealed output. Credential contents never appear in argv or helper output.
The endpoint is fixed to the Life sleep receiver; credential fields cannot authorize another route.

For development device setup, explicit DEBUG launch flags mirror the user-facing actions:
`--prepare-sleep-webhook`, `--import-sleep-webhook`, `--enable-sleep-webhook`,
`--send-sleep-webhook`, and `--sleep-webhook-status`. They contain no secrets. The DEBUG status file
contains only enablement, safe status text, installation/event identifiers, receipt date and revision.
It is evidence of a locally validated acknowledgement, not proof of physiological accuracy.

Validation: targeted delivery/transport/setup tests run in DhoopGoalTests; provider-transition and
import-precedence tests run in WhoopStore. App wiring requires both iOS and macOS builds. The UI follows
the generated settings reference using StrandDesign fonts, spacing and colors, standard accessible
controls and scrolling content. No generated image or demo sleep data is part of the shipped UI.
