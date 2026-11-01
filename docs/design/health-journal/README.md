# Health journal design and visual verification

`concept-v1.png` is a generated design study using fictional notes and abstract art, not an implementation capture. The exact built-in imagegen prompt is in `concept-v1.prompt.txt`. Native implementation uses existing StrandDesign tokens, fonts and feedback components, with localization across shipped languages.

Actual implementation screenshots have **not** been captured for build 529. No simulator or new phone installation was used. Do not substitute the generated study for visual verification or a PR gallery. Physical layout, compact tab overflow/reselection, keyboard/picker behavior, VoiceOver, Dynamic Type and reduced-motion behavior remain unverified.

After an owner-authorized installation of build 529, repeat actual synthetic native capture using `HealthJournalRenderProof.runIfRequested`:

```sh
xcrun devicectl device process launch --device "$DHOOP_DEVICE_ID" \
  com.devkunjadia.zhoop.loshi.noop --terminate-existing \
  -- --health-journal-render-proof --health-render-run="$DHOOP_CAPTURE_RUN_UUID"
xcrun devicectl device copy from --device "$DHOOP_DEVICE_ID" \
  --domain-type appDataContainer --domain-identifier com.devkunjadia.zhoop.loshi.noop \
  --source tmp/dhoop-health-ui-v1 --destination "$DHOOP_NEW_CAPTURE_FOLDER"
```

Choose a fresh UUID and new output folder; perform this only when interrupting/relaunching the app is acceptable. Wait for the finite capture run to finish before copying. Verify result.json has the expected build/runId, rendered=true, syntheticOnly=true and networkUsed=false. The harness only uses isolated fixture clients, not owner entries, credentials or photos.

Prepared cases: timeline dark/light at390pt, narrow320pt, accessibility text size, editor, topic input, detail, empty, unconfigured connection and read failure. Remaining captures should also exercise actual keyboard, loading/saving, correction conflict/history, pending photos and validation behavior before a UI PR. Keep labeled actual captures under a new versioned subdirectory; retain earlier captures. No UI PR is created by this change.
