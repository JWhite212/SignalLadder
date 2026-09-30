#!/usr/bin/env bash
# Scripts/release.sh — turn a commit into a signed, notarised, stapled DMG, on
# this Mac.
#
#   SIGNALLADDER_IDENTITY=<40-character SHA-1> Scripts/release.sh
#   SIGNALLADDER_IDENTITY=<40-character SHA-1> Scripts/release.sh --skip-notarize --allow-dirty
#
# It runs Scripts/make-app.sh release, checks the result, has Apple notarise
# the app and staples the ticket to it, wraps that app in a DMG, signs the DMG,
# has Apple notarise the DMG and staples that too. The app is notarised before
# it goes into the DMG so the app carries its own ticket: a first launch works
# with no network, even after it has been dragged out of the image.
#
# WHAT IT NEVER DOES. It never uploads, tags, publishes, installs into
# /Applications or launches the app it built. Publishing is the maintainer's
# step, after the DMG has been tried on a clean account (docs/dev/releasing.md).
# What it does contact is Apple: the timestamp service whenever it signs, and,
# without --skip-notarize, the notary service.
#
# Inputs
#   SIGNALLADDER_IDENTITY  Required. The 40-character SHA-1 of a "Developer ID
#                         Application" certificate in the keychain. Anything
#                         else is refused: a development or distribution
#                         certificate signs an app that cannot be notarised.
#   NOTARY_PROFILE        A notarytool keychain profile. Default: SignalLadder.
#                         Create it once with `xcrun notarytool store-credentials`.
#   DEVELOPER_DIR         Honoured as usual, to pick which Xcode builds.
#
# Flags
#   --skip-notarize       A dry run. Everything except Apple's notary service and
#                         stapling. It still signs, so it still asks Apple for a
#                         timestamp. Output names end in -unnotarized, and the
#                         file is not for anyone else.
#   --allow-dirty         Build even with uncommitted changes. Without it a dirty
#                         tree is refused, so a release is always a commit.
#
# Output, in build/release/
#   SignalLadder-<version>.dmg          (SignalLadder-<version>-unnotarized.dmg)
#   SignalLadder-<version>.dmg.sha256   for the file above, from shasum -a 256
#   SignalLadder-<version>.build.txt    commit, toolchain, checks and sizes
# Files are written only once every check has passed. A run that fails leaves
# nothing there that looks like a release.
#
# Why it is built the way it is
#   - The calls that can wait are bounded. Apple's tools have hung on this Mac
#     (codesign -d, seen by the maintainer) and macOS has no timeout(1), so those
#     calls go through bounded(), which uses perl's alarm. A call that overstays
#     is killed and reported as timed out, never waited on.
#   - The signing identifier is read from Resources/Info.plist, never written
#     here. The bundle identifier and the Team ID together make the Designated
#     Requirement, which is what a user's Accessibility grant is keyed on, so
#     the script checks the signature carries exactly the plist's identifier
#     and the expected team, and stops if they differ.
#   - Apple's timestamp service failed about half the time on 2026-09-25 and
#     more often than that on 2026-09-30 (see TIMESTAMP_TRIES), so a signing
#     step that fails on a timestamp is retried, and a hung one is not.
#   - The notarytool output is read as a property list with plutil, and a
#     submission counts as accepted only if the status reads exactly Accepted.
#     Anything unreadable stops the run.
#
# Measured, 2026-09-30, macOS 26.7.1, Apple silicon, Xcode 27.0 (27A5228h, a
# beta), Apple Swift 6.4: --skip-notarize --allow-dirty took 98 s and made an app
# of 3.98 MB and a DMG of 2.83 MB. The first real run against Apple's notary
# service, the same day and toolchain, took 312 s: both submissions accepted,
# both tickets stapled, and spctl said Notarized Developer ID for both. Only the
# success path has met Apple; a rejection has been tried on canned answers
# alone. docs/dev/releasing.md has the rest.

set -euo pipefail

# ------------------------------------------------------------------ constants

# The Team ID is half of the Designated Requirement. It is baked into every
# user's Accessibility grant, so a build signed by any other team is a
# different app to macOS, and every user would have to grant access again
# (maintainer's decision, 2026-09-30: the seller is the maintainer as an
# individual). Changing it is a one-line edit, made on purpose.
EXPECTED_TEAM_ID="RVVRP4WY6B"

# Notarisation is usually quick and occasionally is not. notarytool stops
# waiting after NOTARY_WAIT, and Apple carries on processing; the outer bound
# is there only in case notarytool itself hangs.
NOTARY_WAIT="40m"
NOTARY_WAIT_SECONDS=2700

# Apple's timestamp service fails often enough that a retry or two is not
# enough. Measured on 2026-09-30: 23 of 33 signing attempts failed with "A
# timestamp was expected but was not found", each after about 15 s, in runs of up
# to five in a row, and a later attempt got through every time. At that rate five
# tries all fail one time in six (0.7 to the fifth is 0.17) and ten about one
# time in thirty-five. The DMG is signed after the app has been through
# notarisation, so giving up there would throw that wait away.
TIMESTAMP_TRIES=10
TIMESTAMP_PAUSE=10

