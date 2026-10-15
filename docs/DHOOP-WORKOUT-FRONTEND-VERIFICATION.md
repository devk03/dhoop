# Shared workout frontend — build 497

## Implemented locally

Life is canonical for website, MCP and native actions. iOS Strength now opens its dated, paged
Life dashboard and canonical sessions. Sets separate prescriptions from actuals. Native forms
cover all twelve shared web actions, including program configuration, athlete profile, effective
benchmarks, progression adjustment, substitutions, session logs and explicit status changes.

Manual commands use a separate default-off Keychain permission. Exact bytes and operation UUID
are saved before sending. Recovery is GET-only. An unknown outcome blocks replacement commands;
full original intent and hash are checked. Committed receipts survive refresh failure. Input and
receipts remain exportable without credentials; the queue is not part of existing metadata/SQL
backup formats. Older local recordings and source deliveries are retained without conversion.

This is the owner's iOS-specific integration. macOS retains the existing strength frontend and
Android has no canonical Life frontend yet. No shared physiological calculation or database schema
changed in this update. Source seed/capture_only lifecycle integration remains a separate gate;
existing legacy apply recordings are not automatically changed.

## Automated verification

- 63 selected native dashboard, command, source client, endpoint and transport tests passed.
- Tests cover timeout/relaunch recovery without a second POST, exact target/clear identity,
  missing receipt after known running state, identical retry bytes/lowercase operation IDs,
  cancellation before send, normalized program names, and retained corrupt queues.
- Signed iOS NOOPiOS and unsigned macOS Strand builds passed locally.
- Source comment lint and `git diff --check` passed.
- The localization audit was run and reports new English UI copy absent from the catalog.
  Localization coverage is not complete; its baseline or gate was not weakened.

The ImageGen reference and exact prompt are retained in
`docs/design/dhoop-shared-tracker-frontend-study.*`. Reference data is illustrative only.
App values come from canonical responses or actual recordings. Rendered-device visual acceptance
and physical workout acceptance are not claimed. The owner requested publication without more
hands-on tests.

## Physical phone and collection evidence

Build 496 was independently confirmed installed and running on the physical phone before this
update. Imperial preferences were retained. The app's saved alarm configuration was semantically
unchanged across that installation; this was not a fresh read of the strap's hardware alarm.

On 2026-10-14, three current diagnostic reads from the physical phone showed live packet counts
10 → 31 → 41, with fresh readable HR and the same selected WHOOP identity. This confirms incoming
receipt during that window. The day's stored HR count stayed at 37,201, and its latest stored
sample timestamp did not advance in those reads. Continuous persistence was therefore NOT
verified by that check. The local log contained initial notification errors followed by active
subscriptions; the errors alone do not establish the cause of a persistence gap. Neither this
check nor a Bluetooth acknowledgement establishes physiological accuracy.

After that window, an automatic full pre-update app-data preservation copy succeeded. Its SQLite
`quick_check` was `ok`, with migrations through v47. Today's HR count was 37,704 (+503) and its
latest timestamp advanced by 503 seconds. This establishes subsequent persistence/backfill, not
that every live-preview packet was synchronously saved. Total HR was 659,215 (+2,341 versus the
pre-496 preservation copy); R–R was 268,385 (+900); steps was 659,331 (+2,341). Daily metrics,
sleep sessions and metric-series counts were unchanged, and all five lift tables remained empty.
The private preservation copy and raw diagnostics stay outside Git.

No more wearer testing was requested after the owner declined it. Build 497 installed successfully
on the physical phone under the unchanged bundle/signing identifiers. No uninstall, new migration,
credential activation or firmware command was part of this update.

## Service gates

Life backend through `e0f1ae3` has passed its synthetic receiver/command/MCP/workout checks and
Worker build locally, according to the coordinating thread. It has not been deployed or activated
for this native frontend. Dedicated source/frontend credentials and enable flags are not configured
by this change. App controls do not imply that the production endpoints are available. Keep the
frontend lifecycle flag off until native binding-only seed and capture_only evidence integration
is implemented and verified. There is no automatic resolution of an uncertain owner-wide command.
