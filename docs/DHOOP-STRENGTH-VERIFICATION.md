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

## Build 485 accepted source-history correction

- Forty-seven selected tracker client, delivery and transport tests passed in
  `/private/tmp/dhoop-history-only-485-final-tests.log`. The new cases exercise the production client
  against bounded synthetic receiver responses: retired capture eligibility without a current
  manifest, prepare versus send, unchanged IDs/observations, source-only receipt recognition,
  rejection of uncertain/legacy attempts, changed identity/provenance, tombstones, newer source data,
  missing captures, changed unrendered evidence and changed SQLite rows.
- Tests also verify a durable attempted marker before transport, blocking a superseded apply,
  duplicate preparation, local pause retention, relaunch, and active/archive backup import without
  treating an old snapshot as proof that the original phone never submitted later. Original bytes
  and archive provenance remain retained. In-memory SQLite fixtures do not migrate the owner's DB.
- The generated reference is `docs/design/dhoop-history-only-review-study.png`, with its built-in
  ImageGen prompt in the adjacent `.prompt.txt`. It contains demo states, not phone screenshots or
  live data. Implementation uses shared tokens/actions, wrapping details and separate preparation
  and sending. Actual Dynamic Type/VoiceOver/gesture quality remains a physical acceptance item.
- Signed generic-device iOS build and macOS app build passed:
  `/private/tmp/dhoop-history-only-485-final-ios-build.log` and
  `/private/tmp/dhoop-history-only-485-final-macos-build.log`. Build 485 retains the stable bundle,
  Loshi signing team and workout metadata document type. It has not been installed on the phone.
- No live Life request, receiver deployment, credential activation, physical app installation,
  WHOOP command or physiological verification was performed for this pass. Full/set/occurrence
  tombstones remain review gates; historical deletion recovery is still separate implementation work.

## Build 486 historical deletion and exact receipt lookup

- Fifty-eight selected native client, delivery and transport tests passed:
  `/private/tmp/dhoop-receipt-lookup-486-final-tests.log`. Full-delete review covers retired routines,
  explicit newer-source review, unchanged physical IDs, minimal patches retaining newer raw data,
  preserved manual fields, current tombstone evidence, missing/foreign source rejection,
  uncertain/legacy attempts, already-tombstoned gating, duplicate preparation, changed remote
  evidence, restored local rows, relaunch and retention of unrelated workouts/sensor samples.
- Read-only lookup tests recover an original receipt after local edits/deletion without ingestion,
  restoring old rows or creating another physical workout. They retain immutable bytes, distinguish
  original/current revisions, keep missing results unknown, reject wrong identity/mappings and false
  reconciliation, preserve earlier positive receipts, and distinguish missing source metadata and
  processed stale events from current acceptance. A recovered positive receipt can unblock a
  previously unprepared local deletion under the same physical UUID. URLSession interception checks
  the actual dedicated POST lookup route and exact body. These are synthetic receiver boundaries.
- Life added the corresponding read-only route locally in `c98ba65`. Its focused route tests forbid
  database writes/lease/reconciliation operations and cover auth, installation, host, size,
  fingerprint conflicts, foreign masking, archived/deleted source, missing metadata and manual
  ownership. Its production Worker build passed; full TypeScript checks retain pre-existing errors.
  No receiver deployment, dedicated credentials or live route call was performed.
- The generated study is `docs/design/dhoop-deletion-receipt-review-study.png`; adjacent `.prompt.txt`
  retains its built-in generation/edit prompts. It contains demo states, not actual device UI/data.
  Controls use shared action tokens and explicit preparation/sending/lookup states. Physical gesture,
  Dynamic Type, VoiceOver, contrast and lifecycle acceptance remain outstanding.
- Signed generic-device iOS build and macOS app build passed:
  `/private/tmp/dhoop-deletion-lookup-486-ios-build.log` and
  `/private/tmp/dhoop-deletion-lookup-486-macos-build.log`. Build 486 retains the stable bundle,
  Loshi team and workout backup document type. It has not been installed on the physical iPhone.
- The subsequent read-only device availability check found `0A-Homeboy` paired, with its developer
  tunnel unavailable (`/private/tmp/dhoop-486-device-availability.json`). No phone launch, strap
  command or container modification was attempted. Availability is not evidence of collection.