# What bash reports for a process that perl's alarm killed with SIGALRM.
TIMED_OUT=142

# ---------------------------------------------------------------------- state

SKIP_NOTARIZE=0
ALLOW_DIRTY=0
WORK=""
MNT=""
MOUNTED=0
KEEP_WORK=0
LAST_SUBMISSION_ID=""
APP_SUBMISSION="not submitted"
DMG_SUBMISSION="not submitted"
DR_READ_BACK="yes"
CAP_OUT=""
CAP_RC=0

# ------------------------------------------------------------------- helpers

die()  { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
indent() { sed 's/^/    /'; }

# shellcheck disable=SC2016  # the perl program is single-quoted on purpose
bounded() {
    local seconds="$1"
    shift
    perl -e 'alarm shift @ARGV; exec @ARGV or die "cannot run $ARGV[0]: $!\n"' "$seconds" "$@"
}

# bounded, with the output kept in CAP_OUT (stderr included) and the status in
# CAP_RC, so the caller can look at both without set -e ending the run.
capture() {
    local seconds="$1"
    shift
    CAP_RC=0
    CAP_OUT="$(bounded "$seconds" "$@" 2>&1)" || CAP_RC=$?
}

# bounded, run up to <attempts> times with a pause between them. A call that
# timed out is not tried again: a hang is a prompt or a fault, and doing it
# three times only makes the wait three times as long.
retry() {
    local attempts="$1" pause="$2" seconds="$3" n rc=0
    shift 3
    n=1
    while [ "$n" -le "$attempts" ]; do
        rc=0
        bounded "$seconds" "$@" || rc=$?
        if [ "$rc" -eq 0 ]; then
            return 0
        fi
        if [ "$rc" -eq "$TIMED_OUT" ]; then
            return "$rc"
        fi
        if [ "$n" -lt "$attempts" ]; then
            warn "${*:1:3} failed (attempt $n of $attempts, exit $rc); trying again in ${pause}s."
            sleep "$pause"
        fi
        n=$((n + 1))
    done
    return "$rc"
}

# bounded, with the output shown as it arrives and copied to a log. The status
# returned is the command's, not tee's.
run_logged() {
    local log="$1" seconds="$2" rc=0
    shift 2
    set +e
    bounded "$seconds" "$@" 2>&1 | tee "$log"
    rc="${PIPESTATUS[0]}"
    set -e
    return "$rc"
}

# A command and what it said, for the final report. Sets CAP_OUT and CAP_RC.
show_check() {
    echo "  \$ $*"
    capture 60 "$@"
    if [ -n "$CAP_OUT" ]; then
        printf '%s\n' "$CAP_OUT" | sed 's/^/      /'
    fi
    if [ "$CAP_RC" -eq "$TIMED_OUT" ]; then
        echo "      (timed out after 60 s)"
    else
        echo "      (exit $CAP_RC)"
    fi
}

# The bytes in every regular file under a path, and the same as decimal
# megabytes, which is how Finder counts.
tree_bytes() { find "$1" -type f -exec stat -f %z {} + | awk '{ s += $1 } END { print s + 0 }'; }
megabytes()  { awk -v b="$1" 'BEGIN { printf "%.2f MB", b / 1000000 }'; }

# 14.0 and 14.0.1 as numbers that compare, so a missing part counts as zero.
version_number() { awk -F. '{ printf "%d", $1 * 1000000 + $2 * 1000 + $3 }' <<<"$1"; }

usage() {
    cat <<'EOF'
Usage: SIGNALLADDER_IDENTITY=<40-character SHA-1> Scripts/release.sh [--skip-notarize] [--allow-dirty]

Builds, signs, notarises and staples build/release/SignalLadder-<version>.dmg.
It never uploads, tags, publishes, installs or launches anything.

  --skip-notarize  Dry run: no Apple notary service, no stapling. Output names
                   end in -unnotarized.
  --allow-dirty    Build with uncommitted changes (refused by default).

Environment:
  SIGNALLADDER_IDENTITY  40-character SHA-1 of a "Developer ID Application" identity.
  NOTARY_PROFILE        notarytool keychain profile (default: SignalLadder).
  DEVELOPER_DIR         Which Xcode to build with.

See docs/dev/releasing.md.
EOF
}

beta_banner() {
    {
        echo "!!"
        echo "!! THIS XCODE IS A BETA: $BETA_REASON"
        echo "!! $XCODE_LINE"
        echo "!! A release is built with a released Xcode. A beta compiler and SDK can change"
        echo "!! between seeds, and what customers run should be what a released toolchain built."
        echo "!! Install the released Xcode and run this again with DEVELOPER_DIR set to it."
        echo "!!"
    } >&2
}

cleanup() {
    if [ "$MOUNTED" -eq 1 ] && [ -n "$MNT" ]; then
        bounded 60 hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
    fi
    if [ -n "$WORK" ] && [ -d "$WORK" ]; then
        if [ "$KEEP_WORK" -eq 1 ]; then
            echo "The working folder was kept for inspection: $WORK" >&2
        else
            rm -rf "$WORK"
        fi
    fi
}

# --------------------------------------------------------------------- inputs

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize|--skip-notarise) SKIP_NOTARIZE=1 ;;
        --allow-dirty) ALLOW_DIRTY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
    shift
