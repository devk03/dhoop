# Sleep metric share graphic

Sleep → Share sleep freezes the currently selected wake date into a local preview and native
image share action. It does not sync, start live HR, upload to Life, or change stored sleep data.

## Included content

- WHOOP and the selected comparison provider have separate duration rings against the existing
  **8h 15m duration goal**. The percentage is duration-goal attainment, not a sleep quality score.
  An actual Eight Sleep provider is named **8sleep**, with its Apple Health transport identified.
  Other providers retain their actual names. A missing source stays unavailable on that date.
- The selected provider's timestamped stage diagram retains gaps and unclassified intervals.
  Stage totals are wake-date totals; a selected chart/HR window can cover one of several periods.
  Missing REM/deep/light values are omitted from the compact totals; recorded zero remains zero.
- Average HR uses positive measured readings from the selected sleep period, excluding recorded
  awake spans and gaps. A period with no timestamped stages instead uses its actual boundary
  window and explicitly says “sleep window.” Sample counts remain in the app's detailed data,
  rather than repeated inside the share artwork.
- HRV and resting HR come from that exact stored sleep session where available, otherwise from
  the same source's record on the same wake date. No latest-date carry or other-provider fallback
  is used. Imported WHOOP rMSSD, unverified local HRV, and provider SDNN remain distinguished.
- Comparison heart metrics are read-only HealthKit quantities belonging to that provider and
  sleep window. Own-app writeback is excluded. No new permission prompt is triggered by export.
- **Snoring time is omitted while uncollected.** Dhoop currently has no snoring ingestion feed.
  The compact metric table includes a row only when a source has a finite recorded value. Missing
  comparison cells use an em dash; zero is not substituted for absence. A future real zero-minute
  snoring measurement remains displayable. No duration or sensor inference is manufactured.

## Compact layout

Two side-by-side duration rings share a single goal label. The stage diagram and its totals share
one panel, and one provider-labelled table replaces the two diagnostic heart-stat cards. Missing
metric rows, repeated source paragraphs and measurement-count copy are omitted. One footer names
the sources and wake-date basis. HRV retains rMSSD, SDNN, or an explicit unverified-method qualifier;
RHR from a daily record retains its wake-date qualifier. Unknown HRV methods are not relabelled.
The source resolver, sample windows, aggregation and stored data are unchanged.

The preview and image use the same immutable report. Only rendered pixels enter the native share
sheet; internal attribution IDs are not rendered or attached as metadata. Sharing still requires
the user's native share action. The black artwork uses StrandDesign fonts, colors, spacing, cards
and progress components. The preview follows Dynamic Type; the exported image uses a fixed large
text style for a stable layout. Large-text headings wrap and the stage plot grows without crowded
clock ticks; its full clock range remains below the diagram. No chart gestures affect scrolling.

## Original data verification — build 503

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

## Compact artwork verification — build 505

- Five Foundation export tests passed, including the new observed-row/method regression: absent,
  invalid and uncollected metrics are not presented as zeros; recorded zero stays displayable;
  local unverified HRV, imported rMSSD and provider SDNN retain their labels. Existing date/source,
  selected-episode and asleep-window tests passed unchanged.
- The final hosted render test passed with four inspected fixtures: 390×740 standard artwork,
  320×804 narrow artwork, 390×2428 accessibility-size preview and 390×403 unavailable-state
  artwork. The export is always rendered at the existing fixed large text size; the accessible
  preview can grow and scroll. Narrow stage totals use two columns instead of breaking values.
- At the supplied screenshot's 780-pixel width, the standard fixture corresponds to 780×1480
  instead of 780×3367, a 56% reduction in height. These rendered fixture values are demo data.
  Height ceilings of 800 points at 390 width and 900 at 320 catch a return to the stacked report.
- The localization gate against `705f838`, doc-comment lint and diff hygiene passed. New surface
  strings have translations; the joined clock range contains already-localized values and an
  en dash. No baseline was changed.
- The signed iOS build passed with products outside the synced Documents folder
  (`SYMROOT=/private/tmp/dhoop-505-build-products`); deep/strict signature verification passed.
  The default Documents output had Finder metadata that prevented signing. No certificate,
  profile, bundle identifier or app entitlement changed to resolve that packaging issue.
- Build 505 installed on physical iPhone **0A-Homeboy**, and an independent app-info read confirms
  `bundleVersion:505`. The normal app launch succeeded. No user test steps were required. A new
  production image from the owner's actual sleep records was not manually saved in this pass;
  export layout verification uses the production renderer with clearly identified demo fixtures.

No DB migration/reset, strap command, alarm change, credential rotation or background polling was
required. Android UI is unchanged. Numeric aggregation is presentation-only and writes no signal
or score back to storage.

Built-in ImageGen studies and exact prompts are saved in `docs/design/`:

- `dhoop-sleep-export-study.png` and `.prompt.txt`
- `dhoop-sleep-export-metrics-study.png` and `.prompt.txt`
- `dhoop-compact-sleep-share-study.png` and `.prompt.txt`

Production artwork is rendered from source data by `SleepExportCard`, not from these demo bitmaps.
