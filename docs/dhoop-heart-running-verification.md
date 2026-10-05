# Dhoop heart dashboard and Running verification

Verified on 2026-10-04 against the installed iOS build 424. This is collection and
implementation evidence, not validation of physiological accuracy.

## Delivered behavior

- Today displays a static saved-data snapshot, compact aligned cards, historical
  HR date selection and observed one-minute averages. Missing readings remain
  gaps. Strain is absent from Today. Protein logging remains independent of
  calories and weight; weight/deficit goals remain opt-in.
- The Today live button requests a separate 60-second stream. Running is the
  third tab after Today and Sleep. Its goal credits only observed time inside
  the selected zone; stale readings, gaps and paused time do not accrue credit.
- Running can request a WHOOP strap alert after three observed seconds outside
  the target zone following zone entry, with a 30-second cooldown. It respects
  the existing workout-haptic preference and requires the intended connected,
  worn WHOOP with a confirmed encrypted bond. Test buzz uses the existing
  reversible haptic command; no new strap command was introduced.
- Zone baselines and HRR estimates retain explicit local-method labels. These
  are not claimed to reproduce WHOOP's personalized proprietary calculations.
- Existing history sync uses a 15-minute cadence; iOS background execution is
  not guaranteed at an exact deadline. The dashboard does not redraw per packet.

## Build and test evidence

- 46 DhoopGoalTests passed, including 12 Running tests and three historical-HR
  projection tests; eight timed-session lifecycle tests are in this total.
- Three StrandDesign sampling tests passed separately.
- iOS working-tree, isolated committed-source iOS, and shared macOS builds passed.
- Signed build 424 was installed with the existing bundle/team identifiers.
  The device preference still reports `units.system=imperial`.
- On an archived real-device dataset, chart preparation reduced 8,201 vertices
  to 387 while preserving all 30 run boundaries and each run's extrema. This
  is a cardinality measurement, not an FPS measurement.

## Hardware observations

All times below are America/Los_Angeles; observations address registry device
`my-whoop` (WHOOP 5.0 / MG).

| Check | First observation | Second observation |
| --- | --- | --- |
| Readable live packets | 25 at 20:02:42 | 60 at 20:03:17 |
| Latest live receipt | 20:02:41 | 20:03:16 |
| Saved HR rows in copied database | 31,532, latest 19:59:06 | 31,686, latest 20:02:00 |
| Database integrity | `quick_check=ok` | `quick_check=ok` |

The two live checks both reported fresh HR from the same active device. Their
saved HR count stayed at 31,686 and usable R–R count at 4,930 during the short
session. The database copies independently show history advancing before that
session. These are separate receipt and persistence observations; they do not
prove that every sample from the 60-second stream was saved.

The strap log recorded realtime enable at 20:02:16 and disable at 20:03:17.
At 20:03:32, the collection resolver reported `receivingHR=false`, rather than
continuing to label the stale value live. The user physically confirmed that
Running's Test WHOOP buzz vibrated the strap.

## Verification still pending

- A real exercise-triggered out-of-zone alert, including phone-background
  delivery, has not been exercised. Unit tests verify timing rules; the physical
  test verifies the motor command only.
- The requested manual history sync after the live session has not yet been
  observed. The last captured history timestamp was 20:02:00.
- Manual visual, scrolling-performance, light/dark, Dynamic Type and VoiceOver
  checks on the installed phone remain pending: iPhone Mirroring requires the
  user's local Mac authentication. Source/build checks do not establish these.
- No physiological accuracy or VO₂ max estimate validation was performed.

## Scope and upstream review

Changes are local commits. No push, merge, database migration or data deletion
was performed. Existing pending branding and imperial changes were preserved.
Running is an iOS fork feature; no Android feature parity is claimed.

The bounded ryanbr/noop review found existing timestamp quarantine, device-family
selection, freshness/provenance and HRV filtering already present. The maximum-HR
override correction from upstream PR #2461 was adopted separately. WHOOP 5
500 ms R–R filler quarantine was excluded because adopting it requires a new
schema migration and its Android twin; migration approval has not been granted.
No broad upstream merge was made.

## Build 425: expandable cards

Heart rate remains a compact full-width horizontal card. HRV, Steps, Protein and
VO₂ max use two equal columns with square minimums and content-driven row
heights. Narrow widths and accessibility text sizes use one column. Each metric
opens a larger detail view; Protein opens its existing entries/target editor with
the same store instance. Preview charts omit crowded axes; expanded charts keep
their axes, dates, sources and gaps. Empty detail charts do not reserve a large
blank plotting area. Live HR remains a separate 60-second action.