done

IDENTITY="${SIGNALLADDER_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-SignalLadder}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for tool in perl git security codesign lipo hdiutil ditto shasum plutil xcrun xcodebuild swift stat awk sed find sw_vers; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found. It ships with macOS or Xcode."
done
PLISTBUDDY=/usr/libexec/PlistBuddy
[ -x "$PLISTBUDDY" ] || die "$PLISTBUDDY not found."

START_SECONDS=$SECONDS
START_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    step "Dry run (--skip-notarize): nothing will be submitted to Apple's notary service"
else
    step "Release: the app and the DMG will be submitted to Apple's notary service"
fi

# ------------------------------------------------------------------- identity

step "Checking the signing identity"

if [ -z "$IDENTITY" ]; then
    echo "error: SIGNALLADDER_IDENTITY is not set." >&2
    if [ -n "${SIGNALLADER_IDENTITY:-}" ]; then
        echo "       SIGNALLADER_IDENTITY is set, with one D. The name has two, as in Ladder: SIGNALLADDER_IDENTITY." >&2
    fi
    echo "       Set it to the 40-character SHA-1 of your Developer ID Application certificate." >&2
    echo "       List candidates with: security find-identity -v -p codesigning" >&2
    exit 1
fi
hash_re='^[0-9A-Fa-f]{40}$'
[[ "$IDENTITY" =~ $hash_re ]] || die "SIGNALLADDER_IDENTITY must be the 40-character SHA-1 of a signing identity. Got: '$IDENTITY'"
IDENTITY="$(printf '%s' "$IDENTITY" | tr 'a-f' 'A-F')"

IDENTITIES="$(security find-identity -v -p codesigning 2>&1)" || die "security find-identity failed: $IDENTITIES"
IDENTITY_LINE=""
while IFS= read -r line; do
    case "$line" in
        *") $IDENTITY \""*) IDENTITY_LINE="$line" ;;
    esac
done <<<"$IDENTITIES"
[ -n "$IDENTITY_LINE" ] || die "$IDENTITY is not among the valid code-signing identities in your keychain. An expired or revoked certificate is not listed. See: security find-identity -v -p codesigning"

IDENTITY_NAME="${IDENTITY_LINE#*\"}"
IDENTITY_NAME="${IDENTITY_NAME%\"*}"
case "$IDENTITY_NAME" in
    "Developer ID Application: "*) ;;
    *) die "$IDENTITY is '$IDENTITY_NAME'. Only a \"Developer ID Application\" certificate signs an app that can be notarised for distribution outside the App Store." ;;
esac
team_re='\(([A-Z0-9]{10})\)$'
[[ "$IDENTITY_NAME" =~ $team_re ]] || die "cannot read a Team ID from the identity name '$IDENTITY_NAME'."
IDENTITY_TEAM="${BASH_REMATCH[1]}"
[ "$IDENTITY_TEAM" = "$EXPECTED_TEAM_ID" ] || die "the identity belongs to team $IDENTITY_TEAM but this script expects $EXPECTED_TEAM_ID. The team is part of every user's Accessibility grant; see EXPECTED_TEAM_ID at the top of this script."
note "$IDENTITY_NAME"

# ------------------------------------------------------------------ toolchain

step "Recording the toolchain"

DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
[ -n "$DEV_DIR" ] || die "no developer directory: xcode-select -p printed nothing and DEVELOPER_DIR is not set."

XCODE_VERSION="$(bounded 60 xcodebuild -version 2>&1)" || die "xcodebuild -version failed or timed out: $XCODE_VERSION"
SWIFT_VERSION="$(bounded 60 swift --version 2>&1)" || die "swift --version failed or timed out: $SWIFT_VERSION"
XCODE_LINE="$(printf '%s' "$XCODE_VERSION" | tr '\n' ',' | sed 's/,/, /g; s/, $//')"
MACOS_VERSION="$(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"

# Two signs that Xcode is a beta: Apple installs it as Xcode-beta.app, and its
# Info.plist names an icon called XcodeBeta. Measured 2026-09-30 on this Mac:
# Xcode 27.0, build 27A5228h, at /Applications/Xcode-beta.app, icon XcodeBeta.
# Neither is a promise, so a beta with both renamed would pass unremarked, and
# the build number is no help: Xcode 16.2 was released under a four-digit build.
BETA=0
BETA_REASON=""
dev_dir_lower="$(printf '%s' "$DEV_DIR" | tr '[:upper:]' '[:lower:]')"
case "$dev_dir_lower" in
    *beta*) BETA=1; BETA_REASON="the developer directory is $DEV_DIR" ;;
