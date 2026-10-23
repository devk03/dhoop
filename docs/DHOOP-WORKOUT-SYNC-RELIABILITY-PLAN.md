# Workout sync reliability — 2026-10-23

## Observed failure

Read-only copies from the physical iPhone confirmed build 509, enabled editing, and valid batch
save capabilities. Its queue contains 29 committed commands and one older uncertain `update_set`.
That operation has a negative receipt lookup. A different workout retains five edited sets and
an explicit whole-workout submission, but that submission never reached the frontend command
queue. The older operation blocks `prepare`; foreground draft recovery only follows draft IDs,
so it cannot clear the legacy blocker. The generic retry message does not identify this cause.

Life independently observed no active server fence and identified a matching receipt gap: stale
legacy commands return HTTP 409 without a durable no-effect rejected receipt. A negative lookup
alone is not permission to discard an operation or declare it applied.

## Implementation and verification sequence

1. Reproduce a retained legacy uncertain operation blocking a newer saved workout. Also cover
   receipt lookup failure, a running fence, a wrong receipt identity, and interrupted delivery.
2. Add one bounded shared exact-operation delivery path. Recover attempted operations before
   retrying; retry only prepared or verified not-observed operations with their original bytes.
   Recover a terminal receipt immediately after a conflict response. Never replace operation IDs,
   rewrite frozen revisions, drop drafts, or invent a successful acknowledgement.
3. Recover the older queue operation before preparing a newer explicit workout save. A committed
   or rejected terminal receipt unblocks the queue. Uncertain/running or malformed responses keep
   it blocked and retain input. Handle foreground/relaunch as well as the open workout screen.
4. Show whether the current workout waits for an older change, needs connection recovery, was
   rejected and needs review, or was saved with a verified receipt. Keep local-only edits distinct.
5. Coordinate Life's durable stale rejection for validated legacy actions, retaining HTTP 409,
   original request/hash identity, and zero domain effects. No broad contract rewrite is needed.
6. Run targeted model/client tests and actual native simulator UI scenarios for retained legacy
   saves, interrupted transport, relaunch, and explicit review. Preserve existing local-edit and
   one-batch-save checks. Build the iOS app; check localization and source hygiene.
7. Re-read the physical queue and authenticated Life data with bounded diagnostics. Install a
   signed optimized build with the same bundle/team/Keychain identities after simulator checks.
   Do not mutate real workouts merely to produce evidence. Report any unverified production save
   separately from simulator, HTTP, and read-only physical evidence.

## Constraints

No database migration or reset, no credential export, no WHOOP alarm or BLE changes, no production
fixture workouts, and no infinite retry monitor. Pending immutable submissions and local drafts
remain recoverable. This is the personal iOS Life frontend; Android and upstream NOOP's offline
contract are unchanged.

At audit time the Mac had less than 1 GB free, then could not create a shell temporary file.
Builds require disk headroom; the audit does not authorize erasing owner data to obtain it.

## Current evidence and remaining gates

- Read-only physical inventory confirmed installed build 509. Two small app-data copies showed
  29 committed frontend commands, one uncertain legacy command, and a different workout draft
  with five edited sets and a frozen submission absent from the frontend queue. No database or
  credential was copied, and no production workout was changed for verification.
- Before the fix, the production-shaped regression observed zero receipt lookups and zero POSTs
  for the blocked workout. It failed. After the fix, 30 existing/new model and frontend tests pass.
  These include terminal receipt recovery, a running fence, offline/auth/malformed/wrong-identity
  lookups, removed permission, direct terminal rejection, standalone legacy recovery without a draft, unchanged-target
  preflight, real target conflict, offline preflight, and a rejected newer frozen save that advances
  only after review and an explicit new Save.
- The lightweight harness uses symlinks to production model/client/controller files and the real
  XCTest sources. Only the unused application dashboard reader is stubbed; tests inject their
  own canonical-read closures. This does not verify the app dashboard reader, actual URLSession
  authentication, native rendering, or production mutation. The full app build is still required.
- Lightweight command: `swift test --package-path /private/tmp/dhoop-sync-regression
  --scratch-path /private/tmp/dhoop-sync-regression-build --jobs 2`. Evidence:
  `/private/tmp/dhoop-sync-regression-red.log` and `/private/tmp/dhoop-sync-regression-all.log`.
- Localization and detached-comment gates pass against `d4e3698`; five new status strings have
  all ten existing locales and all older catalog entries are unchanged. Swift syntax parsing and
  `git diff --check` pass. Syntax parsing is not type checking or an app build.
