# Dhoop strength verification

## Software evidence — October 14, 2026

- Build 477: iOS and macOS builds passed. No physical installation of this build has been verified.
- The final iOS artifact was regenerated/built and checked for the stable bundle ID, build number
  and exported `.dhoopworkouts` file type. Generated plist/project files are not committed.
- 66 selected engine and session-recovery tests passed, including session-only exercise order,
  unchanged recorded slots/current timing, undo, notes, source identities and relaunch recovery.
- 18 selected tracker client/transport tests passed, including immutable retries, conflict retention,
  bounded private error handling, local persistence checks and receipt validation.
- The subsequent 13 client tests passed after tightening archive-summary consistency. Companion
  backup tests cover archive round trips, conflicting event IDs, missing files, disabled restoration,
  original bindings and credential exclusion. They do not verify the native Files interface.
- The latest 14 client tests passed after preserving the actual validation reason and full local
  notes when tracker payload preparation fails. The iOS target was rebuilt afterward successfully.

Evidence logs are local development artifacts, not product data:
`/private/tmp/dhoop-strength-reorder-tests.log`,
`/private/tmp/dhoop-tracker-conflict-archive-final-tests.log`,
`/private/tmp/dhoop-tracker-archive-consistency-tests.log`,
`/private/tmp/dhoop-strength-477-ios-build.log`,
`/private/tmp/dhoop-strength-477-macos-build.log`.
The final iOS metadata rebuild is `/private/tmp/dhoop-strength-477-final-metadata-ios-build.log`.
Latest validation evidence: `/private/tmp/dhoop-tracker-validation-reasons-tests.log` and
`/private/tmp/dhoop-strength-477-reviewed-final-ios-build.log`.

## Build 478 replacement evidence

- iOS build and macOS app/test build passed. The 68 selected engine/recovery tests and 32 selected
  tracker/payload/client tests passed. No build 478 physical installation has been verified.
- A synthetic body produced by `WorkoutCapturePayload` was accepted by the Life receiver's actual
  strict schema at local commit `3cb8a0f`. This checks nullable order, explicit observed order and
  replacement lineage. It does not prove a live POST, canonical projection or phone behavior.
- Evidence: `/private/tmp/dhoop-strength-478-ios-build.log`,
  `/private/tmp/dhoop-strength-478-replacement-app-tests.log`,
  `/private/tmp/dhoop-strength-replacement-contract-tests.log` and
  `/private/tmp/dhoop-native-replacement-fixture-tests.log`.

## Build 479 software evidence

- iOS and macOS compile checks passed. The final selected tracker/client tests passed (26), including
  credential-free cached starts, unknown fetch ages, transient errors, blocked prescriptions,
  fresh-read unblocking and restoration of fetch dates/blocks.
- The selected recovery/numeric tests passed (22). The new last-good-snapshot regression failed on
  the previous code because an encoding error deleted recovery data, then passed after the fix.
- A native-generated `planAtStart` payload passed the Life receiver's strict schema in a bounded
  read-only check. No live POST, credential, website mutation or physical collection was tested.
- Logs: `/private/tmp/dhoop-recovery-encoding-before-tests.log`,
  `/private/tmp/dhoop-recovery-479-verified-tests.log`,
  `/private/tmp/dhoop-cached-start-479-final-tests.log`,
  `/private/tmp/dhoop-cached-start-479-final-ios-build.log`.

## Build 480 control evidence

- iOS and macOS builds passed. Sixteen selected protein store/export tests passed, including
  corrupt-source preservation, failed encoding, independent targets and two-instance writes.
- An isolated probe compiled the previous committed store and demonstrated that adding an entry
  overwrote unreadable history. The new store blocks that write and retains the original bytes.
  The probe used its own temporary UserDefaults suite; no user records or production endpoint changed.
- Pairing/history navigation now uses shared feedback/touch targets. Reduced-motion handling was
  added for history date changes/reset. No new pairing/Bluetooth behavior was exercised.