esac
XCODE_APP="${DEV_DIR%/Contents/Developer}"
if [ "$BETA" -eq 0 ] && [ -f "$XCODE_APP/Contents/Info.plist" ]; then
    icon_name="$("$PLISTBUDDY" -c 'Print :CFBundleIconName' "$XCODE_APP/Contents/Info.plist" 2>/dev/null || true)"
    case "$icon_name" in
        *Beta*) BETA=1; BETA_REASON="its app icon is $icon_name" ;;
    esac
fi

printf '%s\n' "$XCODE_VERSION" | indent
printf '%s\n' "$SWIFT_VERSION" | indent
note "Developer directory: $DEV_DIR"
note "macOS $MACOS_VERSION"
if [ "$BETA" -eq 1 ]; then
    beta_banner
fi

# ------------------------------------------------------------------ the source

step "Reading the version"

PLIST="$ROOT/Resources/Info.plist"
plist_get() { "$PLISTBUDDY" -c "Print :$1" "$PLIST" 2>/dev/null || die "cannot read $1 from Resources/Info.plist"; }

VERSION="$(plist_get CFBundleShortVersionString)"
BUILD_NUMBER="$(plist_get CFBundleVersion)"
BUNDLE_ID="$(plist_get CFBundleIdentifier)"
EXECUTABLE="$(plist_get CFBundleExecutable)"
MIN_OS="$(plist_get LSMinimumSystemVersion)"

version_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
[[ "$VERSION" =~ $version_re ]] || die "CFBundleShortVersionString '$VERSION' is not a version like 1.0.0. It becomes part of a file name."
id_re='^[A-Za-z0-9.-]+$'
[[ "$BUNDLE_ID" =~ $id_re ]] || die "CFBundleIdentifier '$BUNDLE_ID' has characters a bundle identifier should not."
note "SignalLadder $VERSION (build $BUILD_NUMBER), $BUNDLE_ID, macOS $MIN_OS and later"

TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    tag_commit="$(git rev-parse --short "$TAG^{commit}")"
    warn "the tag $TAG already exists, at $tag_commit. This script never tags, so this is only a reminder: if that version was released, bump CFBundleShortVersionString and the changelog first."
fi

COMMIT="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
DIRTY="$(git status --porcelain)"
note "Commit ${COMMIT:0:12} on $BRANCH"
if [ "$BRANCH" != "main" ]; then
    warn "this is not the main branch (it is $BRANCH). A release is normally a commit on main."
fi
if [ -n "$DIRTY" ]; then
    if [ "$ALLOW_DIRTY" -eq 1 ]; then
        warn "the tree has uncommitted changes, and --allow-dirty was given. This build is not a commit and cannot be rebuilt from one:"
        printf '%s\n' "$DIRTY" | head -10 | indent >&2
    else
        echo "error: the tree has uncommitted changes, so this build would not be a commit:" >&2
        printf '%s\n' "$DIRTY" | head -10 | indent >&2
        echo "       Commit them, or pass --allow-dirty for a build that is not a release." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------- output paths

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    SUFFIX="-unnotarized"
else
    SUFFIX=""
fi
# Relative to the repository root, which the script changes into, so what it
# prints is short enough to read.
OUT_DIR="build/release"
BASE_NAME="SignalLadder-${VERSION}${SUFFIX}"
DMG_NAME="${BASE_NAME}.dmg"
APP="build/SignalLadder.app"

mkdir -p "$OUT_DIR"

# A finished, notarised DMG is what has been (or is about to be) published, and
# its checksum with it. Building the same version again gives different bytes,
# so it must be deleted on purpose, not overwritten by a run that was started
# for some other reason. A dry run's output is throwaway and is replaced.
if [ "$SKIP_NOTARIZE" -eq 0 ] && [ -e "$OUT_DIR/$DMG_NAME" ]; then
    die "$OUT_DIR/$DMG_NAME already exists. A second build of the same version has different bytes and a different checksum. Delete it yourself if you mean to build it again, or bump the version."
fi

WORK="$(mktemp -d "$OUT_DIR/.work.XXXXXX")"
trap cleanup EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------- notary credentials

# Checked before the build, not after it: a mistyped profile name should cost a
# few seconds, not a build and a wait. `history` only lists past submissions.
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    step "Checking the notarytool profile '$NOTARY_PROFILE'"
    rc=0
    bounded 120 xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>"$WORK/history.err" || rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ -s "$WORK/history.err" ]; then
            indent <"$WORK/history.err" >&2
        fi
        if [ "$rc" -eq "$TIMED_OUT" ]; then
            die "notarytool did not answer in 120 s. A keychain prompt may be waiting behind another window, or Apple's service may be down."
        fi
        die "notarytool cannot use the profile '$NOTARY_PROFILE'. Create it once with 'xcrun notarytool store-credentials', or set NOTARY_PROFILE to one that exists. docs/dev/releasing.md has the steps."
    fi
    note "The profile works."