The final iOS device and simulator builds passed, as did the shared macOS build.
Build 425 was installed with unchanged signing and bundle identifiers; imperial
preferences were preserved. Simulator checks used an existing copied on-device
snapshot, without demo readings: all five metric detail presentations, nested
HR date selection, protein entries/target controls, light/dark appearance and
accessibility text layout were inspected. The resting-HR detail resolves as one
accessibility element. Full spoken VoiceOver navigation, reduced-motion modal
behavior and physical-phone scrolling performance remain unverified. No new
live subscription, collection polling or database migration was added.

## Build 426: inline live capture and common range averages

The 60-second live control and active capture render inside the horizontal HR
card. There is one session owner, no automatic start and no separate live sheet.
Only the live leaf observes packet updates; saved Today metrics remain static.
Opening a metric history detail ends the inline request. Storage polling in this
leaf is limited to the explicit local `--collection-proof` support run.

Expanded HR, HRV, Steps, VO₂ max and Protein share one range selection and one
control: Today, 7 days, 30 days, 90 days, All history, or inclusive custom dates.
Details emphasize averages, coverage and charts rather than daily record lists.
Unknown days are excluded, observed zero steps count, and today's partial data
is labeled. Protein averages are explicitly logged grams, not complete intake.
HRV and VO₂ source/key/method groups have separate averages. HR uses the actual
sample-weighted mean with uncapped read-only daily SQL aggregates; charts show
daily recorded HR averages. No persisted metric formula or schema was changed.
These are iOS fork presentation features; Android range UI was not changed.

Verification: 54 DhoopGoalTests and six WhoopStore collection tests passed,
including eight new range-contract cases and a 200,002-sample HR fixture. The
iOS device, simulator and shared macOS builds passed. Simulator checks against
the copied real-data snapshot confirmed Steps 7-day average 9,243 from seven
recorded days, 30-day average 9,118 from 30 days, shared selection carrying into
Protein, and custom-date updates. A protein average of 40 g/day shows one
recorded day out of the selected range; it does not count the unlogged days as
zero. Build 426 was installed and launched with the stable identifiers. Imperial
preferences were confirmed before installation. The new inline capture has not
yet been physically exercised on this build; the reused 60-second lease tests
pass, and earlier hardware stream verification is recorded separately above.

## Build 427: Sleep date-range statistics

Sleep uses the shared Today, 7-day, 30-day, 90-day, All history and inclusive
custom-date control. Duration averages exclude missing records and show coverage.
Charts, latest dated record, and stage averages use the same frozen range. Stages
match both the duration date and source; unknown stages remain unknown and actual
zero values remain zero. Imported and on-device sources retain their labels.
Main-window reads use exact wake timestamps without a row cap, so sessions that
began before the range remain eligible. Clock averages wrap around midnight.
Presentation-only habitual-window learning is bounded to the recent 30 days;
this does not change persisted sleep analytics. No migration or data rewrite was
introduced. These are iOS presentation changes; Android UI was not changed.

Verification: 58 DhoopGoalTests and two sleep-window storage tests passed,
including buffer-date exclusion, same-source stage ownership, missing versus zero,
midnight clock averages, exact wake bounds and a 4,001-row uncapped fixture. iOS
device and simulator builds, the shared macOS build, source hygiene and diff
whitespace checks passed. Simulator checks with the archived real phone snapshot
confirmed 7-day (7 recorded dates), 30-day (30 dates), and custom Sep 5–Oct 1
(27 dates) controls update averages, chart and latest record together. Independent
read-only SQL reproduced the displayed rounded means: 7h49m, 11h36m and 12h01m.
Those longer stored Apple Health totals are not physiological validation; imported
source aggregation/deduplication was not audited in this change. Apple Health
aggregate provenance does not establish Eight Sleep as the specific source.
No WHOOP-versus-Eight-Sleep comparison was added. Matching-source sleep windows
were absent in this snapshot and correctly remained unavailable.

Build 427 was installed and launched on the phone with unchanged bundle/team
identifiers. Imperial preferences and no active Running draft were confirmed
before installation. Full spoken VoiceOver, physical-phone filter interaction
and physiological stage accuracy remain unverified. No new BLE behavior or
continuous dashboard refresh was added.

## Build 428: custom HIIT and effort review

