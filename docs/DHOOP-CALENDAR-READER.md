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

Build 514 is installed and launched on the physical iPhone. The reviewed [actual implementation gallery](design/calendar-implementation/build-514-v1/README.md) uses fictional data only. Fresh production verification is recorded below. No UI PR has been opened. The owner requested direct physical installation without simulator checks.

## Current automated verification

Ten focused native contract/client tests pass: endpoint/date/DST/safe-link rules, all-day semantics, snapshot paging, full/empty protected human writing, unavailable links, versioned progress, stale data, connection changes, failed provisioning and unlock recovery. Native iOS Release compilation has passed during implementation; the final signed Release artifact passed strict signature and stable identity checks and was installed in place. Localization adds 42 keys in all ten existing locales while preserving earlier entries. Doc-comment lint and whitespace checks pass. Tests use synthetic data and isolated/injected credentials; no owner task or Calendar event is modified.

## Physical installation and production evidence — build 514

On October 23, 2026, signed Release build 514 from source `bdbddce` was installed in place on the physical iPhone and launched. Executable SHA-256: `0089bf0ff3ef33165cbf3720688dd978e31cbe09406e944eb29f02874b10cad8`. Bundle, team, Keychain access group, App Group and development APNs entitlement were preserved. No uninstall or database migration occurred.

A fresh UUID-bound phone check returned `connected_authenticated_day_read`, followed by `authenticated_day_verified` for Pacific October 23 at `2026-10-24T04:43:13Z`: six events, no remaining page, event detail verified, one linked task available. No human-authored description was present in that sampled task; that production case is not claimed. `writesAttempted` was false. The dedicated Calendar credential was verified in its separate Keychain service before transfer contents were replaced with a consumed marker. The existing native `DhoopCalendar/1.0` user agent worked unchanged.

Life independently reported production day/detail success, rejection of incorrect bearer/installation/Access credentials, rejection of all write verbs, and denial of workout/tracker/MCP access through this credential. Activated Worker version: `8db74529-7a9f-4190-937c-50bafd50b9ae`. No Calendar/task writes were used to verify setup.

The before/after workout frontend file and both draft files were byte-identical: all 33 operation records retained (31 committed, two rejected), plus seven local edits in session 284 and the zero-edit draft for session 287. This checks the affected queue/drafts; it does not constitute a full database audit. After synthetic capture, the app was relaunched normally on Calendar with no provisioning/render/proof flags.

Twelve actual screen-content renders were inspected, including narrow phone, light/dark, tablet width, accessibility, task detail, loading, empty, stale/error and unavailable states. These are native implementation renders at specified point widths, produced on the physical phone with injected fictional fixtures. They do not prove gestures, VoiceOver behavior or system navigation chrome; those were not physically tested in this installation pass. No simulator checks ran, as requested. The annotation strip is imperfect in the light/tall/tablet captures; the gallery labels every image explicitly. No private Calendar text or credentials are published.

## Day timeline — build 515

The Calendar tab now uses a single-day time grid instead of agenda cards. Hour labels use the same Pacific clock as the selected day. Timed blocks are proportional to their actual durations and retain their full event identity for the existing detail sheet. All-day items stay separate above the scrolling grid. Overlapping events get separate lanes, including expanded minimum hit areas for very short events; their displayed times and stored durations remain unchanged. Dense schedules can scroll horizontally so targets do not collapse below readable widths.

The current-time line updates once per minute only within the displayed current day, without a network refresh or scroll jump. Entry focuses near the current hour for today or the first event for another day; Today returns to the current date and hour. Refresh preserves scroll position. Midnight-crossing events are clipped to the visible day; 23/25-hour Pacific daylight-saving days retain actual instants and disambiguated hour labels. Read-only transport, permissions, Keychain identity, linked-task access and full notes are preserved. No database migrations or WHOOP commands are involved. This is the personal iOS Calendar reader; there is no Android twin of the integration.

The built-in imagegen [timeline design study](design/dhoop-calendar-day-timeline-study.png) and its [exact prompt](design/dhoop-calendar-day-timeline-study.prompt.txt) are fictional design references. Actual implementation captures and final device evidence for build 515 are recorded after verification. Five targeted geometry tests passed along with the ten existing Calendar client/contract tests. They cover overlap lane reuse, short-event touch footprints, midnight clipping, exclusive all-day end dates, and Pacific daylight-saving/current-time boundaries.
