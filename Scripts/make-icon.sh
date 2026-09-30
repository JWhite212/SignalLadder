#!/usr/bin/env bash
# Scripts/make-icon.sh — regenerate Resources/AppIcon.icns from docs/assets/logo.svg.
#
# The .icns is a generated file that is checked in. make-app.sh copies it and
# never builds it, so an ordinary build needs none of what runs here. Run this
# when the logo changes, look at the result, and commit the .icns with the logo.
#
# What it does, using only what ships with macOS and Xcode:
#   1. Measures the logo's body rectangle and fits it to Apple's icon grid.
#   2. Draws the SVG to a 1024 x 1024 PNG with a transparent background, through
#      Scripts/render-svg.swift (which explains why WebKit, and not qlmanage).
#   3. Checks that PNG: size, alpha, transparent corners, opaque centre, and a
#      body of the right size in the right place.
#   4. Scales it into the ten sizes an .iconset holds (sips) and packs the
#      .icns (iconutil).
#
# Usage:  Scripts/make-icon.sh
# Output: Resources/AppIcon.icns, replaced only once every step has succeeded.
#
# Three runs on 2026-09-30 (macOS 26.7.1, Apple silicon) gave byte-identical
# files. WebKit's anti-aliasing can differ between macOS releases, so after an
# OS upgrade a regenerated file that differs is not a fault: look at it before
# committing it, and do not regenerate as part of a build.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/docs/assets/logo.svg"
RENDERER="$ROOT/Scripts/render-svg.swift"
OUT="$ROOT/Resources/AppIcon.icns"

# Apple's macOS icon grid: a 1024 px canvas whose rounded-rectangle body is 824
# px square and centred, leaving 100 px each side for the shadow and the room
# between neighbours in the Dock.
CANVAS=1024
BODY=824

die() { echo "error: $*" >&2; exit 1; }

# macOS has no timeout(1), and Apple's tools have hung on this Mac before
# (codesign -d), so nothing here runs unbounded. perl ships with macOS, and an
# alarm survives exec; a run that overstays is killed with status 142.
# shellcheck disable=SC2016  # the perl program is single-quoted on purpose
bounded() {
    local seconds="$1"
    shift
    perl -e 'alarm shift @ARGV; exec @ARGV or die "cannot run $ARGV[0]: $!\n"' "$seconds" "$@"
}

for tool in sips iconutil swiftc perl; do
    command -v "$tool" >/dev/null || die "$tool not found. It ships with macOS or Xcode's command line tools."
done
[ -f "$SVG" ] || die "$SVG not found."
[ -f "$RENDERER" ] || die "$RENDERER not found."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/signalladder-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------ fit to the grid
#
# Measured on 2026-09-30: the body is a 432 x 432 rectangle at (40, 36) in a
# 512-unit viewBox. At 1024 px that is 864 px, 84.4% of the canvas, where the
# grid asks for 824 (80.5%), and its centre sits 4 units (8 px) above the
# canvas centre, so it neither fits the grid nor sits on it. Left alone the
# icon would show about 5% larger than every icon that follows the grid.
#
# The fix is a transform, not a redesign: the viewBox is changed so the body
# lands at 824 px, centred, and everything else in the file scales with it.
# The shadow is part of the file and scales too; it still ends well inside the
# canvas (the check below and the corner pixels would catch it if it did not).
# If the logo's body rectangle changes, this reads the new one.

