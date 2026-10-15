# Sleep metric share graphic — build 503

Sleep → Share sleep freezes the currently selected wake date into a local preview and native
image share action. It does not sync, start live HR, upload to Life, or change stored sleep data.

## Included content

- WHOOP and the selected comparison provider have separate duration rings against the existing
  **8h 15m duration goal**. The percentage is duration-goal attainment, not a sleep quality score.
  An actual Eight Sleep provider is named **8sleep**, with its Apple Health transport identified.
  Other providers retain their actual names. A missing source stays unavailable on that date.
- The selected provider's timestamped stage diagram retains gaps and unclassified intervals.
  Stage totals are wake-date totals; a selected chart/HR window can cover one of several periods.
  Missing REM/deep/light values remain unavailable; recorded zero remains zero.
- Average HR uses positive measured readings from the selected sleep period, excluding recorded
  awake spans and gaps. A period with no timestamped stages instead uses its actual boundary
  window and explicitly says “sleep window.” The displayed count describes observations, not
  complete coverage or physiological accuracy.
- HRV and resting HR come from that exact stored sleep session where available, otherwise from
  the same source's record on the same wake date. No latest-date carry or other-provider fallback
  is used. Imported WHOOP rMSSD, unverified local HRV, and provider SDNN remain distinguished.
- Comparison heart metrics are read-only HealthKit quantities belonging to that provider and
  sleep window. Own-app writeback is excluded. No new permission prompt is triggered by export.
- **Snoring time is “Not collected.”** Dhoop currently has no snoring ingestion feed. No snoring
  duration, zero or sensor inference is manufactured. A real source integration is still needed
  before this field can contain a duration.

The preview and image use the same immutable report. Only rendered pixels enter the native share
sheet; internal attribution IDs are not rendered or attached as metadata. Sharing still requires
the user's native share action. The black artwork uses StrandDesign fonts, colors, spacing, cards
and progress components. The preview follows Dynamic Type; the exported image uses a fixed large
text style for a stable layout. Large-text headings wrap and the stage plot grows without crowded
clock ticks; its full clock range remains below the diagram. No chart gestures affect scrolling.

## Verification

- Signed iOS build 503 passed. The iOS-only views do not enter the macOS app target; Foundation
  projection tests compile/run on macOS. No package, schema or cross-platform backup contract changed.
- 22 sleep/export tests passed, including existing comparison regressions. The final four export
  tests passed again after adding the equal-bounds/different-owner regression: an episode's exact
  owner travels through one resolver into metric reads. Date/source isolation, missing versus zero,
  selected episodes, awake/gap/boundary exclusion and fractional HealthKit timestamps are covered.
- Four code-rendered fixtures passed and were inspected: standard dark artwork, narrow/light-parent
  artwork, accessibility-size preview and unavailable data. Their values are explicitly demo fixtures,
  never app data. Early simulator Busy launch failures were resolved by booting the simulator before
  rerunning. The final build-503 hosted render test passed.
- Build 503 installed on physical iPhone **0A-Homeboy**, preserving the stable bundle/team and app
  data container. Build 502 had launched normally; the final build-503 reopen was denied by iOS as
  locked. No wearer tests were requested. Actual provider availability/permissions and a manually
  saved production sleep image were not independently verified on the phone in this pass.
- Source doc-comment lint and diff hygiene passed. The English-only personal-fork copy still fails
  the localization extraction gate; no translation baseline was weakened.

No DB migration/reset, strap command, alarm change, credential rotation or background polling was
required. Android UI is unchanged. Numeric aggregation is presentation-only and writes no signal
or score back to storage.

Built-in ImageGen studies and exact prompts are saved in `docs/design/`:

- `dhoop-sleep-export-study.png` and `.prompt.txt`
- `dhoop-sleep-export-metrics-study.png` and `.prompt.txt`

Production artwork is rendered from source data by `SleepExportCard`, not from these demo bitmaps.