- Logs: `/private/tmp/dhoop-protein-preservation-tests.log`,
  `/private/tmp/dhoop-controls-480-ios-build.log`, `/private/tmp/dhoop-controls-480-macos-build.log`.
- Build 480 has not been installed or visually verified on the physical iPhone.

## Tracker review-comparison foundation

- Twenty-six selected tracker client/transport tests passed. The new cases cover typed endpoint
  absence versus generic 404, changing manifest revisions, capture/manifest revision mismatch,
  read-only comparison and retention of the exact queued intent.
- The comparison makes no POST, cached-plan update, replacement event or activation. Missing capture
  visibility does not establish that an uncertain original event was rejected.
- Test evidence: `/private/tmp/dhoop-tracker-review-comparison-tests.log`.
- The iOS app build passed (`/private/tmp/dhoop-review-comparison-ios-build.log`); the build 480
  artifact retains the stable signing/bundle identity and workout backup file type. Not installed.
- The explicit reviewed replacement-delivery UI/writer remains unfinished. No physical, production
  receiver or physiological verification is implied by these tests.

## Build 481 reviewed recovery

- Forty-six selected manifest/client/delivery/transport tests passed. Reviewed global-only recovery
  retains source revision; a changed prescription creates a higher revision without changing observed
  set values or original start provenance. Preparation sends no POST and stays paused after relaunch.
- Tests reject unknown receipts, changed identity/load mode, changed local/remote snapshots, equal
  or newer server source revisions, workout/occurrence tombstones and repeated preparation. An
  already accepted capture can review a newer local correction with exact original bindings.
- The view uses named StrandDesign tokens and shared action/secondary-button components. Comparison
  columns stack for accessibility Dynamic Type. Runtime gesture, VoiceOver and visual acceptance
  on the physical iPhone remain unverified.
- Evidence: `/private/tmp/dhoop-reviewed-recovery-481-final-tests.log`.
- iOS and macOS builds passed (`/private/tmp/dhoop-reviewed-recovery-481-final-ios-build.log`,
  `/private/tmp/dhoop-reviewed-recovery-481-final-macos-build.log`). The signed build 481 artifact
  retains the stable bundle/team and workout backup file type. It has not been installed.
- The correction test also verifies retaining the accepted reviewed write plan across relaunch and
  later local corrections, independently of immutable start provenance. Ownership disagreement
  between same-revision reads prevents preparation. Source doc-comment hygiene passed.
- History-only correction is not implemented by this path; it never occurs automatically.

## Build 482 shared-action evidence

- Fourteen alarm-manager tests passed, covering explicit save results, corrupt/invalid-state
  preservation, attributed complete versus partial reads, duplicate read rejection, changed links,
  and failed owned-slot readback during explicit retry. Commands were mocked; no physical vibration
  or alarm-storage verification is established by these tests.
- Fourteen workout-review/store tests passed. Five shared action/contrast tests passed, covering
  duplicate taps, actual async failure/retry, cancellation and readable button/switch contrast.
- Activity-review UI now awaits write/readback and distinguishes a saved decision from failed
  history refresh. Sleep/protein manual checks await their bounded pass, preserve failed credential
  input, and keep acceptance tied to dated receipts. Manual network delivery is not tested here.
- Evidence: `/private/tmp/dhoop-alarm-action-completion-tests.log`,
  `/private/tmp/dhoop-workout-review-action-tests.log`, `/private/tmp/dhoop-shared-action-contract-tests.log`.
- Both app builds passed (`/private/tmp/dhoop-action-controls-482-ios-build.log`,
  `/private/tmp/dhoop-action-controls-482-macos-build.log`). Source comment hygiene passed.
- Build 482 has not been installed or physically tested. This is additional control coverage;
  it does not establish completion of the remaining app-wide audit or strength hardware checks.

## Build 483 catalog and routine safety

- Three new catalog-model tests passed: failed-read retention versus actual empty success,
  superseded source reads, and foreign/duplicate row rejection. These test the shared read boundary;
  they do not establish native picker behavior or routine-editor gesture acceptance.
