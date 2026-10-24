# Strength RIR, historical corrections and progression — 2026-10-23

## Native behavior

- Strength rows expose optional actual RIR beside weight/reps, with a separate row when width or Dynamic Type requires it. Unknown is blank; a recorded zero is retained as zero. Input remains a durable local draft until the explicit whole-workout Save/Finish.
- Completed workouts, including archived programs, can correct actual weight, reps and RIR without reopening or changing completion dates. This requires Life's `historicalSessionEditing` capability. History and last-week comparison provide entry points. Closing a sheet retains local edits; its confirmation no longer claims to discard them.
- Last-week comparison accepts stored finite RIR 0–5, including legacy fractional values, without guessing missing RIR from the target. New actual RIR writes remain whole numbers; unrelated edits do not rewrite an unchanged fractional baseline.
- Eligible active strength slots expose automatic/manual rep-range preferences and target RIR. Life's authoritative `progressionPreference` metadata determines eligibility. Duration and priming work do not expose these controls. Manual range writes are integer 1–30, ordered; automatic writes omit the range. Existing automatic DTO metadata outside those write limits remains readable.
- Preference writes use `update_progression_preferences`, occurrence-specific `sessionExerciseId`, explicit mesocycle, the shared revision/receipt queue and an explicit Save. No inferred actuals, local progression formula, volume prescription, new sets or per-set network writes are added.
- Life owns the adaptive planner and nightly recomputation. Its coordinated release preserves past/started/logged workouts, manual overrides and deloads, and treats missing RIR as unknown. Backend evidence and deployment are maintained in the Life repository.

## Design and boundaries

The built-in imagegen study is `docs/design/dhoop-rir-history-progression-study.png`; the prompt record is alongside it. The image was inspected before implementation. Illustrative values are demo data only. Native UI uses existing StrandDesign tokens/components, black surfaces, violet/cyan accents and existing accessibility conventions.

This is the explicitly authorized personal iOS Life frontend. Android and upstream NOOP's offline scope are unchanged. There are no migrations, database resets, strap commands, credential exports or synthetic production workout writes.

## Automated evidence

- Real Xcode `DhoopGoalTests`: 50 focused tests passed across frontend delivery, session drafts, inline actuals, previous-set reads, history pagination and progression preferences. This compiles the real tracker reader rather than the lightweight harness stub.
- After review, 10 targeted tests passed, including stored fractional RIR 2.5 and legacy automatic 30–60 metadata. Review identified and removed the overly strict historical whole-number restriction.
- Historical correction regression preserves completed status, scheduled date and completion timestamp, emits only intended actual changes in one batch, and leaves unknown RIR unknown. Editing emits zero requests.
- Preference tests pin occurrence identity, manual constraints, automatic range omission, and denied replay after permission removal while retaining exact operation bytes.
- Localization adds 16 keys in all ten existing locales and preserves every existing entry. The i18n ratchet, detached-comment lint and whitespace checks pass.
- Simulator rendering/interaction checks are not run: the owner explicitly waived them in favor of focused tests, a real device build and direct installation. Model tests and compilation are not visual verification.

Logs: `/private/tmp/dhoop-511-goal-tests.log`, `/private/tmp/dhoop-511-review-regressions.log`, `/private/tmp/dhoop-511-i18n-final.log`.

## Physical rollout

The pre-install read-only copy on 0A-Homeboy records 29 committed commands, two rejected terminal commands and no unresolved operation. Session 284 has seven local edited sets and no pending submission. These are the current preservation baseline, superseding the earlier build-510 snapshot. No Save is invoked for verification.

Release **511** is built with optimization `-O`, strictly signed and installed in place on the physical iPhone. Device inventory confirms Dhoop 11.8.0/build 511. Source `7a25402`; executable SHA-256 `8bd6a75c9c201f2a62e3f718aaad2f6f23bc75c466a713050ad65b70ed0bfd53`. Bundle/team, APNs development, Keychain and App Group identities are unchanged, and the workout metadata backup type remains declared. Only the known XcodeGen-generated Info.plist diff was restored after the final build; generated project/products are not committed.

Life deployed coordinated source `04f7dd4`, Worker `79a85d52-fdd0-44af-90a3-958a0bcfe434`, before native installation. Its nightly scheduler is gated to 23:35 Pacific.

A post-install read-only comparison confirms all 31 prior immutable operation payloads are preserved, queue states remain 29 committed/two rejected/zero unresolved, and all seven local edited sets plus pending state remain unchanged. This is retention proof, not acceptance of unsaved edits. No owner Save was pressed.

The initial post-install launch was denied by iOS because the phone was locked. Installation is verified; a fresh authenticated in-app history/capability read and current physical UI interaction are not yet verified. The owner was asked only to unlock briefly, with no manual test steps.

