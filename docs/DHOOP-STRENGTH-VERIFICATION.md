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

## Build 489 strap-log control pass

- Three hostless preparation tests passed (`/private/tmp/dhoop-log-controls-489-tests.log`):
  successive same-name exports retain exact independent UTF-8 contents; a blocked staging-directory
  write retains the earlier export and blocking file; filenames cannot escape their staging folder.
  Tests use temporary fixtures, not owner logs. They protect preparation, not native picker behavior.
- Signed generic-device iOS and macOS builds passed:
  `/private/tmp/dhoop-log-controls-489-ios-build.log` and
  `/private/tmp/dhoop-log-controls-489-macos-final-build.log`. Build 489 retains stable bundle/team
  and the workout metadata document type. Source comment hygiene and diff checks passed.
- Strap-log controls now use shared action states and full-width wrapping. Preparation creates a
  retained local file; verified saving and native sharing are separate. Pending operations reject
  duplicates. Preparation/read/write failure and cancelled saving preserve the previous prepared
  file. A changed active source during diagnostic reads prevents publishing that mixed snapshot.
- macOS Copy reports the pasteboard setter's actual Boolean result; iOS completes after the native
  setter. These native clipboard/picker actions were compiled but not exercised on the owner's phone.
  Save controls for both prepared logs and CSVs reset when the file URL changes, so success for an
  older file cannot remain attached to a new preparation. Share controls make no completion claim.
- Settings no longer describes connection/full pairing as proof of streaming or persistence, and
  does not promise HR-only sleep staging from an incomplete bond. Data collection remains the place
  to inspect actual counts/freshness. No decoder, analytic formula or numeric data changed.
- Built-in ImageGen reference `docs/design/dhoop-strap-log-controls-study.png` and adjacent exact
  prompt show demo states. Implementation keeps native error/save dialogs; the reference's inline
  error is illustrative. Physical picker cancellation, Dynamic Type, VoiceOver, gestures and visual
  acceptance remain outstanding. This is an Apple Settings UX change; no Android storage contract changed.
- No migration, owner log export, clipboard write, phone launch/installation, WHOOP command or cue
  was executed by tooling. The full goal remains active, with storage approval and hardware gates pending.

## Build 490 exercise operation controls

- Thirteen existing hostless storage/export tests passed
  (`/private/tmp/dhoop-exercise-controls-490-tests.log`): one complete raw archive round-trip,
  seven interval file-store tests and five Zone 2 storage tests. They cover failure retention,
  scoped deletion, committed archives with cleanup warnings and original record preservation.
  They do not directly exercise UIKit controllers or native save/share pickers.
- Signed generic-device iOS and macOS builds passed:
  `/private/tmp/dhoop-exercise-controls-490-ios-build.log` and
  `/private/tmp/dhoop-exercise-controls-490-macos-build.log`. Stable bundle/team/document type
  remain. Build 490 is not installed. Source comment hygiene and diff checks passed.
- Zone 2, HIIT and interval saves expose typed shared pending/success/failure state from the existing
  controller operation. Labels retain their footprint while saving. Failed storage keeps the paused
  session for retry; a committed archive with a draft-cleanup warning is still correctly reported
  as saved. Zone 2 retains explicit early-end versus completed-goal labels and does not mark an early
  end as goal attainment. Stored timing, HR, ownership and vibration behavior are unchanged.
- Exercise history export uses full-width shared controls and separate prepare/save/share actions.
  Preparing again preserves the earlier file until success. Failed deletion also retains that copy;
  successful deletion invalidates it. Export/save/deletion operations are mutually gated. Save feedback
  resets per file, and the prepared timestamp uses the same capture instant encoded in the JSON.
  No in-app restore or receiver/production synchronization is added.
- Built-in ImageGen reference `docs/design/dhoop-exercise-operation-controls-study.png` and adjacent
  original/correction prompts contain fictional states. The correction removes invented tabs and
  makes the retained earlier export available after failed preparation. Charts/numbers in the study
  are not implemented as data. Physical accessibility, gestures and visual acceptance remain unverified.
- No migration, owner export, storage deletion, clipboard write, phone launch/installation, WHOOP
  command or cue was performed by tooling. Apple presentation/operation states changed; stored data
  format, physiological formulas and Android schema remain unchanged. The full goal remains active.
- Next concrete controls audit: Settings alternate-icon changes still need serialization/readback
  review, and its update-check label changes while pending rather than using the shared reserved state.

## Build 491 icon choices and update check

- Four hostless icon-selection tests passed (`/private/tmp/dhoop-settings-icon-491-tests.log`):
  failed native change retains the requested choice for retry, a competing pending choice cannot
  replace it, completion without matching readback cannot claim application, and already-applied/
  unsupported choices issue no system write. Isolated defaults and a simulated native service prove
  controller behavior; they do not prove actual iOS Home Screen rendering or native dialog behavior.
