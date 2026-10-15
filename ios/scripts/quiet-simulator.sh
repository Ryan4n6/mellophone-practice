#!/bin/bash
# Boot the test simulator with its indexing turned off.
#
# A freshly booted simulator starts Spotlight's indexers and the media
# analysis services they call, and on this Mac they took enough of the
# machine to nearly stop it while the tests ran. A simulator has its own
# service manager and takes the same disable a Mac does. The setting is kept
# in the simulator's own data, so this is a no-op after the first time, and it
# is run every time anyway because "Erase All Content and Settings" or a new
# runtime brings the services back.
#
#   bash ios/scripts/quiet-simulator.sh            # the iPhone 17 the tests use
#   bash ios/scripts/quiet-simulator.sh <udid>
set -u

UDID="${1:-F261A484-12AC-4611-9344-348D0EB38138}"
SERVICES=(
  com.apple.spotlightknowledged.updater
  com.apple.spotlightknowledged
  com.apple.mediaanalysisd
  com.apple.mediaanalysisd.service
)

if ! xcrun simctl list devices | grep -q "$UDID"; then
  echo "[SIM] no simulator with id $UDID" >&2
  exit 1
fi

if ! xcrun simctl list devices | grep "$UDID" | grep -q Booted; then
  echo "[SIM] booting $UDID"
  xcrun simctl boot "$UDID" || { echo "[SIM] boot failed" >&2; exit 1; }
fi
xcrun simctl bootstatus "$UDID" >/dev/null 2>&1

SIM_UID="$(xcrun simctl spawn "$UDID" id -u 2>/dev/null || echo 501)"
for service in "${SERVICES[@]}"; do
  xcrun simctl spawn "$UDID" launchctl disable "user/$SIM_UID/$service"
  # Fails when the service is not running, which is the state wanted.
  xcrun simctl spawn "$UDID" launchctl bootout "user/$SIM_UID/$service" >/dev/null 2>&1
done

# Only lines that SAY disabled count. The listing names enabled services too
# ("=> enabled", or "=> false" on older runtimes), and counting every line
# that mentions a service made this check pass when the disables had failed
# (#37). Each service is looked for by its exact quoted name, because one
# name is the start of another.
LISTING="$(xcrun simctl spawn "$UDID" launchctl print-disabled "user/$SIM_UID" 2>/dev/null)"
OFF=0
for service in "${SERVICES[@]}"; do
  if printf '%s\n' "$LISTING" | grep -qE "\"$service\" => (disabled|true)"; then
    OFF=$((OFF + 1))
  else
    echo "[SIM] $service is not disabled" >&2
  fi
done
if [ "$OFF" -ge "${#SERVICES[@]}" ]; then
  echo "[SIM] $UDID is up with indexing off ($OFF services disabled)"
else
  echo "[SIM] only $OFF of ${#SERVICES[@]} indexing services report disabled on $UDID" >&2
  exit 1
fi
