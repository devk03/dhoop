# Dhoop strength verification

## Software evidence — October 14, 2026

- Build 477: iOS and macOS builds passed. No physical installation of this build has been verified.
- The final iOS artifact was regenerated/built and checked for the stable bundle ID, build number
  and exported `.dhoopworkouts` file type. Generated plist/project files are not committed.
- 66 selected engine and session-recovery tests passed, including session-only exercise order,
  unchanged recorded slots/current timing, undo, notes, source identities and relaunch recovery.
- 18 selected tracker client/transport tests passed, including immutable retries, conflict retention,
  bounded private error handling, local persistence checks and receipt validation.
- The subsequent 13 client tests passed after tightening archive-summary consistency. Companion
  backup tests cover archive round trips, conflicting event IDs, missing files, disabled restoration,
  original bindings and credential exclusion. They do not verify the native Files interface.

Evidence logs are local development artifacts, not product data:
`/private/tmp/dhoop-strength-reorder-tests.log`,
`/private/tmp/dhoop-tracker-conflict-archive-final-tests.log`,
`/private/tmp/dhoop-tracker-archive-consistency-tests.log`,
`/private/tmp/dhoop-strength-477-ios-build.log`,
`/private/tmp/dhoop-strength-477-macos-build.log`.
The final iOS metadata rebuild is `/private/tmp/dhoop-strength-477-final-metadata-ios-build.log`.

## Physical checks still required

1. Install over the existing app with its stable bundle/signing identity. Preserve SQLite and
   pairing. Confirm older workouts and imperial preferences still appear.
2. Create a routine with two exercises. Start it with the original WHOOP connected and perform at
   least three timed sets. Enter weights/repetitions, a warm-up mark and a note. Inspect stored
   readings twice: capture the receipt/stored counts and timestamps at each observation.
3. Move an exercise card while resting. Confirm the current rest deadline, completed set labels,
   notes and numeric inputs remain unchanged. Undo, then move it again and relaunch. The reordered
   sheet and original source IDs must recover without duplicate sets.
4. Check native taps, holds, drag-off cancellation, scrolling and chart scrubbing. Check large
   Dynamic Type, VoiceOver labels, Reduce Motion and light/dark contrast on the actual device.
5. Separately test background/locked collection and disconnection/reconnection, recording real
   gaps and source identity. Strength pause/resume is still implementation work; it cannot be
   reported as verified from these builds.
6. Edit and delete a historical test session. Confirm unrelated workouts and raw sensor rows remain
   unchanged. Review local persistence separately from any tracker receipt/canonical website update.
7. Export and import a companion metadata package through Files. Confirm the connection remains off,
   no credentials are restored and workout history still requires its separate `.noopbak` backup.

No vibration tests or substitute notifications are permitted during the owner's current quiet
window, ending October 14 at 14:26:57 America/Los_Angeles (21:26:57 UTC). Cues are not queued for
later replay. Wake-alarm configuration is unchanged.

Tracker production activation, dedicated credentials and live-data writes remain separately
unapproved. These checks establish collection/persistence behavior, not physiological accuracy.