Running now offers Zone goal and HIIT modes. HIIT configures 1–30 rounds, work
and recovery durations, optional warm-up/cool-down and a three-hour upper bound.
Recovery occurs between rounds. A single explicit HIIT owner holds one HR lease
through work and recovery; zone-goal sessions are mutually exclusive. Another
manual AppModel workout blocks starting HIIT and pauses an ongoing HIIT session.
Timing uses monotonic active elapsed, serviced by receipt callbacks and a 1 Hz
timer. A service interruption longer than three seconds pauses at the last
serviced position, rather than skipping workout instructions. Relaunch restores
a draft paused. There is no automatic live HR start from the dashboard.

The existing reversible WHOOP haptic pattern is requested with one loop for work,
two for warm-up/recovery/cool-down and three for completion. Loops control pattern
length, not a promised number of distinct pulses. Every cue respects the workout
haptics preference and same-device, connected, encrypted, worn WHOOP gates. No
new BLE command or packet payload was added. Cue text reports requests, not proof
of physical delivery. Exact background cue timing cannot be guaranteed by iOS;
the UI asks the user to keep the app open for reliable interval cues.

Session-owned HR samples retain receipt timestamp, active elapsed, interval and
gap segment beyond the live buffer's five-minute window. Saved review shows a
gap-preserving HR chart with work/recovery bands, observed time-weighted mean,
peak, coverage, frozen dated zone method, measured zone time and expandable
interval summaries. Boundary-crossing zone intervals are excluded. Final fresh
receipts before workout end are retained even when the timer just completed.
No calories, strain or physiological accuracy score is inferred.

Local JSON files under Application Support/DhoopHIIT hold resumable drafts and
completed sessions; the newest 20 appear in history while all saved files remain.
Save failure leaves a paused recoverable draft; already-saved IDs are not restored
as duplicate active drafts. These local fork logs are not added to the shared
.noopbak database contract. No migration was added. Android HIIT is not implemented;
this is the user's iOS fork feature with no changes to shared analytics formulas.

The built-in imagegen tool generated the design reference in
assets/dhoop-hiit-ui-reference.png; its exact prompt is saved alongside it in
assets/dhoop-hiit-ui-prompt.txt. The implemented setup uses paired work/recovery
tiles, compact timing controls and a full-width start action. Active workouts
use a bounded interval timer and paired HR/elapsed cards. Review uses a chart,
paired averages, coverage and zone bars, plus expandable intervals. Existing
Today/Sleep/Running tab order is preserved. Demo figures in the reference are
not app data. Layout uses StrandDesign tokens, adaptive grids, Dynamic Type,
semantic accessibility labels and no added animation.

Verification: 67 DhoopGoalTests passed, including nine HIIT cases covering phase
boundaries, delayed ticks, pauses, freshness/source rejection, weighted effort,
zone boundaries, receipt-time interval ownership, completion, and 701-sample
Codable persistence. Final signed iOS and simulator builds, source hygiene and
whitespace checks passed. Build 428 installed with the stable bundle/signing
identifiers. Imperial preferences and absence of an active run draft were read
before installation. Simulator app launch succeeded, but computer-use coordinate
actions failed with noWindowsAvailable and its tab-bar accessibility snapshot
exposed only the container; final HIIT visual interaction could not be completed.
A user-operated 15-second real-WHOOP test was requested. Physical HIIT cue timing,
full on-device visual/VoiceOver review and persisted HIIT hardware HR evidence
remain pending; earlier single-buzz confirmation is not a HIIT workout test.

## Build 429: separate sleep sources and comparison redesign

Sleep presents independent WHOOP and Apple Health cards, source coverage and
matched-date duration differences. It no longer uses a WHOOP-preferred resolver
that can fill WHOOP with Apple values. WHOOP namespaces follow registered WHOOP
identities plus retained canonical imports. Whole records win per date; computed
rows are admitted only when recorded sleep_performance input provenance names a
known WHOOP source. Unknown or non-WHOOP computed provenance is excluded.

A new read-only HealthKit query preserves provider bundle identifiers and names
in memory. It excludes this app's bundle and NOOP sync-identifier records, never
combines providers, unions duplicate/overlapping intervals within one provider,
and leaves conflicting stages unclassified. Coarse unspecified sleep does not
become light/core. Nearby stage fragments (up to a 90-minute seam) form an episode;
actual gaps remain excluded. Episodes contribute to their local wake date, with
later naps contributing only recorded duration. Queries include 36-hour context
on both sides of historical ranges before wake-date filtering, preventing a
midnight boundary from misattributing part of the following night's sleep.

