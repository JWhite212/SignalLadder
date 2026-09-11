#!/bin/bash
# Scripts/verify-live.sh — automated live verification of a running SignalLadder.app
#
# Task 6 was written as a human checklist because the app exposes its state only
# through an NSMenu. It does not have to be: the menu is readable over the
# Accessibility API, notifications are postable from the shell, and macOS records
# whether a banner was actually drawn. This script does every part of that
# verification that does not require changing a system security setting.
#
# What it CANNOT do, by design, and why:
#   - grant or revoke Accessibility  (TCC; a security setting, and deliberately
#                                     not scriptable by anything but the user)
#   - change SignalLadder's alert style to None   (a system setting)
#   - toggle Do Not Disturb                        (a system setting)
# Those three steps stay manual. Everything else runs here.
#
# PRIVACY: this script never reads notification content. It reads the menu's
# health line and capture count, and posts one fixed test notification of its
# own. No captured text is printed, stored, or transmitted.
#
# Usage:  ./Scripts/verify-live.sh
# Exit:   0 all automated checks passed, 1 a check failed, 2 could not run

set -uo pipefail

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  \033[2m·\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- preconditions

head_ "Process"

PID=$(pgrep -f "SignalLadder.app/Contents/MacOS/SignalLadder" | head -1)
if [ -z "$PID" ]; then
    bad "SignalLadder is not running — launch it with: open build/SignalLadder.app"
    exit 2
fi
ok "running as pid $PID (up $(ps -o etime= -p "$PID" | tr -d ' '))"

# Idle CPU is sampled HERE, before anything in this script touches the app.
# `ps %cpu` is an average over the whole process lifetime, so reading it after
# driving the menu measures this script's own effect and reports it as the
# app's idle cost. Sample the cumulative CPU-time delta over a quiet window
# instead — that is the only figure that means what the name says.
cpu_seconds() { ps -o time= -p "$1" | tr -d ' ' | awk -F: '{s=0; for(i=1;i<=NF;i++) s=s*60+$i; print s}'; }

IDLE_WINDOW=10
T0=$(cpu_seconds "$PID")
sleep "$IDLE_WINDOW"
T1=$(cpu_seconds "$PID")
IDLE_CPU=$(awk -v a="$T0" -v b="$T1" -v w="$IDLE_WINDOW" 'BEGIN { printf "%.2f", (b - a) * 100 / w }')

# ------------------------------------------------------------------- menu state
# NSMenu content is rebuilt in menuNeedsUpdate, so the menu must actually be
# opened for the values to be current. Reading it without opening returns
# whatever was there at build time — the mistake that invalidated two rounds of
# the Focus spike.

read_menu() {
    osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  tell process "SignalLadder"
    set itm to menu bar item 1 of menu bar 1
    perform action "AXPress" of itm
    delay 1.2
    set acc to {}
    repeat with mi in menu items of menu 1 of itm
      try
        set end of acc to (name of mi as text)
      end try
    end repeat
    key code 53
    set AppleScript's text item delimiters to linefeed
    return acc as text
  end tell
end tell
APPLESCRIPT
}

head_ "Menu state"

MENU=$(read_menu)
if [ -z "$MENU" ]; then
    bad "could not read the menu over the Accessibility API"
    note "the process running this script needs Accessibility permission"
    exit 2
fi

HEALTH=$(printf '%s' "$MENU" | head -1)
COUNT_BEFORE=$(printf '%s' "$MENU" | grep -o 'Captured [0-9]*' | grep -o '[0-9]*')
: "${COUNT_BEFORE:=0}"

note "health: $HEALTH"
note "count:  $COUNT_BEFORE"

case "$HEALTH" in
    "Working — verified")            ok "health is verified" ;;
    "Checking…")                     note "health not yet established (no self-test has completed)" ;;
    "Cannot verify itself")          bad "degraded — see the cause line below" ;;
    "NOT capturing notifications")   bad "BLIND — the app believes it is capturing nothing" ;;
    *)                               bad "unrecognised health line: $HEALTH" ;;
esac

CAUSE=$(printf '%s' "$MENU" | sed -n '2p')
case "$CAUSE" in
    Captured*|"") : ;;
    *) note "cause:  $CAUSE" ;;
esac

# -------------------------------------------------------------- delivery reality
# The single most valuable check, and the one that took a live bug to learn:
# a notification suppressed by Do Not Disturb is never drawn as a banner, so the
# Accessibility layer has nothing to see and the self-test fails through no fault
# of capture. The app cannot currently detect this; the system log records it.

