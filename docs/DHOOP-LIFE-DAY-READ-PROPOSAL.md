# Proposal: Life day reader in Dhoop

Status: exploration only, 2026-10-18. No native feature, endpoint, credential, grant or deployment
is created by this proposal. Life remains authoritative; Dhoop does not create a second task store.

## Smallest native surface

Add one **Life day** entry below the health metrics in Today, opening a dismissible navigation
sheet. Keep Today, Sleep, Exercises and Alarms as the four tabs. The entry makes no network request
until opened and does not inherit WHOOP refresh, live-HR or Bluetooth timing.

The sheet has a date selector, **Tasks** and **Events** sections, and an Open Life action.
Show every category by default, with completed tasks in a labelled expandable group. Completion
is a read-only indicator, not a tappable checkbox. Notes remain distinct from tasks and do not
count toward completion. Events show their source, time or Untimed/All day; events never acquire
a completion checkbox. Include social `tracker_events` even when they have no Google link.
Use the existing StrandDesign components, typography, spacing and responsive button styles.

Native seams: `StrandiOS/Cut/CutTodayView.swift` for entry placement; a separate future
`StrandiOS/Life/` reader/sheet. `StrandiOS/App/RootTabView.swift` needs no new tab.

## Connection boundary

Reuse the configured Life origin, installation identity, Keychain storage approach, HTTPS-only
transport, redirect refusal and bounded response/error handling. Do **not** reuse authorization:
the current source/frontend tokens and Cloudflare credential are dedicated to workout routes.
`WorkoutSyncEndpoint` only permits the configured `track.kunjadia.dev` origin and reviewed paths.
Backend aliases must not silently broaden that native allowlist.

A future activation needs an explicitly approved **day:read** grant for the exact new route,
bound to the same installation, with a separate Keychain account. Do not extract existing secrets,
borrow a general MCP token/browser cookie, widen a workout grant, or hide task reads beneath a
workout URL. Existing owner login and Google OAuth credentials stay on Life. The UI can reuse
connection identity without promising that workout-only setup already enables private task reads.

## Proposed read contract — Life to confirm

`GET /api/integrations/dhoop/day?date=YYYY-MM-DD&view=overview&limit=25`

- `view`: `overview`, `tasks`, `calendar`, `events`; only page views accept `cursor`.
- One explicit day in `America/Los_Angeles`; timed instants retain RFC3339 offsets and source zone.
  All-day dates and untimed tracker events remain dates, not invented midnight appointments.
- Overview returns a separate first page for each source, avoiding task pages hiding social or
  calendar events. Each source defaults to 25 items, maximum 50; later pages use its opaque cursor.
  Reject unknown/repeated parameters, invalid dates and mismatched cursor/date/view combinations.
- Envelope: `schemaVersion:1`, `date`, `timeZone`, `fetchedAt`, source sections below.
- Each section: `status` (`ok`, `unavailable`, `not_connected`), `asOf`, opaque `snapshotToken`,
  `items`, `hasMore`, `nextCursor`, and optional exact server `total`. Missing totals are unknown;
  loaded-row counts must not be displayed as full-day totals. Partial upstream reads are explicit.
- Page tokens bind date/view/filters and source snapshot. Changed or expired snapshots return409
  `DAY_SNAPSHOT_CHANGED`; do not append mixed revisions. External Calendar has its own freshness;
  the workout Life revision alone cannot establish a consistent task/event/calendar snapshot.
- Cap the response at128 KiB and bound underlying queries/provider pages. Do not download all
  history or fetch an unbounded Calendar collection before slicing a small native page.

| Item | Required fields |
| --- | --- |
| Task/note | `itemId:string|null`, canonical `ref:string|null`, `kind:task|note`, readable `title`, `done:boolean|null`, `date`, `category:{id,label}`, `calendarLink` or null. Null identity is explicit legacy data; do not mint IDs from titles/positions. Notes have null completion. |
| Tracker event | `id` (canonical UUID), `date`, `title`, `category`, `startTime`/`endTime` or null, `timeZone`, `gcalEventId` or null, `updatedAt`. No `done`. |
| Calendar event | `calendarId`, `eventId`, `title`, `allDay`, timed `startAt`/`endAt` or date bounds, `timeZone`, optional recurrence occurrence identity, explicit linked task/event identity, `localProjection:boolean`. No `done`. |

A task calendar link carries the confirmed event identity/time and scheduling state, not an inferred
title match. Pending local projections stay labelled pending. Deduplicate a linked event's visual
row only by explicit calendar ID/event ID or canonical entity link, retaining both source identities.
Keep unlinked calendar/social items visible. Exclude notes, people, attendees, calendar descriptions,
journal text and health metrics from this minimal payload; titles are already separate from notes.

## Ownership, loading and offline behavior

Life should project its existing day-item extraction/calendar-link resolver, `readEvents` and
Calendar display rules through a dedicated read service shared with web/MCP. Existing `read_day`
contains unrelated health/journal fields; do not pass that whole body to native. The current MCP
`read_calendar_day` fetches `calendarDayEvents` before slicing; review its upstream bound first.
Reads must not reconcile, create default blocks, repair IDs, complete tasks or reschedule anything.

Use one cancellable overview request on open/date change and explicit pull-to-refresh/Load more.
No polling, notifications or background task reader. Preserve the last page, scroll and date on
failure; show per-source failure separately from a successful empty day. Fence responses by
connection generation/date/snapshot. A late reply cannot populate another day or installation.
401/403 pauses reads and offers connection review; Calendar failure must not erase tracker events.

An optional bounded, file-protected cache may retain the last seven explicitly visited days,
partitioned by origin/installation/day, with Last updated and Offline labels. It is a dated read
cache, not an editable queue or a database migration. Disabling/disconnecting clears this feature's
cache; credentials, titles and arbitrary server errors never enter diagnostic logs. Open Life uses
the approved origin and a validated relative route; native never forwards credentials to a browser.

## Implementation acceptance checks — later phase

Verify completed task parity, notes versus tasks, readable category labels, untimed social events,
linked/unlinked Calendar events, all-day/recurring/DST boundaries, pending projections, no identity
guessing, bounded multi-page reads, snapshot conflicts, partial failures, offline cache and late-day
responses. Verify task grants reject workout writes and workout grants reject task reads. Fixture
tests must prove zero task/calendar mutations. Build/install only after implementation is requested;
this documentation-only exploration requires no app build or live owner-data test.