A provider selector appears when several readable providers are present. The
previously selected bundle ID is retained; otherwise a displayed source named
Eight Sleep is preferred when available, without relabeling another provider.
Legacy Apple aggregates remain a clearly labeled fallback when direct HealthKit
records are unavailable; their producer is unknown and their totals can combine
providers. Existing Health sync/storage is not rewritten. No migration, upload,
Health write or automatic authorization prompt was added.

Duration deltas use only dates with both sources. Stage comparisons use only
paired nonnil values when total dates overlap; missing stages stay unavailable.
If there are no shared dates, each source's available stage averages are labeled
separately and no difference is asserted. Repository refresh revisions reload
the comparison after sync/rescore. This is an iOS-only presentation/read feature;
shared analytics formulas and the Android database/backup contract are unchanged.

The built-in imagegen tool produced assets/dhoop-sleep-comparison-reference.png
from the exact prompt in assets/dhoop-sleep-comparison-prompt.txt. Implemented
changes include compact range chips, paired source tiles, a comparison strip,
small multi-date lines with gaps, paired deep/REM/light-core/unclassified rows,
and expandable source notes. A single selected date has no oversized duration
chart or repeated latest-night total. No demographic comparisons or invented
figures from the generated image were implemented. StrandDesign tokens and
adaptive grid layouts are used; the established tab order is retained.

Verification: 77 DhoopGoalTests passed, including ten new source-isolation,
overlap, missing-data, matched-date, midnight-window and DST cases. Final signed
iOS/simulator builds and the shared macOS build passed, as did source hygiene
and whitespace checks. Simulator rendering/AX checks against the archived real
phone data verified Today, seven-day and All history, missing WHOOP values,
separate source coverage and stage totals. All history reads 345 WHOOP dated
records (daily columns plus imported metric series) and 32 saved Apple dates;
these have no overlap. The unsigned simulator cannot read HealthKit, and its
explicit entitlement error exercises the labeled saved-data fallback. A simulator
crash in HKSource.default() was fixed by filtering returned source bundle IDs
instead; subsequent navigation/read checks passed.

Build 429 installed and launched on the phone with stable identifiers. Imperial
preferences, no active Running draft and a null HIIT draft were confirmed before
installation. Live Eight Sleep provider retrieval on the phone, full spoken
VoiceOver navigation and physiological agreement on a paired overnight record
remain unverified. No successful live WHOOP/Apple comparison is claimed from
non-overlapping archived dates.

## Build 430: unified Cardio, interval editing and older sessions

The former Running tab is Cardio. Train offers Zone run, HIIT and Intervals;
History presents local zone summaries, every saved HIIT/interval JSON file and
repository workouts through one date-filtered index. HIIT and timed Intervals
share the explicit vibration/HR engine but retain separate editable plans and
saved kind labels. Intervals starts with a four-by-four-minute editable plan.
All duration controls use five-second steps; work/recovery permit five seconds
and optional warm-up/cool-down permit zero. Older files without a kind decode
as HIIT without rewriting them. No new haptic command was introduced.

Zone runs retain observed time-in-target goals and the existing gated below/above
WHOOP cues after first entering target. Zone 2 remains selectable using the dated
HRR/custom-zone method; a manual BPM target remains available. The fresh status
now says Below/In/Above target instead of leaving the initial waiting message
visible after readings arrive. Another manual workout prevents starting or
continuing a zone/interval session concurrently.

History includes all local saved files, reading the metadata off-main and full
interval detail on demand. There is no 20-file history cutoff. Shared workout
reads use an explicit start-date window and SQLite's uncapped limit while retaining
source union, dismissed-span filtering, existing source dedup and bounded HR
enrichment. Date/type filters, search, month groups and 40-row display pages make
older sessions accessible. Saved sessions advance the history date anchor, so a
new workout is not hidden behind the screen's original opening time. Known
strength aliases and dedicated lifting-source rows are excluded; generic activity
remains honestly labeled. Local/imported representations link only with effectively
identical start/end boundaries (within two seconds and one unambiguous local
candidate), and both details stay accessible. Overlap alone does not merge sessions.

The phone's noopAutoDetectWorkouts preference was read as true. Cardio now exposes
that toggle and the review/save suggestion which the custom Today page omitted.
Detection scans saved HR after refresh, uses the existing sustained-activity
threshold and excludes local zone/HIIT/interval spans as well as shared workouts.
It never saves a suggestion without the user's Save action. Short intervals can
fall below the detector threshold; explicit recording remains available.