- Life deployed the paired stale-receipt fix in commit `223521f`, Worker version
  `8db4a4f2-b043-465b-86e7-cb71b7507765`. Its rejected legacy operation is retained as an immutable
  no-effect receipt. No new API or database migration is required by the native change.
- Native UI regressions now cover legacy recovery, offline save/relaunch with the same operation,
  and rejected-save review before an explicit replacement. They are **not run**: the user's later
  direct instruction waived simulator checks and requested building/installing on the phone.
  Fixtures are DEBUG/simulator-only and do not access production credentials or create real workouts.
- Release build **510 is built, signed, installed in place, and launched on the physical iPhone**
  “0A-Homeboy.” Fresh device inventory confirms version 11.8.0/build 510. Source: `b76d6a4`.
  Strict deep signature verification passed, with unchanged bundle, team, APNs development,
  Keychain and App Group identities. The actual app compiler command uses `-O`.
- Executable SHA-256:
  `a726b859a920a4e5365641b951107c6540ddfdf5efac1617908ae47892eb25da`.
  Artifact: `/private/tmp/dhoop-510-products/Release-iphoneos/NOOP Staging.app`.
  Build log: `/private/tmp/dhoop-510-direct-device-build-final.log`.
  Signing/install/launch/inventory evidence: `/private/tmp/dhoop-510-signature-proof.json`,
  `/private/tmp/dhoop-510-physical-install.json`, `/private/tmp/dhoop-510-physical-launch.json`,
  and `/private/tmp/dhoop-510-installed-inventory.json`.
- A bounded physical read before and after launch verifies actual startup queue recovery:
  29 committed plus one uncertain operation became 29 committed plus two terminal rejected
  operations, with zero unresolved operations. The legacy operation and the newer stale frozen
  submission both have verified rejected receipts. Every previous operation's immutable bytes
  remain unchanged. The five edited sets and the frozen pending draft remain exactly unchanged.
  Evidence: `/private/tmp/dhoop-510-queue-comparison.json`.
- This verifies installation, retention and terminal receipt recovery; it **does not prove the
  newer workout values were accepted**. The retained stale submission requires review of the
  current Life workout and another explicit Save. No synthetic production workout was created,
  no new Save was clicked, and no replacement operation ID was manufactured.

## Direct build and optional broader checks

Disk headroom increased enough to attempt the existing cached device build. Xcode initially
blocked in macOS file coordination while opening the generated project inside Documents. A
temporary project outside Documents, referring to the same current source and package lock,
resolved that block. Signing then rejected Finder/resource-fork metadata on generated products
inside Documents. Moving only generated products outside Documents resolved signing. No files,
databases or app data were erased, and no entitlements or signing identifiers were weakened.

The successful direct build reused the existing device and package caches:

```bash
xcodebuild -project /private/tmp/dhoop-510-project/Strand.xcodeproj \
  -scheme NOOPiOS -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/devkunjadia/Documents/ChatGPT/Zhoop/build/DhoopDevice \
  -clonedSourcePackagesDirPath /Users/devkunjadia/Documents/ChatGPT/Zhoop/build/DerivedData/SourcePackages \
  -disableAutomaticPackageResolution -parallelizeTargets -jobs 2 \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=8MSX699Z2T \
  BUILD_DIR=/private/tmp/dhoop-510-products build
```

The full app-hosted model tests and simulator UI checks below remain available for broader QA;
the user explicitly waived simulator checks for this installation. They have not been reported
as passing:

```bash
xcodegen generate
xcodebuild -project Strand.xcodeproj -scheme DhoopGoalTests -destination 'platform=macOS' \
  -only-testing:DhoopGoalTests/WorkoutFrontendClientTests \
  -only-testing:DhoopGoalTests/WorkoutSessionDraftTests test
```

Create a separate iOS 26.4 simulator for the UI fixtures; never reuse a simulator containing owner
health data or connection credentials. With its identifier substituted for `ISOLATED_SIMULATOR`:

```bash
xcodebuild -project Strand.xcodeproj -scheme DhoopFlowUITests \
  -destination 'platform=iOS Simulator,id=ISOLATED_SIMULATOR' \
  -only-testing:DhoopFlowUITests/WorkoutDraftUITests test
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release \
  -destination 'generic/platform=iOS' build
```

Inspect the UI test attachments, verify strict signing and unchanged bundle/team/APNs/Keychain
entitlements, then install the signed app in place using `devicectl`. Re-read the two small queue
and draft paths afterward. Distinguish a rejected-but-retained submission from an acknowledged
save. Do not modify real owner workouts merely to satisfy a test.