fi

# ----------------------------------------------------------------------- build

step "Building the release app (Scripts/make-app.sh release)"
export SIGNALLADDER_IDENTITY="$IDENTITY"

attempt=1
while :; do
    rc=0
    run_logged "$WORK/make-app.log" 1500 "$ROOT/Scripts/make-app.sh" release || rc=$?
    if [ "$rc" -eq 0 ]; then
        break
    fi
    if [ "$rc" -eq "$TIMED_OUT" ]; then
        die "the build did not finish in 25 minutes and was stopped. A keychain prompt for the signing key may be waiting behind another window."
    fi
    # Only the timestamp is worth another go. Anything else would fail the same
    # way. The log always mentions "--timestamp" in its Signing line, so match
    # what codesign says when the service fails, not the word.
    if grep -qiE "timestamp service|timestamp was expected" "$WORK/make-app.log"; then
        if [ "$attempt" -lt "$TIMESTAMP_TRIES" ]; then
            warn "signing the app failed on Apple's timestamp service (attempt $attempt of $TIMESTAMP_TRIES). Trying again in ${TIMESTAMP_PAUSE}s; the compile is already done."
            sleep "$TIMESTAMP_PAUSE"
            attempt=$((attempt + 1))
            continue
        fi
        die "Apple's timestamp service did not answer in $TIMESTAMP_TRIES tries. It is unreliable at times, so wait a few minutes and run this again."
    fi
    die "the build failed (exit $rc). The log is above."
done
[ -d "$APP" ] || die "$APP does not exist after the build."

# ----------------------------------------------------------------- the binary

step "Checking the executable"

BIN="$APP/Contents/MacOS/$EXECUTABLE"
[ -f "$BIN" ] || die "$BIN not found."
ARCHS="$(lipo -archs "$BIN")"
[ "$ARCHS" = "arm64" ] || die "the executable has architectures '$ARCHS'. SignalLadder is Apple silicon only, so it must be exactly arm64. Was this run from a Rosetta terminal?"
note "Architectures: $ARCHS"

# The binary carries its own idea of the oldest macOS it will start on, which
# comes from Package.swift and not from Info.plist. If it were newer than the
# plist says, the app would be offered to Macs it then refuses to start on.
MINOS=""
if capture 60 xcrun vtool -show-build "$BIN" && [ "$CAP_RC" -eq 0 ]; then
    MINOS="$(printf '%s\n' "$CAP_OUT" | awk '$1 == "minos" { print $2; exit }')"
fi
if [ -n "$MINOS" ]; then
    if [ "$(version_number "$MINOS")" -gt "$(version_number "$MIN_OS")" ]; then
        die "the executable needs macOS $MINOS but Info.plist promises $MIN_OS. Check the platform in Package.swift."
    fi
    note "Runs on macOS $MINOS and later (Info.plist says $MIN_OS)"
else
    warn "could not read the executable's minimum macOS with vtool, so it was not compared with Info.plist's $MIN_OS."
    MINOS="unknown"
fi

# ------------------------------------------------------------------- signature

step "Checking the signature"

verify_signature() {
    local target="$1" rc=0
    bounded 120 codesign --verify --deep --strict --verbose=2 "$target" 2>&1 | indent || rc="${PIPESTATUS[0]}"
    if [ "$rc" -eq "$TIMED_OUT" ]; then
        die "codesign --verify timed out on $target."
    fi
    if [ "$rc" -ne 0 ]; then
        die "codesign --verify failed on $target (exit $rc)."
    fi
}
verify_signature "$APP"
note "codesign --verify --deep --strict passed."

capture 60 codesign -dvv -r- "$APP"
if [ "$CAP_RC" -eq "$TIMED_OUT" ]; then
    # codesign -d has hung on this Mac before. Nothing after this point could
    # honestly say the requirement was read back, so a real release stops here.
    if [ "$SKIP_NOTARIZE" -eq 1 ]; then
        warn "codesign -d timed out after 60 s, as it has before on this Mac. The designated requirement was NOT read back. Continuing only because this is a --skip-notarize run."
        DR_READ_BACK="no, codesign -d timed out"
    else
        die "codesign -d timed out after 60 s, as it has before on this Mac, so the designated requirement could not be read back. A release is not made without that check. Try again; if it keeps timing out, run --skip-notarize to see whether the rest is sound."
    fi
elif [ "$CAP_RC" -ne 0 ]; then
    printf '%s\n' "$CAP_OUT" | indent >&2
    die "codesign -d failed on the app (exit $CAP_RC)."
