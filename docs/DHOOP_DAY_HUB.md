# Day Hub: iPhone Home Screen and full-screen overview

The large Home Screen widget combines a calendar window from 90 minutes before to 90 minutes after its displayed time, logged protein and estimated calories, today’s Life strength workout status, and the latest dated WHOOP/8sleep sleep comparison. Tapping the background opens the full-screen overview; event links open the real Calendar details. Food opens the existing inline food logger, and workout/sleep links select their existing tabs. Today also has a Day Hub button.

Apple supports fixed widget families, not an entire-screen third-party Home Screen widget on iPhone. Day Hub uses systemLarge. The full-screen overview is inside Dhoop. Add it from the Home Screen widget picker: Dhoop → Day Hub. Widget placement is an owner-controlled iOS action and is not established by implementation renders.

## Source ownership and dates

- Food uses the same shared ProteinLogStore and legacy Cut food records as the app. It does not create a second food log, require weight tracking, or enable a deficit goal. Missing calories stay unknown, explicit zero stays zero, and totals are recorded estimates rather than complete intake. Food edits publish the local snapshot after a short event debounce.
- Workout reads use the existing Life credential and typed active strength program. Bounded planned/in-progress/completed/skipped reads for today must share one Life revision. No workout is marked done based on a local WHOOP capture or a guessed exercise. Truncated history remains partial. Failed reads retain the actual last successful read; current app status changes request a refresh.
- Sleep uses the same SleepRangeModel, WHOOP source-provenance gates, and provider identity resolver as Sleep. Only an identified Eight Sleep provider receives the 8sleep label. Both durations describe one actual wake date; absent input remains empty. Rings measure duration against the existing 8h15m goal, not a clinical quality score.
- Calendar uses existing read-only Life access and the existing widget-sharing setting. The bounded window fetches both calendar dates when it crosses midnight. Real instants preserve DST and event gaps; clipping affects drawing only. Overlaps have separate lanes, and duplicates across adjacent day reads are removed. Missing or paginated data never implies an empty schedule.

## Refresh and privacy

The extension reads a small credential-free App Group cache and never opens SQLite, reads credentials, polls a server, or starts strap streaming. Widget timeline entries are five minutes apart for six hours; iOS decides actual delivery. Advancing the window does not fetch fresh source data. The overview moves its time window once per minute without a sensor stream.

Dhoop performs bounded foreground refresh opportunities at most every 15 minutes unless explicitly refreshed or the canonical workout status changes. Sleep repository changes are debounced and limited to one local reread per five minutes. Failed network reads retain their dated cache. There is no agent monitor, server cron, or continuous background timer. The view does not promise live server status while iOS suspends the app.

The cache contains only the displayed event titles/organizers, food aggregates, workout titles/statuses, and sleep durations/provenance. No Keychain values, individual food names, R–R records, or raw sensor data enter it. Content is privacySensitive. This personal iPhone feature does not change Android, physiological calculations, database schema, backup contracts, or wake alarms.

