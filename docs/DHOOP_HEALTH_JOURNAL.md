# Dhoop private Health journal

Personal iOS frontend for the owner's existing Life Health journal. The website, MCP and phone read/write the same records. This is an explicitly requested personal-fork integration; it is not an upstream NOOP cloud service. No migration, strap command, physiological inference, diagnosis or automatic photo analysis is added. Android/macOS app parity is intentionally outside this owner-specific iOS frontend; the pure client is tested on macOS.

## Data and privacy

- Canonical endpoint: `https://track.kunjadia.dev/api/integrations/dhoop/health`.
- Dedicated Health bearer, installation UUID and path-scoped Cloudflare service credential; no sleep/protein, calendar, workout or full MCP credentials.
- Keychain service `(bundleIdentifier).health-journal`, account `dedicated-credential`, `WhenUnlockedThisDeviceOnly`. No credentials in source, URL handlers, logs, backups or shared widgets.
- All networking is foreground, ephemeral, cookie/cache-free and refuses every redirect. Reads occur on opening/refreshing the journal; save/upload/retry requires an owner action. No periodic background job or automatic queue replay.
- Original photos are selected through the system picker with current encoding and are never recompressed by the client. Signature, size and SHA256 are checked. Life retains embedded original metadata. Photo bytes are fetched only after selecting that exact photo, with authenticated metadata/digest verification.
- Text-only entries are valid. Photos are optional, up to eight originals/entry, 10 MiB each, JPEG/PNG/WebP/HEIC/HEIF.
- Local drafts and original sidecar files are in Application Support/HealthJournal with complete iOS file protection and backup exclusion. Draft edits persist separately from originals. Existing strap data and backup whitelist are untouched.
- Removing a selected photo from an unsent draft removes its reference; original local files are conservatively retained. This version has no server deletion or local purge command. No existing health record is deleted.

## Save and recovery

Build 531 retries a retained local state write when the app becomes accessible again after a temporary storage failure. This restores the Save action without resending network writes. An unreadable/corrupt archive still blocks overwriting existing bytes.

A draft stores its selected observation timestamp and IANA timezone at compose time. Travel/retry never reassigns dates. Life remains the authority for recordedAt, provenance and versions.

Before a request leaves the phone, the exact JSON bytes/request UUID and installation identity are persisted. Ambiguous failures retry those exact bytes. Notes and each original photo have independent receipts: accepted text or photos are not resent when a remaining upload fails. “Saved to Life” requires all receipts. “Entry saved; photo pending” identifies partial completion. Completed local receipts are retained but not listed as pending drafts.

A 409 retains draft text/photos and blocks automatic replay. For an entry or topic correction, Review shows the latest Life value beside the draft. Continue permits editing against that explicitly reviewed version; another intervening change blocks it again. A different installation cannot receive queued records silently. Credentials for the same canonical endpoint/installation can rotate only after successful authenticated reads.

Timeline pages use stable observation ID deduplication; Refresh resets paging state. Failed reads have explicit errors and do not masquerade as an empty journal. Date filters use each observation's original local date. History paging verifies the observation did not change between pages.

## Connection provisioning

Protected JSON envelope (values supplied outside Git):

```json
{"schemaVersion":1,"endpoint":"https://track.kunjadia.dev/api/integrations/dhoop/health","bearerToken":"<Health-only base64url token>","installationId":"<Health UUID>","accessClientId":"<Health path-scoped ID>","accessClientSecret":"<Health path-scoped secret>"}
```

Import via Health connection, or copy to the app's `tmp/dhoop-health-provisioning.json` and explicitly launch with `--configure-health`. Setup verifies capabilities and a read, then saves/verifies Keychain storage. Only after success is the developer-assisted app-container transfer file replaced with a consumed marker. The interactive file importer reads the selected original without attempting to rewrite a potentially read-only file provider. A safe result file contains status/build only; no owner entry is created during setup. Auth activation is separate from code/build readiness.

## Verification

Run the owning native tests (macOS destination, no simulator):

```sh
xcodebuild -project /private/tmp/dhoop-529-project/Strand.xcodeproj \
  -scheme DhoopGoalTests -destination 'platform=macOS' \
  -derivedDataPath build/DhoopGoalTests \
  -clonedSourcePackagesDirPath build/DerivedData/SourcePackages \
  -disableAutomaticPackageResolution BUILD_DIR=/private/tmp/dhoop-518-test-products \
  -only-testing:DhoopGoalTests/HealthJournalTests test
```

Generate the project from project.yml, then compile the NOOPiOS Release device target. See build-529 readiness for performed results. No tests write synthetic records to the owner's live Health database.

Synthetic implementation screenshot capture is opt-in in `HealthJournalRenderProof`. On an already installed compatible build, launch `--health-journal-render-proof --health-render-run=<fresh UUID>` and copy `tmp/dhoop-health-ui-v1` from the app container. Check result.json build, runId, rendered=true and syntheticOnly=true before labeling screenshots verified. The client uses isolated fixture files and no network/Keychain. This does not authorize installation and no simulator is required. The generated design study under `docs/design/health-journal/concept-v1.png` is a mockup, not an implementation screenshot.

## Navigation

Existing Today (0), Sleep (2), Exercises (5), Alarms (6) and Calendar (7) tags are preserved; Health is 8. Build 530 places Calendar before Alarms to prioritize the main tab bar. Each has its own path and scroll signal. The platform owns tab overflow: on a compact iPhone with a five-item tab limit, Alarms and Health are available through More. Calendar widget requests still select Calendar (7); `--health-journal-open` selects Health. Physical overflow/reselection has not yet been verified on build 529. No existing tab or connection was removed to make room.


## Activation and recovery verification — build 531

The owner approved Health-only activation. Build 530 completed fresh native authenticated capabilities/entries reads, verified Keychain save/readback, and replaced the one-time transfer file with a consumed marker. The same Health installation and original draft queue were preserved through the in-place update to signed build 531. The hardware baseline queue was empty; an additional unsent local draft was retained. Nonempty queue and partial-upload preservation are covered by isolated tests.

A normal build-531 Health relaunch, without the setup flag, produced five independently observed native GET /entries HTTP 200 responses using the persisted credential. The bounded server observation stopped and retained only sanitized route/status/native-agent metadata, not records, headers, photos or credentials. Fifteen native tests passed; the temporary-write recovery regression failed before the fix and passed afterward. Signed device build, stable signing identity, localization and source gates passed. No database/schema migration or synthetic production medical record was used.

Live production entry saving/photo upload and physical picker/layout accessibility checks have not been exercised. Current-session journal rows remain visible on a same-filter refresh failure; changing the filter clears stale rows. The journal page cache is memory-only; durable local drafts and pending original files survive relaunch. Network failures show Retry; authentication failures direct the owner to Health connection for a verified same-installation credential replacement. These checks demonstrate recovery, not a guarantee of uninterrupted network availability.

Life owns service credential rotation. Cloudflare's dashboard displays the dedicated service credential expiry as **November 2, 2027, 01:06 AM in the dashboard's local timezone**; it has not been converted to UTC here. Replace the scoped service credential before that expiry using the protected connection import. Keep the same Health installation and canonical endpoint; verify authenticated reads before Keychain replacement. Retain exact pending request bodies/IDs and original-photo receipts. Do not use full MCP, calendar, workout, sleep or protein credentials as a fallback.