else
    SIG_DETAILS="$CAP_OUT"
    DR_LINE="$(printf '%s\n' "$SIG_DETAILS" | grep 'designated =>' || true)"
    [ -n "$DR_LINE" ] || die "codesign printed no designated requirement."
    printf '%s\n' "$SIG_DETAILS" | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp)=|^CodeDirectory' | indent || true
    printf '%s\n' "$DR_LINE" | indent

    [[ "$DR_LINE" == *"identifier \"$BUNDLE_ID\""* ]] || die "the designated requirement does not name the identifier '$BUNDLE_ID' from Info.plist. The app was signed as something else, so a user's Accessibility grant would not carry over."
    ou_re="subject[.]OU[]] = \"?${EXPECTED_TEAM_ID}\"?"
    [[ "$DR_LINE" =~ $ou_re ]] || die "the designated requirement does not name team $EXPECTED_TEAM_ID."
    [[ "$SIG_DETAILS" == *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]] || die "the signature's TeamIdentifier is not $EXPECTED_TEAM_ID."
    [[ "$SIG_DETAILS" == *"(runtime)"* ]] || die "the Hardened Runtime flag is missing, and Apple's notary service refuses an app without it."
    [[ "$SIG_DETAILS" == *"Timestamp="* ]] || die "the signature has no secure timestamp, and Apple's notary service refuses one without it."
    note "The designated requirement names $BUNDLE_ID and team $EXPECTED_TEAM_ID. Hardened Runtime and a secure timestamp are present."
fi

# --------------------------------------------------------------- notarisation

# Submit a file, wait, and stop unless Apple says Accepted. Sets LAST_SUBMISSION_ID.
notarise() {
    local file="$1" label="$2"
    local out="$WORK/notary-$label.plist" err="$WORK/notary-$label.err"
    local rc=0 id status

    step "Notarising the $label with Apple"
    note "Nothing prints until Apple answers. The wait gives up after $NOTARY_WAIT, and Apple carries on processing after that."
    bounded "$NOTARY_WAIT_SECONDS" xcrun notarytool submit "$file" \
        --keychain-profile "$NOTARY_PROFILE" --wait --timeout "$NOTARY_WAIT" \
        --output-format plist >"$out" 2>"$err" || rc=$?

    id="$(plutil -extract id raw -o - "$out" 2>/dev/null || true)"
    if [ -z "$id" ]; then
        if [ -s "$err" ]; then
            indent <"$err" >&2
        fi
        if [ -s "$out" ]; then
            indent <"$out" >&2
        fi
        if [ "$rc" -eq "$TIMED_OUT" ]; then
            die "notarytool did not finish in $NOTARY_WAIT_SECONDS s and gave no submission id. Look at the submission list with: xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
        fi
        die "notarytool reported no submission id (exit $rc), so nothing here can say whether the $label was accepted. Look at the submission list with: xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
    fi
    LAST_SUBMISSION_ID="$id"
    note "Submission $id"

    status="$(plutil -extract status raw -o - "$out" 2>/dev/null || true)"
    if [ -z "$status" ]; then
        # Not every notarytool version puts the status in the submit output.
        # Ask for it rather than assume.
        bounded 120 xcrun notarytool info "$id" --keychain-profile "$NOTARY_PROFILE" \
            --output-format plist >"$out.info" 2>>"$err" || true
        status="$(plutil -extract status raw -o - "$out.info" 2>/dev/null || true)"
    fi

    if [ "$status" = "Accepted" ]; then
        note "Apple accepted the $label."
        return 0
    fi

    echo "Apple did not accept the $label. Status: ${status:-unknown}." >&2
    if [ "$status" = "In Progress" ]; then
        die "Apple was still processing submission $id when the wait ended. Ask again later with: xcrun notarytool info $id --keychain-profile $NOTARY_PROFILE"
    fi
    echo "Apple's log for submission $id (xcrun notarytool log):" >&2
    bounded 120 xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || warn "could not fetch the log."
    die "the $label was not accepted; nothing was stapled or written to build/release."
}

# Sign the DMG with a secure timestamp, trying again only when the timestamp
# service is what failed. Any other failure would fail the same way each time.
sign_dmg() {
    local n=1
    while :; do
        capture 120 codesign --force --sign "$IDENTITY" --timestamp "$1"
        if [ -n "$CAP_OUT" ]; then
            printf '%s\n' "$CAP_OUT" | indent
        fi
        if [ "$CAP_RC" -eq 0 ]; then
            return 0
        fi
        if [ "$CAP_RC" -eq "$TIMED_OUT" ]; then
            die "codesign timed out signing the DMG. A keychain prompt may be waiting behind another window."
        fi
        if [[ "$CAP_OUT" == *"imestamp"* ]]; then
            if [ "$n" -lt "$TIMESTAMP_TRIES" ]; then
                warn "signing the DMG failed on Apple's timestamp service (attempt $n of $TIMESTAMP_TRIES). Trying again in ${TIMESTAMP_PAUSE}s."
                sleep "$TIMESTAMP_PAUSE"
                n=$((n + 1))
                continue
            fi
            die "Apple's timestamp service did not answer in $TIMESTAMP_TRIES tries. It is unreliable at times, so wait a few minutes and run this again."
        fi
        die "codesign could not sign the DMG (exit $CAP_RC)."
    done
}

