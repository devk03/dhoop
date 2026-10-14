# Dhoop strength/control goal: completion audit

Snapshot: October 14, 2026, build 494 source. This is a requirement audit, not a completion claim.
The original objective is `/Users/devkunjadia/.codex/attachments/9031d8ef-eb18-4c66-93c8-24d84dfcc8db/pasted-text-1.txt`.
Detailed command evidence and its limits are in `docs/DHOOP-STRENGTH-VERIFICATION.md`.

| Requirement | Current authoritative evidence | Remaining acceptance |
| --- | --- | --- |
| Shared controls across Today/details/Sleep/Exercises/Meditation/Alarms/onboarding/Settings | StrandDesign action/button/switch components and current screen call sites; scoped failure tests and app builds | Physical taps, holds, drag-off, scrolling and chart scrubbing; failed-read retention is now implemented; native runtime acceptance remains missing |
| Actual async completion, duplicate prevention and retained input | Shared action-controller tests; protein, catalog, previous-performance, pairing, alarm and picker boundaries | Native dialogs/pickers and full screen lifecycle remain unverified |
| Strength inside Exercises | RunningView routes Strength to the existing Lift Log | Physical navigation |
| Exercise search/create, reusable ordered routines | Catalog browser/model and program editor; read-failure and atomic-store tests | Variation parent relationships are not implemented; native storage approval pending |
| Weights/reps/completion/effort/notes and warm-ups | Session engine/controller, pending-input/recovery and edit tests | Real two-exercise/three-timed-set workout, saved entries and unit checks |
| Supersets | Life source grouping contract exists | Native grouping/round persistence and UI are not implemented; approval pending |
| Rest, add/reorder/replace, previous performance | Engine, recovery, source-owned previous reads and their scoped tests | Physical ordering/rest/replacement and relaunch checks |
| History edit/delete/progress and data preservation | Atomic scoped store mutations, retained identities and raw HR; numeric/store tests | Coherent detail snapshot and failed-read retention now have scoped tests; physical edits/deletion with unrelated-record checks |
| WHOOP collection ownership across work/rest | Controller acquires/releases shared ownership; source and duplicate-claim tests | Two successive real incoming/persisted observations and actual session coverage |
| Timed-set HR, gaps, stale/source/count reporting | Saved timestamps, half-open measured-HR store reads and history projections | True paused working intervals are not implemented; hardware evidence missing |
| Pause/resume, lock/background, reconnect and relaunch | Existing rest/session restoration and source identity are tested | Existing restoration is not true pause/resume. Durable phase ledger requires approval, implementation, parity tests and physical checks |
| Shared buzz ownership and wake preservation | Existing coordinator and alarm readback/ownership tests with mocked commands | No new hardware cue behavior verified; wearer confirmation remains separate |
| No inferred reps/exercises/muscular strain | Explicit manual sets and measured-HR paths; no new physiological estimator in this goal | Continue checking this invariant when phase/superset work lands |
| ImageGen references for interactions/routines/active logging/history | Strength interaction/order/replacement studies and operation-state studies under docs/design, with prompts | Generated references do not prove the actual UI matches or is accessible |
| Black/deep palette, light/dark, Dynamic Type, VoiceOver, reduced motion, minimum hit targets | Named design components/tokens and current motion/accessibility call sites | Full visual, contrast, clipping and assistive-technology acceptance on the physical phone |
| Meaningful software checks and required builds | Scoped tests and iOS/macOS build logs recorded per build | Tests for the unimplemented native phase/superset/variation storage must follow approval; do not count existing tests as coverage for missing features |
| Physical install and full acceptance | Stable signed generic-device artifacts; latest read-only phone listing reports unavailable | Not achieved. No new build has been physically installed or fully tested during these passes |

## Storage boundary

The current proposal replaces the earlier six-field plan with **five nullable fields** and one
authoritative phase ledger. Exact names, semantics, parity and migration requirements are in
`docs/DHOOP-LIFE-WORKOUT-PLAN.md`. Approval is still pending. No migration has been written or applied.
Legacy timing/group/parent values must remain unknown rather than being backfilled from guesses.

## Tracker coordination

Life retains the agreed optional source timeline locally, with bounded parsing/merged validation,
tombstone references and exact receipt lookup. Receiver tests/builds passed at the documented local
commits. It is undeployed. Native transmission must not assume an unactivated destination supports
the new field. Dedicated workout credentials and production activation remain separate approvals;
existing buzz or sleep/protein credentials cannot be reused.

## Completion decision

**Incomplete.** Remaining work is the native approved phase/superset/variation implementation,
the complete physical acceptance list. Neither compilation,
test existence, receiver acceptance nor Bluetooth ACKs proves streaming, persistence on the owner's
phone, felt vibration or physiological accuracy. No official WHOOP-app writes are part of this goal.
