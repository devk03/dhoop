# Simpler Exercises — build 498

- Replaced the large text selector with native vector icons and retained accessible names/touch
  targets. Narrow widths and accessibility text can scroll the selector rather than compress labels.
- Exercises has one compact Test buzz control. Full delivery diagnostics and locked-phone caveats
  remain in Settings → WHOOP alerts → Troubleshooting. No alert engine, timing or wake alarm changed.
- Removed repeated HIIT buzz tests, routine delivery prose and the expanded meditation delivery
  explanation. Relevant paused/error states and storage failures remain visible.
- Strength opens the canonical Life workouts with compact refresh/program/settings controls.
  Manual credential fields live under Advanced connection; they are not part of the primary flow.
- Added explicitly invoked, one-time local setup into separate source/frontend Keychain entries.
  It reuses the existing phone identity, refuses incompatible credentials or existing source history,
  checks authenticated reads/capabilities without workout writes, and retains failed transfer data.
  Transfer contents retire only after verified Keychain storage and successful reads. No secrets are
  compiled, committed or logged. Optional Access headers are workout-specific; redirects stay denied.
- 70 selected client, receipt, endpoint, transport and provisioning tests passed. Signed iOS build
  passed, source-comment lint and diff hygiene passed. Build 498 installed on the physical iPhone.
  No manual wearer test was requested. New UI copy still has the previously documented localization
  coverage gap; no localization baseline or check was weakened.
- ImageGen layout reference and exact prompt are retained under docs/design/dhoop-simple-exercises-study.*.
  Illustration settings and dates are not app data.

The Life backend is published, but automatic phone connection is NOT activated yet. The exact
workout-only Cloudflare Access app and one-year service credential are staged for the browser
security policy's required action-time approval. Existing sleep, buzz, owner-login and MCP policies
remain unchanged. The corresponding source/frontend Worker secrets are not configured yet.
The private handoff stays outside Git. Frontend lifecycle stays off: native binding seed and
capture_only physical recording integration has not been implemented/verified end to end.

This is the owner's iOS frontend scope; Android and macOS UI are unchanged. There is no database
migration, physiological algorithm change, raw strap command addition, or firmware modification.
