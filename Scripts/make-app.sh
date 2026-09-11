#!/usr/bin/env bash
# Scripts/make-app.sh — assemble and sign SignalLadder.app from the SPM build.
#
# There is no .xcodeproj by design: Package.swift is the single source of
# truth, and this script is the only thing that knows about bundle layout.
set -euo pipefail

CONFIG="${1:-debug}"
IDENTITY="${SIGNALLADDER_IDENTITY:-0C46A31C354444B7CC472CD29DE37303A090E844}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/SignalLadder.app"
BIN=".build/${CONFIG}/SignalLadder"

echo "==> Building (${CONFIG})"
swift build -c "$CONFIG" --product SignalLadder

[ -f "$BIN" ] || { echo "error: $BIN not found after build" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SignalLadder"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Signing with $IDENTITY"
codesign --force --options runtime \
         --identifier com.jamiewhite.signalladder \
         --sign "$IDENTITY" \
         "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo
echo "Note: the Designated Requirement is deliberately NOT read here."
echo "codesign -d has been observed to hang on this machine; run it yourself if needed:"
echo "  codesign -d -r- $APP"
