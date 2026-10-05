# Dhoop sleep robustness audit

## Pre-registered evaluation — October 5, 2026

Recorded before measurements for this audit. Starting commit: c3c1e65.

- Engineering prediction: acquisition gaps, event ordering and later syncs must not fabricate observed
  sleep or erase a previously supported interval solely because of bookkeeping. Each confirmed defect
  gets a minimal synthetic reproduction at its owning public boundary, failure before repair, and a
  passing regression afterward. Matching Swift/Kotlin behavior is checked with compiled Swift oracles.
- Stage benchmark: run the unchanged shipped SleepStagerV2 through Tools/SleepPSG on all 31 subjects
  of PhysioNet sleep-accel v1.0.0, without fitting parameters or selecting subjects. No additional
  exclusions. Evaluation domain is the dataset's labeled recording windows, including wake, as used
  by the existing baseline harness. Report four-class agreement/kappa, class marginals and signed
  stage-fraction bias; compare against the majority-class baseline where supported.
- Prediction: the shipped four-class classifier exceeds the constant majority-class accuracy on this
  cohort. The threshold is simply positive improvement over that baseline; report the result even if
  it fails. No accuracy target is promised for WHOOP 5 or this user.
- No calibration or temporal tuning occurs in this audit. The entire public cohort is an external
  measurement of the existing fixed recipe, not a held-out claim about a newly fitted model. Any later
  fitted change requires a separate untouched validation set and protocol.
- The dataset uses Apple Watch sensor inputs and human-scored polysomnography. It can expose
  limitations in the recipe; it cannot establish WHOOP 5 performance or validate an individual's
  REM/deep estimates. Apple Health/Eight Sleep agreement is also not physiological ground truth.
- The existing private phone copies may be used read-only for regression replay and coverage checks.
  They will not be used to fit thresholds, treated as stage ground truth, or committed.
- No schema migration, raw-sample rewrite or phone availability is required. Any new build is prepared
  locally for a later device connection; hardware checks are reported separately.

Dataset attribution: Olivia Walch (2019), *Motion and heart rate from a wrist-worn wearable and labeled
sleep from polysomnography*, PhysioNet v1.0.0, doi:10.13026/hmhs-py35, Open Data Commons Attribution
License v1.0. Original study: Walch, Huang, Forger and Goldstein, SLEEP 42(12), zsz180 (2019).
Source: <https://physionet.org/content/sleep-accel/1.0.0/>.

Outcomes will be appended below; this pre-registration is not revised after measurement.


## Engineering contracts added before repair measurements

- Short-fragment cleanup must preserve acquisition breaks already identified by the detector. Test
  leading/trailing/middle fragments on both sides of a >20-minute gap and retain contiguous-arousal behavior.
- Wear reconciliation must be chronological and bounded by the analysis cutoff. A later OFF must not
  extend backward across a sustained-HR interval. A later ON must not revoke the same evidence. Known
  OFF intervals without sustained contradictory HR retain their bounds. Equal-timestamp OFF wins over
  ON, and confirmation cannot borrow HR from or beyond the next wear event. Input beyond the cutoff
  must not change an earlier result. This intentionally revises build 435's blanket preservation of
  matched OFF/ON intervals when sustained HR contradicts the recorded span.
- HR-only fallback must honor the existing 16-hour cap and supplied off-wrist evidence just as motion
  detection does. No new physiological thresholds or stage parameters are fitted.
- A required computed-score or sleep write failure must leave the retry obligation and input watermark
  unsettled. Successful retry must remain possible even when no new raw readings arrive.


## Confirmed outcomes — build 436

### Reliability repairs

- **Acquisition gaps:** the original public HR-only path turned two recorded blocks totaling 100 minutes
  into a 450-minute sleep window. Both the short-run merger and an HR-supported motion-gap bridge could
  cross a hard gap: the latter accepted a lone far-edge HR sample as evidence for the whole interval.
  They now honor the existing 20-minute break threshold, including leading/trailing/one-sided fragments.
  Contiguous brief-arousal merging remains covered. The public regression failed before repair.
- **Chronological wear:** each OFF segment resolves independently against HR before the next wear event.
  New OFF/ON events cannot retroactively extend an earlier interval across sustained wear evidence.
  Events after the cutoff are ignored, same-second conflicts resolve to OFF, and duplicate samples do
  not add evidence. HR is normalized once, not once per event; the no-OFF path skips that work.
- **Fallback parity:** HR-only sessions now honor the existing 16-hour cap and supplied off-wrist
  evidence. The normal detector, fallback, and fragmentation rescue agree on the inclusive one-hour floor.
