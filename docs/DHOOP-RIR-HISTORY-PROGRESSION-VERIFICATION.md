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
