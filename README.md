<p align="center">
  <img src="docs/assets/dhoop-icon.png" alt="Dhoop" width="96">
</p>

<h1 align="center">Dhoop</h1>

<p align="center"><b>An on-device WHOOP companion for heart health, sleep, and cardio training.</b></p>

<p align="center"><sub>A personal fork of <a href="https://github.com/hackyguru/zhoop">Zhoop</a>, built on <a href="https://github.com/ryanbr/noop">NOOP</a>. Offline, on-device, no account, no cloud.</sub></p>

---

## Why this fork exists

[NOOP](https://github.com/ryanbr/noop) is an excellent open-source, local-first app for WHOOP straps:
it pairs over Bluetooth, keeps everything on your device, and computes recovery, strain, HRV and sleep
itself. It shows a lot.

[Dhoop](https://github.com/devk03/dhoop) is a personal fork of [Zhoop](https://github.com/hackyguru/zhoop)
focused on historical heart metrics, sleep comparisons, and cardio training. Weight and deficit
tracking are optional and off by default. The Bluetooth and local analytics foundation comes from NOOP.

## Today, Sleep, and Cardio

- **Today:** historical heart-rate averages, HRV, steps, independent protein logging, and dated VO₂ max
  records. Metric cards open a shared range selector with custom dates and averages over recorded data.
  The dashboard uses snapshots refreshed every 15 minutes or at midnight, rather than updating with
  every received packet. **Live HR · 60s** starts a temporary capture inside the heart-rate card.
- **Chart inspection:** touch and hold, then drag to inspect a recorded value and its date or time.
  Missing readings remain gaps; source and method labels distinguish imported records and estimates.
- **Sleep:** choose a date range and compare WHOOP records or local estimates with a selected Apple
  Health provider, including Eight Sleep when its records are available. Providers stay separate;
  matched-night averages use dates available from both sources.
- **Cardio:** zone-targeted runs count only observed time in the chosen zone. HIIT and interval plans
  support five-second timing increments and optional WHOOP vibration cues. History combines local
  sessions and saved/imported workouts with date, type, and search filters. Auto-detection suggests
  sustained activity for review; it does not guarantee detection of short intervals.
- **Goals:** optional weight-loss tools retain Zhoop's food, weight, and deficit tracking. Protein-only
  logging and its optional target work independently. Body measurements follow the selected metric
  or imperial preference without changing stored units.
- **Data collection:** the WHOOP status row opens device, receipt, storage, freshness, and sync evidence.
  A Bluetooth connection alone does not prove successful streaming or persistence.

Devices, Apple Health, Goals, and Settings are reached from the gear on Today.

## Status and data portability

This is a personal iPhone fork, tested with WHOOP 5.0 / MG. Shared Apple components are also compiled
for macOS; Android remains in the repository but does not have feature parity with this iPhone interface.
Locally estimated metrics are not official WHOOP scores, and collection evidence does not validate
physiological accuracy. See the [verification record](docs/dhoop-heart-running-verification.md) for
builds, tests, hardware observations, and remaining checks.

Keep Dhoop open for reliable interval timing. If iOS interrupts timing, the interval session pauses
instead of skipping ahead through missed cues. Background vibration behavior still needs exercise testing.

The general `.noopbak` backup does **not** include local zone runs and HIIT/interval files. Cardio
history provides a separate JSON export containing those records and drafts. Keep both exports when
preserving your data; the Cardio JSON export currently has no in-app restore.

## Build and run on an iPhone

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. `cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig`, then set your own
   `BUNDLE_ID_PREFIX` and `DEVELOPMENT_TEAM` in it. That file is gitignored.
2. `xcodegen generate`
3. Open `Strand.xcodeproj`, choose the **NOOPiOS** scheme and your iPhone, and run.

Pairing a WHOOP 5.0 / MG needs the strap freed from the official WHOOP app first; see
[docs/IOS.md](docs/IOS.md) and the pairing notes in [NOOP's README](https://github.com/ryanbr/noop#readme).

## Credit

The weight-loss interface comes from [hackyguru/zhoop](https://github.com/hackyguru/zhoop).

All the hard work under the hood belongs to **NOOP** and its contributors:
[github.com/ryanbr/noop](https://github.com/ryanbr/noop). NOOP in turn builds on
[johnmiddleton12/my-whoop](https://github.com/johnmiddleton12/my-whoop) and
[b-nnett/goose](https://github.com/b-nnett/goose); see [ATTRIBUTION.md](ATTRIBUTION.md) and [NOTICE](NOTICE).

Most documents in [`docs/`](docs/), [CHANGELOG.md](CHANGELOG.md), and the contributor guides come from
NOOP. Dhoop-specific verification notes and design references are documented separately.

## License

Dhoop is a fork of Zhoop and NOOP and stays under NOOP's license,
[PolyForm Noncommercial 1.0.0](LICENSE): free for noncommercial use.

Required Notice: Copyright 2026 NoopApp

Dhoop is not affiliated with, endorsed by, or connected to WHOOP, Inc. or the NOOP project. "WHOOP"
is used only to identify the hardware the app works with.
