# Native food estimates and shared calorie ranges

The existing Protein tile opens Food. Food name, protein grams, optional estimated kcal, and a
plus button are visible in one form; adding does not open a second editor. Single-day protein
and calorie subtotals share a compact card. The same date filter controls entries and range
averages. Protein history charts remain available for longer ranges. The keyboard has a Done
control. Success identifies a local save; failures retain the input.

## Data preservation and meaning

`dhoop.protein.entries` gains optional `calories` on the existing entry. IDs, days, protein amounts,
and logging timestamps stay intact. Missing calorie estimates decode as nil and encode without
a calorie field. Explicit zero remains valid. A calorie-only food can record zero grams. Legacy
Cut foods remain readable in the same daily display and are counted once. New quick-entry foods
do not create Cut days, change a weight target, apply calorie buffers, or trigger deficit math.
No health database migration or rewrite is involved.

Calorie subtotals include only recorded estimates. Coverage shows estimated entries versus all
entries; a day with only unknown estimates stays unavailable, rather than becoming zero.
Range averages include days with actual estimates, not unlogged days. These are logged subtotals,
not claims of complete daily intake or prescribed nutrition targets.

## Shared goals

Inclusive dated goal periods use `{id,startDate,endDate,minCalories,maxCalories}`. The default is
unset; equal bounds represent a single daily target. Real dates, UUID identities, ordered bounds,
nonoverlap, maximum 200 periods, and the existing Life limits are validated on both sides.

The Food screen performs a bounded goal read using the existing protein-only credential and
Access headers. Only a matching installation and validated read enable shared editing. It caches
the last successful document and preserves offline edit drafts on this phone. Save and Remove
are explicit actions against the read version. A conflict or uncertain outcome requires refresh
and a new action. Success requires readback containing the desired state and an increased version,
except for an already matching no-op. A credential/installation change hides the old cache.

The exact shared API contract lives in Life's `docs/integrations/DHOOP_NUTRITION.md`. GET uses only
`?resource=nutrition-goals`; POST has only the allowed upsert/remove envelope. No food records are
read through this adapter. No new credentials, Access destinations, Calendar permissions, or
recurring monitor are added. Widgets receive no nutrition credentials.

## Completed-day calorie summaries

The existing v2 protein payload may append optional `calorieSummary` with exactly four fields:
`calories`, `entryCount`, `estimatedEntryCount`, and `coverage:logged_estimates`. With no known
estimates, calories is JSON null. The count includes all food/protein records considered for
calorie coverage, independently from the unchanged protein-specific count. Individual food names,
records, and goals are not sent. This is a daily summary, not a live two-way food-row mirror.
Life's existing manual-value precedence remains in force.

Calorie export is separate from protein export. Under the owner's explicit request for both apps,
opening Food may enable the previously unconfigured calorie flag only after a verified goal read
and only when protein delivery is already on. An explicit false is preserved. The Life sync setting
retains a separate Calorie estimates switch. A calorie-bearing pending request is paused when
that switch is off; its immutable bytes are neither changed nor discarded, and it does not request repeated background retries while held. Existing sleep/protein
pending requests, revision order, acknowledgments, date mapping, and retry behavior stay compatible.
Delivery waits for completed dates and an iOS execution opportunity, as before.

## Verification

Build 520's targeted nutrition suite passed 33 tests: legacy entry preservation, zero versus
unknown estimates, calorie-only entries without Cut side effects, old pending bytes, count
semantics, exact request fields, dates/overlap/bounds, server readback, CAS refresh requirements,
connection identity, and locale-safe numeric entry (including pasted thousands separators). The new unversioned-success regression was observed failing before the
client fix and passing afterward. iOS and macOS builds and the localization/doc-comment gates
are checked separately from physical installation, UI renders, and authenticated production reads.

Native capture, with a new output directory and an unlocked physical iPhone:

```sh
Tools/capture-dhoop-food-log-ui.sh CORE_DEVICE_ID docs/design/food-log-implementation/NEW_VERSION
```

Fixtures use isolated defaults, fake credentials and a fake goal transport. They cannot connect to
Life, export real food, publish fake data, or modify owner goal drafts. The
[generated design study](design/dhoop-food-entry-study.png) contains demo data and is separate from
actual implementation evidence. Tests never create owner food or goal records in production.

## UI review map

| Before | After |
| --- | --- |
| Meal name hidden behind an optional disclosure | Food name is always visible above the amount row. |
| Protein amount only, with a separate wide add action | Protein, optional estimated kcal, and one plus action share the entry form. |
| Calorie-only legacy foods missing from the protein entry list | The daily food list includes them with unknown protein shown explicitly. |
| Separate tall daily metric summaries | Single-day protein and calorie subtotals share a compact responsive card. |
| No dated calorie preference editor | Collapsible From/Through range editor reads and saves the shared Life document. |
| No shared range conflict state | Busy/error/last-confirmed states retain the draft and require refresh before retrying. |
| No estimate coverage | Unknown calories remain unavailable and estimated/total entry counts stay visible. |
| Keyboard controls contributed by multiple forms | Only the focused form contributes its keyboard Done control. |
| No calorie export preference | Life sync has a separate Calorie estimates switch and respects explicit opt-outs. |

Build 520 was installed in place on the physical iPhone. Synthetic native Food, Calendar, Alarms,
and combined-ring captures are retained in docs/design; their READMEs distinguish known baseline
layout issues and unverified interaction states. A fresh authenticated Calendar read passed.
The nutrition read failed without error classification in build 520; build 521 adds safe
connection diagnostics before any credential changes or claim of active goal synchronization.
No physical VoiceOver, gesture, Home Screen placement, or new timer-vibration verification is claimed.

## Installed connection verification

Build 521 was installed in place and successfully read the production goal document (version 0,
no configured periods). Initial HTTP 409 installation_conflict was traced to a missing Worker
installation binding, not missing phone credentials. The sole installation in existing delivery
receipts matched the active phone. Binding that existing identity repaired the read without
rotating tokens, changing Access paths, altering receipts, or creating test food/goal records.
Calorie summaries are enabled alongside the existing protein connection. Existing food IDs,
legacy food content, and decoded wake-alarm configuration were preserved across the update.