The built-in imagegen reference is assets/dhoop-cardio-ui-reference.png, with exact
prompt in assets/dhoop-cardio-ui-prompt.txt. The implementation uses existing
StrandDesign tokens, compact mode/navigation controls, grouped history and source
details. Demo figures, the mockup's Apple Watch attribution, notes and delete
controls were not introduced into the app. This is iOS fork functionality; no
database migration, shared stored workout formula or Android schema was changed.

Verification: 84 DhoopGoalTests passed, including five history tests and two added
interval/legacy-decoding tests. Tests cover all 101 indexed fixtures, date/type/
search composition, conservative linking, imported strength aliases, five-second
phase progression and older HIIT files. Final signed iOS/simulator builds and
the shared macOS build passed, plus source hygiene and diff whitespace checks.
Simulator launch and the renamed Cardio tab were observed; coordinate control
continues to fail with noWindowsAvailable, preventing full Cardio UI navigation.
Five-second physical cue timing and end-to-end on-phone history/detection review
remain unverified.

Installation is held: two preference reads show a zone-session draft marked
running. The user was asked to end and save it before updating. Build 430 has
not been installed on the phone yet; build 429 remains the last confirmed install.
Imperial settings and existing local session storage are preserved.

## Build 431: chart point inspection

Charts accept a short stationary hold followed by a drag. Selection snaps to an
actual recorded point, shows its value, units and recorded date/time (and source
where supplied), and clears when the finger lifts. Existing range averages remain
visible. The dashboard remains snapshot-based; scrubbing adds no fetch, polling
loop, database write or realtime-HR request.

Shared coverage includes DashboardChart, TrendChart, OverviewHRChart, Sparkline,
Hypnogram and YearHeatStrip. App adapters cover Sleep comparison, HIIT/interval
HR, training load, live HR, metric comparison, workout recovery/heatmap, sleep HR
and debt, hourly stress, dose response, the heartbeat scatter and legacy optional
calorie-balance bars. Decorative gauges/progress indicators are not time series.
Values-only legacy traces name the recorded sample or interval pair rather than
inventing a date that their input does not contain.

Today keeps its full-width HR card and square metric grid. Expansion is on the
metric header so dragging a chart does not open the sheet. Hosted legacy cards
have a separate details link. Active scrubbing blocks ancestor tab/day navigation
and HR chart panning. VoiceOver can step through points without creating one
accessibility element per sample. Existing named colors/fonts/surface/spacing
components are used; the new selection does not animate or require motion.

Recorded-point lookup is independent of drawing reduction. Today HR retains all
one-minute averages for inspection; expanded metric/protein and HIIT charts also
inspect their complete in-memory rows. Missing daily bars explicitly say no value,
recorded zero stays zero, and a line-gap selection identifies its nearest recorded
endpoint. Separate sources are not interpolated onto each other's dates. Daily
markers are constrained to the visible partial-day plot; canvas inspection omits
padded points outside the visible timeline.

Validation:

- StrandDesign: 120 tests passed, including seven new selection tests for
  irregular timestamps, boundaries, source/segment gaps, interleaved series,
  missing days versus zero, nonfinite input, accessibility stepping and points
  omitted by display reduction. Log: `/private/tmp/dhoop-chart-tests-final.log`.
- Signed NOOPiOS device build, iOS simulator build and Strand macOS build passed.
  Logs: `/private/tmp/dhoop-scrub-ios-final.log`,
  `/private/tmp/dhoop-scrub-sim-final.log`, `/private/tmp/dhoop-scrub-mac-final.log`.
- Doc-comment hygiene passed. Staged whitespace checks passed.
- Native and secondary-account read-only review completed. Native review's
  partial-day marker, per-series gap, out-of-bounds sleep point and pan-conflict
  findings were addressed.
- Build 431 installed and launched on the physical iPhone with the existing
  bundle/signing identity. Installation also delivers build 430's Cardio work.
  The zone run was paused before installation, no HIIT workout was active, and
  its saved draft was byte-identical after launch. Unit preferences were unchanged
  and automatic workout detection remained enabled.
- Simulator Today and expanded Steps rendered with the existing recorded data.
  Steps retained its seven-day average, coverage and source labels. Charts expose
  adjustable accessibility controls. An immediate chart drag did not navigate
  away. A sustained hold-and-drag readout was not observed mid-gesture with the
  available automation API; hands-on phone scrubbing, VoiceOver gestures and
  light/dark/Dynamic Type checks remain pending user confirmation.

