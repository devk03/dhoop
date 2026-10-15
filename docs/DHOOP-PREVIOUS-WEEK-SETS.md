# Previous-week set comparison

The info control to the left of each set opens a read-only sheet. Done and the native swipe-down
gesture dismiss it. Today's weight/reps/RIR remain in the existing edit buffer; the sheet never
submits a command, refreshes the dashboard cache, or copies a prior result into a current set.
History remains readable while current-set editing is disabled or a save is pending.

“Last week” means **the immediately previous program week**, not a rolling seven-day window.
Life resolves the same program, session key, slot, exercise, load mode, set type and set number.
Only a completed workout and completed set with recorded actuals qualify. First program weeks,
changed exercises, incomplete/missing sets and absent actuals display an explicit unavailable
state. Older weeks, other programs and prescribed targets never silently fill the gap.

The bounded authenticated GET uses the existing iPhone Keychain connection:

`/api/integrations/dhoop/workouts/dashboard?view=previous_set&mesocycleId=N&sessionId=N&setId=N`

Native validates the response against the requested current set and revision. A disconnected,
disabled, cancelled, superseded or identity-mismatched read cannot populate the sheet. The read
does not replace cached workout state or write credentials. Each popup fetches one set, without
downloading history or starting a polling loop. API failures offer an explicit retry.

Mass uses Life's canonical pounds, converted once for the owner's selected lb/kg preference.
Per-hand and added loads retain their labels. Bodyweight sets show reps without a fabricated
weight; verified duration-mode counts show seconds. Recorded zero is not missing. Source workout
title, program week, scheduled date and available completion timestamp remain attached.

## Verification

- Life implementation `f0275a1`, documentation `a3c4dab`, deployed Worker
  `361d7e9b-454b-4b8d-9705-330e5d0579dd`. The tracker chat reported exact-week/matching/auth,
  missing/zero/mode, bounded read-only and concurrency tests passing, along with existing
  MCP/receiver/history/Strength/completion suites and production build. Deliberately restoring
  an older-week fallback failed its regression test. No owner workout edits were used.
- Native: 13 targeted Foundation tests passed, including five previous-set tests, four existing
  draft tests and four dashboard tests. These cover identity/week/type boundaries, all load modes,
  units, missing actuals, GET-only bounded requests, unchanged cached/persisted state, stale
  revisions, disabled connections and a response arriving after disconnection.
- Two hosted iOS layout tests passed. Actual rendered fixtures were inspected at narrow 320-point
  widths in light/dark mode and accessibility-size text. The comparison wraps instead of clipping;
  the existing weight/reps fields retain room. Demo values exist only in fixtures/design studies.
- Signed iOS build 504 passed. Doc-comment lint, diff hygiene and the localization gate against
  `8c79786` passed; four new surface strings include translations without changing any baseline.
- Build 504 installed on physical iPhone `0A-Homeboy`. Its opt-in `--workout-history-proof`
  result was recovered after reconnecting: `authenticated_history_reads_verified`, revision 93,
  `previousSetReadVerified:true`, `previousSetAvailability:available`, `writesAttempted:false`.
  Existing history and Strength reads also passed. Native validated the current identity and
  previous-week comparison before accepting the response. No owner workout was modified.
  Real-device popup hand interaction was not manually tested. An explicit unavailable comparison
  remains a valid outcome for other sets.

Built-in ImageGen reference and exact prompt: `docs/design/dhoop-previous-week-sets-study.png`
and `.prompt.txt`. The app renders native StrandDesign controls; no bitmap supplies workout data.
This is the existing personal iOS Life frontend; Android/macOS interfaces are unchanged. No DB
migration, data reset, strap command, wake-alarm change or new credential is involved.
