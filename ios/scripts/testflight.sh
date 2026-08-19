#!/usr/bin/env bash
#
# testflight.sh: archive, export and upload Honk It Up! to App Store Connect.
#
# Usage:
#   bash scripts/testflight.sh --dry-run   archive, export and verify, NO upload
#   bash scripts/testflight.sh             the above, then upload
#
# THE ONE THING THIS SCRIPT EXISTS TO PREVENT
#
# A build's DISTRIBUTION AUDIENCE is fixed by Apple at UPLOAD time and can never
# be changed. A build uploaded as INTERNAL_ONLY can never reach the App Store:
# not through the UI, not through the API, not later. It simply does not appear
# in the version picker, and nothing tells you why. In the sibling repo
# Ryan4n6/TPS-iOS that cost six days of DEVELOPER_REJECTED states that looked
# like a submission bug, and it was invisible because the ship path's real job,
# getting a build to internal testers, worked perfectly every time.
#
# So the audience is checked twice: the export method BEFORE archiving, and the
# uploaded build's actual buildAudienceType AFTER, which is the only report that
# comes from Apple rather than from us.
#
# Prerequisites, already provisioned on this mac:
#   ~/.appstoreconnect/AuthKey_4X9H8LCJ7T.p8   the Massfeller LLC ASC API key
#   an Apple Distribution certificate for team 88JY59HYPS

set -euo pipefail

ASC_KEY_ID="4X9H8LCJ7T"
ASC_ISSUER="ffc0258c-d69f-4a90-a734-7e7b11dc4739"
ASC_KEY="$HOME/.appstoreconnect/AuthKey_${ASC_KEY_ID}.p8"
APP_ID="6802899812"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${ARCHIVE:-/tmp/HonkItUp.xcarchive}"
EXPORT_DIR="${EXPORT:-/tmp/HonkItUp-export}"
ASC="python3 $ROOT/scripts/asc.py"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# asc.py needs a CA bundle or HTTPS to Apple fails cert verification. Made
# self-contained so callers do not have to export it.
export SSL_CERT_FILE="${SSL_CERT_FILE:-$(python3 -c 'import certifi; print(certifi.where())' 2>/dev/null || true)}"

fail() { echo "FATAL: $*" >&2; exit 1; }

[[ -f "$ASC_KEY" ]] || fail "App Store Connect key not found at $ASC_KEY"

echo "[1/7] preflight, before anything is built"

# The export method decides the audience. Check it in the file rather than
# trusting that nobody edited it.
METHOD=$(/usr/libexec/PlistBuddy -c "Print :method" "$ROOT/exportOptions.plist")
[[ "$METHOD" == "app-store-connect" ]] || \
  fail "exportOptions.plist method is '$METHOD', not app-store-connect. Uploading with this would fix the wrong audience PERMANENTLY."
echo "      export method: $METHOD"

