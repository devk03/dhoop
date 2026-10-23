# Workout sync reliability — 2026-10-23

## Observed failure

Read-only copies from the physical iPhone confirmed build 509, enabled editing, and valid batch
save capabilities. Its queue contains 29 committed commands and one older uncertain `update_set`.
That operation has a negative receipt lookup. A different workout retains five edited sets and
an explicit whole-workout submission, but that submission never reached the frontend command
queue. The older operation blocks `prepare`; foreground draft recovery only follows draft IDs,
so it cannot clear the legacy blocker. The generic retry message does not identify this cause.

Life independently observed no active server fence and identified a matching receipt gap: stale
legacy commands return HTTP 409 without a durable no-effect rejected receipt. A negative lookup
alone is not permission to discard an operation or declare it applied.

## Implementation and verification sequence

1. Reproduce a retained legacy uncertain operation blocking a newer saved workout. Also cover
   receipt lookup failure, a running fence, a wrong receipt identity, and interrupted delivery.
2. Add one bounded shared exact-operation delivery path. Recover attempted operations before
   retrying; retry only prepared or verified not-observed operations with their original bytes.
   Recover a terminal receipt immediately after a conflict response. Never replace operation IDs,
   rewrite frozen revisions, drop drafts, or invent a successful acknowledgement.
3. Recover the older queue operation before preparing a newer explicit workout save. A committed
   or rejected terminal receipt unblocks the queue. Uncertain/running or malformed responses keep
   it blocked and retain input. Handle foreground/relaunch as well as the open workout screen.
4. Show whether the current workout waits for an older change, needs connection recovery, was
   rejected and needs review, or was saved with a verified receipt. Keep local-only edits distinct.
5. Coordinate Life's durable stale rejection for validated legacy actions, retaining HTTP 409,
   original request/hash identity, and zero domain effects. No broad contract rewrite is needed.
6. Run targeted model/client tests and actual native simulator UI scenarios for retained legacy
   saves, interrupted transport, relaunch, and explicit review. Preserve existing local-edit and
   one-batch-save checks. Build the iOS app; check localization and source hygiene.
7. Re-read the physical queue and authenticated Life data with bounded diagnostics. Install a
   signed optimized build with the same bundle/team/Keychain identities after simulator checks.
   Do not mutate real workouts merely to produce evidence. Report any unverified production save
   separately from simulator, HTTP, and read-only physical evidence.

## Constraints

No database migration or reset, no credential export, no WHOOP alarm or BLE changes, no production
fixture workouts, and no infinite retry monitor. Pending immutable submissions and local drafts
remain recoverable. This is the personal iOS Life frontend; Android and upstream NOOP's offline
contract are unchanged.

At audit time the Mac had less than 1 GB free, then could not create a shell temporary file.
Builds require disk headroom; the audit does not authorize erasing owner data to obtain it.
