# Local Life sync diagnostics

WHOOP history collection, local sleep analysis, and delivery to Life are separate stages. A successful
Bluetooth connection or a tap on WHOOP Sync does not prove that Life received a summary. A never-logged
protein day has no total to export; it must not become an invented zero. Sleep uses the wake date;
Life assigns it to the preceding journal date. Protein retains its consumption date. Export eligibility
uses Life's Pacific calendar regardless of the phone's current location.

## Explicit support capture

Build 532 adds an opt-in local capture available in signed iOS builds. Build 533 aligns protein
candidate comparison with the enabled calorie-export setting and includes the existing sync error
message. Build 532's protein-candidate list can incorrectly report differences when calorie export is
enabled; do not use that list as evidence of a backlog. Normal launches return without
collecting a report. It records counts, source-frontier dates, analysis readiness and delivery status,
without health measurements or credentials. Reports still contain private activity dates and event
identifiers: retain them locally and do not publish them.

Use a new UUID for each invocation. The iPhone must be unlocked for a development launch. Substitute
the paired device identifier and UUID below:

```sh
xcrun devicectl device process launch --device DEVICE --timeout 35 \
  com.devkunjadia.zhoop.loshi.noop \
  --life-sync-readiness --life-sync-readiness-run=UUID
```

Apply launch arguments to a new process. If Dhoop is already running, a support operator may need
`--terminate-existing`; first check that doing so will not interrupt an active history download.
An optional `--life-sync-request-strap-sync` invokes the existing guarded manual Sync action once,
then captures a second report after fifteen seconds. It does not introduce a reconnect, pairing reset,
new strap command, or direct Life POST. If disconnected or unbonded, the existing manual action can
defer/ignore the sync; a requested sync is not a completed sync.

Read each file through the app data container using `devicectl device copy from`:

- `tmp/life-sync-readiness-UUID-before.json`
- `tmp/life-sync-readiness-UUID-after.json` (only when manual sync was requested)

UUID filenames use Foundation's uppercase UUID representation. Validate the report's run ID, build,
phase and capture time before interpreting it. The unversioned `tmp/life-sync-readiness-proof.json`
is only the most recent capture and is insufficient to establish a fresh run.

## Interpretation

- Separate connected, bonded, history-ready, backfilling and last successful sync. A pending
  reconnect is not evidence of incoming data.
- `latestStored*HRorOpticalAt` includes measured HR **or optical estimates**; it does not prove a
  new measured-HR sample. The labeled today counts distinguish stored measured HR and usable R–R.
- Source resolution can change during a read. If `activeSourceChangedDuringRead` is true, do not
  attribute the entire report to one active source. Union frontier dates are explicitly separate.
- Sleep candidates use the same before/after analysis-readiness fence as production export.
  Raw data present does not imply that a completed sleep estimate exists or is ready to export.
- `lifeSummaryDeliveryInvoked` is false: this helper does not itself send summaries. Ordinary
  automatic export can run independently. A candidate or local status does not prove receipt;
  verify the matching metric, date, event/revision and validated receiver acknowledgement.
- Cached widget state and old checkpoint dates are historical evidence, not a live connection check.

This is iOS-specific support tooling. It changes no analytics formula, stored physiological value,
database schema, credentials, alarm state or cross-platform backup contract.
