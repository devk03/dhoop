# Alarms and countdown timers

Actual SwiftUI components rendered on the physical iPhone with build 520, using synthetic data. Each image opens at full size. These are implementation renders, not design mockups or captures of iOS Home Screen chrome.

Repeat: `Tools/capture-dhoop-alarm-timer-ui.sh CORE_DEVICE_ID docs/design/alarm-timer-implementation/NEW_VERSION` with an unlocked paired phone. The script is bounded and checks a fresh run identity.

Fixtures use isolated state and no live calendar/nutrition transport or strap writes. They do not establish VoiceOver usability, gestures, actual notification/vibration delivery, or Home Screen placement.

## Alarms · dark · 390pt

[![Alarms · dark · 390pt](alarms-390-dark.png)](alarms-390-dark.png)

## Alarms · narrow · 320pt

[![Alarms · narrow · 320pt](alarms-320-dark.png)](alarms-320-dark.png)

## Alarms · light · 390pt

[![Alarms · light · 390pt](alarms-390-light.png)](alarms-390-light.png)

## No alarms · 390pt

[![No alarms · 390pt](alarms-empty.png)](alarms-empty.png)

## Idle countdown · 390pt

[![Idle countdown · 390pt](timer-idle-390.png)](timer-idle-390.png)

## Idle countdown · 320pt

[![Idle countdown · 320pt](timer-idle-320.png)](timer-idle-320.png)

## Idle countdown · light

[![Idle countdown · light](timer-idle-light.png)](timer-idle-light.png)

## Running countdown · 390pt

[![Running countdown · 390pt](timer-running.png)](timer-running.png)

## Paused countdown · 390pt

[![Paused countdown · 390pt](timer-paused.png)](timer-paused.png)

## Storage error · 390pt

[![Storage error · 390pt](timer-storage-error.png)](timer-storage-error.png)

## Accessibility Dynamic Type · 390pt

[![Accessibility Dynamic Type · 390pt](timer-accessibility.png)](timer-accessibility.png)

## Settings fixture · 390pt

[![Settings fixture · 390pt](alarm-settings.png)](alarm-settings.png)

The settings fixture lacks its normal navigation container; muted navigation rows here do not establish their interactive appearance in the installed app. Countdown delivery is phone-managed; locked/suspended execution is best effort. No wake alarm is borrowed.
