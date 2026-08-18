#!/usr/bin/env bash
#
# run-device.sh: build, install and launch Mellophone on a physical iPhone.
#
# Signing resolves headlessly through the Massfeller LLC App Store Connect API
# key plus -allowProvisioningUpdates, which also registers the App ID and the
# development profile on first run. No Xcode GUI step, no hand-managed profiles.
#
# Usage:
#   bash scripts/run-device.sh              # first paired device
#   bash scripts/run-device.sh <device-id>  # a specific one
#
# List devices with: xcrun devicectl list devices

set -euo pipefail

ASC_KEY_ID="4X9H8LCJ7T"
ASC_ISSUER="ffc0258c-d69f-4a90-a734-7e7b11dc4739"
ASC_KEY="$HOME/.appstoreconnect/AuthKey_${ASC_KEY_ID}.p8"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.massfeller.mellophone"
DERIVED="$ROOT/build/DeviceDD"

if [[ ! -f "$ASC_KEY" ]]; then
  echo "FATAL: App Store Connect key not found at $ASC_KEY" >&2
  exit 1
fi

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  # Match the UUID by shape, not by column index. The Model column contains
  # spaces ("iPhone 16 Pro (iPhone17,1)"), so a positional $(NF-2) picks up the
  # literal string "16" and every downstream command then fails on a device id
  # that does not exist.
  #
  # Do NOT filter on a specific state word. A usable phone reports "available
  # (paired)" over the network and plain "connected" over USB, and filtering for
  # one of them made this script exit SILENTLY under `set -e` when the phone was
  # plugged in, which is the exact moment it is supposed to work. Exclude the
  # states that are genuinely no good instead, and say so out loud.
  #
  # `|| true` keeps a no-match from killing the script before the error message
  # below can explain what happened.
  DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
    | grep -i iphone \
    | grep -viE 'unavailable|no DDI' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1 || true)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  echo "FATAL: no usable iPhone found. Current devices:" >&2
  xcrun devicectl list devices 2>&1 | sed 's/^/  /' >&2
  echo >&2
  echo "A phone showing 'no DDI' needs Developer Mode on (Settings > Privacy &" >&2
  echo "Security > Developer Mode, which requires a restart) and to be unlocked." >&2
  exit 1
fi
echo "[1/4] device $DEVICE_ID"

echo "[2/4] regenerating project from project.yml"
( cd "$ROOT" && xcodegen generate )

echo "[3/4] building for device"
xcodebuild \
  -project "$ROOT/Mellophone.xcodeproj" \
  -scheme Mellophone \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER" \
  build

APP="$DERIVED/Build/Products/Debug-iphoneos/Mellophone.app"
if [[ ! -d "$APP" ]]; then
  echo "FATAL: built app not found at $APP" >&2
  exit 1
fi

echo "[4/4] installing and launching"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
# --terminate-existing matters: installing over a RUNNING app does not restart
# it, so without this you screenshot the old build and chase a bug that was
# already fixed. (Learned the hard way in TPS-iOS.)
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  "$BUNDLE_ID"

cat <<'NOTE'

Installed and launched.

The DEBUG build shows a live timing readout at the bottom of the Metronome tab:
beats sounded, audio-clock vs wall-clock elapsed, their skew, and the worst
schedule error so far. That panel is the evidence for the timing claim in
issue #3.
NOTE
