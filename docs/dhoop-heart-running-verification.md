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