- Signed generic-device iOS and final macOS builds passed:
  `/private/tmp/dhoop-settings-icon-491-ios-build.log` and
  `/private/tmp/dhoop-settings-icon-491-macos-final-build.log`. Build 491 retains stable bundle/team/
  document type and is not installed. Diff and source comment hygiene checks passed.
- Settings separates requested icon choice from last-confirmed system icon, disables concurrent
  choices, retains failures for explicit retry/keep-current, and stores the existing `appIcon.alt`
  preference only from confirmed system state. A native setter error no longer blindly inverts a draft.
  The same assets and identifier remain; unsupported installations show an explicit explanation.
- The update-check control uses the shared reserved state region and unchanged label; results are
  below a full-width control instead of competing in a narrow horizontal row. A successful read is
  not an installation. The existing endpoint/checker/automatic-check behavior is unchanged; tooling
  did not issue a release-network request or install an update.
- Built-in ImageGen reference `docs/design/dhoop-settings-icon-update-study.png` and adjacent prompts
  illustrate fictional requested/confirmed and read states. The result inset is a state illustration,
  not a new UI card or a second installed-version authority. Actual device accessibility, gestures,
  native icon confirmation and visual acceptance remain outstanding.
- No migration, owner preference mutation, actual icon setter, phone launch/installation, strap
  command or cue ran in tooling. This Apple UI state change does not change Android stored data or
  physiological formulas. The full goal remains active.
- Remaining concrete source findings: OnboardingWizard still has private primary/secondary styles
  with independent hardcoded press motion and plain Back/disclosure buttons. The notification-step
  permission callback needs a pending/navigation gate so repeated taps cannot advance twice.

## Build 492 onboarding controls and permission navigation

- Three hostless gate tests passed (`/private/tmp/dhoop-onboarding-controls-492-tests.log`): duplicate
  requests/completions advance one page only, changed-page completion does not advance, and a stale
  callback cannot consume a newer request after invalidation. These exercise the pure gate, not an
  actual system permission prompt or the complete SwiftUI onboarding runtime.
- Signed generic-device iOS and macOS builds passed:
  `/private/tmp/dhoop-onboarding-controls-492-ios-verified-build.log` and
  `/private/tmp/dhoop-onboarding-controls-492-macos-verified-build.log`. Bundle/team/document type
  remain stable. Diff/comment hygiene passed. Build 492 has not been installed.
- Notification continuation is gated by original page/request ID; Back and repeated Continue are
  disabled while pending. Disappearance invalidates the request, and Finish cannot invoke its owner
  twice. Existing consent behavior is preserved: denial does not prevent onboarding completion,
  and per-feature switches still handle permission denial.
- Primary, secondary, scan/import, Back and disclosure controls use shared StrandDesign feedback.
  Labels retain their footprint while pending; Back/disclosure hit areas are at least 44 points.
  Onboarding page/disclosure transitions respect system/in-app reduced-motion preferences.
- Import selection retains its URL/type for explicit retry after failure. Picker failures are shown;
  cancelling another-source chooser preserves the earlier retry context. An active chooser/import
  blocks competing imports and navigation, without observing fast HR updates at the wizard root.
  Failed optional imports may still be skipped. File permissions on a real device and late native
  picker callbacks remain unverified; a retained URL is not proof that access will remain available.
- Import completion is separate from metric availability. Importers, stored rows, units and their
  existing typed outcome reporting are unchanged. No import/permission request was run by tooling.
- Built-in ImageGen reference `docs/design/dhoop-onboarding-operation-controls-study.png` and all
  prompts beside it contain fictional states. Corrections keep Continue enabled after optional
  failure, hide retry during import and disable the competing source. The existing scrollable
  onboarding shell remains; this is not a new layout or an actual permission/data screenshot.
- Read-only availability again reports `0A-Homeboy` unavailable
  (`/private/tmp/dhoop-492-device-availability.json`). No installation, phone launch, strap command,
  motor cue, owner-data mutation or migration occurred. The full goal remains active.
- Next scoped review: alarm-detail custom navigation/destructive controls and root tab transition
  motion. The add-device wizard already uses shared primary/row feedback in the inspected paths.

## Build 493 local alarm results and reduced-motion shell

- Sixteen alarm-manager tests passed (`/private/tmp/dhoop-alarm-controls-493-tests.log`). New
  fixture cases cover failed toggle/delete/skip/report writes preserving state and original bytes,
  idempotent local deletion, and wearer reports requiring the known past occurrence. Mocked offline
  links execute no strap commands in those failure cases; this is not a physical alarm test.
