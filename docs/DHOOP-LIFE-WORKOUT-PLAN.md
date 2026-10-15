# Dhoop and Life workout integration

This plan extends the active strength/control goal. The wire contract is maintained in
[`DHOOP_WORKOUT_SYNC.md`](/Users/devkunjadia/Developer/life/docs/integrations/DHOOP_WORKOUT_SYNC.md).
Production activation and physical-device acceptance remain separate from local implementation.
The tracker thread reviewed this ownership split and recovery algorithm in Life commit `3662f70`;
its focused receiver tests passed without changing runtime receiver behavior.
The follow-up tracker review in Life commit `494b609` specifies native history-only and deletion
completion without changing receiver runtime code.
Life commit `c98ba65` adds a read-only exact event receipt lookup with focused receiver tests and a
production build. It remains local and undeployed; native delivery activation is a separate gate.
Life commit `f751538` makes read-only lookup the first recovery step throughout the contract;
ingestion retry is a separate write requiring current observations or an explicit reviewed choice.
Life commit `82ea3ac` adds the optional source phase ledger. Focused receiver tests and the production
build passed; deployment, dedicated credentials and native storage approval remain separate gates.
Test-only follow-up `6154998` pins session-wide rest pauses, set-associated work pauses, zero-duration
evidence and unresolved ends after completion. The focused receiver suite passed again; invalid
intervals reject before the atomic batch, preserving queued canonical and source writes.

## One workout, logged once

Life owns reusable programs, scheduled prescriptions, manual canonical edits and progression.
Dhoop owns the physical recording, actual sets and rest periods, and measured WHOOP heart-rate
timeline. A workout can run without network access. Dhoop retains the original prescription and
the recorded measurements; refreshed targets never become performed values.

The primary flow is Exercises → Strength → routine → workout. An explicitly selected cached routine
remains usable offline with its real fetch age. Local routines remain available independently.
Life-backed routine edits use Life's program editor; in-session replacements are actual workout
observations and do not silently rewrite the reusable program.

### Owner experience

1. Open Exercises → Strength and choose a local routine or a Life routine. Keep both origins
   visible; an exercise name does not establish a shared identity.
2. For a Life routine, read the current plan or explicitly choose its validated cached copy.
   Show prescribed targets beside entry fields, without counting them as completed sets.
3. Start one physical session. Log working sets, warm-ups, effort and notes there while shared
   WHOOP collection records actual heart-rate samples across work and rest. Changes made during
   the session remain observations, not edits to the reusable Life program.
4. Finish by saving on the phone. If delivery is configured, retain the exact same workout and
   set identities in the pending delivery. Network failure must leave a usable local history.
5. In history, distinguish recorded values from current Life values. Show whether Life accepted
   the observations, applied import-owned fields, preserved a manual edit, or saved history only.
   Receiver acceptance alone is not evidence that progression finished or all fields applied.
6. Correct or delete the same physical session through explicit review. Do not create a second
   workout to resolve a conflict. Keep the original event and start prescription as provenance.

Local exercises and routines continue to work independently. Creating one does not create or
rename a Life catalog entry. A future optional standalone export must retain a stable custom UUID
and explicit load mode; it cannot convert a Life-backed capture into another standalone workout.

On completion, local storage succeeds first. Optional configured delivery uses the same physical
workout, occurrence and set UUIDs. History distinguishes local storage, receiver acceptance,
canonical application, preserved manual edits and pending progression. A network failure must not
require logging the workout again.

## Ownership and timing

| Fact | Authority | Required behavior |
| --- | --- | --- |
| Planned load/repetitions/rest | Life for Life-backed routines | Freeze the start snapshot; distinguish targets from actuals. |
| Performed load/repetitions/effort/notes | Dhoop capture or explicit manual Life edit | Preserve exact units, explicit clears and manual ownership. |
| Set timing/order | Actual Dhoop actions | Do not infer from plan order or a retrospectively completed set. |
| Heart-rate readings | Persisted WHOOP sensor records | Use the original strap and real time windows; preserve gaps. |
| Progression | Life canonical data | Do not advance from a receipt alone or history-only observations. |
| Session-only substitutions | Dhoop capture | New occurrence/set UUIDs; retain performed original work and lineage. |