Evidence: `/private/tmp/dhoop-511-device-build.log`, `/private/tmp/dhoop-511-signature-proof.json`, `/private/tmp/dhoop-511-install.json`, `/private/tmp/dhoop-511-installed-inventory.json`, `/private/tmp/dhoop-511-launch.log`, and `/private/tmp/dhoop-511-queue-comparison.json`.


## Keyboard dismissal follow-up — build 512

The workout screen adds one localized **Hide keyboard** accessory button above the numeric pad and enables interactive keyboard dismissal while scrolling. Resigning the current text-field responder does not submit, finish, clear or replace the durable workout draft. No other screens, save logic, server contract or stored values change. Existing StrandDesign typography, touch-target and press-feedback tokens are used.

The actual optimized iOS Release build passes, as do strict deep signing/identity/entitlement verification, the existing workout metadata type declaration, localization in all ten locales, detached-comment lint and whitespace checks. Evidence: `/private/tmp/dhoop-512-device-build.log`, `/private/tmp/dhoop-512-signature-proof.json`, `/private/tmp/dhoop-512-i18n.log`. No simulator or physical keyboard interaction is claimed as verified. The Mac currently reports the iPhone unavailable, so build 512 installation is pending reconnection; build 511 remains the last confirmed physical installation.

## Return and explicit reopen — build 513

Closing a workout screen now leaves a **Return to last workout** shortcut on Strength. A device-local bookmark remembers only the original Life origin, installation, mesocycle and session IDs; Life remains authoritative for results and status. Foreign/disabled connections and invalid bookmarks cannot supply the shortcut. Before a bookmark exists, a visible Lifting history action provides access to earlier sessions. Local actuals still restore through the existing durable workout draft.

Completed sessions show the existing explicit **Reopen workout** action in their top summary rather than after every exercise. Only a completed session offers this action; merely returning to a screen performs reads/navigation, not a status write. The command remains `update_session` with the original mesocycle/session IDs and `status: planned`, using the existing revision/immutable receipt queue. Protected local edits must be saved/reviewed first. No date, sets, physical-start operation or new contract is added.

The Life thread verified the existing reopen contract with isolated completion tests: actual load/reps/RIR, set checkmarks, notes, prescription and schedule remain; the session completion timestamp clears and the linked Sheet item becomes unchecked atomically. No real owner workout was reopened for verification.

Real native tests passed: 24 across bookmark scope/identity, durable drafts and reopened history; two bookmark tests passed again after tightening the invalid-ID fixture; the existing explicit manual completion/reopen permission test also passed with physical start disabled. The optimized iOS Release build and strict signature/identity checks pass. Localization in all ten locales, detached-comment lint and whitespace checks pass. Evidence: `/private/tmp/dhoop-513-focused-tests.log`, `/private/tmp/dhoop-513-bookmark-tests.log`, `/private/tmp/dhoop-513-reopen-command-test.log`, `/private/tmp/dhoop-513-device-build.log`, `/private/tmp/dhoop-513-signature-proof.json`, `/private/tmp/dhoop-513-i18n.log`.

No database migration, reset, backend deployment, production workout write or strap command was needed. The owner is away from the Mac; build 513 is prepared for a later in-place install, not reported installed or physically interaction-tested. Build 511 remains the last confirmed physical installation.


## Physical build 513 installation — 2026-10-23

Build **513** is now installed in place and launched on the physical iPhone **0A-Homeboy**, confirmed by fresh device inventory. Its unchanged verified executable SHA-256 is `72f89b1bbe6c08758ef945c1f7acce57adc04cbb79c5f2697ae3724583ea9d95`; source remains `031ebfe`. This supersedes the earlier pending-install notes for builds 512/513 and the earlier locked-launch limitation.

The before/after read-only comparison preserves all 33 immutable command payloads (31 committed/two rejected/zero unresolved), all seven local edits in session 284, and the zero-edit session 287 draft. Pending state is unchanged. No Save or Reopen was invoked.

The fresh native authenticated proof succeeds at Life revision 769: two history pages/40 rows, exact session detail, strength-filtered history, strength dashboard and previous-set contract all validate. The previous set is honestly unavailable (`set_not_completed`), rather than a substituted result. Fresh native capability receipt confirms batch saving, manual completion/reopening, historical editing and progression preferences enabled, while physical lifecycle start remains disabled. The proof records no writes attempted. Physical keyboard/reopen interactions and physiological accuracy are not asserted by these read-only checks.

Evidence: `/private/tmp/dhoop-513-home-install.json`, `/private/tmp/dhoop-513-home-launch.json`, `/private/tmp/dhoop-513-home-inventory.json`, `/private/tmp/dhoop-513-home-verification.json`, and `/private/tmp/dhoop-513-home-after/history-proof.json`.
