#!/usr/bin/env bash
# Scripts/make-app.sh — assemble and sign SignalLadder.app from the SPM build.
#
# There is no .xcodeproj by design: Package.swift is the single source of
# truth, and this script is the only thing that knows about bundle layout.
set -euo pipefail

CONFIG="${1:-debug}"
IDENTITY="${SIGNALLADDER_IDENTITY:-0C46A31C354444B7CC472CD29DE37303A090E844}"

# Ad-hoc signing ("-") is rejected deliberately, not overlooked. It silently
# drops --identifier and degrades the Designated Requirement to a per-build
# cdhash, which destroys the Accessibility permission grant on every rebuild.
# A build that fails loudly is recoverable in seconds; one that is silently
# signed wrong costs a re-grant every time until somebody works out why.
if [[ ! "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo "error: SIGNALLADDER_IDENTITY must be the 40-character SHA-1 of a signing identity." >&2
    echo "       Got: '${IDENTITY}'" >&2
    echo "       Ad-hoc ('-') and name-based identities are rejected on purpose — see above." >&2
    echo "       List candidates with: security find-identity -v -p codesigning" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/SignalLadder.app"
STAGING="build/.SignalLadder.app.staging"
BIN=".build/${CONFIG}/SignalLadder"

# Assemble and sign in a staging path, and only replace the existing bundle
# once everything has succeeded. A failure anywhere leaves the previous good
# bundle untouched rather than destroying it and leaving an unsigned one
# behind at the same path.
trap 'rm -rf "$STAGING"' EXIT

echo "==> Building (${CONFIG})"
swift build -c "$CONFIG" --product SignalLadder

[ -f "$BIN" ] || { echo "error: $BIN not found after build" >&2; exit 1; }

echo "==> Assembling"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN" "$STAGING/Contents/MacOS/SignalLadder"
cp Resources/Info.plist "$STAGING/Contents/Info.plist"

echo "==> Signing with $IDENTITY"
codesign --force --options runtime \
         --identifier com.jamiewhite.signalladder \
         --sign "$IDENTITY" \
         "$STAGING"

echo "==> Verifying"
codesign --verify --deep --strict "$STAGING"

echo "==> Installing to $APP"
rm -rf "$APP"
mv "$STAGING" "$APP"

echo "Built $APP"
echo
echo "Note: the Designated Requirement is deliberately NOT read back here."
echo "codesign -d has been observed to hang on this machine; run it yourself if needed:"
echo "  codesign -d -r- $APP"