# Attach the ticket. The ticket can take a little while to reach the CDN
# stapler reads from, so a miss just after Accepted is tried again.
staple() {
    if ! retry 5 20 300 xcrun stapler staple "$1"; then
        die "stapler could not attach the ticket to $1. Apple accepted it, so this may be the ticket not having reached the CDN yet: try 'xcrun stapler staple' on the file again in a few minutes. The working folder was kept."
    fi
}

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    APP_ZIP="$WORK/SignalLadder-${VERSION}-app.zip"
    step "Zipping the app for the notary service"
    bounded 300 ditto -c -k --keepParent "$APP" "$APP_ZIP" || die "ditto could not zip the app."
    note "$(megabytes "$(stat -f %z "$APP_ZIP")") zip"
    KEEP_WORK=1
    notarise "$APP_ZIP" "app"
    APP_SUBMISSION="$LAST_SUBMISSION_ID, Accepted"
    step "Stapling the app"
    staple "$APP"
    verify_signature "$APP"
    note "The stapled app still verifies."
    KEEP_WORK=0
else
    step "Skipping notarisation and stapling of the app (--skip-notarize)"
fi

# ------------------------------------------------------------------------- DMG

step "Building the DMG"

STAGE="$WORK/dmg-root"
DMG="$WORK/$DMG_NAME"
VOLNAME="SignalLadder $VERSION"
mkdir -p "$STAGE"
# ditto, not cp: it keeps the signature's extended attributes and the ticket.
bounded 120 ditto "$APP" "$STAGE/$(basename "$APP")" || die "ditto could not copy the app into the DMG folder."
ln -s /Applications "$STAGE/Applications"

bounded 300 hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" 2>&1 | indent \
    || die "hdiutil create failed."
[ -f "$DMG" ] || die "hdiutil did not make $DMG."

step "Signing the DMG"
sign_dmg "$DMG"
capture 60 codesign --verify --strict --verbose=2 "$DMG"
printf '%s\n' "$CAP_OUT" | indent
[ "$CAP_RC" -eq 0 ] || die "the signed DMG does not verify (exit $CAP_RC)."
capture 60 codesign -dvv "$DMG"
if [ "$CAP_RC" -eq 0 ]; then
    printf '%s\n' "$CAP_OUT" | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp)=' | indent || true
elif [ "$CAP_RC" -eq "$TIMED_OUT" ]; then
    warn "codesign -d timed out on the DMG. Its details were not read back; the verify above passed."
fi

# Look inside what will be shipped, before waiting on Apple for it. Mounted
# read-only, out of sight of Finder, on a path inside the working folder.
step "Checking what is inside the DMG"
MNT="$ROOT/$WORK/mount"
mkdir -p "$MNT"
bounded 120 hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MNT" "$DMG" >/dev/null 2>"$WORK/attach.err" \
    || { indent <"$WORK/attach.err" >&2; die "hdiutil could not mount the DMG to check it."; }
MOUNTED=1
[ -d "$MNT/$(basename "$APP")" ] || die "the DMG does not hold $(basename "$APP")."
[ -L "$MNT/Applications" ] && [ "$(readlink "$MNT/Applications")" = "/Applications" ] \
    || die "the DMG's Applications link is missing or points somewhere else."
[ "$(lipo -archs "$MNT/$(basename "$APP")/Contents/MacOS/$EXECUTABLE")" = "arm64" ] \
    || die "the app inside the DMG is not arm64 only."
verify_signature "$MNT/$(basename "$APP")"
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    bounded 60 xcrun stapler validate "$MNT/$(basename "$APP")" 2>&1 | indent \
        || die "the app inside the DMG does not carry a stapled ticket."
fi
note "The DMG holds an arm64 $(basename "$APP") whose signature verifies, and an Applications link."
detach_ok=0
for n in 1 2 3; do
    if bounded 60 hdiutil detach "$MNT" >/dev/null 2>&1; then
        detach_ok=1
        break
    fi
    sleep 2
done
if [ "$detach_ok" -eq 0 ]; then
    bounded 60 hdiutil detach "$MNT" -force >/dev/null 2>&1 || warn "could not unmount $MNT."
fi
MOUNTED=0

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    KEEP_WORK=1
    notarise "$DMG" "dmg"
    DMG_SUBMISSION="$LAST_SUBMISSION_ID, Accepted"
    step "Stapling the DMG"
    staple "$DMG"
else
    step "Skipping notarisation and stapling of the DMG (--skip-notarize)"
fi

# ----------------------------------------------------------- final verification