- No SQLite migration, owner-data deletion, WHOOP command, motor cue, physiological validation or
  physical app installation occurred in this pass. Definitive cancellation of an unobserved
  in-flight event is not implemented; a negative lookup cannot authorize superseding that event.

## Build 487 settings/control and export safety pass

- Three hostless file-copy tests passed (`/private/tmp/dhoop-settings-copy-487-tests.log`): successful
  save/replacement retains the prepared source, failed source reads retain existing destinations,
  and directories are not replaced by files. Tests use temporary fixtures, not owner data.
- One raw sensor export regression passed (`/private/tmp/dhoop-raw-export-487-tests.log`), checking
  eight successive exports retain distinct paths and their original device values. The same test
  failed against the former second-only filename implementation
  (`/private/tmp/dhoop-raw-export-487-before.log`) and passed after restoration of the fix. Only
  platform-local temporary naming changes; sensor rows/format/schema/physiology are unchanged.
- Three shared action-controller tests passed (`/private/tmp/dhoop-control-actions-487-tests.log`):
  pending duplicate prevention, failure/retry and cancellation without false success. These do not
  directly execute Settings backup dialogs or verify real native picker cancellation/restore.
- Signed generic-device iOS and macOS builds passed:
  `/private/tmp/dhoop-settings-controls-487-ios-build.log` and
  `/private/tmp/dhoop-settings-controls-487-macos-build.log`. Build 487 retains bundle/team/document
  type. It is not installed. Source comment hygiene and diff checks passed.
- Shared feedback uses dimming for rows/cards so their bounds do not scale. Settings backup/export
  controls report the actual asynchronous result, and iPhone labels are full-width instead of
  compressed. The generated `docs/design/dhoop-settings-archive-feedback-study.png` and adjacent
  prompt file contain demo states only. Actual gestures, VoiceOver, Dynamic Type and visual quality
  remain unverified on the physical phone.
- No DB migration, owner backup/restore, live export, phone launch, WHOOP command or motor cue was
  performed. The full controls audit, pause/superset/variation storage awaiting migration approval, and hardware gates
  remain outstanding. Existing physiological calculations, branding and wake configuration remain.
- Next independent control work: avatar/background picker transfers still swallow read/decode
  failures and clear their selection. Pending input, errors/retry and superseded selection reads
  need review before the all-screen controls requirement can be considered complete.

## Build 488 retained image selections

- Six hostless tests passed (`/private/tmp/dhoop-image-selection-488-tests.log`): superseded read
  success/failure, retry after read/commit failure, duplicate prevention and cancellation, invalid
  avatar preservation, background decode/write failure preservation, and unreadable recent presets.
  Fixtures use isolated preference suites and temporary directories. ImageIO diagnostics come from
  deliberately unreadable/truncated fixtures; recovered native images are not rejected solely for
  a warning. Tests do not exercise Photos permission dialogs on the physical phone.
- Both app builds passed: `/private/tmp/dhoop-image-selection-488-ios-build.log` and
  `/private/tmp/dhoop-image-selection-488-macos-build.log`. Signed build 488 retains the stable bundle,
  Loshi team and `com.dhoop.workout-metadata` document type. It is not installed.
- Shared selection generations prevent stale transfers from replacing a newer choice. Failed reads,
  decoding and writes preserve the current image and selected input for explicit retry. Settings
  shows pending, error, retry/cancel and confirmed-success feedback using named design tokens.
  Explicit removal/preset changes cancel pending import before changing the selection.
- The built-in ImageGen demo reference is `docs/design/dhoop-image-import-feedback-study.png`, with
  the exact prompt beside it. Its separate panels illustrate operation states; Settings retains its
  existing inline sections rather than adopting new photo-editing screens. Physical Dynamic Type,
  VoiceOver, picker gestures and visual acceptance remain unverified.
- No migration, owner image import, preference reset, phone launch, strap command or cue occurred.
  The full goal remains active, including approved storage design and physical collection gates.
- Read-only availability check still found `0A-Homeboy` unavailable on the Mac
  (`/private/tmp/dhoop-488-device-availability.json`). No installation or container write was attempted.

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
