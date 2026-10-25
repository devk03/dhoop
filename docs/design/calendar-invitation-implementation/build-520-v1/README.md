# Calendar invitation and Home Screen widget baseline

Actual SwiftUI components rendered on the physical iPhone with build 520, using synthetic data. Each image opens at full size. These are implementation renders, not design mockups or captures of iOS Home Screen chrome.

Repeat: `Tools/capture-dhoop-calendar-invitation-ui.sh CORE_DEVICE_ID docs/design/calendar-invitation-implementation/NEW_VERSION` with an unlocked paired phone. The script is bounded and checks a fresh run identity.

Fixtures use isolated state and no live calendar/nutrition transport or strap writes. They do not establish VoiceOver usability, gestures, actual notification/vibration delivery, or Home Screen placement.

## Pending invitation · 390pt

[![Pending invitation · 390pt](invitation-pending-390.png)](invitation-pending-390.png)

## Pending invitation · 320pt

[![Pending invitation · 320pt](invitation-pending-320.png)](invitation-pending-320.png)

## Light · 390pt

[![Light · 390pt](invitation-light.png)](invitation-light.png)

## Accessibility Dynamic Type · 390pt

[![Accessibility Dynamic Type · 390pt](invitation-accessibility.png)](invitation-accessibility.png)

## Accepted state · 390pt

[![Accepted state · 390pt](invitation-accepted.png)](invitation-accepted.png)

## Failed accept · 390pt

[![Failed accept · 390pt](invitation-error.png)](invitation-error.png)

## Setup not activated · 390pt

[![Setup not activated · 390pt](invitation-setup-pending.png)](invitation-setup-pending.png)

## Small widget content

[![Small widget content](widget-small.png)](widget-small.png)

## Medium widget content · baseline clipping

[![Medium widget content · baseline clipping](widget-medium.png)](widget-medium.png)

## Large widget content

[![Large widget content](widget-large.png)](widget-large.png)

## Unavailable widget content

[![Unavailable widget content](widget-unavailable.png)](widget-unavailable.png)

The medium widget baseline clipped its footer. A subsequent build constrains intrinsic row height and reduces medium rows to two. RSVP states here are synthetic; live RSVP activation is still pending explicit owner approval.
