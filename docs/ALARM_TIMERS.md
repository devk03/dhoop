# Alarms and countdown timers

The iOS Alarms page offers Alarms and Timers. The main alarm list retains wake times, repeat
labels, enabled state, and the authoritative delivery status. Technical coverage, history, slot
details, and bedtime settings are under the gear. Unresolved alarm-removal warnings stay visible.

Timers support hours/minutes/seconds, quick presets, pause, resume, and cancellation. One durable
countdown is stored separately from wake alarms and health data. A running timer uses the shared
buzz coordinator with an exclusive session owner and a fresh cue identity on resume. Another
exercise can prevent it starting; a wake-alarm window takes priority. Invalid/corrupt saved timer
data is preserved and cannot arm a buzz. Cancellation and pause cancel pending cues.

## Delivery boundary

This is a phone-managed countdown, not a verified strap-side scheduled timer. It sends the
existing reversible WHOOP buzz command and never reads, overwrites, or borrows wake-alarm slots.
The foreground screen stays awake during a running timer. Locked/background delivery is best
effort; suspension, force-quit, Bluetooth loss, and a competing wake alarm can prevent delivery.
Relaunch does not replay an expired timer. Reconnection does not silently re-arm a lost cue:
pause and resume while the same strap is connected.

An optional iPhone notification backup is off by default, labeled separately, and never presented
as a WHOOP vibration. Focus/silent mode and notification permissions still apply. A Bluetooth
acknowledgment is not wearer confirmation. The compact delivery line distinguishes requests,
acknowledgments, unavailability, missed cues, and an explicitly confirmed vibration.

## Verification

Build 519 passed 55 targeted Calendar, timer, wake-alarm, and shared-buzz tests. The timer cases
cover pause/resume timing, duplicate prevention, cancellation, competing owners/wake windows,
disconnect/relaunch behavior, corrupt-file preservation, and foreground screen-awake release.
The iOS Release and macOS app builds passed. No new countdown vibration has been physically
confirmed by the wearer in this change; prior remote-buzz confirmations are separate evidence.

Repeatable native synthetic UI capture:

```sh
Tools/capture-dhoop-alarm-timer-ui.sh CORE_DEVICE_ID docs/design/alarm-timer-implementation/NEW_VERSION
```

The script is bounded, requires an unlocked physical iPhone, and rejects a stale result UUID.
Synthetic controllers cannot transmit BLE or modify owner alarms. The generated design study
is [separate from implementation evidence](design/dhoop-alarm-timer-study.png).
