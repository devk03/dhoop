# Whole-workout draft verification — 2026-10-20

Life remains the canonical workout tracker. The iOS screen keeps a scoped pending edit, not an
independent workout history. No WHOOP recording permissions, wake alarms, or physiological
calculations change.

## Request behavior

Previously, each inline set check awaited an `update_set` POST and a session-dashboard GET;
the shared client busy state disabled other rows. Actual input was only transient view state.

Typing and checkmarks now checkpoint a per-workout JSON draft without scheduling HTTP. Explicit
**Save workout** or **Finish workout** freezes one `update_session` batch, then performs one
canonical refresh after acknowledgement. Capability and foreground reads remain separate. No
per-set fallback exists when `sessionBatchSave` is unavailable.

The draft stores source origin, installation, workout/set IDs, base revision, unit conversion,
number locale, intentional fields, and any frozen operation identity. Unknown acceptance uses
receipt recovery before retrying the same operation bytes. A terminal rejected receipt requires
review; a new operation is created only after another explicit Save. Remote edits never silently
replace deliberate input. Reverting a field to its pre-save value during a pending request remains
an unsent undo after that request commits.

A queued Finish runs after the earlier Save is resolved, using the remaining local edits. Date and
status eligibility are checked before queuing; queued Finish can be cancelled. Marking a set
incomplete follows Life's clear-actuals rule. New numeric results on an incomplete set require an
explicit checkmark before sending. Prescription hints never become logged work.

Foreground/relaunch recovery examines only explicitly saved pending intentions for the current
connection, with a finite bound. Unsaved drafts are not transmitted. An unreadable draft remains
untouched; Retry cannot replace it with a fresh document. Storage failures retain visible input
and prevent transmission until local persistence succeeds.

## Evidence

- 71 targeted native model/client/refresh regressions passed. They include rapid edits, persisted
  units/locale, pending Save plus Finish, newer edits and undo, exact operation retry, receipt-before-
  draft-checkpoint crash recovery, conflicts, implied clears, unreadable files and finite relaunch
  recovery that does not send unsaved drafts.
- An additional transport-level conflict regression passed: HTTP 409, exact rejected receipt lookup,
  explicit remote review, and a new revision/operation only after another Save.
- A realistic 96-set fixture performed zero HTTP requests during edits. Local Mac checkpoint timing
  was approximately 1 ms at the 95th percentile; the checkpoint was 34,113 bytes. This is not an
  iPhone latency measurement.
- Native simulator UI verification passed: inline weight/reps/checkmark, zero mock POSTs, process
  termination/relaunch with values retained, then exactly one mock batch POST from Save workout.
  The proof mode is explicitly simulator-only, uses demo values and an injected transport, and
  neither seeds the app's health database nor accesses production credentials.
- The iOS app built in Release with `-O` for the app, analytics and store. Strict code-sign verification
  confirmed unchanged bundle/team/APNs/Keychain/App Group identity. Build number: 509.
- Source-comment and whole-change localization gates passed without baseline changes.

## Physical boundary

The final connection check reported the paired iPhone's developer tunnel unavailable. Build 509
was prepared, not installed at that observation. No synthetic production workout write was used
for testing. Actual phone latency and a real user's whole-workout save remain distinct from the
simulator/mocked evidence above. The pre-existing physical sleep-delivery check is also separate.
