# Inline workout logging and shared completion — build 501

## Behavior

- The workout page edits actual weight/repetitions directly in aligned exercise rows. The check
  action saves that exact set through the existing Life frontend receipt endpoint. Filled checks
  indicate the server's completed value; typed changes remain unsaved until submitted. An unchanged
  completed set can be unchecked. Optional RIR and advanced prescription/program controls remain.
- Empty actual inputs show prescription hints. Checking a blank row never copies targets into
  actuals. Mass conversion retains Life's pounds contract and the chosen imperial/metric display;
  total, per-hand, added-load, bodyweight and timed modes preserve their existing semantics.
- Each exercise has inline Swap selection and Save replacement, explicitly scoped to the shared
  program. Existing eligible-catalog and receipt checks apply. Unsaved set edits block replacement
  and workout completion; a concurrent changed set retains the draft for review instead of silently
  overwriting it. Uncertain command outcomes use the existing receipt-recovery UI, with no blind retry.
- The compact status/notes header replaces the large Edit workout log button. Notes, metrics and
  advanced targets are still accessible. Controls use StrandDesign tokens, shared press/pending
  behavior, native keyboard fields, VoiceOver labels and at least 44-point touch targets. Large text
  switches the row to a vertical form; content can scroll.
- Finish workout / Reopen workout are explicit canonical Life actions gated by the additive
  `sessionCompletion` capability. They do not start WHOOP recording. Scheduling is a separate explicit
  action; an unscheduled workout must receive a date first. Start/in-progress/skip remain lifecycle
  gated, and combined date-plus-completion commands are refused.
- Returning from a changed detail reconciles that row in loaded history, including removing a
  reopened workout from completed results. Other loaded rows and selected filters stay mounted;
  the stale revision cursor cannot append more pages until Refresh.

## Coordinated Life fix

The Life tracker chat owns the backend changes: service/tests `ddd5e14`, contract `218ad78`,
publication notes through `fe23985`. Worker `18d4d692-8529-4419-9d10-ec6bb47e862c` is deployed on
both private tracker hosts. The shared service batches session/linked-Sheet completion, uses one
checkbox parser with note-line isolation, repairs the exact linked checkbox on repeated completion
or reopen, and handles folded finishers. It covers canonical strength, run, yoga and AirBike sessions;
it does not guess links between unrelated raw recordings by title/date.

The Life agent reports passing bidirectional, retry, rollback and concurrency tests plus existing
receiver/MCP/workout/history/scheduling regressions and the production build. Reinstating the old
transition-only write caused the repair regression to fail. Existing broad TypeScript errors and an
unrelated `test:tagging` module-loader issue remain documented by that chat; the affected real Sheet
move suite passed independently. No migration, secret/Access-policy change or owner workout mutation
was performed for this verification.

## Native verification

- 17 targeted native tests passed: manual-completion capability boundaries while physical Start
  stays off; blank targets versus actuals; metric conversion, clearing, bodyweight/timed modes,
  invalid input and concurrent drafts; history reconciliation and cursor/duplicate protection.
- Signed iOS build and shared macOS build passed. Source doc-comment lint and diff hygiene passed.
- Four hosted simulator UI checks passed. New UIKit-backed render fixtures cover 320-point dark
  and light layouts plus accessibility text. Actual input/check controls were visually inspected;
  unsupported flattened-render placeholders were replaced by native hosted rendering. Fixture
  numbers are demo data only. A final render-only pass corrected safe-area clipping and passed.
- Build **501** is independently confirmed installed on physical iPhone **0A-Homeboy**, with stable
  bundle `com.devkunjadia.zhoop.loshi.noop`. Normal launch succeeded after the read-only probe.
- The phone's existing Keychain-authenticated probe verified two history pages / 40 distinct rows
  at revision 93, filtered history, exact detail and Strength reads. It reported one active lifting
  program / 24 pending workouts, scheduling=true, **manualCompletion=true**, **physical lifecycle=false**,
  and **writesAttempted=false**. No live owner set, date or completion was changed to manufacture proof.
  This proves authenticated capability/reads, not an accepted production mutation or strap recording.

No DB schema change/reset, credential minting, strap command, wake-alarm change or destructive file
operation was required. The personal-fork English UI still fails the localization extraction audit;
no translation baseline was weakened. Android UI is unchanged; no physiological/schema/backup
contract changed.

Built-in ImageGen reference and exact prompt: `docs/design/dhoop-inline-set-logging-study.png` and
`.prompt.txt`. The implementation uses real Life data and shared components, not the mockup's demo
values or bitmap UI.
