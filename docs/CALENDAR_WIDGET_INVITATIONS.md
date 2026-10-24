# Calendar widget and invitation acceptance

The iOS Home Screen widget displays upcoming events, available organizer identity, and a pending
invitation indicator. Small, medium, and large families are supported. Add it with the iPhone's
Home Screen widget picker after opening Dhoop. Tap an event to open its native details; a widget
tap or deep link can never accept an invitation.

The widget reads a credential-free App Group snapshot. A bounded foreground request prefetches
up to seven dates and up to 100 events per date, at most once per 15 minutes unless explicitly
refreshed. It retains the actual read timestamp, including its date for older reads. Turning off
Calendar reading or widget sharing clears the cache. Missing or partial reads do not become
false empty schedules. Widgets show the last successful read, not a live connection or proof
that the schedule has not changed since. Existing OS execution opportunities and WidgetKit
control refresh timing; there is no background keepalive or recurring network monitor.

Apple references: [Widget updates](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
and [links into the app](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity).

## Invitation details

Event details distinguish Organizer from Created by. Neither is automatically labeled the actual
sender of a forwarded invitation. Only invitation metadata supplied by Life is displayed; older
responses remain readable with acceptance unavailable. Pending status applies to the selected
day's returned events, not an exhaustive invitation inbox.

Accept requires an eligible self-attendee invitation, a strong ETag, an explicitly configured
Accept-only connection, and a direct owner tap. It applies only to the displayed event or dated
recurring occurrence. There is no creation, scheduling, general editing, deletion, decline, or
tentative action in this app. Responses are not queued or retried automatically. Conflicts and
uncertain outcomes require a fresh read before another explicit tap; no optimistic success is
shown. Server readback must identify the requested event and accepted self response.

## Separate activation

Calendar reading remains independent. Acceptance requires new owner access approval before
activation: a dedicated RSVP token and installation UUID, an explicit server flag, one-year
Cloudflare service credentials scoped only to the exact `/calendar-rsvp/accept` and
`/calendar-rsvp/capabilities` paths on `track.kunjadia.dev`, and a separate phone Keychain entry.
The capability probe performs no Google or database write. No Google credentials enter Dhoop
or the widget. The Life contract is `docs/integrations/DHOOP_CALENDAR_INVITATIONS.md` in the
separate Life repository. No real invitation is used for automated write testing.

## Verification

Build 519 passed 55 targeted tests, including six invitation/widget-contract cases and 15 existing
Calendar reader/timeline cases. Scope, ETags, exact three-field request bodies, response ownership,
enrollment capabilities, no automatic conflict retry, safe links, and missing/partial caches are
covered. Both the iOS Release app and macOS shared app compiled. These checks do not prove a real
invitation was accepted, a widget was manually placed on the Home Screen, or physical VoiceOver
and touch interactions were tested.

```sh
Tools/capture-dhoop-calendar-invitation-ui.sh CORE_DEVICE_ID docs/design/calendar-invitation-implementation/NEW_VERSION
Tools/capture-dhoop-sleep-comparison-ui.sh CORE_DEVICE_ID docs/design/sleep-comparison-implementation/NEW_VERSION
```

Both scripts are finite and verify fresh UUID-bound results. Fixtures are synthetic and do not
read owner Calendar credentials, transmit RSVP requests, or publish fake events to the App Group.
Widget captures show the actual shared content component; Home Screen OS chrome is not simulated.

The sleep summary uses the same selected wake date for two concentric duration rings, WHOOP
outside and the selected comparison provider inside. Both use the existing 8h15m goal. Empty
readings keep their ring empty. This changes presentation only, not sleep calculations or sources.
Large text moves duration labels outside the rings to preserve readability.
