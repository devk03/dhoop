# WHOOP cue delivery on Apple platforms

Dhoop routes notification-waveform requests through `BuzzDeliveryCoordinator`, owned by
`BLEManager`. This is an app-side scheduler and durable delivery ledger, not a firmware scheduler.
It does not modify health tables or borrow wake alarms. Android's existing delivery implementation
is unchanged; the added read-only alarm payload helper has a byte-identical Kotlin twin.

## Delivery contract

- App-scheduled, command requested, response received, successful command acknowledgment, and
  wearer-confirmed vibration are separate states. GATT write completion is not motor evidence.
- WHOOP 5 opcode 19 success additionally requires the documented final response detail 5.
  Pending, failure, and unknown responses are not promoted to successful acknowledgment.
- Requests are committed before transmission. A crash in the intervening window can miss a cue;
  it cannot safely be retried because the protocol provides no idempotent motor operation.
- Responses must match the device, connection, opcode, origin sequence, and a five-second window.
  Reuse of a sequence invalidates the earlier pending match.
- Session-owned schedules cancel on pause, change, cancellation, and disconnection. Expired or
  disconnected cues do not replay on reconnect. A transmitted one-shot cannot be recalled reliably
  on WHOOP 5; no unverified stop command is introduced.
- Restored future requests wait for their feature to revalidate them. HIIT and Zone 2 restore paused.
  Meditation can revalidate its persisted future deadline. Already-requested cues never replay.
- Explicit exercise ownership suppresses competing ambient cues. Overlapping requests within 250 ms
  are recorded as suppressed instead of stacking indistinguishable motor commands.
- Sensor cues require fresh receipt evidence. Zone 2 and ambient coaching reject readings older than
  two seconds. Ambient coaching has a thirty-second cooldown and yields to an exercise session.
- Ledger and meditation files use atomic writes and, on iOS, protection available after first unlock.
  Corrupt storage fails closed and offers retry; no existing file is silently replaced.

## Execution matrix

| Feature | Foreground | Background / phone locked | Suspended | Force-quit |
|---|---|---|---|---|
| Meditation completion | App deadline and shared scheduler | Best effort on Bluetooth execution or app timer | No guaranteed deadline execution; explicitly labeled iPhone notification fallback if authorized | No app-driven WHOOP cue; existing system notification may remain |
| HIIT / intervals | Absolute phase deadlines; only next transition pending | HR receipts also service timing; missed boundary pauses rather than replaying late transitions | Cannot guarantee transitions; resumes paused when a deadline was missed | No app-driven cue; session restores paused |
| Zone 2 | Fresh receipt-driven zone alerts | Same receipt logic when Core Bluetooth provides execution | No fresh callback means no new alert; stale samples never count | No app-driven alert; session restores paused |
| Legacy intervals / breathing | Shared transport; foreground pacing | Execution gaps pause/stop rather than send stale pacing | Not supported as a precise suspended timer | No app-driven cue |
| Biofeedback / live-session coaching | Cancellable, expiring pulse schedules | Best effort; calming rejects stale HR and delayed callbacks | No continuous pacing guarantee | Pending schedules require owner revalidation |
| Lift rest warning | Existing session timer, bounded to the rest window | Best effort; warning suppressed after rest ended | No exact-time guarantee | No app-driven warning |
| Haptic clock | Bounded pulse schedule | Best effort, expiry enforced | Missed pulses are not replayed | No app-driven clock pulses |
| Inactivity, stress, user gestures, notification mirrors | Existing preference/physiology gates plus shared delivery | Only when the corresponding event grants execution | No independent timer guarantee | No app-driven cue |
| Existing wake alarm | Existing configuration retained | Firmware behavior is separate from app execution | WHOOP 5 physical execution remains unverified | Do not infer success from SET acknowledgment |

Core Bluetooth background mode permits execution for Bluetooth events, not continuous arbitrary
work. State restoration can relaunch after some system terminations, but not normally after a user
force-quits. Sources: [Apple background processing guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
and [TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).

## Firmware alarm boundary

[Protocol notes](PROTOCOL_ALARMS.md#whoop-5mg-alarms) describe six WHOOP 5 IDs, one-shot due
processing, and possible supersession when several slots are due together. This is not hardware
verification of multi-cue workouts. Safe readback/restoration, exact timing, repeated transitions,
and wearer-perceived patterns remain unverified on the user's device. GET may return zeros after
failure, so zeros are not evidence of a free slot.

The alert panel can issue only GET revision 4 for IDs 1–6 and display attributed raw responses.
It performs no SET, DISABLE, or RUN. No experimental workout alarm is armed. The WHOOP 5 manual
buzz no longer issues RUN_ALARM, which can clear a stored alarm. WHOOP 4 retains its previously
verified manual-buzz sequence; that behavior has not been revalidated during this change.

## Physical verification: pending

The user deferred hardware testing. Compilation, unit tests, and command responses cannot close
this checklist. On the actual WHOOP 5 and iPhone, record firmware, time, feature/session, app state,
request/response result, and the wearer's yes/no vibration confirmation for each case:

1. Read the six alarm slots without changing them; retain raw responses and existing wake settings.
2. Manual buzz foreground, background and locked. Do not infer the last two from foreground success.
3. Full meditation completion foreground and locked, pause/resume and cancel before completion.
4. At least three consecutive HIIT transitions and three interval-workout transitions while locked.
5. Zone 2 below/above crossings using real fresh readings; stale data must not create alerts.
6. Disconnect before a cue, reconnect afterward, and confirm no stale cue replay. Resume explicitly.
7. Cancel/change an active session and wait beyond the former deadline; confirm no later cue.
8. Force-quit and wait through a deadline. Confirm the documented absence of app-driven strap cues
   and separately record any phone notification. Relaunch must not replay missed buzzes.
9. Re-read alarm slots and confirm wake-alarm configuration was preserved.

Strap-side scheduling experiments require a separately reviewed preservation plan and verified
readback, or explicit approval of the exact alarm tradeoff. No such write is included here.