This is Apple UI work for the personal fork; no Android UI parity is claimed.
No analytics formula, stored schema, BLE command or physiological validation was
changed. No migration, data deletion, push or merge was performed. Prior pending
branding/imperial changes remain separate from these commits.

## Build 432: review and regression repairs

Review covered the current working tree and the recent goal/dashboard, inline HR,
range-average, Sleep comparison, zone/HIIT/interval, Cardio history, and scrubbing
commits. Native reviewers covered charts and Cardio; a read-only secondary-account
review covered Sleep and range/protein behavior. The coordinator verified findings
against callers and added failure-path tests. No claim of universal bug-freedom or
physiological accuracy follows from this review.

Repairs:

- Sleep-stage and recovery-calendar accessibility selections could index outside
  a newly shortened series. Readouts now resolve safely against current data and
  reset when the series changes. Regression tests exercise stale selection indices.
- Generic deep-timeline readouts appended `bpm` to supplied temperature/HRV units
  and announced every metric as heart rate. The caller's units and metric label
  now pass through unchanged. The full inspection index is prepared once per
  input update instead of rebuilding it during every hover update.
- Apple sleep totals counted explicit awake time overlapped by a broad asleep
  sample. A new regression test reproduced 480 minutes where only 420 were asleep;
  it failed before the fix and passes now. Awake intervals are excluded from total
  sleep and its stage totals, without changing stored sleep records.
- Comparison filtering checked SyncIdentifier while HealthKitBridge exports sleep
  with ExternalUUID. Both markers now exclude Dhoop/NOOP writeback across bundle
  identities, preserving independent-provider comparisons. Ordinary third-party
  providers remain included.
- A successful HIIT archive followed by failed draft cleanup left the completed
  session resumable, risking loss of later progress on restart. Archive success
  now closes the session; cleanup failure is reported separately. Actual file-write
  failure tests cover both writes and preservation of the original draft.
- Detected-workout saving reported success after swallowed SQLite errors. The
  repository now returns actual persistence success, retains the suggestion on
  failure, and captures its owning device. Cardio also checks candidate identity
  before enqueueing and immediately before executing a save. A read-only SQLite
  fixture verifies that rejected writes cannot report success.
- Today could remain frozen indefinitely in the foreground. Its snapshot now
  refreshes every fifteen minutes or at local midnight, with cancellation when
  inactive; it still has no per-packet dashboard updates. Goal-only reads/backfill
  stop on cancellation, goal disablement or device change. Metric history observes
  completed repository refreshes and updates its date bound. Large history chart
  metadata uses a dictionary instead of a nested date search.
- General `.noopbak` exports omit local Cardio records. History now discloses that
  limitation and offers a separate portable JSON export of all local zone/interval
  records and drafts. The snapshot is captured on MainActor before detached file
  encoding, avoiding a finish-during-export race. Raw bytes, including damaged
  records, are preserved. This file has **no in-app restore**; the general backup
  format remains unchanged.

Validation:

- 123 StrandDesign tests passed: `/private/tmp/dhoop-review-design-tests.log`.
- 93 DhoopGoalTests passed: `/private/tmp/dhoop-review-goal-verified.log`.
- 8 detected-workout repository tests passed, including failed storage writes:
  `/private/tmp/dhoop-review-workout-tests-final.log`. The test target now explicitly
  links the already-pinned GRDB dependency it imports.
- 4 existing unit-preference tests passed:
  `/private/tmp/dhoop-review-preferences-tests.log`.
- Signed iPhone and simulator builds passed:
  `/private/tmp/dhoop-review-ios-installed.log`,
  `/private/tmp/dhoop-review-sim-installed.log`. The macOS app compiled as part of
  the passing repository-test run. Source-comment and staged whitespace checks passed.
- Simulator Today rendered its recorded-data grid and compact historical HR card.
  Coordinate control again returned `noWindowsAvailable`; physical finger gestures,
  full VoiceOver/Dynamic Type checks, and real exercise/background vibration remain
  hands-on verification gaps.
- Existing uncommitted text changes were compared with the pre-review patch and
  matched exactly. No migrations, database deletion, publication or merge occurred.

The scope remains the personal Apple fork. Storage-error handling changes the
reported result, not the workout schema or analytics; no Android change is claimed.

Build 432 was subsequently installed and launched on the physical iPhone. The
installed-app inventory confirms version 432. The paused zone draft is byte-identical
before/after launch, unit preferences are unchanged, and auto-detection remains on.
No live workout was interrupted (zone paused, HIIT draft empty before installation).