step "Final verification"
FAILS=0

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    note "This build was not notarised, so Gatekeeper is expected to reject it. What they report:"
fi

show_check spctl -a -t exec -vv "$APP"
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    if [ "$CAP_RC" -ne 0 ] || [[ "$CAP_OUT" != *"source=Notarized Developer ID"* ]]; then
        warn "the app is not assessed as Notarized Developer ID."
        FAILS=$((FAILS + 1))
    fi
fi

show_check spctl -a -t open --context context:primary-signature -vv "$DMG"
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    if [ "$CAP_RC" -ne 0 ] || [[ "$CAP_OUT" != *"source=Notarized Developer ID"* ]]; then
        warn "the DMG is not assessed as Notarized Developer ID."
        FAILS=$((FAILS + 1))
    fi
fi

# A dry run never touches stapler, not even to validate: there is nothing to
# find, and the dry run's promise is that it stays away from notarisation.
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    show_check xcrun stapler validate "$APP"
    if [ "$CAP_RC" -ne 0 ]; then
        warn "the app has no valid stapled ticket."
        FAILS=$((FAILS + 1))
    fi

    show_check xcrun stapler validate "$DMG"
    if [ "$CAP_RC" -ne 0 ]; then
        warn "the DMG has no valid stapled ticket."
        FAILS=$((FAILS + 1))
    fi
fi

if [ "$FAILS" -gt 0 ]; then
    KEEP_WORK=1
    die "$FAILS final check(s) failed. Both files were accepted by Apple, so nothing needs submitting again: the stapled DMG is in the working folder, and nothing was written to build/release."
fi
KEEP_WORK=0

# --------------------------------------------------------------------- outputs

step "Writing the outputs"

APP_BYTES="$(tree_bytes "$APP")"
mv -f "$DMG" "$OUT_DIR/$DMG_NAME"
DMG_BYTES="$(stat -f %z "$OUT_DIR/$DMG_NAME")"
(cd "$OUT_DIR" && shasum -a 256 "$DMG_NAME" >"$DMG_NAME.sha256" && shasum -a 256 -c "$DMG_NAME.sha256") | indent
DMG_SHA="$(awk '{ print $1 }' "$OUT_DIR/$DMG_NAME.sha256")"

RECORD="$OUT_DIR/$BASE_NAME.build.txt"
{
    echo "SignalLadder $VERSION (build $BUILD_NUMBER)"
    echo "Bundle identifier:   $BUNDLE_ID"
    echo "Kind:                $(if [ "$SKIP_NOTARIZE" -eq 1 ]; then echo "dry run, NOT notarised, not for distribution"; else echo "notarised and stapled"; fi)"
    echo "Started:             $START_TIME"
    echo "Commit:              $COMMIT ($BRANCH)"
    echo "Uncommitted changes: $(if [ -n "$DIRTY" ]; then echo "yes (--allow-dirty)"; else echo "no"; fi)"
    echo "Signed with:         $IDENTITY_NAME"
    echo "Requirement read:    $DR_READ_BACK"
    echo "Architectures:       $ARCHS (minimum macOS $MINOS)"
    echo "Mac:                 macOS $MACOS_VERSION"
    echo "Developer dir:       $DEV_DIR"
    echo "Xcode:               $XCODE_LINE"
    printf '%s\n' "$SWIFT_VERSION" | sed 's/^/Swift:               /'
    echo "Beta Xcode:          $(if [ "$BETA" -eq 1 ]; then echo "YES ($BETA_REASON)"; else echo "no"; fi)"
    echo "App notarisation:    $APP_SUBMISSION"
    echo "DMG notarisation:    $DMG_SUBMISSION"
    echo "App size:            $APP_BYTES bytes ($(megabytes "$APP_BYTES"))"
    echo "DMG size:            $DMG_BYTES bytes ($(megabytes "$DMG_BYTES"))"
    echo "DMG SHA-256:         $DMG_SHA"
} >"$RECORD"

# ---------------------------------------------------------------------- report

ELAPSED=$((SECONDS - START_SECONDS))
step "Done in ${ELAPSED}s"
note "App:      $(megabytes "$APP_BYTES") (every file in the bundle added up; $APP_BYTES bytes)"
note "DMG:      $(megabytes "$DMG_BYTES") ($DMG_BYTES bytes)"
note "SHA-256:  $DMG_SHA"
echo
echo "Written to $ROOT/$OUT_DIR:"
echo "  $DMG_NAME"
echo "  $DMG_NAME.sha256"
echo "  $(basename "$RECORD")"
echo
if [ "$BETA" -eq 1 ]; then
    beta_banner
fi
if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    echo "This was a dry run. The DMG is signed but NOT notarised, and Gatekeeper is expected to refuse it on another Mac."
    echo "Do not publish it."
else
    echo "Next, and it is yours to do: try the DMG on a clean account, then tag and publish."
fi
echo "Nothing was uploaded, tagged, published, installed or launched."