- **Durable scoring:** required Swift score/session/motion/stage writes report failures without
  advancing the completed-input watermark or settling retry debt. Existing stale-daily cleanup waits
  for those writes to succeed. SQLite fault injection reproduced the old false-success behavior;
  removing the injected failure permits a nonforced retry with unchanged raw input. Android already
  propagates these failures; corresponding tests verify that behavior. Successful earlier transactions
  can still exist after a later failure: this is retry safety, not one transaction for the whole pass.
- The input fingerprint advances to v5 on both platforms so the existing upgrade rescore sees the
  changed analysis. No schema migration, raw-data rewrite, new BLE command or stage-model tuning occurs.

### Tests and builds

- 394 Swift sleep/bridge-related analytics tests passed.
- 28 native app/scheduler tests passed, including four real-engine failed-write/retry cases.
- 375 Android tests in 41 selected classes passed; full app Kotlin compilation completed.
- Signed iPhone and macOS builds passed. Source-comment hygiene, translation checks against main and
  whitespace checks passed. Native and secondary-account reviews completed; the independent write lane
  used an isolated worktree and was reviewed before integration.
- Standalone optimized Swift helpers produced the interval/merge literals asserted by Kotlin. Cases
  cover shuffled/repeated events, conflicting timestamp ties, future events, half-open boundaries,
  duplicate/invalid HR, density and gap limits, and connected versus disconnected fragments.
- The SleepPSG port check passed all 55 synthetic/degenerate nights: 12,377 epoch labels were identical.
- Build 436 is prepared locally. The user is away from the laptop; it was not installed or tested on
  the physical phone during this pass. The phone remains on the previously verified build 435.

Primary logs: `/private/tmp/dhoop-sleep-robust-analytics-final.log`,
`/private/tmp/dhoop-sleep-robust-app-tests.log`, `/private/tmp/dhoop-sleep-robust-android-final.log`,
`/private/tmp/dhoop-sleep-robust-iphone-final.log`, `/private/tmp/dhoop-sleep-robust-mac-final.log`.
Android verification used a local Gradle init script that creates an empty schema-output directory
when the existing Sync task has no exported files; no tests were skipped, and no schema/build-rule
changes were committed. These selected tests do not assert a generated Room schema export.

### Measured stage-classifier baseline

[Full baseline output](assets/dhoop-sleep-psg-baseline.txt). Dataset files came from the public S3 mirror
listed by PhysioNet; all 125 downloaded files matched the published SHA256 manifest. This cohort has
been used by upstream before and is **not** an unseen hold-out validation set. No coefficient or
threshold was fitted in this audit, and the stage classifier itself was unchanged.

Reproduce (dataset outside the repository):

```bash
cd Tools/SleepPSG
swift run -c release sleeppsg --section port
swift run -c release sleeppsg --dataset /path/to/sleep-accel-1.0.0 --section baseline
```

Evaluation domain: all 26,773 labeled 30-second epochs across the dataset's 31 subjects, wake included.
N1/N2 map to light; N3 to deep. Five sensor terms are present; this dataset has no beat-to-beat RR.

| Measurement | Result |
| --- | ---: |
| Four-class epoch agreement | 59.67% |
| Constant majority-class (light) baseline, 14,775 / 26,773 epochs | 55.19% |
| Cohen's kappa | 0.363 |
| Wake recall | 30.8% |
| Deep fraction bias, pooled | +5.17 percentage points |
| REM fraction bias, pooled | +4.46 percentage points |
| Wake fraction bias, pooled | −4.92 percentage points |

The pre-registered majority-baseline prediction passed by about 4.5 percentage points. That is a
modest improvement, not evidence of precise individual REM/deep timing. Wake was often missed, and
both deep and REM were overestimated on this cohort. These results use Apple Watch sensor inputs;
they do not establish WHOOP 5 accuracy. Agreement with Eight Sleep is useful comparison evidence,
not ground truth. No before/after clinical accuracy gain is claimed for the reliability fixes.

### Remaining limits and next evidence

- Wear-event queries start at the analysis window. A still-relevant OFF preceding that window is not
  seeded into the query; correcting that read boundary needs its own storage/caller regression coverage.
- The existing banked-session overlap healer does not guarantee removal of every obsolete, nonoverlapping
  computed session after a changed detection. This patch deliberately adds no broad deletion or rewrite
  policy. Current comparison totals use dated daily records/provenance; legacy session-based views and
  historical baseline reads still warrant a separate reconciliation review.
- No independent personal multi-night stage reference exists yet. A longitudinal comparison should
  report dated sleep duration/onset/wake differences, source and input coverage on every night, preserve
  missing nights, and keep a later window untouched for any parameter calibration.
- iOS background execution can defer a long pass. Retry debt now survives required write failures,
  but the app still needs a later execution opportunity; this is not a guarantee of continuous processing.
