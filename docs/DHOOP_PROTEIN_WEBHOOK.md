# Dhoop protein export — v2 extension

This extends the existing authenticated `POST /api/webhooks/sleep` transport. The path and existing Cloudflare Access pair stay the same; no Cloudflare policy widening or new
endpoint is needed. Protein uses a NEW dedicated PROTEIN_WEBHOOK_TOKEN bearer stored in phone Keychain.
The existing SLEEP_WEBHOOK_TOKEN remains sleep-only. The receiver selects authentication by payload kind
and must reject either bearer when used for the other kind.
Sleep v1 payloads, validation, acknowledgements and behavior remain unchanged.

## Protein request (exact fields)

```json
{
  "schemaVersion": 2,
  "kind": "protein",
  "eventId": "8121824e-16d4-4d1a-a21c-2a49675913ec",
  "installationId": "34927a8c-d5ae-44bc-b8f5-9e307e455d58",
  "revision": 2,
  "day": "2026-10-06",
  "proteinGrams": 84.5,
  "entryCount": 3,
  "source": "dhoop",
  "coverage": "logged_entries",
  "timeZone": "America/Los_Angeles",
  "generationDate": "2026-10-06T19:30:00Z"
}
```

Examples are synthetic documentation values, never production test health records.

- `day` is the consumption date and maps to the SAME Life row; no sleep-style day subtraction.
- Canonical lowercase UUIDs; positive JavaScript-safe integer revision. Sleep and protein share the
  same persisted installation ID and increasing revision counter, with at most one pending event per metric and one network request at a time.
  Independent retry deadlines prevent a protein-specific failure from delaying sleep.
- `proteinGrams` is a finite number from 0 through 1000 when `entryCount` is a positive integer at
  most 100000. It is the sum of protein-only logs plus known protein in food entries, never calories.
- For an explicit retraction after all entries for a previously exported day are removed,
  `proteinGrams` is JSON null and `entryCount` is 0. This clears only an automatically owned value.
- A never-logged day sends nothing. Unreadable/corrupt local logs must fail closed, not become clears.
- `coverage: logged_entries` always means grams logged so far, NOT a claim of complete daily intake.
- `source` is exactly `dhoop`; no food names, calorie totals, weight, target or individual entries leave
  the phone. Strict Gregorian date, Pacific-only timezone and UTC-Z generation timestamp use v1 rules.
- Revisions order events. Generation timestamps are not conflict ordering. Retried bytes are immutable.

## Acknowledgement

HTTP exactly 200, bounded JSON, no redirects. Echo `schemaVersion:2`, `kind:protein`, `eventId`,
`installationId`, `revision`, `day`, and `status:accepted`. Optional outcome: `stored`, `cleared`,
`duplicate`, `stale`, `manual_preserved`. No `wakeDate` field is required for protein.

Use the existing global immutable event/revision identity ledgers to prevent cross-metric identity
reuse. Maintain a separate `protein-webhook:v2:<day>` ownership receipt. Determine staleness per metric
and day, not globally. Row + receipt + identity + consistency queue changes must be atomic.

## Manual fallback and morning check-in

- Existing/manual protein values and deliberate blanks take precedence, including same-value edits.
- New imports fill unowned empty cells, and corrections replace only their own automatic values.
- Retraction clears the automatic value and leaves ownership metadata so later additions may refill it.
- Do not sum the website total with Dhoop's total: they are alternatives, not independent meals.
- Preserve website food entries. An existing itemized log is manual. Ensure the website's protein editor
  correctly displays and preserves imported totals; opening and saving must not silently turn them to 0.
- Morning check-in prefills yesterday's protein from the corresponding Life row, labels Dhoop values
  as logged protein, and leaves manual input available. Track touched state and expected event/revision.
- An untouched prefill resolves the latest server value inside the transaction. If it was retracted,
  require a fresh manual answer rather than writing stale data or assuming zero. Explicit edits mark manual.
- Audit every manual writer, including generic row updates, updateCell, addItemToDay and MCP paths.
  Reserve receipt settings keys from generic writes. Use resolved values consistently in journal/scoring.
- Calories and weight are neither required for protein export nor synthesized by the receiver.

## Activation and verification

The sender adds a separate default-off protein toggle; enabling protein does not change the sleep toggle.
User authorization for this integration permits enabling it on the user's configured phone after the
receiver and new build are verified. No database migration is required or authorized.

Test old pending v1 checkpoint decoding, shared revision ordering, exact ack validation, unknown-versus-zero,
food/protein aggregation, explicit clear, manual overrides, retry/reorder/cross-metric collisions,
check-in correction/retraction races and imported-value editing. Retain HTTPS, redirect refusal, 16-KiB
limits, Keychain credentials and timezone gates. Test real delivery only if genuine protein entries exist;
never fabricate food or grams in production to prove connectivity.


## End-of-day scheduling

Build 439 selects only dates through yesterday in the phone's local Pacific calendar. It never sends
today's partial protein or sleep, including from Send completed days. The usual background opportunity
is the next local midnight plus five minutes; iOS chooses when work actually runs. Foreground and
post-processing callbacks catch up completed dates. Up to two requests per metric (newest, then oldest
outstanding) prevent older corrections starving; a persisted backlog marker requests continuation.
Retry deadlines are independent per metric. Missing background time, force-quit or network availability
can delay delivery; opening Dhoop provides a retry opportunity.

Initial capture scans the seven completed dates. Protein receipts retain up to 366 dates; subsequent
edits/removals for those retained dates also reconcile. Older unexported historical protein is not
silently backfilled, and entries beyond the retained receipt window do not imply deletion.
