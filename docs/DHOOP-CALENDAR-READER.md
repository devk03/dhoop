# Personal Life Calendar reader

This explicitly requested personal iOS integration adds a fifth native Calendar tab. Today, Sleep, Exercises and Alarms keep their existing tags/paths. Calendar uses new tag 7; removed legacy tags remain removed. Android, physiological calculations, WHOOP commands and workout delivery are unchanged. There are no database migrations.

## Read-only contract

The reviewed origin is `https://track.kunjadia.dev`. Only GET `/api/integrations/dhoop/calendar/day?date=YYYY-MM-DD[&cursor]` and GET `/api/integrations/dhoop/calendar/event?date&eventId[&taskRef&beforeVersion]` exist in the native endpoint type. URL query values are encoded, redirects/cookies are refused, requests have 12/20-second limits, and responses are bounded below 1 MiB. Calendar has its own bearer, installation UUID and optional dedicated Cloudflare Access credential pair; no workout/export/buzz or Google/Apple credential is reused.

A day retains explicit Pacific dates, timed instants versus exclusive all-day dates, actual Google versus local projection source, and snapshot pagination. Projection rows say Pending sync. Conflicted snapshots restart from page one; malformed pages fail without pretending they prove a Calendar change. Different-day or changed-connection replies cannot become the selected day's contents. Failed refresh retains a matching prior day and labels it stale; an empty day is shown only after a verified complete response. Reads happen on entry, foreground, date change or explicit refresh. There is no polling timer or background Calendar job.

Event context resolves only explicitly linked task refs. A failed linked-task read remains Unavailable, not Unlinked. Full human purpose, original notes and description render as text without sentence/line limits or native rewrites. Agent context expands separately and includes instructions, criteria and safe links. Status and dated accomplishments/next steps are separate; a moved task's current date is distinguished from its historical event date. Owner titles/text are not interpreted as localization keys, HTML or commands. Only HTTPS links and UUID-shaped Codex thread links can open. Older progress pages preserve newest handoff identity and never merge different history versions.

## Provisioning

A dedicated Keychain service `<bundle-id>.calendar-reader`, account `dedicated-credential`, uses WhenUnlockedThisDeviceOnly. A background launch before unlock can recover credentials on the next foreground read without rewriting them.

The explicitly invoked `--configure-calendar` reads app-container `tmp/dhoop-calendar-provisioning.json` (max 8192 bytes):

```json
{"schemaVersion":1,"baseURL":"https://track.kunjadia.dev","installationId":"<dedicated-calendar-UUID>","readToken":"<dedicated-calendar-only-bearer>","accessClientId":"<dedicated-calendar-Access-ID-or-null>","accessClientSecret":"<matching-secret-or-null>"}
```

Real envelopes belong only in private local transfer files, never source, screenshots, chat or app build artifacts. Authenticated candidate day reads precede saving/enabling. Different existing credentials are refused; failed setup preserves prior credentials and transfer contents. Transfer contents are retired only after Keychain read-back and successful authenticated reads. `tmp/dhoop-calendar-connection-result.json` contains status/binding metadata only. Add `--calendar-verification-run=<UUID>` to match a fresh setup/proof run.

`--calendar-reader-proof` runs bounded authenticated day/event GET checks, exporting only counts/status to `tmp/dhoop-calendar-read-proof.json`. `--calendar-reader-open` opens the actual Calendar tab. No Calendar or task mutation is used for verification.

## Visual review

The inspected [imagegen study](design/dhoop-calendar-reader-study.png) is a separately labeled mockup with fictional values, not implementation evidence. Its exact built-in imagegen prompt is [saved separately](design/dhoop-calendar-reader-study.prompt.txt).

`Tools/capture-dhoop-calendar-ui.sh CORE_DEVICE_ID NEW_OUTPUT_DIRECTORY` captures the actual SwiftUI screen implementations through isolated UIKit hosting at 320/390-point phone and 768-point tablet viewports. It includes light/dark, accessibility size, empty, loading, stale/error, task-unavailable and expanded-detail examples. The injected fixtures cannot access credentials or the network. An opaque hosting window prevents owner background content entering captures. Captures show screen content; system tab/navigation chrome and physical gestures are not asserted by these renders. They do not read or seed an owner database.

The capture script uses a fresh run UUID and finite eight-attempt bound; it refuses to overwrite earlier output directories. Images are labeled Implementation/Synthetic data with viewport widths. Store reviewed images under `docs/design/calendar-implementation/` in a versioned folder and link full-size repository images from any UI PR gallery. New Calendar screens have no pre-feature baseline. This iOS feature has no desktop app screen; the separate Life website owns its web gallery.

Actual captures, final signed installation and authenticated production checks remain pending and must be recorded before claiming those outcomes. No UI PR has been opened. The owner requested direct physical installation without simulator checks.

## Current automated verification

Ten focused native contract/client tests pass: endpoint/date/DST/safe-link rules, all-day semantics, snapshot paging, full/empty protected human writing, unavailable links, versioned progress, stale data, connection changes, failed provisioning and unlock recovery. Native iOS Release compilation has passed during implementation; the final artifact is still being verified. Localization adds 42 keys in all ten existing locales while preserving earlier entries. Doc-comment lint and whitespace checks pass. Tests use synthetic data and isolated/injected credentials; no owner task or Calendar event is modified.
