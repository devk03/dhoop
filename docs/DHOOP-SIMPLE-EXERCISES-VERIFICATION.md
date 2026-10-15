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

The owner approved the workout-only connection. Cloudflare Access app
`a9ca68b3-bd68-4fd0-8b9f-5e4a263b419e` now grants only the dedicated one-year
Dhoop Workout iPhone service token through Service Auth, on the two workout paths on
track.kunjadia.dev and tracker.kunjadia.dev. Existing sleep, buzz, owner-login and MCP
policies remain unchanged. Life configured the five dedicated workout bindings; active
Worker version is `a06635a7-330b-4d59-b06c-eb0b2c9b0760` (runtime `e0f1ae3`).

Life's 19 live checks passed: authenticated dashboard/catalog/manifest and capabilities;
separate source/frontend bearer enforcement; missing Access rejection; unrelated row,
sleep, buzz and photos-route rejection; and lifecycle start rejection. No accepted workout
write or Life revision change occurred. Manual commands are permitted, frontend start is
not. Native binding seed and capture_only physical recording integration remain unverified.

The private one-time envelope was copied to the physical iPhone with mode 0600. iOS
currently rejects both foreground and non-activating setup launches because the device
is locked. Keychain import and on-phone authenticated reads are not yet verified; the
private handoff remains intact for the requested brief unlock. No wearer test is required.

This is the owner's iOS frontend scope; Android and macOS UI are unchanged. There is no database
migration, physiological algorithm change, raw strap command addition, or firmware modification.