Apple references: [Widget families](https://developer.apple.com/documentation/widgetkit/widgetfamily/), [keeping widgets up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

## Verification

Pure tests cover exact three-hour clipping, overlap lanes, midnight cache completeness, cross-day deduplication, DST elapsed time, bounded five-minute entries, day-rollover hiding, and unknown versus zero calories. Existing protein and Calendar contracts run alongside them. App-target builds, real source checks, and synthetic implementation captures are reported separately in the release evidence.

Repeat synthetic native captures with an unlocked paired phone:

```sh
Tools/capture-dhoop-day-hub-ui.sh CORE_DEVICE_ID docs/design/day-hub-implementation/NEW_VERSION
```

The fixtures do not alter owner records or send fake data. Design mockups are labeled separately: [generated study](design/dhoop-day-hub-study.png). Actual Home Screen placement, physical VoiceOver interaction, and new countdown vibrations are not implied by component renders.

## Final implementation review

[Build 524 gallery](design/day-hub-implementation/build-524-v1/README.md) contains the actual
large widget, narrow stress case, light/unavailable states, full overview and accessibility layout.
The plot axes retain a readable bounded size at accessibility settings; the range, event links,
metrics and source details retain Dynamic Type and scroll rather than compress.

A real iPhone read in build 522 populated food, the complete current-day strength snapshot,
both sleep sources, and the complete calendar window; all source read timestamps were within
one minute. This establishes collection/readback, not physiological accuracy, future background
delivery timing, Home Screen placement or a felt vibration. The final build’s installation and
source checks are recorded separately in docs/verification. No fake owner records were written.

## Cold-start sleep cache safeguard

The final restart review found that the producer cleared sleep before its replacement read
completed. Build 525 waits for the repository’s initial refresh, tags the cached sleep with its
database context, and keeps a dated same-context result when a read is unavailable. Switching
to another context does not carry that result over. If Health is locked/unreadable, an already
read Eight Sleep duration can survive only for that same wake date, retaining the earlier read
time. A previous night is never relabeled as the next night. Two targeted regression tests
cover unavailable reads, context changes and partial same-night Health reads. No sleep rows
are changed or deleted. The build-524 UI gallery remains applicable: build 525 changes cache
resolution, with no layout changes.

## Paired dashboard page on iOS 26

Build 526 adds **Day Hub Calendar** (`systemLarge`, four grid rows) and **Day Hub Summary**
(`systemMedium`, two grid rows). Place Calendar above Summary on a dedicated page. Both use
the same credential-free cache, timeline provider and navigation links. The publisher refreshes
all three stable kinds, including the original combined widget, after one source publication.
No additional API polling, source permissions, DB changes or strap commands are introduced.

The large calendar shows its full three-hour plot without the expanded app’s duplicate event
list. The medium summary retains food totals, workout status and the dated two-ring sleep
comparison. Text inside the fixed widget rectangles is bounded; the linked app overview
continues to support larger text and scrolling.

[Build-526 pair gallery](design/day-hub-implementation/build-526-pair-v1/README.md) contains actual
component renders with synthetic data. iOS controls Home Screen placement and Dock behavior;
the app cannot arrange a page or hide the shared Dock. No app icons or Dock items were changed.

A fresh build-526 physical read confirmed food totals, the complete current-day workout
snapshot, both sleep sources and the complete calendar window. The production calorie-goal
read also passed, with calorie summaries enabled. The previous locked-phone readback limit
was resolved for this run. No production test food, goal or workout records were written.

Home Screen automation was attempted with iPhone Mirroring, which reported Mac Bluetooth off.
Placement requires enabling that connection or an owner drag-and-drop action; it is not claimed
as completed by the component screenshots.

## Compact widget redesign (build 527)

The combined widget and matching pair use one Today/date header, whole-hour calendar ticks,
and four flat metric fields. The extra range/sync row, nested backgrounds, compact sleep
rings, repeated workout read time and decorative icons are removed. The full in-app overview
keeps source details, larger text and full-size event links. Estimated calories remain labeled
and missing values remain unavailable; a complete empty workout read says “Not scheduled.”
Older sleep retains its wake date, with WHOOP and 8sleep durations in a consistent order.

The exact ±90-minute window and event instants are unchanged. Only axis labels are rounded
to whole hours; tests cover off-hour windows and both daylight-saving transitions. Event
surfaces cover the red time indicator to keep it clear of title text. No cache schema,
physiological calculation, source refresh or additional network work changed.

[Generated simplification study · demo data](design/dhoop-widget-simple-study.png) is a design
reference, not an implementation screenshot. The implementation retains the vertical day
calendar. Physical captures and installation status are recorded separately; no owner image
or health/calendar data was sent to image generation.

[Build-527 visual review](design/day-hub-implementation/build-527-simple-v1/README.md) includes actual native light/dark, narrow, missing-source, long-title and expanded accessibility captures. Build 527 was installed in place on the physical iPhone; Home Screen placement itself was not changed.
