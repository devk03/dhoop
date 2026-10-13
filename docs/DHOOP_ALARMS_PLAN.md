# Dhoop Alarms implementation plan

Planning specification, October 12, 2026. No alarm configuration, firmware, application code, or health database was changed while preparing this plan.

Dhoop should have a dedicated **Alarms** tab with the familiarity of iPhone Clock and a clear view of what the WHOOP has actually stored. A person should be able to create, edit, enable, disable, label, repeat, and skip an alarm without navigating through Settings. A saved preference is distinct from a scheduled strap alarm. The central engineering requirement is reliable, independently executing WHOOP scheduling with preservation of existing alarms.

## Outcome and release criteria

The first useful release is an exact-time WHOOP alarm manager for the user's physical WHOOP 5 and iPhone. It adds a fourth native tab after Today, Sleep, and Exercises; preserves all existing identifiers and data; and exposes verified scheduling coverage for every enabled alarm.

Completion requires all of the following:

- Create, edit, disable, delete, skip-next, weekday repeat, and reconnect behavior passes targeted production-boundary tests.
- The alarm time, next occurrence, device status, and any countdown are resolved from one snapshot and one supplied clock.
- No operation clears or replaces an external or unknown alarm without the owner's specific approval.
- A fresh, correlated, matching full-record readback is required for **Stored on WHOOP**. A Bluetooth connection or SET response is insufficient.
- Physical one-shot tests pass in foreground, locked, disconnected, and force-quit conditions. A powered-down-phone test is a separate release requirement before describing that condition as supported.
- Each physical pass has both observable scheduling evidence and an explicit wearer report. Target test firing error is within five seconds of the scheduled instant; failures remain failures until explained and retested. This threshold is a release target, not a claimed firmware guarantee.
- Repeat coverage is tested with two independently stored upcoming occurrences and two successive real morning alarms. Any remaining coverage horizon is visible.
- Cancellation is verified to prevent the scheduled vibration, and unrelated strap alarms remain unchanged before and after the suite.
- Signed iOS and required macOS/shared builds pass. Pure protocol/math changes include their Android twins and oracle tests; an iOS-only screen or AlarmKit adapter is explicitly identified as such.
- The implemented screens are compared with the approved design study on the physical phone, including large text, dark/light appearance, readable switches, and native scrolling.

Do not finish by reporting compilation or a command ACK as successful wake delivery. If safe readback, ownership, or scheduled execution cannot be established, stop the affected write feature and report the specific capability gap.

## What exists today

| Surface | Existing behavior | Required change |
| --- | --- | --- |
| iOS navigation | Today, Sleep, Exercises in `RootTabView` | Add Alarms without disturbing existing navigation paths, tab reselection, or safe areas |
| Alarm screen | `SmartAlarmView` combines one wake preference with wind-down controls | Replace the iOS entry point with the new manager; preserve the legacy screen until routing and shared-platform behavior are reconciled |
| WHOOP 5 arming | `armStrapAlarm` writes revision 4, default slot 1; Experimental-gated | Typed, attributed, slot-specific scheduling with readback before success |
| WHOOP 5 disabling | `disableStrapAlarm` sends revision 2 with ID 255 | Remove wildcard disable from normal feature paths; target only an owned, freshly checked slot |
| WHOOP 5 reading | Six slot reads are correlated to connection/sequence and displayed as raw diagnostic strings | Add an independently validated typed decoder and evidence model before using reads to allocate or restore slots |
| Repeat scheduling | Foreground/connect/event hooks and a daily app timer rearm one instant | A finite schedule of actual strap occurrences with explicit remaining coverage; no dependence on continuous iOS execution |
| Readback comparison | Existing `AlarmReadback` helper uses device attribution and a 120-second tolerance | Keep its existing cross-platform diagnostic contract; add exact WHOOP 5 slot/operation comparison rather than weakening it or reusing the broad tolerance |
| Immediate vibration | Shared `BuzzDeliveryCoordinator`; WHOOP 5 command 19 | Reuse for a non-consuming test buzz, separate from scheduling and alarm execution |
| Phone backup | Existing local-notification implementation | Optional iOS 26 AlarmKit adapter, with legacy notifications accurately labeled |

The confirmed build-459 locked-phone three-buzz tests establish notification haptics through APNs and app Bluetooth execution. They do **not** verify command-66 scheduled WHOOP wake execution. Existing code also contains wording that calls an alarm armed from intent or an experimental write; the new screen must use evidence instead.