body_rect="$(grep -F -m1 'fill="url(#body)"' "$SVG" || true)"
[ -n "$body_rect" ] || die "cannot find the body rectangle (fill=\"url(#body)\") in $SVG."

attribute() { sed -nE "s/.*[[:space:]]$1=\"([0-9.]+)\".*/\\1/p" <<<"$body_rect"; }
body_x="$(attribute x)"; body_y="$(attribute y)"
body_w="$(attribute width)"; body_h="$(attribute height)"
for value in "$body_x" "$body_y" "$body_w" "$body_h"; do
    [ -n "$value" ] || die "cannot read x, y, width and height from the body rectangle: $body_rect"
done

[ "$(grep -c 'viewBox=' "$SVG")" -eq 1 ] || die "expected exactly one viewBox in $SVG."
old_view_box="$(sed -nE 's/.*viewBox="([^"]*)".*/\1/p' "$SVG")"

# The new viewBox is a square, centred on the body, wide enough that the body
# takes BODY/CANVAS of it. The last field is the body's size in pixels before
# the fit, for the message.
fit="$(awk -v x="$body_x" -v y="$body_y" -v w="$body_w" -v h="$body_h" \
           -v canvas="$CANVAS" -v body="$BODY" -v old="$old_view_box" '
    BEGIN {
        if (w != h) exit 2
        split(old, box, " ")
        span = w * canvas / body
        printf "%.6f %.6f %.6f %.6f %.1f\n", x + w / 2 - span / 2, y + h / 2 - span / 2, span, span, w * canvas / box[3]
    }')" || die "the body rectangle is not square (${body_w} x ${body_h}); the grid fit assumes it is."
new_view_box="${fit% *}"
before_px="${fit##* }"
echo "==> Logo body: ${body_w} x ${body_h} units = ${before_px} px at ${CANVAS} px; grid wants ${BODY} px"

sed -E "s|viewBox=\"[^\"]*\"|viewBox=\"${new_view_box}\"|" "$SVG" > "$WORK/logo-on-grid.svg"

# ---------------------------------------------------------------------- draw
echo "==> Building the renderer"
bounded 300 swiftc -O -o "$WORK/render-svg" "$RENDERER" || die "could not build $RENDERER."

echo "==> Drawing ${CANVAS} x ${CANVAS} PNG"
MASTER="$WORK/master.png"
bounded 90 "$WORK/render-svg" "$WORK/logo-on-grid.svg" "$MASTER" "$CANVAS" "$BODY" \
    || die "the render failed or did not pass its checks (see above)."

# Read the file back with a tool that had no part in making it.
pixel_width="$(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/ { print $2 }')"
pixel_height="$(sips -g pixelHeight "$MASTER" | awk '/pixelHeight/ { print $2 }')"
has_alpha="$(sips -g hasAlpha "$MASTER" | awk '/hasAlpha/ { print $2 }')"
[ "$pixel_width" = "$CANVAS" ] && [ "$pixel_height" = "$CANVAS" ] \
    || die "the PNG is ${pixel_width} x ${pixel_height}, expected ${CANVAS} x ${CANVAS}."
[ "$has_alpha" = "yes" ] || die "the PNG has no alpha channel."

# ------------------------------------------------------------------- iconset
echo "==> Building the iconset"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    bounded 60 sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    bounded 60 sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Packing the .icns"
bounded 60 iconutil -c icns -o "$WORK/AppIcon.icns" "$ICONSET" || die "iconutil failed."

# Unpack it again and count: an .icns that iconutil accepted but that is
# missing a size is only found out when Finder draws a blurry icon.
bounded 60 iconutil -c iconset -o "$WORK/unpacked.iconset" "$WORK/AppIcon.icns" || die "iconutil cannot read back its own output."
unpacked="$(find "$WORK/unpacked.iconset" -name '*.png' | wc -l | tr -d ' ')"
[ "$unpacked" -eq 10 ] || die "the .icns holds ${unpacked} images, expected 10."

# Replace the checked-in file only now, and by rename, so a failure above
# leaves the previous .icns exactly as it was.
mkdir -p "$(dirname "$OUT")"
cp "$WORK/AppIcon.icns" "$OUT.new"
mv "$OUT.new" "$OUT"

echo
echo "Wrote ${OUT#"$ROOT"/} ($(wc -c < "$OUT" | tr -d ' ') bytes, ${unpacked} images)"
