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