head_ "Delivery conditions"

# Only state CHANGES are logged, so a quiet window means "unchanged", not "off".
# Look back far enough to find the last transition, and say plainly when there
# isn't one — the functional check further down (was our test banner actually
# drawn?) is the authoritative answer either way.
# Each state-update line carries BOTH `state:` and `previousState:`, each with
# its own suppressionState. Everything from `previousState` on must be cut away
# first or the check reports the state the machine just LEFT — which reads as a
# live fault that has in fact already cleared.
DND=$(/usr/bin/log show --last 6h --predicate 'subsystem CONTAINS "donotdisturb"' --style compact 2>/dev/null \
      | grep "Did receive state update" | tail -1 \
      | sed 's/previousState.*//' \
      | grep -o 'suppressionState: [a-zA-Z ]*' | head -1 \
      | sed -e 's/suppressionState: //' -e 's/ *$//')

if [ -z "$DND" ]; then
    note "no Do Not Disturb transition logged in 6h — state unknown from the log alone"
elif [ "$DND" = "inactive" ]; then
    ok "Do Not Disturb is inactive — banners will be drawn"
else
    bad "Do Not Disturb is active ($DND) — banners are NOT drawn, so capture cannot work"
    note "this suppresses the self-test too; a failed canary here says nothing about capture"
fi

MUTED=$(/usr/bin/log show --last 5m --predicate 'process == "NotificationCenter"' --style compact 2>/dev/null \
        | grep -c "com.jamiewhite.signalladder.*muted by DND")
[ "${MUTED:-0}" -gt 0 ] && bad "$MUTED of our own notifications were muted by DND in the last 5 minutes"

# ------------------------------------------------------------------ live capture
# Posts one notification and checks the count moves. This is the only positive
# evidence that capture works end to end.

head_ "Live capture"

osascript -e 'display notification "Automated capture check" with title "SignalLadder Test" subtitle "verify-live.sh"' >/dev/null 2>&1
sleep 3

DRAWN=$(/usr/bin/log show --last 1m --predicate 'process == "NotificationCenter"' --style compact 2>/dev/null \
        | grep "com.apple.ScriptEditor2" | grep -c "canDisplayWhileCenterIsClosed: true")

if [ "${DRAWN:-0}" -gt 0 ]; then
    ok "test banner was drawn (not muted)"
else
    note "could not confirm the test banner was drawn — capture result below is inconclusive"
fi

COUNT_AFTER=$(read_menu | grep -o 'Captured [0-9]*' | grep -o '[0-9]*')
: "${COUNT_AFTER:=0}"

if [ "$COUNT_AFTER" -gt "$COUNT_BEFORE" ]; then
    ok "capture count rose $COUNT_BEFORE → $COUNT_AFTER — capture is working live"
else
    bad "capture count did not move ($COUNT_BEFORE → $COUNT_AFTER) — the banner was not captured"
fi

# --------------------------------------------------------------------- contradiction
# Worth calling out loudly: if capture demonstrably works but health is not
# verified, the health display is stale or wrong. That combination is the exact
# failure this milestone exists to prevent, in its quietest form.

if [ "$COUNT_AFTER" -gt "$COUNT_BEFORE" ] && [ "$HEALTH" != "Working — verified" ]; then
    head_ "Contradiction"
    bad "capture demonstrably works, yet health reports \"$HEALTH\""
    note "the app is telling the user something its own behaviour disproves"
fi

# ------------------------------------------------------------------------ cost

head_ "Resource cost"

RSS=$(ps -o rss= -p "$PID" | tr -d ' ')
note "idle CPU ${IDLE_CPU}% (sampled over ${IDLE_WINDOW}s before this script touched the app)"
note "resident $((RSS / 1024)) MB"
awk -v c="$IDLE_CPU" 'BEGIN { exit !(c <= 2.0) }' \
    && ok "idle CPU within budget" \
    || bad "idle CPU ${IDLE_CPU}% is above 2%"

# ------------------------------------------------------------------- still manual

head_ "Still requires you (system security settings)"
note "revoke/grant Accessibility          → tests live recovery without relaunch"
note "set alert style to None             → tests delivery faults are not blamed on capture"
note "toggle Do Not Disturb               → tests the suppression path"

head_ "Result"
printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
