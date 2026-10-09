# Inline protein logging

The home Protein card and its Log protein action both open the same Protein screen.
The grams input and Add protein action are visible at the top. Adding an entry keeps
this screen open, clears the input, and displays the saved amount and timestamp.
Optional meal naming and the independent daily target use inline disclosures.
History filters, known food protein, entry removal, and averages remain available.

The implementation uses StrandDesign tokens, NoopCard and NoopButtonStyle. Large
Dynamic Type stacks the input and action. The saved-status region reserves space.
Protein-only entries continue to use ProteinLogStore and never create a calorie day.
No database schema or export-contract change is required. This is an iOS navigation
change; the other platforms do not use ProteinLogCard.

## Design study

[Generated reference](protein-inline-entry-study.png). All displayed data is fictional.
Generated using the built-in imagegen tool. The app uses its existing button tokens
and range controls; the image is a hierarchy reference, not a pixel-perfect contract.

Final prompt:

Use case: ui-mockup. High-fidelity iPhone Dhoop Protein screen design study, flat screenshot without phone frame, black background, dark rounded surfaces, restrained deep teal protein accent, clean native iOS typography. Navigation header Protein with Done. Immediately below header, visible inline Log protein today card: a large compact text field with placeholder Grams, adjacent g unit and prominent Add protein button; optional Meal label hidden under disclosure. No separate logging sheet, no extra navigation. Below show Week Month All Custom time controls, average logged protein metric, gradient teal bar chart, and entries list. Keep input primary and instantly accessible, metrics secondary. Optional target under a collapsed disclosure. Touch targets spacious; readable text, no giant cards. Top label Design study - Demo data. Chart numbers fictional. Single screen portrait. Use no green lime accents. No status bar fake chrome.

## Verification — October 9, 2026

- Signed iOS build 456 passed and was installed and launched on 0A-Homeboy.
- Simulator build passed with fresh DerivedData after a stale missing C-module cache failure.
- Simulator UI: tapping the Today card opens the visible grams field; saving 12.5 g
  keeps the same screen open, clears the field, shows confirmation, updates the total
  and entry list, and updates Today to 12.5 g. The home Log protein action opens the
  same inline input. Test entries were added only in the simulator.
- Large Dynamic Type has an adaptive stacked layout; physical-phone logging and
  large-type/VoiceOver interactions have not been user-confirmed.
