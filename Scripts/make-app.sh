#!/usr/bin/env bash
# Scripts/make-app.sh — assemble and sign SignalLadder.app from the SPM build.
#
# There is no .xcodeproj by design: Package.swift is the single source of
# truth, and this script is the only thing that knows about bundle layout.
set -euo pipefail

CONFIG="${1:-debug}"
IDENTITY="${SIGNALLADDER_IDENTITY:-}"

# No default identity: a hash only works on the Mac whose keychain holds it,
# so a default would send everyone else to a codesign failure after a full
# build. Set it once in your shell profile instead:
#   export SIGNALLADDER_IDENTITY=<40-character SHA-1>
if [ -z "$IDENTITY" ]; then
    echo "error: SIGNALLADDER_IDENTITY is not set." >&2
    echo "       Set it to the 40-character SHA-1 of a code-signing identity in your keychain." >&2
    echo "       List candidates with: security find-identity -v -p codesigning" >&2
    echo "       An ad-hoc signature is not accepted: macOS would forget the Accessibility" >&2
    echo "       permission on every rebuild. docs/getting-started.md has the details." >&2
    exit 1
fi

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

# The signing identifier is read from Info.plist and not written here a second
# time. It is part of the Designated Requirement, so it decides whether macOS
# keeps a user's Accessibility grant, and two copies of it could drift apart
# and sign the app under a name its own Info.plist does not carry.
# Scripts/release.sh checks that the signature and the plist agree.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
[ -n "$BUNDLE_ID" ] || { echo "error: CFBundleIdentifier is empty in Resources/Info.plist" >&2; exit 1; }

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

# Which build this is (M5 plan, O12). Three keys go into the staged copy of
# Info.plist, so before the signature, which seals the file: the commit's short
# hash, the time of the build in UTC, and whether the files git tracks had
# changes that were not committed. Settings shows them as its version line, so a
# stale copy can be told from a new one when both say 0.1.0. They are not in
# Resources/Info.plist, so the repository holds no build's details, and
# Scripts/release.sh, which builds through this script, gets them with no change
# of its own: it already refuses a modified tree without --allow-dirty.
#
# The check is the one the M5 plan names, git status --porcelain
# --untracked-files=no, so a new file git does not track yet is not counted,
# though the build compiles it. The stamp then says the tracked files were
# unchanged, which is no claim that the build is exactly that commit.
#
# All three or none. Outside a git checkout (a source archive, say) there is no
# commit to name, and an unstamped build is still a build: the app then says its
# commit was not recorded. "Inside a checkout" means this folder is the top of
# one: a folder that sits inside some other repository has been copied out of
# its own, and would otherwise be stamped with that repository's commit. Each way
# of not stamping records its reason, and the build says which it was, so an
# unstamped build is not a mystery.
STAMP_COMMIT=""
STAMP_CHANGES=""
STAMP_SKIP=""
if ! INSIDE="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || [ "$INSIDE" != "true" ]; then
    # Git's own first line, when it gave one: it is what names a refusal such as
    # a checkout owned by another user, which looks like no checkout at all.
    SAID="$(git rev-parse --is-inside-work-tree 2>&1 >/dev/null | head -n 1 || true)"
    STAMP_SKIP="there is no git checkout here${SAID:+ (git said: $SAID)}"
elif [ -n "$(git rev-parse --show-prefix 2>/dev/null)" ]; then
    STAMP_SKIP="this folder is inside another repository and is not the top of one"
elif ! STAMP_COMMIT="$(git rev-parse --short=7 HEAD 2>/dev/null)" || [ -z "$STAMP_COMMIT" ]; then
    STAMP_COMMIT=""
    STAMP_SKIP="the checkout has no commit yet"
# If git cannot say whether the tracked files are modified, nothing is stamped: a
# build that claims to be clean on no evidence is worse than an unstamped one.
elif ! STAMP_CHANGES="$(git status --porcelain --untracked-files=no 2>/dev/null)"; then
    STAMP_COMMIT=""
    STAMP_SKIP="git status failed, so whether the tracked files have changes is not known"
fi
if [ -z "$STAMP_SKIP" ]; then
    if [ -n "$STAMP_CHANGES" ]; then STAMP_MODIFIED=true; else STAMP_MODIFIED=false; fi
    STAMP_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "==> Stamping the build ($STAMP_COMMIT, $STAMP_DATE, modified: $STAMP_MODIFIED)"
    /usr/libexec/PlistBuddy \
        -c "Add :SLBuildCommit string $STAMP_COMMIT" \
        -c "Add :SLBuildDate string $STAMP_DATE" \
        -c "Add :SLBuildModified bool $STAMP_MODIFIED" \
        "$STAGING/Contents/Info.plist"
else
    echo "==> Not stamping the build: $STAMP_SKIP"
fi

# The icon is a checked-in generated file (Scripts/make-icon.sh builds it from
# docs/assets/logo.svg); a build only copies it. It goes in before signing
# because the signature seals everything under Contents.
ICON="Resources/AppIcon.icns"
[ -f "$ICON" ] || { echo "error: $ICON not found. Regenerate it with Scripts/make-icon.sh." >&2; exit 1; }
cp "$ICON" "$STAGING/Contents/Resources/AppIcon.icns"

# A Developer ID signature asks Apple's timestamp service for a secure
# timestamp by default, and that service failed about half the time on
# 2026-09-25 ("A timestamp was expected but was not found"). Only
# notarisation needs the timestamp, so debug builds go without it. Nothing
# else changes: the Designated Requirement, and with it the Accessibility
# grant, depends on the identity and identifier, not the timestamp. Release
# builds still ask for one and still fail loudly without it.
if [ "$CONFIG" = "release" ]; then
    TIMESTAMP="--timestamp"
else
    TIMESTAMP="--timestamp=none"
fi

echo "==> Signing with $IDENTITY ($TIMESTAMP)"
codesign --force --options runtime "$TIMESTAMP" \
         --identifier "$BUNDLE_ID" \
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