- Signed generic-device iOS and macOS builds passed:
  `/private/tmp/dhoop-alarm-controls-493-ios-build.log` and
  `/private/tmp/dhoop-alarm-controls-493-macos-build.log`. Stable bundle/team/document type remain;
  build 493 is not installed. Source comment/diff hygiene passed.
- Local alarm mutators expose their actual save result. Native deletion/menu failures are surfaced;
  skip/report controls use shared async feedback. Their success means local metadata was saved,
  not that WHOOP cleared an alarm or the wearer felt a motor cue. Existing exact slot ownership,
  wake preservation and readback scheduling are unchanged.
- Alarm-detail destructive/navigation and export controls use shared feedback. Wearer-report buttons
  stack at accessibility Dynamic Type. Native confirmation dialogs remain. The iOS tab crossfade and
  Strength session-bar transition respect system/in-app reduced-motion preferences.
- Built-in ImageGen reference `docs/design/dhoop-alarm-local-action-study.png` and adjacent prompts
  show fictional states only. Repeat captions were corrected to one readout. Actual interface
  accessibility/gestures/native dialogs and hardware behavior remain unverified.
- `docs/DHOOP-GOAL-COMPLETION-AUDIT.md` records each full requirement and its acceptance gap. Some
  history-detail session/workout/previous-volume reads still swallow failures into fallbacks;
  they require correction. Superset/variation/true pause storage still awaits the five-field approval.
- No migration, owner alarm edit/delete/report, phone launch/installation, strap command, cue,
  production update or physiological validation was performed by tooling. The full goal is incomplete.

## Build 494 coherent strength detail reads

- Four WhoopStore detail tests passed (`/private/tmp/dhoop-detail-snapshot-494-store-tests.log`):
  current whole-session metadata and paired workout/prior sets, missing versus valid empty,
  query failure versus partial/empty detail, and rejection of foreign set attribution. All fixtures
  are in-memory; a temporary query shadow preserves the real table, and no owner DB/schema changed.
- Four hostless detail-model tests passed (`/private/tmp/dhoop-detail-snapshot-494-model-tests.log`):
  failed-refresh retention with fresh-authority blocking, actual missing-result clearing, identity
  rejection, and superseded success/failure. Twenty-two existing workout/journal/cache tests passed
  (`/private/tmp/dhoop-detail-snapshot-494-workout-decoder-tests.log`) after sharing the same decoder.
- Signed generic-device iOS and macOS builds passed:
  `/private/tmp/dhoop-detail-snapshot-494-ios-build.log` and
  `/private/tmp/dhoop-detail-snapshot-494-macos-build.log`. Stable bundle/team/document type remain;
  build 494 is not installed. Diff/comment hygiene passed.
- One read transaction provides session, sets, exact paired workout and prior exercise rows. Errors
  throw instead of becoming missing workout/previous history. The full current session row supplies
  metadata and the editor, including corrected/cleared RPE and notes. Metric formulas and stored
  values are unchanged; this read API serves Apple UI and does not change Android storage contracts.
- Failed refresh retains a dated last-confirmed view; edit/delete require a fresh successful read.
  Actual missing results clear the old display without creating a replacement. Late results cannot
  replace newer reads. HR publication is tied to the successful detail-read ticket and recorded strap;
  pending reads are distinct from no measured data. HR windows remain half-open and unsmoothed.
- Built-in ImageGen reference `docs/design/dhoop-history-detail-read-study.png` and its prompts show
  fictional data. An edit removes invented Health/Watch provenance. Native visual/accessibility,
  real failure/retry behavior and physical sensor-data acceptance remain unverified.
- No migration, owner data edit/delete, active collection, phone installation/launch, motor cue,
  production activation or physiological validation occurred. Native phase/superset/variation storage
  still requires approval. The full goal remains incomplete.

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

### Approved phase/group/variation storage — October 14, 2026

The owner explicitly approved the reviewed five nullable columns before implementation. GRDB v47
and Room 40→41 append the same fields in matching table order. The shared schema oracle advances
with them. Legacy values remain NULL, without inference or backfill. SQLite backups include these
columns as part of the database; optional Codable row fields retain compatibility with older metadata.
The Apple backup manifest's previously stale schema marker now identifies v47. No owner database or
physical phone has been opened or migrated by these isolated test runs.

Storage verification: 53 existing lifting/detail/schema tests passed before the new fixtures;
15 metadata/schema/provenance tests then passed in
`/private/tmp/dhoop-lift-phase-metadata-tests.log`. Android schema oracle, migration-chain and
legacy-entity tests passed with full-module compilation in
`/private/tmp/dhoop-lift-phase-android-schema-tests.log`. The Swift upgrade fixture starts at v46,
seeds existing exercises, targets, sessions, sets and raw HR, applies v47 twice and checks preservation
and NULL metadata. Round trips cover all five new values and independent parent/variation history.
These are software checks, not phone migration, collection or wearer evidence.
