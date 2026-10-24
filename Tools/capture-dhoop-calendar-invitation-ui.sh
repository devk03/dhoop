#!/bin/zsh
# Bounded native implementation renders, synthetic data only. Does not read owner calendars or credentials.
set -euo pipefail
dhoop_capture_device="${1:?Usage: capture-dhoop-calendar-invitation-ui.sh CORE_DEVICE_ID [NEW_OUTPUT_DIRECTORY]}"
dhoop_capture_output="${2:-docs/design/calendar-invitation-implementation/$(date -u '+%Y%m%dT%H%M%SZ')}"
if [[ -e "$dhoop_capture_output" ]]; then
  print -u2 'Choose a new output directory to preserve earlier captures.'
  exit 1
fi
dhoop_capture_probe=$(mktemp -d /private/tmp/dhoop-calendar-invitation-capture.XXXXXX)
dhoop_capture_run=$(uuidgen)
xcrun devicectl device process launch --device "$dhoop_capture_device" --terminate-existing --timeout 30 \
  com.devkunjadia.zhoop.loshi.noop --calendar-invitation-render-proof "--calendar-invitation-render-run=$dhoop_capture_run" > "$dhoop_capture_probe/launch.log" 2>&1
for dhoop_capture_attempt in {1..8}; do
  if xcrun devicectl device copy from --device "$dhoop_capture_device" --domain-type appDataContainer \
    --domain-identifier com.devkunjadia.zhoop.loshi.noop --source tmp/dhoop-calendar-invitation-ui-v1/result.json \
    --destination "$dhoop_capture_probe/result-$dhoop_capture_attempt.json" --timeout 10 > "$dhoop_capture_probe/read-$dhoop_capture_attempt.log" 2>&1; then
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));sys.exit(0 if d.get("rendered") and d.get("syntheticOnly") and d.get("fixtureNetworkUsed") is False and d.get("runId")==sys.argv[2] else 1)' \
      "$dhoop_capture_probe/result-$dhoop_capture_attempt.json" "$dhoop_capture_run"; then
      mkdir -p "$(dirname "$dhoop_capture_output")"
      xcrun devicectl device copy from --device "$dhoop_capture_device" --domain-type appDataContainer \
        --domain-identifier com.devkunjadia.zhoop.loshi.noop --source tmp/dhoop-calendar-invitation-ui-v1 \
        --destination "$dhoop_capture_output" --timeout 30
      print "Implementation renders: $dhoop_capture_output"
      exit 0
    fi
  fi
  sleep 2
done
print -u2 "Capture did not finish successfully. Inspect $dhoop_capture_probe; no output is claimed."
exit 1
