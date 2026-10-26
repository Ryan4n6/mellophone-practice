#!/usr/bin/env bash
#
# make-golden.sh: what the iOS chart reader says about each of our charts, for
# scripts/check-score.js to hold the web app's port to (#58).
#
#   bash scripts/score-golden/make-golden.sh
#
# Builds dump.swift against the app's own sources (the reader, the timeline,
# the renderer), then writes one golden file per committed fixture beside this
# script. Charts in ios/MellophoneTests/Fixtures/local/ (Sam's, never
# committed) get theirs in that folder's golden/, which git ignores with the
# rest of it. Run it after changing the Swift reader or timeline, and commit
# the golden files that change with the Swift change that changed them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/scripts/score-golden"
APP="$ROOT/ios/Mellophone"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "[GOLDEN] building the Swift reader"
# TonePlayer.swift's class plays through the app's engine, which a command
# line tool does not have. Its static renderer is all the dump needs.
python3 - "$APP/Audio/TonePlayer.swift" "$BUILD/TonePlayer.swift" <<'PY'
import sys
s = open(sys.argv[1]).read()
a, b = s.index('final class TonePlayer {'), s.index('    static func render(frequency:')
open(sys.argv[2], 'w').write(s[:a] + 'enum TonePlayer {\n' + s[b:])
PY
# Top level code is only allowed in a file called main.swift.
cp "$HERE/dump.swift" "$BUILD/main.swift"
swiftc -O -enable-bare-slash-regex -o "$BUILD/dump" \
  "$BUILD/main.swift" "$APP"/Import/*.swift "$APP/App/Log.swift" \
  "$APP/Model/Note.swift" "$APP/Model/NoteData.swift" "$APP/Model/Instrument.swift" "$APP/Model/NoteCheck.swift" \
  "$APP/Audio/Pitch.swift" "$APP/Audio/PartTimeline.swift" "$APP/Audio/ToneSequence.swift" "$APP/Audio/ClapSound.swift" \
  "$BUILD/TonePlayer.swift"

dump() { "$BUILD/dump" "$1" 2>/dev/null > "$2"; echo "[GOLDEN] $(basename "$2"): $(grep -c '^E' "$2") events"; }

FIX="$ROOT/ios/MellophoneTests/Fixtures"
for pdf in "$FIX"/*.pdf "$APP/Resources/Sample Chart - Band Room March.pdf"; do
  dump "$pdf" "$HERE/$(basename "$pdf" .pdf | tr ' ' '_').txt"
done
if compgen -G "$FIX/local/*.pdf" > /dev/null; then
  mkdir -p "$FIX/local/golden"
  for pdf in "$FIX"/local/*.pdf; do dump "$pdf" "$FIX/local/golden/$(basename "$pdf" .pdf | tr ' ' '_').txt"; done
fi