Pausing must retain active working intervals and rest state across relaunch. Elapsed wall time must
not be presented as working time. WHOOP collection ownership must remain compatible with other
features, and rest cues must use the shared buzz system without changing wake alarms.

## Reviewed recovery

1. For an uncertain delivery outcome, look up its exact original receipt first. Preserve its bytes
   and IDs; neither a missing capture nor a newer global revision authorizes replacement.
   Lookup submits the stored body to the dedicated read-only route, not to ingestion. A recorded
   receipt can be recovered after local edits/deletion without replaying older observations.
   `not_observed` remains unknown and cannot authorize replacement or a second physical UUID.
2. For a confirmed revision rejection, read the exact current manifest and bounded capture, with
   matching Life/source revisions across pages. Bracket the capture read with matching manifests.
   Show status, schedule, prescription changes, actual values, ownership and tombstones for review.
3. A typed `capture_not_found` means the capture is not visible to this installation. It can conceal
   another installation's capture. Generic 404, authentication failure and transport failure must
   not become an absent-capture result.
   After a definite revision rejection, unchanged frozen destination/installation and valid exact
   bindings permit an explicitly reviewed first apply under the same physical UUID. The receiver
   must still fence a foreign installation or concurrent creation; absence is not ownership proof.
4. Confirm the selected rejected intent is still the latest local intent. A newer accepted source
   revision is not a baseline onto which old observations may be silently lifted.
5. A global-revision-only recovery may create a new event with refreshed `baseLifeRevision` after
   explicit review. Preserve the source revision when content is identical. Keep the original event.
6. Changed prescriptions require an explicit reviewed new source revision/event with unchanged
   cycle/session/occurrence/slot/set IDs, exercise identities and load bases. Retain original
   `planAtStart` provenance and all measured values. Do not match by name, position or similarity.
7. Retired targets, changed identities/load bases, tombstones and ambiguous receipts remain local
   for review. A never-accepted invalid binding cannot silently become standalone or history-only.
8. For an already accepted capture, an explicit history-only correction uses a new source revision
   and event. Label it as source history only: no canonical set application or progression. This
   path needs no current replacement prescription, but still requires coherent current capture
   evidence and verified existing bindings. No automatic fallback is permitted.
9. Immediately before committing a reviewed replacement intent, verify the original event, current
   local recording, destination and review snapshot are still applicable. A concurrent change
   invalidates the proposal; preserve input and require a new comparison.

## Implementation and acceptance checklist

- [x] Local-first UUID-bound set/session persistence and WHOOP collection ownership.
- [x] Frozen cached starts, explicit replacement lineage and observed execution ordering.
- [x] Immutable outbox, exact receipt retries, paused local retention and metadata backup.
- [x] Read-only source/canonical comparison and coherent manifest/capture comparison foundation.
- [x] Reviewed upsert/apply-recovery proposal, differences UI and immutable replacement-intent writer.
- [x] Reviewed full historical deletion recovery (native software tests passed; activation and
      physical acceptance remain pending). Partial deletion still needs current valid bindings.
- [x] Explicit accepted-capture history-only correction and accurate receipt labels (native software
      path tested; production and physical acceptance remain pending).
- [ ] Complete pause/resume with durable active intervals and measured-window attribution.
- [ ] Supersets and exercise variations after approval of the required additive storage changes.
- [ ] Consistent controls throughout remaining goal screens, with ImageGen references and accessible
      pressed, disabled, pending, success and failure states.
- [ ] Physical iPhone routine with two exercises and three timed sets, two successive incoming and
      persisted sample observations, pause/lock/reconnect/relaunch, edits/deletion and gesture checks.
