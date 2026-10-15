# Dhoop strength/control goal: completion audit

Snapshot: October 14, 2026, build 496 source. This is a requirement audit, not a completion claim.
The original objective is `/Users/devkunjadia/.codex/attachments/9031d8ef-eb18-4c66-93c8-24d84dfcc8db/pasted-text-1.txt`.
Detailed command evidence and its limits are in `docs/DHOOP-STRENGTH-VERIFICATION.md`.

| Requirement | Current authoritative evidence | Remaining acceptance |
| --- | --- | --- |
| Shared controls across Today/details/Sleep/Exercises/Meditation/Alarms/onboarding/Settings | StrandDesign action/button/switch components and current screen call sites; scoped failure tests and app builds | Physical taps, holds, drag-off, scrolling and chart scrubbing; failed-read retention is now implemented; native runtime acceptance remains missing |
| Actual async completion, duplicate prevention and retained input | Shared action-controller tests; protein, catalog, previous-performance, pairing, alarm and picker boundaries | Native dialogs/pickers and full screen lifecycle remain unverified |
| Strength inside Exercises | RunningView routes Strength to the existing Lift Log | Physical navigation |
| Exercise search/create, reusable ordered routines | Catalog browser/model and program editor; read-failure and atomic-store tests | Variation creation, parent validation and independent histories are implemented; physical creation and load-basis checks remain |
| Weights/reps/completion/effort/notes and warm-ups | Session engine/controller, pending-input/recovery and edit tests | Real two-exercise/three-timed-set workout, saved entries and unit checks |
| Supersets | Life source grouping contract exists | Native grouping, observed rounds, interleaved execution and recovery are implemented; physical acceptance remains |
| Rest, add/reorder/replace, previous performance | Engine, recovery, source-owned previous reads and their scoped tests | Physical ordering/rest/replacement and relaunch checks |
| History edit/delete/progress and data preservation | Atomic scoped store mutations, retained identities and raw HR; numeric/store tests | Coherent detail snapshot and failed-read retention now have scoped tests; physical edits/deletion with unrelated-record checks |
| WHOOP collection ownership across work/rest | Controller acquires/releases shared ownership; source and duplicate-claim tests | Two successive real incoming/persisted observations and actual session coverage |
| Timed-set HR, gaps, stale/source/count reporting | Saved timestamps, half-open measured-HR store reads and history projections | Confirmed half-open work intervals exclude pause/recovery gaps; hardware evidence missing |
| Pause/resume, lock/background, reconnect and relaunch | Existing rest/session restoration and source identity are tested | True pause/resume and durable ledger now have engine/controller/storage/parity tests. Physical lock/background/reconnect/relaunch checks remain |
| Shared buzz ownership and wake preservation | Existing coordinator and alarm readback/ownership tests with mocked commands | No new hardware cue behavior verified; wearer confirmation remains separate |
| No inferred reps/exercises/muscular strain | Explicit manual sets and measured-HR paths; no new physiological estimator in this goal | Continue checking this invariant when phase/superset work lands |
| ImageGen references for interactions/routines/active logging/history | Strength interaction/order/replacement studies and operation-state studies under docs/design, with prompts | Generated references do not prove the actual UI matches or is accessible |
| Black/deep palette, light/dark, Dynamic Type, VoiceOver, reduced motion, minimum hit targets | Named design components/tokens and current motion/accessibility call sites | Full visual, contrast, clipping and assistive-technology acceptance on the physical phone |
| Meaningful software checks and required builds | Scoped tests and iOS/macOS build logs recorded per build | 184 selected strength/recovery/tracker tests and 53 store tests passed; standalone Swift/Kotlin ledger oracle covers 414 cases. App-build and physical evidence are separate |
| Physical install and full acceptance | Stable signed generic-device artifacts; latest read-only phone listing reports unavailable | Not achieved. No new build has been physically installed or fully tested during these passes |

## Storage boundary

The current proposal replaces the earlier six-field plan with **five nullable fields** and one
authoritative phase ledger. Exact names, semantics, parity and migration requirements are in
`docs/DHOOP-LIFE-WORKOUT-PLAN.md`. The owner approved these exact five fields on October 14, 2026. GRDB v47 and Room 40→41 are implemented and tested; no physical phone migration has been verified.
Legacy timing/group/parent values must remain unknown rather than being backfilled from guesses.

## Tracker coordination

Life retains the agreed optional source timeline locally, with bounded parsing/merged validation,
tombstone references and exact receipt lookup. Receiver tests/builds passed at the documented local
commits. It is undeployed. Native transmission must not assume an unactivated destination supports
the new field. Dedicated workout credentials and production activation remain separate approvals;
existing buzz or sleep/protein credentials cannot be reused.

## Completion decision

**Incomplete.** Native phase/superset/variation storage and UI are implemented with scoped software
checks. The complete physical acceptance list remains outstanding. Neither compilation,
test existence, receiver acceptance nor Bluetooth ACKs proves streaming, persistence on the owner's
phone, felt vibration or physiological accuracy. No official WHOOP-app writes are part of this goal.

## Current acceptance boundary

The owner supplied the five-field migration approval and native work resumed. The earlier migration
approval blocker is resolved. The latest read-only listing reports `0A-Homeboy` disconnected
(`/private/tmp/dhoop-strength-495-device-state.json`). No new phone installation or wearer test is
claimed. The full objective remains unchanged.

Remaining physical checks: connect/unlock the phone; install the signed current build; verify routine
creation, variations, a two-exercise/three-timed-set workout, pause/resume, two successive real incoming
and persisted HR observations, lock/background, reconnection and relaunch; verify history edit/delete,
units, scrolling/scrubbing, native drag-off cancellation, Dynamic Type and VoiceOver. Actual felt buzzes
require wearer confirmation and remain separate from mocked command/timer tests.

Receiver deployment and dedicated workout credentials remain separately gated; existing buzz or
sleep/protein credentials cannot be reused. The native optional phase ledger is retained locally
and is not silently sent to an unverified receiver.