Implementation references: [alarm protocol](PROTOCOL_ALARMS.md), [current delivery contract](BUZZ_DELIVERY.md), [BLE manager](../Strand/BLE/BLEManager.swift), [legacy alarm screen](../Strand/Screens/SmartAlarmView.swift), [alarm integration](../Strand/App/AppModel.swift), [iOS shell](../StrandiOS/App/RootTabView.swift), [payload encoder](../Packages/WhoopProtocol/Sources/WhoopProtocol/HapticPayloads.swift), and [existing diagnostic comparison](../Packages/StrandAnalytics/Sources/StrandAnalytics/AlarmReadback.swift).

## Hardware capabilities and assumptions

The repository protocol notes describe WHOOP 5 IDs 1–6, one-shot absolute timestamps, a 21-byte revision-4 alarm record, targeted revision-2 disable, and execution event 57. They also describe partial writes, read fallbacks containing zeros, and interference between concurrent due alarms. These documented facts are candidates for this user's firmware until verified on the physical device.

The current encoder has a 20-byte semantic body; the notes explain how protocol padding supplies a zero crescendo byte. Do not assume the current encoder is broken or append bytes speculatively. Validate the decoded GET shape and actual transmitted framing, including padding, against captured clean-room frames and pure tests. Preserve raw result and validation detail separately.

| Capability | Product policy |
| --- | --- |
| One stored exact-time alarm | First hardware gate; ship only after scheduled physical tests |
| Six simultaneous stored slots | Treat as documented capacity, not six verified free slots; discover and protect each slot |
| Weekday recurrence | Implement in Dhoop as future dated occurrences; do not imply firmware recurrence |
| Future firing without phone execution | Verify independently after disconnect/force-quit/power-down; never route this through silent pushes |
| Preview | Use notification haptics. WHOOP 5 RUN_ALARM can consume a stored alarm and is not a safe preview |
| Stop an active wake | A separate operation from disabling a future alarm; validate physical gesture and targeted stop behavior before exposing a promise |
| Snooze | Not assumed. Requires another safely stored future occurrence and a verified dismissal interaction |
| Custom intensity, waveforms, crescendo | Defer; accepted effect bytes are not validated perceptual controls |
| Sleep-stage or recovery-based early wake | Defer; neither accurate live sleep staging nor firmware smart-wake control is established here |

