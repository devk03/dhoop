# iOS — Install & Build

> **iOS is now a direct download (v1.96).** Grab **`NOOP-v<version>-ios.ipa`** from the
> [Releases](https://github.com/ryanbr/noop/releases) page and install it with **AltStore** or **SideStore** — see
> **[Install (sideload)](#install-sideload)** below. No Mac, no Xcode, no App Store, and no Apple
> Developer account needed — **and NOOP stays anonymous**, because the `.ipa` has no Apple developer
> signature and **you** sign it on your own iPhone with your own free Apple ID. It carries only a
> replaceable ad-hoc capability template so the sideloader can provision HealthKit and the App Group
> shared with the widget. The app target (`NOOPiOS` +
> `NOOPiOSWidgets`) also still builds from source in Xcode if you'd rather (**[Build from source](#build-from-source)**).
> A CI job ([`app-build.yml`](../.github/workflows/app-build.yml)) compiles both the macOS and iOS
> targets on every change so iOS can't silently break.

## Install (sideload)

The `.ipa` is **not signed by an Apple developer identity** — that's what keeps the project
anonymous. Its replaceable ad-hoc signature only describes the capabilities AltStore/SideStore must
provision; iOS won't run it until the sideloader signs it **on your device, with your own free Apple
ID**. Nothing about this touches NOOP's identity or Apple's servers on our side.

1. **Install a sideloader on your computer** — [AltStore](https://altstore.io) or
   [SideStore](https://sidestore.io) (both free). Follow their one-time setup (it installs a helper +
   AltStore/SideStore onto your iPhone using your own Apple ID).
2. **Download `NOOP-v<version>-ios.ipa`** from [Releases](https://github.com/ryanbr/noop/releases) to your iPhone (or your
   computer, then AirDrop/transfer it).
3. **Open the `.ipa` with AltStore/SideStore** (Share → AltStore, or the app's "+" button). It signs
   and installs NOOP. First launch may need **Settings → General → VPN & Device Management → trust
   your Apple ID**.

### If AltStore's Error Log says "Install NOOP Failed"

The same failure also shows up **on the phone**, in AltStore's own Error Log, where it names NOOP and so
looks like NOOP's fault:

> **Install NOOP Failed** — `NSCocoaErrorDomain 3840`
> *The data couldn't be read because it isn't in the correct format.*

**Read the whole log before concluding anything.** If it also contains:

> **Refresh AltStore Failed** — `NSCocoaErrorDomain 3840`

then AltStore could not refresh **its own app**, which nothing about NOOP's `.ipa` or NOOP's source can
cause. Every "… Failed" line is the same decode failure hitting whatever AltStore happened to be doing at
that minute — installing NOOP, refreshing NOOP, refreshing itself. The NOOP-named lines are the symptom,
not the cause.

`NSCocoaErrorDomain 3840` is a parse error: AltStore expected structured data and got something else back
(usually an HTML page). See the section below — it is the same underlying problem as the desktop sign-in
failure, just reported from the phone instead of AltServer.

### If AltServer can't sign in with your Apple ID

A failure at **step 1** — before NOOP is involved at all — looks like this:

> **AltServer could not sign in with your Apple ID. The data is not in the correct format.**
>
> `NSCocoaErrorDomain 3840` · *Encountered unknown tag html on line 1*

**This is a known AltStore bug on OS 26.2, not a problem with your setup.** It is reported upstream in
[altstoreio/AltStore#1695](https://github.com/altstoreio/AltStore/issues/1695) and
[#1699](https://github.com/altstoreio/AltStore/issues/1699), on macOS Tahoe 26.2 with iOS/iPadOS 26.2, and
at the time of writing there is no maintainer fix or workaround. Nothing you can change on your machine
resolves it.

What the error means, for the record: AltServer asked Apple's ID service for a property list and received
an **HTML page**, so the parser hit `<html>` on the first line. The "malformed data byte group / invalid
hex" line beneath it is the same failure reported by the older-style parser, not a second fault.

**What actually works today:**

- **Use [SideStore](https://sidestore.io) instead.** It is a separate implementation that does not go
  through AltServer's Apple ID sign-in, and NOOP's source works there identically — the same URL, the same
  auto-updates. This is the practical answer while the upstream bug is open.
- **Install the `.ipa` directly** with any sideloader that signs on-device, if you prefer not to add a
  source at all.
- **Watch the issues above** if you would rather wait for AltStore itself.

Local network filtering — a DNS blocker, a VPN, a captive portal — can produce an identical-looking error
by returning a block page, so it is worth ruling out if you have any. But it is **not** the usual cause,
and the two reports that prompted this note were both the upstream bug.

This is AltStore's own setup rather than anything NOOP controls, but it is the first step of the install,
so it is written down here rather than left as a dead end.

### Add NOOP as a source (recommended — auto-updates)

So you never have to manually re-download, add NOOP's **source** to AltStore/SideStore once — new
releases then show up (and re-sign) automatically:

**Source URL:** `https://raw.githubusercontent.com/ryanbr/noop/main/altstore-source.json`

> Make sure you copy the **raw** URL above exactly. If a sideloader says **"given data not valid
> JSON"** when you add the source, you've pasted a normal web page URL (which returns HTML) instead of
> the raw file — use the `raw.githubusercontent.com` URL above.

- **AltStore:** open AltStore → **Browse** tab → tap **＋** (top-left) → paste the URL → **Add Source**.
  NOOP appears under the source; tap **Free** / **Get** to install. From then on it updates itself on
  AltStore's background refresh (you can also pull-to-refresh **My Apps**).
- **SideStore:** open SideStore → **Browse** / **Sources** → **＋ Add Source** → paste the same URL → add.

The source always tracks the latest release, so you're one tap from the newest build instead of
hunting for the `.ipa` each time.

> ### Two honest limitations of free-Apple-ID sideloading
> - **7-day expiry.** Apps signed with a *free* Apple ID stop launching after 7 days and need
>   re-signing. **AltStore/SideStore refresh this automatically** in the background — keep the
>   sideloader installed and NOOP keeps working.
> - **Apple-only features require their extensions and capabilities.** Keep the
>   `NOOPWidgets.appex` extension enabled when AltStore/SideStore asks: it renders the Home/Lock-Screen
>   widgets and Live Activities and shares data through the provisioned App Group. Removing app
>   extensions while signing disables those surfaces. Other signing tools must likewise preserve and
>   provision the requested HealthKit and App Group entitlements. Building from source with your own
>   Apple ID in Xcode and selecting your Team for both targets configures them automatically.

iOS shares the cross-platform Swift packages with macOS, so the number-crunching (recovery, strain,
HRV, sleep) is the **same code** and produces the same results. iOS is newer and less battle-tested
than macOS/Android — live BLE on a real iPhone is still being validated by the community, so reports
are very welcome.

## Build from source

Prefer to build it yourself (which also grants HealthKit/widgets under your own Apple ID)? Run
`xcodegen generate`, then build the **`NOOPiOS`** scheme in Xcode. The reconciliation that brought the
[PR #42](../../../pull/42) port onto current `main` is summarised in **"Lessons from the fold-in"**
below.

> 🛠️ **Signing it under your own Apple ID** (thanks @gingerbeardman for the original recipe). Apple
> requires a bundle id and app group unique to *your* developer account — otherwise the build collides
> with any other NOOP install already on your device (an AltStore/SideStore sideload, or someone
> else's build). Two steps:
> 1. `cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig` and set
>    `BUNDLE_ID_PREFIX` to your own reverse-domain prefix (e.g. `com.yourdomain`), then re-run
>    `xcodegen generate`. This one gitignored file drives **every** target's bundle id *and* the shared
>    App Group together (`$(BUNDLE_ID_PREFIX).noop`, `group.$(BUNDLE_ID_PREFIX).noop.staging`) — nothing
>    hard-coded in Swift, nothing else to edit, and it survives future regenerates.
> 2. In Xcode, **select your Team** (Signing & Capabilities) for the `NOOPiOS` **and** `NOOPiOSWidgets`
>    targets — the one step Apple still requires you to do by hand.
>
> Skip step 1 and the build still works under the default `com.noopapp` identifiers — fine if this is
> the only NOOP install on your device.

> ℹ️ **Cross-platform engineering lives in [`CROSS_PLATFORM.md`](CROSS_PLATFORM.md)** — the shared-code
> boundary across the macOS / iOS / Android clients, the `Platform.swift` shim convention, the
> Swift↔Kotlin parity discipline, and the playbook for adding a feature across all three. Read that
> first if you're building something that should land on more than one client.

This document describes how NOOP — a standalone, fully offline companion app for
WHOOP straps — is positioned for iOS, what already works, and the concrete plan
for a native iOS app target.

> **Not affiliated with WHOOP.** NOOP is an independent, unofficial project. It is
> not affiliated with, endorsed by, or connected to WHOOP, Inc. "WHOOP" is used
> nominatively only to identify the hardware the app interoperates with — your own
> device and your own data. NOOP performs no DRM circumvention and ships no WHOOP
> proprietary code, firmware, or assets. **NOOP is not a medical device;** all
> metrics (HR, HRV, recovery, strain, sleep, SpO₂, temperature) are approximations
> and not clinically validated.

The reverse-engineering that makes any of this possible is built on prior
community work: the WHOOP 4.0 protocol from **`johnmiddleton12/my-whoop`** and
the WHOOP 5.0 / MG protocol from **`b-nnett/goose`**. See [`../ATTRIBUTION.md`](../ATTRIBUTION.md).

---

## TL;DR

- **All five shared packages already build for iOS.** Every `Package.swift` declares
  `.iOS(.v16)` alongside `.macOS(.v13)`, and the only UI-framework-specific code is
  guarded with `#if canImport(UIKit)` / `#if canImport(AppKit)`.
- The work to ship on iOS is **app-layer only**: a new iOS app target that reuses
  `WhoopProtocol`, `WhoopStore`, `StrandAnalytics`, `StrandImport`, and `StrandDesign`
  unchanged, plus iOS variants of the handful of macOS-only app-layer services
  (menu bar, screen lock, Shortcuts, pasteboard).
- **CoreBluetooth is fully available on iOS** and the BLE engine is already written
  with iOS background collection in mind (state restoration hooks exist).
- **HealthKit is available on iOS** (it is not on macOS), so iOS can do *two-way*
  Apple Health: read live, and write NOOP-computed metrics back. On macOS, Apple
  Health is import-only via the static `export.xml` / `export.zip` file.

---

## Current platform support in the packages

The shared logic lives in five SwiftPM packages under [`Packages/`](../Packages/). Each
declares both platforms in its manifest:

| Package | Role | Platforms declared | iOS-relevant notes |
|---|---|---|---|
| `WhoopProtocol` | BLE frame parsing, CRC, command/event/packet decode — the reverse-engineering core | `.iOS(.v16)`, `.macOS(.v13)` | Platform-pure. **Never imports CoreBluetooth or any UI framework.** Exposes GATT UUIDs as plain *strings* (see `DeviceFamily.swift`); the app wraps them in `CBUUID`. |
| `WhoopStore` | GRDB/SQLite persistence (migrations, decoded streams, metric caches) | `.iOS(.v16)`, `.macOS(.v13)` | Depends on `WhoopProtocol` + GRDB.swift `6.0.0+`. GRDB supports iOS first-class. |
| `StrandAnalytics` | HRV / recovery / strain / sleep / correlation math | `.macOS(.v13)`, `.iOS(.v16)` | Pure computation; no platform APIs. |
| `StrandImport` | WHOOP CSV + Apple Health (`export.xml`, streaming) importers | `.macOS(.v13)`, `.iOS(.v16)` | Depends on `WhoopProtocol`, `WhoopStore`, ZIPFoundation `0.9.0+`. Uses a streaming `XMLParser` (SAX), so it stays memory-bounded even on iOS for multi-hundred-MB exports. |
| `StrandDesign` | SwiftUI design system (palette, components, charts) | `.macOS(.v13)`, `.iOS(.v16)` | The one package with a platform branch: `Palette.swift` resolves `Color` → sRGB components via `NSColor` under `#if canImport(AppKit)` and `UIColor` under `#elseif canImport(UIKit)`. |

> **Verify:** see each `Packages/<Name>/Package.swift`. The `platforms:` array carries
> both `.iOS(.v16)` and `.macOS(.v13)` in all five.

### The one cross-platform shim that already exists

`StrandDesign/Sources/StrandDesign/Palette.swift` is the template for how UI-framework
differences are handled across the codebase:

```swift
extension Color {
    /// Resolve to sRGB RGBA components in 0...1.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}
```

Because the design system already compiles against UIKit, the SwiftUI components,
charts, and palette render on iOS as-is.

---

## The macOS app today (the reference implementation)

The macOS app target lives in [`Strand/`](../Strand/). It is the reference
implementation; Android ships as a full app (`android/`), and the iOS app is an
experimental, build-from-source community port ([PR #42](../../../pull/42)). The macOS app composes
the packages like this:

- `Strand/App/StrandApp.swift` — the `@main` SwiftUI `App`. Declares a `WindowGroup`
  and a `MenuBarExtra` scene.
- `Strand/App/AppModel.swift` — root `@MainActor` state object. Owns `LiveState`,
  the `BLEManager`, the `Repository` read-model, the `ProfileStore`, and the
  `BehaviorStore`.
- `Strand/BLE/BLEManager.swift` — the CoreBluetooth engine.
- `Strand/Collect/` — the collector, backfiller, clock-correlation, and store paths.
- `Strand/Data/` — `Repository`, importers, and settings stores.
- `Strand/Screens/` — the SwiftUI screens (Today, Trends, Sleep, Workouts, etc.).
- `Strand/System/MacActions.swift` — **macOS-only side effects** (screen lock, Shortcuts).
- `Strand/MenuBar/MenuBarContent.swift` — **macOS-only** menu-bar extra.

Most of `Strand/` is plain SwiftUI + the shared packages and would move to iOS
unchanged or near-unchanged. The macOS-specific pieces are enumerated below.

The on-device database path is resolved in `Strand/Collect/StorePaths.swift`:

```swift
enum StorePaths {
    /// `<AppSupport>/OpenWhoop/whoop.sqlite`, creating the directory if needed.
    static func defaultDatabasePath() throws -> String {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
            .appendingPathComponent("OpenWhoop", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("whoop.sqlite").path
    }
}
```

`FileManager.url(for: .applicationSupportDirectory, …)` is valid on iOS too, so this
helper works unchanged inside the iOS sandbox container. The `WhoopStore` actor opens
the database with WAL journaling and a 5-second busy timeout (`WhoopStore.swift`),
both fully supported on iOS.

---

## CoreBluetooth on iOS

The BLE engine (`Strand/BLE/BLEManager.swift`) uses **CoreBluetooth**, which is the
same framework on iOS and macOS. The strap interaction — scan by service → connect →
discover → **bond** (one confirmed write) → subscribe → reassemble fragmented frames →
route — is identical across platforms.

The engine already discovers the WHOOP 4.0 custom service and characteristics, plus
the standard Heart Rate (`180D` / `2A37`) and Battery (`180F` / `2A19`) services. The
WHOOP 5.0 / MG service family (`fd4b0001-…`, CRC16-Modbus header, the puffin packet
types) is modeled in `WhoopProtocol/DeviceFamily.swift` and exposed as UUID strings
the app wraps in `CBUUID`.

### Background BLE — what's already wired

The engine was written anticipating iOS background collection. `BLEManager` already
implements **CoreBluetooth state restoration**:

```swift
static let restoreID = "com.openwhoop.ble.central"

public func centralManager(_ central: CBCentralManager,
                           willRestoreState dict: [String: Any]) {
    guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
          let p = peripherals.first else { … }
    self.peripheral = p
    self.restoredPeripheral = p
    p.delegate = self
    // Collection only runs post-bond, so a restored link was already bonded; seed flags.
    state.bonded = true
    didBond = true
    …
}
```

When iOS relaunches the app into the background to deliver a BLE event, it calls
`willRestoreState` with the previously-connected peripheral. The engine stores it in
`restoredPeripheral` and, on the next `centralManagerDidUpdateState` `.poweredOn`,
reconnects that exact peripheral instead of starting a fresh scan — no user
interaction required.

> The macOS init deliberately **does not** pass the restoration identifier — the
> source comments call state restoration "an iOS background feature." On macOS:
>
> ```swift
> // Strand (macOS desktop): no state-restoration identifier (iOS background feature).
> central = CBCentralManager(delegate: self, queue: .main)
> ```

### Background BLE — what the iOS target must add

To make `willRestoreState` actually fire on iOS, the iOS target's `CBCentralManager`
must be created **with** the restoration identifier, and the app must declare the
Bluetooth background mode:

```swift
// iOS-only initializer
central = CBCentralManager(
    delegate: self,
    queue: .main,
    options: [CBCentralManagerOptionRestoreIdentifierKey: BLEManager.restoreID]
)
```

| Requirement | iOS action |
|---|---|
| Background execution | `UIBackgroundModes` in `Info.plist` includes `bluetooth-central`. |
| State restoration | Pass `CBCentralManagerOptionRestoreIdentifierKey: BLEManager.restoreID` when constructing the central. `BLEManager.restoreID` already exists. |
| Usage description | `NSBluetoothAlwaysUsageDescription` (the macOS target already supplies a copy in its `Info.plist` — reuse and re-word for iOS). |
| Reconnect on relaunch | Already handled by `willRestoreState` + `centralManagerDidUpdateState`. |
| App Sandbox / entitlement | iOS does not use `com.apple.security.device.bluetooth` (that is a macOS App Sandbox entitlement); the iOS Bluetooth capability is granted via the usage-description prompt + background mode. |

The keep-alive, liveness watchdog, periodic backfill, and reconnect-on-disconnect
timers in `BLEManager` are platform-neutral `DispatchSource` timers. Note that iOS
suspends the app between BLE events, so these timers do **not** run continuously in the
background the way they do on a Mac that stays awake — on iOS, progress is driven by
the system waking the app for BLE traffic. The existing logic (rate-limited
`requestSync`, persisted `backfillLastAt` watermark) is already designed to resume
correctly across process relaunches, which is exactly the iOS background lifecycle.

> **Not available in the Simulator.** CoreBluetooth has no simulator support — the
> source notes "Cannot run in the simulator; verified manually on-device." iOS BLE
> work must be tested on a physical device paired with a real strap.

---

## App-layer items that need iOS variants

These are the only pieces of `Strand/` that are macOS-specific. Each needs an iOS
equivalent (or to be conditionally compiled out).

### 1. Menu bar → there is no menu bar on iOS

`Strand/MenuBar/MenuBarContent.swift` provides a `MenuBarExtra` (a glanceable
zone-tinted HR dot + a compact recovery/HR/battery popover), wired in
`StrandApp.swift`. **iOS has no menu bar.** The iOS equivalents:

- A **Home Screen widget** / **Lock Screen widget** (WidgetKit) showing recovery,
  live/last HR, and battery — the natural iOS analogue of the menu-bar glance.
- A **Live Activity** (ActivityKit) during an active workout or live HR session.
- The popover's content (`RecoveryRing`, `StatePill`, the stats row) is already
  built from `StrandDesign` components and can be reused inside the widget views.

### 2. Screen lock — macOS-only API

`Strand/System/MacActions.swift` locks the Mac by `dlopen`-ing
`login.framework` and calling `SACLockScreenImmediate`. **There is no iOS equivalent;**
a third-party app cannot lock an iPhone. On iOS the `lockScreen` action should be
hidden from the action picker (`MacActionKind`) or remapped (see Shortcuts below).

### 3. Strap double-tap / wrist-off actions — the "run a Shortcut" gap

On macOS, a strap **double-tap** (or a wrist-off trigger) runs a configurable action.
The action set is `MacActionKind` in `MacActions.swift`:

```swift
enum MacActionKind: String, Codable, CaseIterable, Identifiable {
    case none, lockScreen, buzzBack, markMoment, runShortcut
}
```

`AppModel.handleDoubleTap()` dispatches through `runMacAction(_:shortcut:)`. On macOS,
`runShortcut` opens the `shortcuts://run-shortcut?name=…` URL via `NSWorkspace`:

```swift
static func runShortcut(_ name: String) {
    …
    let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
    NSWorkspace.shared.open(url)
}
```

**The portable actions move to iOS directly:**

- `buzzBack` — sends a haptic command to the strap over BLE; purely `BLEManager`, no
  platform API. Works on iOS.
- `markMoment` — appends a timestamp to `moments` in `AppModel` and persists to
  `UserDefaults`. Works on iOS.
- `none` — trivially portable.

**The Shortcuts story differs on iOS** and deserves its own design:

- iOS **can** open `shortcuts://run-shortcut?name=…` via `UIApplication.shared.open(_:)`,
  but iOS will *foreground the Shortcuts app to run the shortcut* — it cannot silently
  run an arbitrary user Shortcut from the background the way a Mac can. This makes the
  "double-tap runs an arbitrary Shortcut while my phone is in my pocket" pattern
  unreliable on iOS.
- The robust iOS approach is to **publish App Intents** (the App Intents framework)
  from NOOP — e.g. "Mark a moment", "Start live HR", "Buzz strap", "Log recovery". The
  user then builds Shortcuts/Automations that call *NOOP's* intents, and NOOP also
  appears in Spotlight, Siri, and the Shortcuts gallery.
- For invoking *other* apps from NOOP, support **x-callback-url** style deep links
  (`x-callback-url` is the de-facto inter-app callback convention) and the standard
  `shortcuts://x-callback-url/run-shortcut?name=…&x-success=…` form so control can
  return to NOOP after the external shortcut completes.

> Net: replace the macOS `runShortcut(_:)` plumbing with (a) **App Intents exposed by
> NOOP** for inbound automation and (b) **x-callback-url / `shortcuts://` deep links**
> for outbound calls, and remove `lockScreen` from the iOS action set.

### 4. Pasteboard

`Strand/Screens/SupportView.swift` copies a string with `NSPasteboard.general`. The
iOS equivalent is `UIPasteboard.general.string = …`. This is a one-call swap; wrap it
in a tiny `#if os(iOS)` / `#if os(macOS)` helper (the same pattern `Palette.swift`
already uses) so the screen compiles on both.

### Summary of app-layer deltas

| macOS-only file/API | iOS replacement |
|---|---|
| `MenuBar/MenuBarContent.swift` (`MenuBarExtra`) | WidgetKit widget + Live Activity; reuse `StrandDesign` views |
| `MacActions.lockScreen()` (`login.framework`) | Not possible on iOS — hide/remap the action |
| `MacActions.runShortcut(_:)` via `NSWorkspace` | App Intents (inbound) + `UIApplication.open` / x-callback-url (outbound) |
| `NSPasteboard` (`SupportView.swift`) | `UIPasteboard` behind an `#if os` helper |
| `NSWorkspace`/`NSImage` app icons in `NotificationSettingsStore.swift` | iOS has no per-app launch icons; replace with iOS notification settings UI |
| `CBCentralManager(delegate:queue:)` | `CBCentralManager(delegate:queue:options:[…RestoreIdentifierKey…])` + `bluetooth-central` background mode |

---

## HealthKit: two-way Apple Health is possible on iOS

This is the biggest *additive* opportunity on iOS.

- **macOS has no HealthKit.** The Mac app therefore consumes Apple Health **one way**,
  by importing the user's exported archive. `StrandImport/AppleHealthImporter.swift`
  stream-parses `export.xml` (optionally inside `export.zip`) with a SAX
  `XMLParser`/`XMLParserDelegate` — never a DOM, because the file can exceed 1 GB. It
  filters to the relevant `Record` types (HeartRate, RestingHeartRate,
  HeartRateVariabilitySDNN, OxygenSaturation, BodyTemperature, RespiratoryRate,
  SleepAnalysis, body-composition, etc.), de-dupes records that appear both top-level
  and nested in a `<Correlation>`, and normalizes units (e.g. `OxygenSaturation` 0–1 →
  percent).
- **iOS has HealthKit**, so the iOS target can do far more than parse a static export:

| Direction | iOS capability |
|---|---|
| **Read** | Query HealthKit live (`HKHealthStore`, `HKSampleQuery`, anchored/observer queries) for HR, RHR, HRV SDNN, SpO₂, wrist/body temperature, respiratory rate, sleep stages, workouts, body composition — the same types `relevantTypes` already enumerates in `AppleHealthImporter`. No manual export needed. |
| **Write** | Write NOOP-computed values back into Apple Health: HR / HRV / SpO₂ / temperature samples decoded from the strap, sleep analysis from `StrandAnalytics.SleepStager`, and workouts from `WorkoutDetector` — so NOOP data shows up across the user's Health ecosystem. |
| **Background delivery** | `HKObserverQuery` + `enableBackgroundDelivery` keep the on-device store current, while a best-effort `BGAppRefreshTaskRequest` periodically writes already-banked strap data back to Health. Fresh WHOOP offloads write immediately from their completion hook. iOS chooses the actual refresh time. |

Because `AppleHealthImporter` already defines the canonical type set, units, and
`SleepStage` mapping, an iOS `HealthKitImporter` can map `HKSample` objects onto the
**same** `StrandImport` models and feed the identical ingest path into `WhoopStore` —
the static-export importer and the live HealthKit importer converge on one schema.

> **Entitlement/Info.plist on iOS:** add the **HealthKit** capability and supply
> `NSHealthShareUsageDescription` (read) and `NSHealthUpdateUsageDescription` (write).
> Keep both directions strictly opt-in and on-device — consistent with NOOP's
> offline, no-cloud stance.

---

## Concrete iOS target structure

The recommended layout keeps the five packages untouched and adds a sibling iOS app
target. The bulk of `Strand/`'s SwiftUI screens move into a shared app layer; only the
platform-specific services are duplicated per OS.

```
Strand/                      # existing macOS app target (reference)
StrandiOS/                   # NEW iOS app target
├── App/
│   ├── StrandiOSApp.swift          # @main; WindowGroup only (no MenuBarExtra)
│   └── AppModel+iOS.swift          # iOS BLE options, HealthKit wiring
├── BLE/
│   └── BLEManager+iOS.swift        # central built WITH RestoreIdentifierKey
├── Health/
│   └── HealthKitBridge.swift       # two-way HealthKit (read + write)
├── System/
│   ├── iOSActions.swift            # UIPasteboard, App Intents, x-callback-url
│   └── NOOPAppIntents.swift        # App Intents exposed to Shortcuts/Siri
├── Widgets/
│   └── NOOPWidget.swift            # Home/Lock-Screen widget (menu-bar analogue)
└── Resources/
    └── Info.plist                  # UIBackgroundModes, Health + Bluetooth usage strings

Shared/                      # (optional) screens lifted out of Strand/Screens
└── …                        # TodayView, TrendsView, SleepView, … reused by both targets
```

The cleanest path is to move the platform-neutral SwiftUI screens
(`Strand/Screens/*` that don't touch `NS…`/`UI…` directly) into a shared location both
targets include, leaving each target with only its `@main` scene and its
platform-specific service shims.

### Package dependencies for the iOS target

The iOS app target depends on exactly the same five local packages the macOS target
already lists in [`project.yml`](../project.yml). Expressed as a SwiftPM target (e.g.
in an Xcode project generated by XcodeGen / Tuist, or a `Package.swift` app target):

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NOOPiOS",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(path: "Packages/WhoopProtocol"),
        .package(path: "Packages/WhoopStore"),
        .package(path: "Packages/StrandAnalytics"),
        .package(path: "Packages/StrandImport"),
        .package(path: "Packages/StrandDesign"),
    ],
    targets: [
        .executableTarget(
            name: "NOOPiOS",
            dependencies: [
                "WhoopProtocol",
                "WhoopStore",
                "StrandAnalytics",
                "StrandImport",
                "StrandDesign",
            ]
        ),
    ]
)
```

Equivalent XcodeGen stanza (mirroring the existing macOS `Strand` target in
`project.yml`, which already declares these five packages under `packages:` and lists
them under the target's `dependencies:`):

```yaml
targets:
  NOOPiOS:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - StrandiOS
      - Shared            # screens lifted from Strand/Screens, if shared
    info:
      path: StrandiOS/Resources/Info.plist
      properties:
        CFBundleName: NOOP
        CFBundleDisplayName: NOOP
        LSApplicationCategoryType: public.app-category.healthcare-fitness
        UIBackgroundModes:
          - bluetooth-central
        NSBluetoothAlwaysUsageDescription: >-
          NOOP connects directly to your WHOOP strap over Bluetooth to read heart rate,
          R-R intervals, battery, and sensor data locally on your iPhone. Nothing leaves
          your device.
        NSHealthShareUsageDescription: >-
          NOOP reads your own Apple Health data on-device to compute recovery, strain,
          and sleep. Nothing leaves your device.
        NSHealthUpdateUsageDescription: >-
          NOOP writes the metrics it computes from your strap back into Apple Health,
          on-device and only when you allow it.
    entitlements:
      path: StrandiOS/Resources/NOOP.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.background-delivery: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.noopapp.noop
        PRODUCT_NAME: NOOP
    dependencies:
      - package: WhoopProtocol
      - package: WhoopStore
      - package: StrandAnalytics
      - package: StrandImport
      - package: StrandDesign
```

> Note the entitlements differ by platform. macOS uses **App Sandbox** entitlements
> (`com.apple.security.app-sandbox`, `com.apple.security.device.bluetooth`,
> `com.apple.security.files.user-selected.read-write` — see
> `Strand/Resources/Strand.entitlements`). iOS instead uses the **HealthKit**
> entitlement plus the `bluetooth-central` background mode and the usage-description
> prompts; it does not use the macOS App Sandbox keys.

---

## Port checklist — done in the v1.94 fold-in

- [x] `StrandiOS` + `NOOPiOSWidgets` app targets depending on the five existing packages (no package changes).
- [x] `CBCentralManager` built with `CBCentralManagerOptionRestoreIdentifierKey` (in `AppModel+iOS`).
- [x] `UIBackgroundModes: [bluetooth-central]` + `NSBluetoothAlwaysUsageDescription` in the iOS Info.plist.
- [x] `MenuBarExtra` replaced by a WidgetKit widget + Live Activity (`StrandiOSWidgets`), reusing `StrandDesign`.
- [x] iOS action layer: `lockScreen` returns false on iOS, `buzzBack`/`markMoment` portable, **App Intents** exposed (`StrandiOS/System/NOOPAppIntents.swift`).
- [x] Clipboard + URL-open routed through `Platform.swift` (`PlatformPasteboard`/`PlatformOpen`).
- [x] `HealthKitBridge` two-way Apple Health (read live + immediate post-offload and periodic background write-back of NOOP metrics).
- [ ] **Still TODO (needs hardware):** verify BLE on a **physical iPhone** with a real strap — CoreBluetooth has no Simulator. This is the one thing CI/compile can't cover.

---

## Lessons from the fold-in (v1.94)

How PR #42's port was brought onto current `main` — useful the next time a screen has to span platforms.

- **Don't merge a stale port; reconcile it.** PR #42 was ~9 releases behind (139 commits, conflicting). A direct merge would have fought conflicts in shared files the macOS app *also* uses. Instead we stood up a **fresh `StrandiOS` target** on current `main` and **harvested** the field-proven iOS-only files (app shell, HealthKit, widgets, App Intents, the `Platform`/`DocumentPicker`/`FileExport` shims), then applied small guards to the shared screens. The shared **packages already built for iOS** (every `Package.swift` declares `.iOS(.v16)`), so ~90% of the code needed nothing.
- **The macOS-only API surface is small + enumerable.** Folding in iOS only required touching these in shared code: file dialogs (`NSSavePanel`/`NSOpenPanel` → `DocumentPicker`/`FileExport`), `NSWorkspace.activateFileViewerSelecting` ("reveal in Finder", `#if os(macOS)`-guarded out), clipboard/`NSImage`/`NSWorkspace.open` (→ `Platform.*`), `MacActions.lockScreen` (returns false on iOS) / `runShortcut` (→ `PlatformOpen`), and two macOS-only SwiftUI modifiers (`.toggleStyle(.checkbox)`, `.onExitCommand`). The macOS-only *files* (`StrandApp`, `RootView`, `MenuBar`, notification settings) are **excluded from the iOS target** in `project.yml`.
- **`ContentView` vs `RootTabView`.** macOS uses a `NavigationSplitView` sidebar (`ContentView` → `RootView`); iOS uses a `TabView` (`RootTabView`). The fold-in's one real drift was `ContentView` (not excluded) referencing the excluded `RootView`. Fix: exclude `ContentView.swift` from iOS and render `RootTabView` via `iOSRootView`, which reproduces the same onboarding / Terms / What's-New gates around the tab bar.
- **CI is stricter than a bleeding-edge local Xcode — on purpose.** The first `app-build` run was red: `AppleHealthView` interpolated a `String?` into a `LocalizedStringKey` subtitle (`"\(optional)"`). A current local Xcode tolerates it as a deprecation (and renders `Optional(...)`); the runner's older Xcode rejects it. The maintainer can't device-test iOS, so the **CI compile gate on an older Xcode is the safety net** — treat its failures as real and fix the source (don't pin the runner to bleeding-edge).
- **Anonymity when harvesting a community branch:** the fetched PR branch carried a real-name commit author. The pre-push hook scans `git log --all`, so **delete the fetched PR ref (and any worktree branches) before pushing**, and re-author harvested files as `NoopApp`. (`git checkout <ref> -- <paths>` brings the *content*; commit it yourself.)

---

*NOOP keeps everything on-device. The iOS plan changes the front door (menu bar →
widgets, AppKit → UIKit, file import → HealthKit) but not the principle: your strap,
your data, no cloud.*


## Dhoop strength capture

Exercises exposes Strength alongside Zone run, HIIT, Intervals and Meditation. Strength reuses the
existing routine, session and set tables; it does not create a second lifting log. The generated
[interaction and workout study](design/dhoop-strength-interactions-study.png) and its
[built-in ImageGen prompt](design/dhoop-strength-interactions-study.prompt.txt) are visual references.
Every number in that board is demonstration data, not an app fixture.

A strength session claims one shared realtime-HR reference and the `strength-workout` buzz owner.
Minimizing or reopening its sheet does not release or duplicate that claim. Save and discard release
it. A restored session retains its original registry device ID; a different active strap cannot advance
its sets or receive its cues. Legacy snapshots without that field display an unverified capture source.
The small collection readout distinguishes readable receipts from measured readings persisted since
workout start. Its last checked timestamp describes the stored count. The live number uses the common
freshness gate; connection alone never proves collection or persistence.

Automatic activity suggestions exclude the active Strength window only for its known original strap.
Unknown-source legacy snapshots do not suppress another device's activity. Foreground review is
disabled during a manual Strength, HIIT or Zone session. Detection remains a sustained-activity
suggestion; it does not infer exercises, repetitions or set boundaries.

Session history reads measured positive sensor rows under the session's original device ID.
Its chart reuses the minute-average, gap-preserving projection and the shared scrubbing component.
Session and timed-set statistics use full-window queries, with half-open bounds so a boundary second
belongs to only one consecutive set. Untimed sets have no HR attribution. Optical estimates are
excluded rather than silently mixed into measured averages. A chart capped at 100,000 readings is
labeled as limited; the summary still covers the full window. Android exposes matching measured-only
queries over the same table; no physiological formula or stored sample value changes.


Routine metadata and ordered targets save together. A finished recording saves its session, exact
set list, paired manual workout and approved routine-target updates in one SQLite transaction.
Corrections and deletion are scoped to that recording and transactional. Failed storage operations
retain entered data and report the failure; they do not dismiss the editor as a successful save.
Preparing a save does not end the durable session. Pending saves suppress session edits and strap
advance gestures. Sets logged retrospectively still carry no invented timing.

These Apple capture APIs change no database schema, backup row shape, physiology formula or unit
representation. Weight remains kg in storage. Android's existing import/CRUD contract is unchanged;
the iPhone capture controller and its private active-session snapshot are Apple-specific.

Life integration is separate from local capture. The agreed direction is for Life to own prescriptions,
progression and canonical history while Dhoop owns offline observations, actual set times and WHOOP
collection. Integration must bind exact Life IDs, retain raw kg and RPE, preserve manual corrections,
and deduplicate revisions and deletions. Proposed receiver endpoints and credentials are not activated
by this local capture change. No workout is written into the official WHOOP app.

Software builds and controller/store tests do not establish locked-phone collection reliability,
wearer-felt vibration, or physiological accuracy. Those require physical-device checks.

### Protein and control feedback

Protein add/remove/target actions use the shared pending/success/error component. Entered grams and
meal text clear only after a successful local write. Mutations re-read current saved entries before
encoding/publishing, so another store instance's newer entries are retained. Unreadable saved history
blocks writes and reports unavailable totals rather than zero; the original bytes remain untouched.
Retry reading is explicit. A failed encoding retains previous entries. Protein-only entries still
create no calorie day or weight-goal change; their JSON format and defaults keys are unchanged.

Pairing navigation/model choices and history day/reset buttons use shared pressed/disabled feedback
and 44-point targets. Native confirmation dialogs remain native. History navigation/reset honors
Reduce Motion. The [control study](design/dhoop-protein-pairing-control-study.png) and
[built-in generation/edit prompts](design/dhoop-protein-pairing-control-study.prompt.txt) are demo
references, not runtime screenshots. Physical interaction/accessibility checks remain outstanding.

### Optional Life workout connection

The iPhone Strength hub exposes Tracker routines; Settings exposes Workout tracker. The connection
is off by default. A dedicated workout credential is stored separately in Keychain, bound to the
explicitly configured owner origin and public installation UUID. Saving the connection keeps it off.
No credentials or production service are created by the app. Reads use bounded pagination and reject
mixed revisions. Read latest and start checks a fresh manifest. An explicit Start cached plan action
uses a complete saved snapshot without a request or Keychain read, even with delivery switched off.
It retains the original public destination, bindings and source IDs. Per-plan fetch timestamps are
separate from index refresh times; legacy unknown ages stay unknown. A reported inconsistent,
unavailable or invalid latest plan blocks cached reuse until a valid fresh read. Backup/restore retains
these blocks and known fetch dates. No recurring polling job is installed.

New captures retain `planAtStart` with live/cached provenance, the original supported hash or null,
and the actual fetch timestamp or null. Older capture bindings keep unknown provenance; a refreshed
cache never retroactively relabels their start. Future reviewed write-precondition changes must retain
this original reference. The local receiver locks first-accepted provenance, including unknown.

A tracker capture retains exact cycle/session/occurrence/set IDs, its prescription snapshot, actual
IANA timezone and original connection destination. Source workout and set UUIDs survive relaunch and
save retries. Additional actual sets have source UUIDs but no prescribed Life set ID; they remain
capture-only and do not alter Life prescriptions or progression. Added and repeated exercises retain
distinct occurrence UUIDs, an explicit load mode and a stable source exercise key from the local
vocabulary ID. Legacy vocabulary IDs receive durable device-scoped source UUIDs. No Life target is
matched by name. Unsupported/excess bindings remain local for review. Bodyweight inputs do not carry
previous mass loads. Per-hand/added/total load labels remain explicit; RIR is never inferred from RPE.

Optional set notes are written into the existing `liftSet.note` column. The active snapshot retains
notes across relaunch; historical correction and explicit clearing preserve numeric values and timing.
The exercise menu can move cards earlier/later within the current session. A separate durable
presentation/suggestion order keeps plan indices, source IDs, completed sets, notes and the current
set/rest timing unchanged. Undo and relaunch retain this order; the routine prescription is unchanged.
Replace remaining sets uses the same picker. The original card retains completed sets and editable
numbers/notes; only unfinished work moves to a new exercise/card and new source IDs. The working set
must be completed before replacing its own exercise. An ongoing rest keeps its original deadline.
Replacements do not write back into a saved routine or persistent Life prescription. A replacement
can itself be replaced; earlier performed observations and lineage remain intact. The active snapshot
retains replacement indices and explicit load modes. Undo restores the original remaining work.
Observed set/occurrence order is distinct from card/plan indices. The save binding retains actual
completion order; unknown order is explicitly nullable, including unperformed original occurrences.
Known order does not manufacture timestamps. Replacement payloads include the original source
occurrence reference, matching the locally tested Life contract at `3cb8a0f`.
This Apple session-editor behavior does not change SQLite rows, backup row shapes or shared analytics;
Android session UI parity is not implemented by this fork change.
The [session-order study](design/dhoop-strength-session-order-study.png) and its
[built-in ImageGen prompt](design/dhoop-strength-session-order-study.prompt.txt) use demo data only.
The [replacement study](design/dhoop-strength-replacement-study.png) and its
[built-in ImageGen prompt](design/dhoop-strength-replacement-study.prompt.txt) are also demo references.
An unencodable active-session update preserves the last good recovery snapshot. Explicit discard
still clears it. Non-finite numeric text is rejected; an encoding failure retains current in-memory
entries, reports a recovery error and prevents saving until corrected. This is Apple input/recovery
behavior; Android has no corresponding session editor in this fork. SQLite row shapes and analytics
are unchanged. The [cached-start/recovery study](design/dhoop-cached-start-recovery-study.png) and
[built-in ImageGen prompt](design/dhoop-cached-start-recovery-study.prompt.txt) contain demo data.
The [picker and delivery study](design/dhoop-tracker-picker-delivery-study.png) and its
[built-in ImageGen prompt](design/dhoop-tracker-picker-delivery-study.prompt.txt) use demo data only.

Delivery intent is written atomically in the private Application Support folder before the SQLite
recording transaction. Credentials are not needed to retain this intent. Only exact persisted session,
set and paired-workout values can become ready to send. Historical corrections retain source IDs;
deletion records a tombstone intent and verifies local removal without deleting sensor samples.
An earlier unverified receipt or an unsupported binding keeps a change in review. These sidecar files
change no database schema and are not currently part of the cross-platform `.noopbak` whitelist.

Each event body is immutable. Timeouts retry the same event. A verified receipt must identify the
requested capture, revision, programmed target and prescribed/capture-only set mappings. A receipt
that accepts observations with derived progression pending is labeled separately; a manual Sync
retries that same receipt. HTTP errors and revision conflicts retain local data. Conflicts do not
silently refresh IDs or overwrite website edits. Timed-set HR summaries use measured sensor rows
for the original strap and half-open actual windows; missing timing and coverage remain unavailable.
Known tracker conflict codes retain neutral, specific explanations through relaunch. Only reviewed
codes from a bounded 4 KiB JSON 409 response are retained; unknown codes, HTML and arbitrary response
details remain generic. A changed revision is evidence for review, not permission to rebind a target.

Settings delivery rows open a review screen. Opening it checks only local persistence and labels the
check time. Tracker comparison is an explicit read, bounded to 200 sets and consistent source/Life
revisions. Local intent, source observations and canonical website values are shown separately;
canonical pounds convert through the exact unit factor for display. Retired targets and history-only
observations do not imply canonical updates. No background comparison poll is started.

The review-recovery client also provides an explicit read-only comparison that brackets capture
pagination with two exact manifest reads. Both manifests and the capture must have the same Life
revision; inconsistent reads fail without changing cached plans or delivery intents. Only the
capture endpoint's bounded JSON `capture_not_found` response represents a capture not visible to
this installation. A generic 404, login page or network error is not capture absence. This absence
can also hide an installation mismatch and never resolves an uncertain delivery receipt. This
comparison now supports an explicit reviewed replacement-delivery action for confirmed revision
rejections. It does not provide history-only correction as a fallback.

Review a new delivery is available for an upsert after a known `life_revision_conflict` or `manifest_conflict`
with no uncertain ACK. The review compares current website values, manual ownership, schedule,
status and prescription differences. Exact cycle/session/exercise/slot/set identities and load bases
must remain unchanged. Equal or newer ambiguous source revisions, retired targets and tombstones
prevent preparation. Unknown outcomes must recover the original receipt first.

Prepare reviewed delivery checks the exact local recording again and obtains another unchanged
coherent tracker comparison. It retains the original event and actual observations, creates a new
immutable event, and keeps the replacement paused until Send prepared delivery is explicitly tapped.
Global-only changes retain the source revision; changed prescription hashes increment it. Original
start provenance is never rewritten. Concurrent edits invalidate the review, and repeated preparation
cannot create another event. This preparation changes sidecar metadata only, not SQLite or Life.
The retained reviewed write-plan snapshot is separate from the original start plan. Subsequent
corrections use the last accepted write precondition while preserving original start provenance;
a later global-only conflict does not become another prescription change merely because the start
plan was older. Historical deletion rebase and history-only correction remain separate work.
The [reviewed delivery design study](design/dhoop-reviewed-delivery-study.png) and
[built-in ImageGen prompt](design/dhoop-reviewed-delivery-study.prompt.txt) contain demo values.

Selected receipt recovery replays the original body only after verifying its current local recording.
Keep locally retains the event and its data, pauses automatic delivery for that capture across relaunch,
and leaves previously accepted website data unchanged. Explicit selected recovery remains available.

Verified completed receipts and deliberately paused, locally persisted intents can leave the active
queue after a complete file snapshot is written and read back. Pending reconciliation stays active.
Archived deliveries remain reviewable from Settings and workout history; receipt recovery retains the
original event body. Earlier archive snapshots are preserved rather than overwritten or removed.

Settings provides a separate `.dhoopworkouts` companion package for tracker manifests, original
capture IDs, delivery intents, receipts, archive snapshots and paused choices. It excludes Keychain
credentials and active unsaved sessions. Restore validates identifiers and immutable event conflicts
before merging, preserves existing metadata and leaves the connection off. It changes no SQLite rows.
Saved routines, sets, notes and sensor data still require the existing `.noopbak` database backup.
The [backup design study](design/dhoop-workout-metadata-backup-study.png) and
[built-in ImageGen prompt](design/dhoop-workout-metadata-backup-study.prompt.txt) contain demo data.
Package preparation/merge and archive recovery have local tests; the native Files export/import
workflow has not yet been verified on the physical iPhone.

### Exercise catalog and routine draft safety

Both exercise-entry sheets use one device-scoped catalog read model. A read failure retains the
last readable same-device entries but disables saving until an explicit successful retry. A verified
empty catalog still permits the first exercise. Late results for a previous source cannot replace
the selected source. The full searchable browser is separate from the short recently used hints;
muscles are user-assigned, and tracked load basis remains an explicit choice.

Exercise add/apply uses shared async controls, retains failed drafts, and holds fields while saving.
Catalog-limit errors use one readable action failure. Routine-item apply is labeled as a draft action;
the parent routine still commits its ordered lines atomically. Invalid nonempty numeric targets cannot
be silently converted to blank targets. Catalog forgetting no longer hides a failed delete/readback.

Existing routine editors do not turn a failed line read into an empty list that can overwrite the
program. An explicit retry preserves typed name/note. Routine and item writes retain their original
source identity when the active strap changes; deletion errors keep the editor open. No schema or
analytics change is introduced. Variations, supersets and durable pause intervals still require the
separately requested migration approval.

The [catalog recovery study](design/dhoop-exercise-catalog-recovery-study.png) and
[built-in generation/edit prompts](design/dhoop-exercise-catalog-recovery-study.prompt.txt) contain demo
names and classifications. Native browsing, editing and Dynamic Type behavior remain unverified on
the physical iPhone.

### Shared alarm, summary and activity actions

Alarm editing uses the shared asynchronous Save control. The editor remains open with its current
draft after permission, validation or storage failure; editing/dismissal is held only while saving.
Local save completion means the definition was persisted. Strap storage and felt vibration remain
separate. Explicit slot reading awaits six attributed, decodable records; a partial inventory or
changed link fails the action. Explicit sync retries await the existing owned-slot reconciler and
surface its error. These controls grant no new ownership or BLE command capability.

Life sync uses shared switches and action controls. Check & send summaries awaits one bounded pass,
instead of displaying queueing as completion. A dated accepted receipt is still the evidence of
website acceptance. Credential fields clear only after configuration succeeds; secure setup failures
remain visible. A failed enable-setting write no longer starts a forced export.

Activity review awaits the actual decision write and history readback. A committed decision with
failed readback is labeled separately and kept visible; it is not reported as a fully refreshed
history. Last readable review rows are retained after a same-device read failure, and rows from a
different selected strap are hidden. Sleep refresh and Exercises/Alarms navigation use shared press
feedback without chart gestures. Native confirmation dialogs are retained.

These are Apple interface/coordinator changes, with no analytics, SQL schema or backup-whitelist
change. The [action-state study](design/dhoop-alarm-sync-review-actions-study.png) and
[built-in ImageGen prompts](design/dhoop-alarm-sync-review-actions-study.prompt.txt) use demo states.
Physical UI behavior and manual network delivery of this build remain unverified.

The workout integration and matching Life receiver are local development work. Production deployment,
dedicated credentials and any Cloudflare path activation require separate authorization. Additional
history-only correction and activation verification require further work before this integration
is considered complete. Physical-device verification remains outstanding.
