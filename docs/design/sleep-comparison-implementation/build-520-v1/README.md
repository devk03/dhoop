# Combined sleep comparison rings

Actual SwiftUI components rendered on the physical iPhone with build 520, using synthetic data. Each image opens at full size. These are implementation renders, not design mockups or captures of iOS Home Screen chrome.

Repeat: `Tools/capture-dhoop-sleep-comparison-ui.sh CORE_DEVICE_ID docs/design/sleep-comparison-implementation/NEW_VERSION` with an unlocked paired phone. The script is bounded and checks a fresh run identity.

Fixtures use isolated state and no live calendar/nutrition transport or strap writes. They do not establish VoiceOver usability, gestures, actual notification/vibration delivery, or Home Screen placement.

## Dark · 390pt

[![Dark · 390pt](sleep-rings-390.png)](sleep-rings-390.png)

## Narrow · 320pt

[![Narrow · 320pt](sleep-rings-320.png)](sleep-rings-320.png)

## Light · 390pt

[![Light · 390pt](sleep-rings-light.png)](sleep-rings-light.png)

## Missing 8sleep record · 390pt

[![Missing 8sleep record · 390pt](sleep-rings-missing-provider.png)](sleep-rings-missing-provider.png)

## No records · 390pt

[![No records · 390pt](sleep-rings-empty.png)](sleep-rings-empty.png)

## Accessibility Dynamic Type · 390pt

[![Accessibility Dynamic Type · 390pt](sleep-rings-accessibility.png)](sleep-rings-accessibility.png)