- [ ] Separately approved receiver deployment, dedicated credentials and production activation.

## Agreed next storage and timing design

The tracker review agreed that the existing wire fields already retain superset UUIDs, zero-based
round indices, observed execution order and distinct variation/parent exercise keys as source
metadata. They may accompany ordinary apply of correctly bound prescribed actuals. They do not
rewrite reusable plans, pool variation performance with a parent, or independently advance
progression. Extra/replaced exercises retain distinct actual-only identities and explicit load bases.

True pause/resume needs an interval ledger; start/end envelopes and an active-seconds total cannot
retain pauses losslessly. One session ledger is the authority for set, rest and pause timing, avoiding
separately persisted competing per-set and session arrays. The following additive nullable native
fields were approved by the owner on October 14, 2026, replacing the earlier six-field proposal:

| Table | Proposed field | SQL type | Purpose |
| --- | --- | --- | --- |
| `liftExercise` | `parentExerciseId` | TEXT | Explicit local variation relationship; never alias child history. |
| `liftProgramItem` | `supersetGroupId` | TEXT | Reusable grouping UUID. |
| `liftSet` | `supersetGroupId` | TEXT | Group actually used for that set. |
| `liftSet` | `roundIndex` | INTEGER | Observed zero-based round, not inferred card order. |
| `liftSession` | `activityIntervalsJSON` | TEXT | One authoritative observed phase ledger. |

The approved versioned migrations are implemented locally: GRDB v47 and Room 40→41. Existing rows retain NULL, with no timing,
grouping or ancestry backfill. The versioned Swift/Room migrations, models and schema oracle agree in local tests; SQLite backups
retain the nullable columns and legacy Codable rows decode without inventing metadata. Existing workout IDs, raw HR and preferences remain.

The proposed optional wire field is `session.activityIntervals`, a typed array (not a JSON string):
`{sourceIntervalId, kind: work|rest|pause, sourceSetId: UUID|null, startedAt, endedAt: timestamp|null}`.
Life commit `82ea3ac` implements and tests this optional source-retention field locally. It is not
deployed; native transmission must not assume a destination supports it before activation. Omission preserves the existing snapshot, null explicitly
clears/marks unknown, and an empty array explicitly retains no intervals. Present arrays replace the
complete observed snapshot at a new source revision. Limits are 512 intervals and the existing 128 KiB
request bound; neither side may truncate evidence to fit.

Work requires a known same-capture set ID. Rest may name its preceding set. Pauses may be session-wide.
Validation uses the complete retained source set registry, including tombstoned sets and sets introduced
in the same atomic revision. Arbitrary/foreign references fail. Set deletion retains historical interval
references; deleted work is excluded from current set/exercise aggregates, and retained evidence is
labeled accurately. Interval correction/removal is explicit, not a side effect of deleting a set.

Closed windows lie within known session bounds; work also lies within its set's known wall envelope.
Confirmed work/rest/pause windows cannot overlap. A real pause may be longer than the surrounding work
or rest. Unknown ends remain unresolved, never proof of ongoing work and never automatically closed
at upload/relaunch. Unobserved gaps stay empty. Set HR uses confirmed half-open work windows and
boundary deduplication; missing readings and unresolved working duration remain unavailable.

The engine must preserve one set UUID through work → pause → work. Pausing rest freezes the remaining
rest and cancels its pending cue; resuming creates a new observed phase and deadline. Recovery must
retain input, phase, remaining rest and interval identities while clearly labeling crash/clock gaps.
Session wall duration and active working duration remain separate. WHOOP ownership and wake alarms
continue through the shared systems; software timing is not a guarantee of suspended-app execution.

Acceptance requires pause/resume/relaunch, interleaved superset order and replacements, distinct
variation histories, half-open HR boundaries, invalid overlap/reference rejection, correction/retry/
null behavior, tombstone retention and unchanged canonical/manual/program/progression values for
metadata-only edits. Physical two-exercise/three-set collection tests remain a separate gate.

