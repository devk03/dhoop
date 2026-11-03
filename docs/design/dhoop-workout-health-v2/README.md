# Health and workout interaction study

Generated with the built-in image generation tool. All photographs, measurements and dates are
fictional. This is a design study, not implementation verification. The app's existing tab structure
is retained; the board's illustrative navigation is not a proposal to replace it.

![Design study — demo data](design-study.png)

The intended hierarchy is an obvious New entry action, a photo-led private Health timeline, a compact
entry editor and inline workout set rows with clear local/remote save feedback. Use StrandDesign
components and tokens. Actual implementation captures will be labeled separately.

## Actual implementation — workout save flow

These are native iPhone 17 simulator captures on iOS 26.4, 1206 × 2622 pixels. All data is an isolated
synthetic fixture. The design study above is separate from these implementation screenshots.

| Before: Save rejects entered results without a separate Done tap | After: explicit Log action, values retained after relaunch |
| --- | --- |
| [![Before save validation](implementation-before/workout-save-requires-done-iphone17.png)](implementation-before/workout-save-requires-done-iphone17.png) | [![After logged results and relaunch](implementation-after/workout-logged-results-relaunched-iphone17.png)](implementation-after/workout-logged-results-relaunched-iphone17.png) |

Repeat the isolated flow using a Debug simulator build:

```sh
xcrun simctl launch SIMULATOR_ID com.devkunjadia.zhoop.loshi.noop \
  --workout-draft-ui-proof --workout-ui-run=NEW_UUID
```

Enter 145 in the first weight field and 9 in repetitions. The button becomes **Log entered sets**;
select it. Verify those exact values, one committed demo operation and untouched unlogged later rows.
Terminate/relaunch the same fixture with the same run UUID to inspect local draft persistence. This
fixture is not a live Life server and is not end-to-end production evidence. Capture the displayed
state with an absolute output path:

```sh
xcrun simctl io SIMULATOR_ID screenshot /absolute/output/workout-state.png
```

The real UI was inspected using computer use. Narrow-screen, accessibility, delay/offline scenarios,
Lower workflows, the Health redesign and physical-device evidence remain separate pending checks.
