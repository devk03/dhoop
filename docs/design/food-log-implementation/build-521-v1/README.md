# Food log refinement

Actual SwiftUI components rendered on the physical iPhone with build 521, using synthetic data. Each image opens at full size. These are implementation renders, not design mockups or captures of iOS Home Screen chrome.

Repeat: `Tools/capture-dhoop-food-log-ui.sh CORE_DEVICE_ID docs/design/food-log-implementation/NEW_VERSION` with an unlocked paired phone. The script is bounded and checks a fresh run identity.

Fixtures use isolated state and no live calendar/nutrition transport or strap writes. They do not establish VoiceOver usability, gestures, actual notification/vibration delivery, or Home Screen placement.

## Food · 390pt

[![Food · 390pt](food-390.png)](food-390.png)

## Food · 320pt

[![Food · 320pt](food-320.png)](food-320.png)

## Food · light · 390pt

[![Food · light · 390pt](food-light.png)](food-light.png)

## Accessibility Dynamic Type · 390pt

[![Accessibility Dynamic Type · 390pt](food-accessibility.png)](food-accessibility.png)

## Expanded dated calorie range · 390pt

[![Expanded dated calorie range · 390pt](goal-expanded.png)](goal-expanded.png)

## Unknown calorie estimates · 390pt

[![Unknown calorie estimates · 390pt](calories-unknown.png)](calories-unknown.png)

## Unreadable storage · 390pt

[![Unreadable storage · 390pt](food-storage-error.png)](food-storage-error.png)

This scripted build-521 capture completed with a fresh run identity. Compared with build 520, the 320pt placeholders fit and the expanded goal no longer repeats the current range below its period list. The healthy collapsed editor hides its refresh action.

## Before / after

The preceding [build-520 gallery](../build-520-v1/README.md) is retained for comparison.
