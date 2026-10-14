# Dhoop and Life workout integration

This plan extends the active strength/control goal. The wire contract is maintained in
[`DHOOP_WORKOUT_SYNC.md`](/Users/devkunjadia/Developer/life/docs/integrations/DHOOP_WORKOUT_SYNC.md).
Production activation and physical-device acceptance remain separate from local implementation.
The tracker thread reviewed this ownership split and recovery algorithm in Life commit `3662f70`;
its focused receiver tests passed without changing runtime receiver behavior.

## One workout, logged once

Life owns reusable programs, scheduled prescriptions, manual canonical edits and progression.
Dhoop owns the physical recording, actual sets and rest periods, and measured WHOOP heart-rate
timeline. A workout can run without network access. Dhoop retains the original prescription and
the recorded measurements; refreshed targets never become performed values.

The primary flow is Exercises → Strength → routine → workout. An explicitly selected cached routine
remains usable offline with its real fetch age. Local routines remain available independently.
Life-backed routine edits use Life's program editor; in-session replacements are actual workout
observations and do not silently rewrite the reusable program.

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

1. For an uncertain delivery outcome, recover the exact original event first. Preserve its bytes
   and IDs; neither a missing capture nor a newer global revision authorizes replacement.
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
- [ ] Reviewed historical deletion recovery when its original receipt needs new preconditions.
- [ ] Explicit accepted-capture history-only correction and accurate receipt labels.
- [ ] Complete pause/resume with durable active intervals and measured-window attribution.
- [ ] Supersets and exercise variations after approval of the required additive storage changes.
- [ ] Consistent controls throughout remaining goal screens, with ImageGen references and accessible
      pressed, disabled, pending, success and failure states.
- [ ] Physical iPhone routine with two exercises and three timed sets, two successive incoming and
      persisted sample observations, pause/lock/reconnect/relaunch, edits/deletion and gesture checks.
- [ ] Separately approved receiver deployment, dedicated credentials and production activation.

The native recovery path passed 46 selected manifest/client/delivery/transport tests, including
unchanged observations, retained provenance, explicit separate send, changed local/remote data,
identities, equal/newer remote source revisions and occurrence tombstones. No production write, migration, installation,
wearer-confirmed cue or physiological accuracy is established by those software checks.
