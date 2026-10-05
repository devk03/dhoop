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