WHOOP's published product description includes exact-time and sleep/recovery-dependent modes and describes no built-in snooze. That is a UX reference, not permission to claim those capabilities in Dhoop's implementation. [WHOOP haptic alarm documentation](https://support.whoop.com/s/article/The-Haptic-Alarm-Dashboard?language=en_US)

## Product and navigation

The tab order becomes **Today · Sleep · Exercises · Alarms**. Use a native alarm symbol and the existing native tab bar. Audit tab-tag consumers and resize every indexed navigation/scroll state consistently; the current arrays have six entries and must not be indexed with a new out-of-range tag. Existing Alarms links in Settings/More should land on this same manager, not a second independent editor.

The scope is alarms. World clocks, a stopwatch, and another timer interface would duplicate other features and are deferred. The existing meditation/exercise experiences remain in Exercises. The Alarms tab should work as a quiet utility, with no heart-rate subscription or continuous dashboard updates.

### Overview

1. Compact Alarms heading with an accessible Add action.
2. WHOOP row with selected device identity, connection, latest alarm check, and available battery reading. No fabricated battery value or endurance prediction.
3. Next alarm summary showing the nearest verified stored occurrence, its date, label, and status. If the earliest intended alarm is pending, show that gap prominently rather than presenting a later verified alarm as the complete plan.
4. Clock-like list with large readable times, smaller AM/PM where appropriate, label, repeat summary, clear blue on-state switches, and a concise status line when needed.
5. Compact coverage row such as “Next 3 occurrences stored through Friday” only when those exact dated occurrences have matching readbacks.
6. Optional bedtime planning row using the existing sleep goal of **8 hours 15 minutes**. For an illustrative 7:00 a.m. wake, 10:45 p.m. is the simple planning time before adding an explicit wind-down/fall-asleep allowance. It is not measured sleep or a promise of 8h15m asleep.
7. Alarm history and device details as secondary navigation.

Avoid an oversized hero, grids of decorative stats, repeated copies of the same alarm time, or low-contrast controls. Time is the primary visual content. Disabled alarms are muted, not unreadable.

### Add and edit

One sheet contains a native time picker plus Label, Repeat, WHOOP vibration, time-zone behavior, and optional Phone backup. Default repeat is Never for a new alarm; weekday/everyday presets and custom days are available. Support locale-appropriate 12/24-hour display. Standard is the only vibration setting until additional patterns pass hardware verification.

Saving commits the desired local definition and immediately attempts safe synchronization when connected. The sheet dismisses normally; the overview shows Pending until automatic verification succeeds. Do not add a second confirmation screen or require the user to manually check readback after every save. A specific external-alarm replacement or uncertain-slot tradeoff is the exception that requires informed approval.

Editing labels does not rewrite hardware when the stored time/pattern is unchanged. Dragging a time picker changes a draft; only Save creates an operation, avoiding a burst of intermediate BLE writes.

### Everyday actions

- **Toggle on:** save intent, resolve next occurrence, allocate safely, verify automatically.
- **Toggle off:** immediately stop future local reconciliation for that definition; retain visible Pending removal until physical disarming is verified. An offline switch cannot guarantee a previously stored alarm is gone.
- **Skip next:** cancel only the next occurrence. Future repeat rules are preserved. If offline, explain that the next strap buzz may still occur until synchronization completes.
- **Delete:** remove the definition from future planning but retain a tombstone/status for any still-stored occurrences. Final removal waits for a verified targeted clear. History remains separate.
- **Test vibration:** one immediate notification waveform, gated away from a scheduled wake. It must never RUN or consume a stored alarm.
- **Dismiss and snooze:** deferred unless validated. A physical double-tap may stop the motor, but Dhoop must not interpret an uncorrelated general double-tap as proof that a specific alarm was dismissed.

## Ownership and preservation

On first use, read all supported slots without writing. Snapshot complete raw records, parsing outcomes, device/firmware identity, connection, read sequence, and time. Repeated consistent zero replies are useful evidence but still do not independently establish an empty slot if the firmware can return zeros on failed storage reads.

Classify slots as external/unknown, known existing Dhoop, newly managed Dhoop, or demonstrably available under a validated read/clear contract. Preserve external and unknown records. Matching a time is not ownership. A migrated legacy preference does not prove it owns slot 1.

Before a write, read the selected slot again. If it differs from the expected owned state, stop rather than restoring a stale snapshot over someone else's update. External edits made by the official WHOOP app are conflicts to surface, not settings to silently undo. The strap has no established cross-client compare-and-swap operation; Dhoop can serialize its own writes and detect changes, but cannot promise atomicity against another connected writer.

No normal operation uses disable-all ID 255. A targeted disable requires both protocol validation and a fresh ownership match. Never borrow a wake slot for meditation, interval transitions, or MCP buzzes. None of those features should write alarm storage.

If no slot can be shown safe, saving remains local/pending. Ask the owner about one exact slot and its existing alarm before replacing anything. Retain the original full record, show what would change, and establish that restoration is actually supported. A stored backup alone is not a restoration guarantee.

Audit and retire legacy automatic writers before enabling the new coordinator: `applySmartAlarm`, connect-settle rearming, daily rearm, alarm-fired callbacks, foreground handlers, per-day wind-down overrides, and any default-off path that still calls wildcard disable. The old and new schedulers must never run independently against the same slots.

## Recurrence and coverage

Separate an alarm definition from its occurrences. A weekday rule may exist indefinitely on the phone, but a strap contains only a finite set of one-shot instants.

The planner expands enabled definitions into future occurrences, sorts by due time, and allocates only safely available slots. Multiple weekdays for one alarm consume multiple slots. Protected external alarms reduce capacity. The UI exposes the actual count and last stored occurrence, not a fixed “six days” promise.

Begin with one verified next occurrence per alarm. After multi-slot validation, fill the available rolling window in chronological order, with fair visibility across definitions. Excess definitions remain saved with a clear future-coverage limitation. When a slot becomes available after execution, reconcile on genuine app/Bluetooth execution opportunities; no midnight timer or background task is a guarantee.

Coincident alarms cannot be assumed to play independently. Offer a single occurrence with combined labels for identical compatible schedules, retaining each definition's association, or require the user to resolve a timing conflict. Deleting/skipping one associated definition must not cancel another still-enabled definition's shared occurrence. Near-overlap guard time must be derived from the validated wake pattern duration; never silently shift a requested wake time.

Default repeat rules follow local wall time. Store the resolved UTC instant and time zone for each hardware occurrence. Travel changes require a safe resync; an already-stored UTC alarm will not reinterpret itself when the phone changes zone. Surface the existing stored time until replacement is verified.

Explicit policies: spring-forward nonexistent times move to the first valid local time with a visible explanation; fall-back repeated times use the first occurrence and fire once. One-time dated alarms retain their explicitly selected instant. Pure tests cover these policies, and shared Swift/Kotlin calculations must use matching semantics and oracle outputs.

## State and recovery

Use separate definition intent, hardware occurrence state, and firing evidence. They answer different questions.

| Display state | Evidence and behavior |
| --- | --- |
| Off | No desired future occurrences; does not imply an offline strap was cleared |
| Pending sync | Saved locally, not verified on strap |
| Checking WHOOP | Current read/write/readback operation in progress |
| Stored on WHOOP | Fresh matching full-record readback for this occurrence and device |
| Pending removal | A previously stored occurrence may still execute until a targeted clear is verified |
| Changed on WHOOP | Record differs from expected ownership/revision; automatic replacement stops |
| Storage unverified | Missing/malformed/stale/ambiguous readback; no green success badge |
| Due, delivery unconfirmed | Scheduled instant passed; lack of a received execution event does not prove no buzz |
| Execution reported | Attributed strap event identifies an execution attempt; not proof of motor output |
| Felt by wearer | Explicit wearer report, separately dated and attributed |

Each state contains a useful next action. Do not flatten every failure into “Disconnected.” A stale match cannot certify a later edit, another slot, or another device.

Persist intent and operation journal before issuing writes. Since firmware updates may be partial, recover a crash or timeout by reading physical state first. Do not blindly resend SET, automatically reconstruct deleted alarms, or retry a motor command. If an edit fails, display both the retained stored occurrence and the pending desired change. Best-effort restoration is allowed only after fresh ownership checking and a verified restoration contract.

On reconnect, process safety-critical pending cancellations for owned records before adding new occurrences, then recompute future times from current intent. Expired operations never replay as a late buzz. Bound BLE attempts per operation, back off, and wait for a new actual connection opportunity rather than starting an endless monitor.

## Relationship to other vibrations

Introduce a shared motor arbitration boundary between scheduled wake alarms and the existing `BuzzDeliveryCoordinator`. The alarm manager owns alarm storage; the buzz coordinator owns app-driven notification cues. Both consume a read-only schedule snapshot for collision decisions.

Suppress competing MCP/ambient/test vibration around a verified imminent wake window. Report suppression honestly. Exercise ownership must not silently disable a stored wake alarm. If a workout overlaps a wake, show a conflict and prevent new overlapping motor requests; do not claim app arbitration can override undocumented strap arbitration. A running notification haptic may interfere with a due stored alarm even though their storage systems are separate.

The verified three-buzz MCP pattern stays distinctive. Standard wake vibration is a separately validated longer alarm pattern, not automatically three pulses. No unbounded “buzz until awake” loop is introduced.

## Optional phone backup

On iOS 26, evaluate AlarmKit as a separately authorized, system-managed backup for the same occurrence. Apple's API supports fixed and relative alarm schedules and alarm presentations that can break through Focus/silent mode. It requires per-app permission and `NSAlarmKitUsageDescription`; its system UI is distinct from Dhoop's strap UI. Availability-check the adapter so the iOS 17 target still builds. [Apple AlarmKit session](https://developer.apple.com/videos/play/wwdc2025/230/), [scheduling sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit).

Phone backup defaults off. When enabled, show separate WHOOP and phone status; permission denied or scheduling failure must not alter strap success. Older iOS uses only an explicitly labeled optional notification fallback. Do not treat notifications as system alarms or duplicate existing backup requests. Never create a new backup simply because an alarm has unknown strap state.

AlarmKit does not establish automatic background WHOOP command execution at the firing instant. If exposed later, a phone Snooze action and a WHOOP snooze are separate operations, with separate confirmations. Keep an existing built-in Clock backup unchanged during hardware validation.

## Sleep integration

Use the existing 8h15m sleep goal as the single source for bedtime guidance. Alarm weekday exceptions belong in the alarm editor; wind-down reminders derive from the selected wake occurrence and an explicit lead setting. Do not keep a second “Wake time” input hidden under Wind-down that silently changes the actual alarm.

The Sleep page may link to the next alarm and display bedtime guidance from the same resolver. WHOOP and 8 Sleep measurements keep their actual dates and sources. Actual sleep duration, time in bed, and planned sleep opportunity remain distinct. No dependence on HRV, VO₂ max, recovery availability, or guessed light sleep is introduced for exact-time alarms.

## Storage and architecture

Prefer a versioned app-local, atomic alarm-state file plus an operation journal, independent of health SQLite. This avoids a health DB migration. Preserve existing preference keys during legacy import and retain old values for rollback. A JSON-version conversion is explicit, tested, and non-destructive; corrupt state fails closed without replacing the source file.

Do not claim this file survives uninstall. Define an explicit export/backup route. Changes to the existing `.noopbak` whitelist require matching platform contracts and tests; avoid silently adding an iOS-only object to that wire format. Ask before any eventual SQLite/Room migration.

Proposed responsibilities:

| Component | Responsibility |
| --- | --- |
| `WhoopProtocol` alarm record/response types | Pure revision validation, encode/decode, separate outer result/detail, raw payload retention |
| `StrandAnalytics` alarm occurrence planner | Pure next-date calculation, repeats, exceptions, DST, conflicts, finite coverage |
| App alarm state store | Definitions, occurrence revisions, ownership, pending operations, immutable evidence |
| Shared alarm coordinator | Serial reconciliation, read-before-write, read-after-write, cancellation, recovery, capability gates |
| Existing BLE manager/router | Connection-safe transport and attributed correlated responses/events; no UI scheduling logic |
| `StrandiOS` Alarms screens | Overview, editor, detail/coverage, history; no direct raw BLE calls |
| iOS 26 phone alarm adapter | AlarmKit authorization, stable system IDs, scheduling/cancellation, availability guards |
| Shared motor arbitration | Collision checks for wake alarms versus immediate cues |

Every hardware occurrence includes definition association, occurrence ID, definition revision, active strap registry ID, slot ID, UTC due time, local time-zone context, expected raw record, operation/connection identity, verification timestamp, and evidence references. Store exact raw hardware data separately from formatted UI text.

Use one resolver for UI/backup/bedtime times, one actor-owned coordinator per selected device, and generation checks that reject stale async completions. Concurrent edits coalesce to the latest desired revision. Pending cancellation cannot disappear because a stale save completed later.

## Design and accessibility

[Generated Alarms design study](design/dhoop-alarms-study.png) · [Generation prompts](design/dhoop-alarms-prompts.md). The board shows the overview, editor, and detail surfaces with demo schedules.

The generated study uses black canvas, near-black rounded surfaces, deep violet/indigo alarm accents, and the established clear blue switch state. Adopt existing StrandPalette, StrandFont, metrics, buttons, and switch components. Add only missing semantic tokens; do not hardcode a new color/spacing system in the screen.

Time is large but balanced; labels and status have enough room to wrap. Dynamic Type may stack status under time. Never shrink text until it becomes unreadable, and never constrain the entire card to one fixed height. Touch targets are at least 44 points, destructive actions have textual labels, and VoiceOver announces time, date, recurrence, enabled intent, and verified hardware status independently. Do not communicate status only through color. Preserve reduced-motion behavior and native scrolling.

Use event-driven snapshots. A minute-level countdown refresh affects only the countdown view; HR notifications and motor receipt traffic must not redraw the full list. Do not introduce live chart gestures into this utility screen. Check the fourth tab on the physical iPhone and at large accessibility sizes; verify content never disappears behind the tab bar or keyboard.

The design study is illustrative. Time values and stored-state pills are demo content, not an assertion that a real alarm is armed. Final UI states must come from the coordinator.

## Verification plan

### Pure and coordinator tests

- Exact encode/decode golden records, existing 20-byte framing versus padded crescendo zero, revision/slot validation, CRC integrity, zero/malformed/partial reply handling, and operation-specific responses.
- Full-record readback equality, correlation to slot/device/connection/operation, stale replies, sequence reuse, and original alarm preservation.
- Never/today/tomorrow, midnight, weekdays, per-day exceptions, skip-next, leap dates, DST gap/fold, local-zone changes, and exact UTC one-time schedules.
- Slot exhaustion, protected slots, coincident compatible alarms, conflicts, shared-occurrence deletion, and visible coverage exhaustion.
- Save/edit/edit, toggle-off racing save, crash before/after write, disconnect during verification, partial update, stale ownership, targeted-cancel failure, and reconnect after expiry.
- Definitions restored after relaunch preserve user intent; hardware success must be reacquired when stale. No duplicate firing commands or wildcard disable in the new coordinator path.
- Phone-backup permission denial, stable identifiers, repeated edits, skip-next, disable/delete, and system changes remain separate from strap results.
- Motor arbitration protects a due wake while keeping unrelated exercise/meditation/MCP histories and preferences intact.

Use the existing test targets and production boundaries, not source-text checks that merely count call sites. New tests must detect a plausible wrong timestamp, unsafe slot mutation, false armed state, duplicate operation, or lost cancellation. Keep existing WHOOP 4 behavior pinned if shared code is touched. Validate any new cross-platform byte/math contract through an independent oracle.

### Physical WHOOP 5 and iPhone

Before the first write, record firmware, device identity, connection state, strap clock evidence, battery, all slot readbacks, and existing wake-alarm configuration. Select a safe test slot only after the ownership/restore gate. Use daytime short-horizon alarms and wearer confirmation before relying on a morning wake.

| Test | Required observation |
| --- | --- |
| Foreground one-shot | Matching stored record, requested versus observed time, wearer felt vibration |
| Two locked-phone one-shots | Lock maintained across firing; repeat success, not inferred from foreground |
| Phone/strap disconnected after arming | WHOOP buzz occurs without BLE delivery at that instant |
| Dhoop force-quit after arming | Stored WHOOP occurrence executes; app does not need relaunch to cause it |
| Phone powered down after arming | Separate proof of strap independence, not just screen-off |
| Two future occurrences stored together | Both fire, first is consumed without clearing the second or external slots |
| Cancel before due | Target slot clear verified, no scheduled buzz, other records unchanged |
| Offline edit/delete then reconnect | Pending status accurate; latest intent wins; expired operations never buzz late |
| Official-app change | Conflict detected without silently overwriting the new external record |
| Notification cue near alarm | Arbitration and physical overlap behavior observed without losing wake |
| Stop gesture and optional snooze | Distinct tests before those features are enabled |
| Two real morning alarms | Wearer reports actual wake experience separately from firmware execution |

A diagnostic session ends explicitly and in less than two hours; propose at most 90 minutes for the short-horizon suite. Morning follow-ups are explicit user check-ins, not an unattended overnight monitor. Preserve protected diagnostics outside Git. After testing, reconcile the original configuration and verify every untouched slot.

Report scheduled intent, stored readback, execution event, felt vibration, and actually waking as separate evidence. One successful trial cannot establish universal alarm reliability or prove the wearer will always wake.

## Implementation sequence and granular commits

1. **Capability and safety foundation:** independently validate WHOOP 5 record decoding and targeted operations; document supported firmware and issue-first protocol changes. No new writes are enabled yet.
2. **Local model and pure schedule planner:** definitions/occurrences, persistence, finite coverage, repeat/skip/DST/conflict tests. Retain legacy settings.
3. **One alarm coordinator:** integrate typed BLE responses, read-before/read-after operations, ownership, cancellation, recovery, and replacement of legacy autonomous writers.
4. **Dedicated tab and Clock-style UI:** approved visual study, consistent components, one editor, clear pending states, and routing of existing Alarms links to the same state.
5. **Optional phone backup and sleep guidance:** availability-gated AlarmKit, permission/status separation, one 8h15m goal source, and retirement of duplicate notification scheduling.
6. **Physical one-shot validation:** build/install without uninstalling, daytime verified slot tests, explicit wearer reports, and preservation checks. Keep the feature labeled Experimental until these pass.
7. **Repeat window and lifecycle validation:** safe multi-slot scheduling, cancellation/reconnect/force-quit/power-down, two morning checks, and published coverage limitations.
8. **Snooze and extra wake patterns, if justified:** separate capability review and physical validation, not bundled into the first release.

Each concern gets a local commit with its actual verification. Regenerate the Xcode project from `project.yml` when adding files; never commit generated project/build artifacts. No schema migration, firmware change, destructive command, PR merge, or external publication is implied by this plan.

## Recommended decisions

Use Alarms as the tab name. Start with exact-time alarms and Standard WHOOP wake vibration, repeating definitions with honestly finite stored coverage, and optional phone backup off by default. Preserve the user's existing wake alarms; protect foreign/unknown slots. Keep skip-next in the first release. Treat snooze, custom intensity/crescendo, smart early wake, world clocks, and remote MCP alarm creation as later features with their own verification and authorization.

Remote agent attention cues remain on the existing three-buzz API. They must not create, change, snooze, or delete a wake alarm. Any future alarm-management MCP tool needs separate explicit owner authorization, stricter scheduling semantics, conflict visibility, and an auditable result.

The first execution gate is safe, typed WHOOP 5 readback and a physically verified one-shot. A polished UI can be implemented while that investigation proceeds, but an alarm must remain visibly unverified until hardware evidence supports it.