# project.yml is the source of truth for both numbers; the pbxproj is generated.
MARKETING=$(grep -E '^\s+MARKETING_VERSION:' "$ROOT/project.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
BUILD_NUMBER=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' "$ROOT/project.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "      version $MARKETING build $BUILD_NUMBER"

# The version string has to exist on App Store Connect and be editable, or the
# build uploads as an orphan no version record can see.
VERSION_STATE=$($ASC get "/v1/apps/$APP_ID/appStoreVersions?limit=20" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for v in d.get('data', []):
    a=v['attributes']
    if a.get('versionString') == '$MARKETING':
        print(a.get('appStoreState')); break
else:
    print('MISSING')
")
[[ "$VERSION_STATE" != "MISSING" ]] || \
  fail "App Store Connect has no version '$MARKETING'. Create it there first, or fix MARKETING_VERSION in project.yml to match."
echo "      ASC version $MARKETING is $VERSION_STATE"

# The build counter is global and monotonic. Apple rejects a duplicate, and a
# counter that never moves is its own quiet failure.
NEWEST=$($ASC get "/v1/builds?filter[app]=$APP_ID&limit=200" | python3 -c "
import json,sys
d=json.load(sys.stdin)
nums=[int(b['attributes']['version']) for b in d.get('data', []) if str(b['attributes'].get('version','')).isdigit()]
print(max(nums) if nums else 0)
")
echo "      newest build on ASC: $NEWEST"
[[ "$BUILD_NUMBER" -gt "$NEWEST" ]] || \
  fail "CURRENT_PROJECT_VERSION ($BUILD_NUMBER) is not ahead of the newest build on ASC ($NEWEST). Bump it in project.yml."

echo "[2/7] regenerating the project from project.yml"
( cd "$ROOT" && xcodegen generate )

echo "[3/7] archiving"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project "$ROOT/Mellophone.xcodeproj" \
  -scheme Mellophone \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER"

echo "[4/7] checking the archive itself"
APP_PLIST="$ARCHIVE/Products/Applications/Mellophone.app/Info.plist"
[[ -f "$APP_PLIST" ]] || fail "no Info.plist in the archive at $APP_PLIST"

check_key() {
  local key="$1" expected="$2"
  local actual
  actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_PLIST" 2>/dev/null || echo "MISSING")
  # Flatten newlines (array values print multi-line) and trim the ENDS only.
  # This used to be `tr -d '\n '`, which deletes every space including the ones
  # inside a value, so "Honk It Up!" became "HonkItUp!" and failed against
  # itself. A preflight that cries wolf is worse than no preflight.
  actual=$(echo "$actual" | tr '\n' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [[ "$actual" == *"$expected"* ]] || fail "$key is '$actual', expected to contain '$expected'"
  echo "      $key ok"
}

# Without this the build lands as "Missing Compliance": invisible to TestFlight
# testers and un-addable to a beta group, with no obvious cause.
check_key "ITSAppUsesNonExemptEncryption" "false"
# Without this iOS suspends the app on screen lock and the metronome dies, which
# is the one thing this app may never do.
check_key "UIBackgroundModes" "audio"
check_key "CFBundleShortVersionString" "$MARKETING"
check_key "CFBundleVersion" "$BUILD_NUMBER"
check_key "CFBundleDisplayName" "Honk It Up!"

# The privacy manifest has to ship, and it declares no collected data at all.
[[ -f "$ARCHIVE/Products/Applications/Mellophone.app/PrivacyInfo.xcprivacy" ]] || \
  fail "PrivacyInfo.xcprivacy is not in the archive"
echo "      privacy manifest present"

# The whole product promise: it works with no network. Prove the binary has no
# networking symbols rather than asserting it in a README.
BINARY="$ARCHIVE/Products/Applications/Mellophone.app/Mellophone"
NET=$(nm -u "$BINARY" 2>/dev/null | grep -icE "URLSession|CFNetwork|NSURLConnection" || true)
[[ "$NET" -eq 0 ]] || fail "the binary references $NET networking symbols; this app is supposed to make no network calls"
echo "      no networking symbols"

echo "[5/7] exporting"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$ROOT/exportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER"

IPA=$(find "$EXPORT_DIR" -name "*.ipa" | head -1)
[[ -n "$IPA" ]] || fail "no .ipa produced in $EXPORT_DIR"
echo "      $IPA ($(du -h "$IPA" | cut -f1))"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "[6/7] DRY RUN, stopping before the upload."
  echo "      Everything above is local and reversible. The upload is not:"
  echo "      Apple fixes the distribution audience the moment it lands."
  echo "      Re-run without --dry-run to send it."
  exit 0
fi

echo "[6/7] uploading"
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER"

echo "[7/7] confirming the audience Apple actually recorded"
echo "      waiting for the build to appear, this can take several minutes"
for attempt in $(seq 1 40); do
  AUDIENCE=$($ASC get "/v1/builds?filter[app]=$APP_ID&limit=200" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for b in d.get('data', []):
    if b['attributes'].get('version') == '$BUILD_NUMBER':
        print(b['attributes'].get('buildAudienceType') or 'UNKNOWN'); break
else:
    print('NOT_YET')
")
  if [[ "$AUDIENCE" != "NOT_YET" ]]; then
    echo "      build $BUILD_NUMBER audience: $AUDIENCE"
    [[ "$AUDIENCE" == "APP_STORE_ELIGIBLE" ]] || \
      fail "build $BUILD_NUMBER uploaded as $AUDIENCE and can NEVER reach the App Store. Bump the build number and upload again with method app-store-connect."
    echo
    echo "Done. Build $BUILD_NUMBER is App Store eligible."
    exit 0
  fi
  sleep 30
done

echo "      the build has not appeared yet. That is normal for a first upload."
echo "      Check the audience before relying on it:"
echo "        python3 scripts/asc.py get \"/v1/builds?filter[app]=$APP_ID&limit=10\""
echo "      It MUST read APP_STORE_ELIGIBLE."
