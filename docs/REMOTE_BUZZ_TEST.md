# Personal Life → APNs → WHOOP buzz test

The owner authorized this personal-fork experiment on October 8, 2026. It is default-off and
expires within two hours. No polling, recurring monitor, health writes, DB migration, wake-alarm
writes, or remote BLE command selection is introduced. APNs support is Apple-specific; Android's
protocol and stored health values are unchanged.

## Implementation and evidence

Life exposes authenticated POST `/api/dhoop/buzz` with one JSON field, `eventId` (a lowercase UUID).
It signs a fixed one-pulse, installation-bound command with a sixty-second lifetime and sends a
sandbox APNs background push (priority 5). It returns `apns_accepted`, not phone delivery or motor
confirmation. The private APNs provider key stays on the sender; Dhoop receives only a separate
32-byte HMAC secret during explicit setup.

Dhoop imports setup into its existing Keychain facility under a distinct account, registers for
APNs, and exports its registration to a protected file. The remote-notification delegate verifies
identity, signature, expiry, and fixed pulse count before using the shared buzz delivery ledger.
Duplicate event IDs never replay; fresh commands have a thirty-second device cooldown and yield
to an active exercise. Disabling the test blocks new requests. The APNs receiver does not arm
firmware alarms or register a notification-service extension to bypass suspension.

Evidence is separate at each stage:

1. HTTP/API acceptance and APNs response, keyed by event ID.
2. `Documents/dhoop-remote-buzz-receipt.json`: authenticated phone receipt and actual UIApplication
   state at receipt. This is written before requesting a buzz.
3. `Library/Application Support/Dhoop/Buzz/delivery-v1.json`: command request/response evidence.
4. Wearer confirmation. A successful APNs or Bluetooth response is not motor evidence.

## Apple setup prerequisites

The app identifier is `com.devkunjadia.zhoop.loshi.noop`, under Loshi team `8MSX699Z2T`.

- Enable Push Notifications on that identifier and refresh the iOS Development provisioning profile
  while retaining the existing certificate/device selection. No certificates need revocation.
- Create an APNs provider key, preferably sandbox and topic-specific if the portal offers those
  options. Download its `.p8` file and retain its Key ID privately.
- Xcode currently reports no account for automatic profile updates. The original profile does not
  include `aps-environment`. A signed build is not ready until its profile and final entitlements
  explicitly include the development APNs environment. The source of truth is `project.yml`.

## Bounded local API test

A local API exercises the same Life APNs implementation before any production deployment:

```sh
node Tools/RemoteBuzz/test-api.mjs prepare --directory /private/tmp/dhoop-remote-buzz-test-NEW
```

Copy the resulting `dhoop-remote-buzz-setup.json` to the app's Documents using `devicectl` (no
credentials printed). In Exercises → Remote push buzz test, explicitly import and enable it.
After registration, copy `dhoop-remote-buzz-registration.json` back to the same private directory.

```sh
node Tools/RemoteBuzz/test-api.mjs configure --directory PRIVATE_DIR \
  --registration PRIVATE_REGISTRATION_FILE --apns-key PRIVATE_P8_FILE --key-id KEY_ID
node --experimental-strip-types Tools/RemoteBuzz/test-api.mjs serve --directory PRIVATE_DIR
node Tools/RemoteBuzz/test-api.mjs call --directory PRIVATE_DIR
```

The local server binds only `127.0.0.1:8799` and shuts down before expiry, at most ninety minutes.
Each call has a ten-second APNs timeout and fifteen-second client timeout. There is no retry loop.
Its private configuration files are mode 0600; they contain sensitive tokens and must not be added
to Git or pasted into chat. Preparing a directory never overwrites prior test credentials.

The Life route uses the same server-env keys written by the configure step. Those secrets are not
configured in production and the route is not deployed by this change. The MCP wrapper remains
pending proof of the push path; existing MCP scopes are not broadened for the prototype.

## Required physical checks

On October 8, 2026, build 452 compiled with the refreshed Loshi development profile and was
installed and launched on the physical iPhone. The signed app was checked for the existing bundle
identifier and `aps-environment: development`. Receiver opt-in, token registration, APNs delivery,
and wearer confirmation were pending at installation; the build result alone is not remote-buzz verification.

The first API test succeeded after correcting the key's allowed topic (the originally selected
identifier omitted `.zhoop`). Event `96560405-9aba-4461-9839-338650c6b25f` was accepted by APNs,
received and authenticated by Dhoop at 11:11:24.352709 PDT with UIApplication state `background`,
and requested WHOOP opcode 19 at 11:11:25.538383 PDT. The wearer confirmed feeling the vibration
while the phone was locked. The copied ledger retained `requested`; no command acknowledgment
is claimed. Lock duration and suspension were not measured, so this proves one locked-phone
API delivery, not a continuous or guaranteed background service. No wake alarm was changed.

First verify foreground API→APNs→phone receipt→WHOOP vibration using one event. Then lock the
phone for at least sixty seconds before making a fresh call, and wait without opening Dhoop.
Record the request and receipt times and ask the wearer whether vibration occurred while locked.
If a push arrives only after opening, record that accurately. Repeat after a longer idle interval
before describing dependable background behavior. Do not infer force-quit support.

Apple may delay or discard background pushes. Force-quitting normally prevents background
execution. Short-lived commands expire instead of creating surprise late buzzes. The successful
thirty-second locked-phone test on build 450 proves Bluetooth cue delivery during that short test,
not that APNs can wake a suspended Dhoop process.

Sources: [APNs requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns),
[background pushes](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app),
[Bluetooth restoration rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).