## Delivery order

The receiver contract already describes accepted-capture history-only corrections and historical
deletion. Finish and test the native reviewed paths against that contract before proposing another
receiver API. History-only correction is an explicit upsert for an already accepted capture with
verified bindings, no deletion arrays and no canonical projection. Deletion uses the default apply
policy and preserves manual canonical values, prescriptions and raw historical provenance.

Both remaining paths need capture-centered coherent reads and a recheck before preparation.
Do not reuse the apply-recovery helper's requirement for a current valid manifest: a previously
accepted programmed capture can support history-only correction or full deletion after its targets
retire. History-only retains the original bindings and start provenance and requires a new event and
higher source revision. Full deletion retains the physical UUID, uses empty observation/deletion
arrays and may keep the original/null manifest reference. Partial deletions remain apply upserts
and still require valid current bindings. Uncertain receipts, foreign installations, tombstones,
newer source revisions and changed local recordings require explicit resolution, not automatic rebase.

Life's detailed eligibility and receipt rules remain authoritative in its contract. In particular,
history-only is currently for already accepted programmed captures; it is not a fallback for a
never-accepted invalid plan or a standalone session. A full-delete receipt preserving manual values
can still accompany a successful source tombstone; verify the resulting source state.

Build 485 implements history-only review from the latest local intent and a verified accepted
source receipt. It reads bounded capture pages twice, retains full response evidence, and repeats
the comparison plus exact local-storage checks before preparing a paused immutable correction.
No current manifest is required. Source acceptance is resolved separately from canonical projection,
so a retired canonical receipt does not erase evidence that the physical capture was accepted.
Original events are retained; a superseded unaccepted apply intent cannot be sent after a reviewed
history-only replacement. Full/set/occurrence tombstones and conflicting bindings still require
resolution; this path never revives a deleted identity.

Submission evidence is stored before POST. Legacy or imported unaccepted backup snapshots do not
prove that a submission never happened, so receipt recovery precedes preparing another correction.
Backup import retains original archive snapshots and immutable event bytes. These changes affect
the iOS integration metadata only, not SQLite, Android schema or physiological calculations.

Build 486 implements full-delete review against coherent source reads, including retired targets,
known set/occurrence tombstones and explicitly reviewed newer observations with unchanged bindings.
A minimal cancellation/timezone patch leaves accepted values, notes, timing and start provenance
untouched beneath the tombstone. Preparation rechecks exact local deletion and remote evidence,
retains original intents, and creates a paused event; sending is separate. Already tombstoned sources
cannot generate another reviewed deletion. Deletion receipts require matching current tombstone
evidence; `manual_preserved` can still represent successful source deletion.

Exact receipt lookup retains the original receipt separately from current source hints and marks
derived progress unknown. It can resolve a committed earlier event after local data changes, then
permit explicit review of an unprepared deletion under the same physical UUID. A missing result
pauses replay and retains earlier positive evidence. Lookup performs no ingestion, reconciliation,
SQLite restoration or data deletion. Definitive cancellation of an unobserved in-flight request
requires a separate receiver fence and is not implemented or inferred from a negative read.

Complete true pause/rest interval storage, supersets and exercise variation relationships only
after approval of the additive native schema changes. Approval of integration design does not
authorize a database migration. Test native behavior before production activation, then verify
the full session and two successive incoming/persisted sample observations on the physical phone.

Production deployment, dedicated workout credentials and end-to-end acceptance are separate gates.
Existing buzz or sleep/protein credentials must not be reused for workout delivery.

The native recovery path passed 46 selected manifest/client/delivery/transport tests, including
unchanged observations, retained provenance, explicit separate send, changed local/remote data,
identities, equal/newer remote source revisions and occurrence tombstones. No production write, migration, installation,
wearer-confirmed cue or physiological accuracy is established by those software checks.
