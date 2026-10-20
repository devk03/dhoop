# Local owner-data visual review

The DEBUG-only `--owner-data-slice` launch argument writes a new private temporary SQLite
review file and `owner-data-snapshot-proof.json`. The old whole-history export argument is
inactive. This tool reads the source inside one GRDB snapshot and never requests source writes,
checkpoints, migrations, deletion, credential access, or preference copying.

The slice keeps all saved summary/provenance rows and complete stored sleep sessions, including
stage JSON. HR, R–R, steps and battery retain every existing row from the local midnight two
days before the latest stored HR reading through that reading. Missing readings remain missing;
R–R order and imported source identifiers remain unchanged. Other tables retain their existing
schema but no rows. A per-table bound fails the export instead of sampling measurements.

The destination is exclusively created; existing files cannot be overwritten. A ready manifest
is written only after the destination transaction commits and SQLite quick-check succeeds.
An old manifest or an incomplete file is not evidence that a new slice succeeded. Verify the
capture date, ready status, counts and SQLite integrity after transferring the file.

Use a fresh isolated simulator with no Life credentials. The DEBUG simulator argument
`--owner-data-review` suppresses `analyzeRecent` so incomplete raw history cannot rescore genuine
saved aggregates. This is a visual-review fixture, not a complete backup or a production restore.
The regular application and physical-phone analytics are unaffected by that simulator guard.

The regression test verifies source preservation, no overwrite, saved stages/HRV, R–R ordering,
chart gaps, copied indexes, and exclusion of unrelated raw payloads. App builds are also required.
Real-data simulator rendering does not establish live delivery, physiological accuracy, or the
completion of the physical phone's current analysis pass.