- Full catalog browsing and error/retry states are implemented with shared components. Routine save
  is held after failed line loading, and source identities/drafts are retained. Numeric target
  validation and routine deletion error reporting are additional Apple UI changes.
- Evidence: `/private/tmp/dhoop-catalog-read-safety-tests.log`. Source comment hygiene passed.
- Specific iPhone destination was unavailable. The generic signed iOS and macOS targets were built;
  logs are `/private/tmp/dhoop-catalog-483-final-ios-build.log` and
  `/private/tmp/dhoop-catalog-483-final-macos-build.log`. No installation or strap command was performed.
- No database migration was written or applied. The six-field approval request for variations,
  supersets and persisted pause windows remains pending. The full goal remains incomplete.

## Build 484 previous-performance and alert controls

- Thirteen selected previous-performance/pending-input tests passed. The new cases verify using
  the recorded strap after active selection changes, rejecting foreign rows, preserving typed
  pending values and known carry on read failure, and rejecting late superseded results.
- Twenty-one Meditation session, enrollment and remote-state tests passed. They verify the pure
  state/enrollment boundaries; they do not directly execute the iOS controllers, Keychain import UI,
  notification scheduling, live network requests or physical cues.
- iOS generic-device build passed (`/private/tmp/dhoop-strength-alerts-484-ios-build.log`). The macOS
  app/test host compiled the shared controller/view changes as part of the selected app tests.
- Test logs: `/private/tmp/dhoop-previous-performance-tests.log`,
  `/private/tmp/dhoop-meditation-buzz-state-tests.log`. Source comment hygiene passed.
- No timer was started, credential imported, motor cue sent, wake configuration changed or physical
  installation performed by these checks. Build 484 UI/hardware verification remains outstanding.

## Physical checks still required

1. Install over the existing app with its stable bundle/signing identity. Preserve SQLite and
   pairing. Confirm older workouts and imperial preferences still appear.
2. Create a routine with two exercises. Start it with the original WHOOP connected and perform at
   least three timed sets. Enter weights/repetitions, a warm-up mark and a note. Inspect stored
   readings twice: capture the receipt/stored counts and timestamps at each observation.
3. Move an exercise card while resting. Confirm the current rest deadline, completed set labels,
   notes and numeric inputs remain unchanged. Undo, then move it again and relaunch. The reordered
   sheet and original source IDs must recover without duplicate sets.
   Replace its unfinished sets. Confirm completed original sets/notes remain, the new card gets the
   remaining count and new IDs, and the original rest deadline remains unchanged. Relaunch and undo
   separately; no unperformed original sets may be fabricated at finish.
4. Check native taps, holds, drag-off cancellation, scrolling and chart scrubbing. Check large
   Dynamic Type, VoiceOver labels, Reduce Motion and light/dark contrast on the actual device.
   Check protein add/remove/target success, retained input after failure, and the unchanged one-screen
   logging flow. Check pairing back/close/model choices and history previous/next/reset controls.
5. Separately test background/locked collection and disconnection/reconnection, recording real
   gaps and source identity. Strength pause/resume is still implementation work; it cannot be
   reported as verified from these builds.
6. Edit and delete a historical test session. Confirm unrelated workouts and raw sensor rows remain
   unchanged. Review local persistence separately from any tracker receipt/canonical website update.
7. Export and import a companion metadata package through Files. Confirm the connection remains off,
   no credentials are restored and workout history still requires its separate `.noopbak` backup.
   Check cached plan fetch dates/unknown ages and that a reported invalid plan remains blocked.
   Start a valid cached plan with delivery off; verify there is no read or silent connection activation.

No vibration tests or substitute notifications are permitted during the owner's current quiet
window, ending October 14 at 14:26:57 America/Los_Angeles (21:26:57 UTC). Cues are not queued for
later replay. Wake-alarm configuration is unchanged.

Tracker production activation, dedicated credentials and live-data writes remain separately
unapproved. These checks establish collection/persistence behavior, not physiological accuracy.
