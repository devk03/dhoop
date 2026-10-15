# Dhoop workout UI and shared-tracker verification

Build 500 keeps Strength on the active, explicitly typed `four_lift_strength` program selected
by Life. Exercises defaults to Strength; active BPM/HIIT/meditation/WHOOP recordings retain
precedence. The next-workout card uses the complete-program `nextUp` result, not the first
page of plans. Scheduled dates are Life values. Unscheduled planned workouts offer a calendar
and date-only Save in Life when the dedicated capability permits it. Existing program/history
records are preserved; unrelated programs and half-marathon actions are removed from Strength's
primary selection/settings. No name-based program classification is used.

## Implemented acceptance checks

- Life history uses revision/filter-bound opaque cursors and 20 summaries per request. Full
  session details load on demand. Overlapping, mismatched or changed-revision pages do not
  partially replace existing rows. Filters and mounted rows remain when detail sheets close.
  Local WHOOP history reveals 20 records at a time; its existing off-main local-file read remains.
- Sleep's Deep/REM/Light/Unclassified breakdown stays visible outside the range-comparison
  disclosure. Every source/date retains its own duration, denominator and method. Missing
  readings differ from zero. Stage timelines preserve gaps. Layout is a reusable component.
- BPM sessions retain accepted HR samples with explicit continuity segments. Legacy summaries
  can read their original strap's stored workout window; that trace is labeled as historical
  wall-clock data that may include pauses. It does not replace original session statistics.
  Workout details and local share previews use real readings only, fading areas and explicit
  gaps/unavailable states. HIIT, imported recordings and completed Life logs share through the
  same native preview shell. Life logs with no attached trace do not invent one.
- Pending detections expire 48 hours after activity end; suppression metadata stays to prevent
  redetection. Confirmed/rejected decisions and raw sensor data remain. Launch/refresh capture
  performs cadenced expiry even when discovery is off; opening review also evaluates expiry.
  The suggestion is explicitly generic sustained cardio: HR alone cannot identify a sport.
  User corrections update only the linked owned row, with the existing transactional journal.
- Shared buttons highlight on press without an entrance animation, reserve async pending state
  synchronously and reject overlapping submissions. Scroll touch delivery is immediate while
  native pan cancellation stays enabled. Per-scroll leases restore previous behavior after the
  last owning component leaves, including forms outside ScreenScaffold. Zone-draft encoding
  runs off the main thread and stale results cannot overwrite a newer/finished draft.

## Verification evidence

- Signed iOS build and shared macOS build passed. Stable bundle/team identifiers are preserved.
- 36 focused history, Strength, schedule-capability, expiry, trace and storage tests passed.
  Additional client/transport/provisioning regression coverage passed in the 86-test run.
- 15 repository review/store tests passed, including activity correction retaining row identity,
  statistics and exact deletion ownership. Four shared action-controller tests passed.
- Twelve native rendered layout cases cover narrow width, light/dark, accessibility text and
  empty data. Images are explicitly labeled test fixtures and are never app health data.
  Physical-iPhone rendering and pending-state checks passed on builds 499 and 500. Build 500's
  pending-state reservation measured 0.388 ms on the device; this is not finger-to-display latency.
- All three build-500 simulator and physical-device UI checks passed, including the shared
  button disabling its enclosing scroll touch delay while retaining native cancellation and
  an enabled pan recognizer. Hosted tests use the actual iOS application; no manual tapping
  or wearer checklist was required.
- Build 499 was independently confirmed installed/running on physical iPhone 0A-Homeboy.
  Authenticated Keychain-backed proof read two history pages/40 distinct summaries at one
  revision, a filtered page, exact details and Strength nextUp detail. It verified one active
  lifting program, scheduling enabled, and frontend lifecycle disabled. All requests were reads;
  no owner workout was scheduled, started or modified. Life Worker version:
  `eb8529ce-1090-4f55-bd54-5c728350b3f9`.
- Build 500 was independently confirmed installed on 0A-Homeboy after the physical tests.
  A normal relaunch afterward was blocked by the phone locking; opening Dhoop after unlock
  remains necessary. A further launch attempt after the unlock reply was also rejected by iOS
  as locked; a fresh build-500 API proof could not run. The successful build-499 API proof above
  and build-500 physical UI checks remain the verified evidence. No manual wearer test is needed.
- Preferences were preserved before installation; imperial units were confirmed. No active zone
  draft existed. No migration, firmware command, wake-alarm change or database reset occurred.

## Limits and scope

WHOOP physical-workout lifecycle linkage remains disabled, as previously approved; scheduling
is independent and does not start or complete a workout. Physiological accuracy was not tested.
The timing benchmark measures the action controller; a whole-app finger-to-displayed-frame
benchmark is not claimed. iPhone Mirroring required Mac authentication, so it did not provide
whole-screen gesture inspection. No manual wearer checklist was requested.

The personal-fork UI copy is English. The i18n diff audit still reports new unextracted literals;
no translation baseline was weakened. This is not an upstream localization-ready change.
Android UI is unchanged: these are personal iOS frontend/review features, with no shared
physiological formula, schema or cross-platform backup-whitelist changes.

ImageGen references and exact prompts are stored under `docs/design/` as
`dhoop-sleep-workout-sharing-study.*` and `dhoop-strength-next-workout-study.*`.
