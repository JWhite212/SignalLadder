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
#   - switch SignalLadder's banners off           (a system setting: Desktop, in
#                                                   Notifications; a style of None before macOS 26)
#   - toggle Do Not Disturb                        (a system setting)
# Those three steps stay manual. Everything else runs here.
#
# PRIVACY: this script never reads notification content. It reads the menu, the app's
# window titles, the one saved key that holds the on-call state, and the rules file,
# and it counts lines of the system log without printing them. It posts notifications
# of its own: one fixed test banner, and, under a flag, banners with the marker's title
# and a body of the script's own. No captured text is printed, stored, or transmitted.
#
# The default run changes nothing but what it opens and closes (the Inspector, the
# rule editor, the Settings window) and the banners it posts. Three flags add a check
# that CHANGES something on this Mac. Each is opt-in, takes one to a run, and is for a
# Mac that is OFF SHIFT, since each does something to the app that a real shift
# depends on:
#
#   --escalation  Adds one rule to rules.json for about a minute, first in the rules
#                 array, before every rule of yours. It matches only a banner with
#                 the marker's title (HarnessText.markerTitle), which no real page
#                 has; its first alert is silent, its panel comes at 10 seconds and
#                 its sound repeats at the quietest gain the format allows, twice.
#                 The script chooses Reload Rules, posts five marker banners, checks
#                 that the menu says one alert is escalating and counts the banners,
#                 and chooses Acknowledge. The menu's Acknowledge is Acknowledge All,
#                 so this refuses to run (exit 2) while the menu shows an Acknowledge
#                 item or a line about something escalating, and it clicks only when
#                 the menu shows nothing but the marker's own escalation, which
#                 includes a last match that names the marker rule. The rule goes
#                 first because the first rule to match wins: were it last, a rule of
#                 yours that matches a banner with the marker's title (a catch-all, a
#                 practice rule for Script Editor) would take the first banner, sound
#                 its alert and start its escalation before this could stop. First, it
#                 takes every banner the script posts, and it can take no real page.
#                 The last match is the second line of defence: it is the one thing
#                 on the menu that tells the marker's escalation from a real page's
#                 that came in after the banners, or from a rule of yours that took a
#                 banner because rules.json was edited during the run and the marker
#                 is no longer first. In either case the run posts no more banners
#                 and acknowledges nothing, so that escalation goes on, to its panel
#                 and its Shortcut if it has them, until you acknowledge it by hand.
#                 When it cannot prove that it touches nothing it exits 1, and what is
#                 escalating stays on the menu until you acknowledge it by hand: the
#                 marker's row, which a capped escalation leaves listed, or another
#                 rule's.
#   --on-call     Switches the app's on-call mode on, checks the menu, rules.json and
#                 the saved key, and switches it off again. This is your real on-call
#                 state: while it is on the Mac is held awake, the app runs a
#                 self-test, which shows a banner, and its check window may open. It
#                 refuses to run (exit 2) if the app is already on call or snoozed.
#   --snooze      Adds the same marker rule, first in rules.json as for --escalation,
#                 set so that a snooze may hold it and with a sound, chooses Reload
#                 Rules and a 15-minute snooze, posts a marker banner, checks that the
#                 menu shows the marker's one match held, and ends the snooze at once.
#                 For as long as it runs, a snooze quiets YOUR OWN rules that are set
#                 to stay quiet during one, as any snooze does. It dismisses the held
#                 summary only when that is the marker's one match and nothing else.
#                 It refuses to run (exit 2) if the app is already on call or snoozed,
#                 or if the menu already shows a held summary, which is a real match's
#                 trace that it would leave alone and could not tell its own match
#                 from.
#
# A flag reads the menu first, before the default checks post a banner or open a window,
# and refuses there when the Mac is in a state that belongs to a real shift; it reads the
# menu again just before it acts, since a page can come in meanwhile.
#
# A flag that changes rules.json copies it beside itself first, with the SHA-256 digest of
# the file it then writes, and puts the original back when it ends, on a normal exit and
# on INT, TERM and HUP, then chooses Reload Rules and checks the file is byte for byte
# the one it began with. It also undoes what it started: it ends a snooze it began,
# switches on-call mode off if it switched it on, and closes the on-call check window
# if it opened it. A trap cannot run after a kill, a power loss or a crashed terminal,
# so the next run of any flag begins with the backup guard of Scripts/harness-guards.sh,
# which puts a leftover backup back only over a file that is still the one the run wrote,
# says what it did, and otherwise refuses (exit 2) and changes nothing. That guard, and
# not the trap, is what keeps your rules file safe. The guards are functions with a script
# test of their own, Scripts/harness-guards-test.sh, which CI runs; this script sources
# them and keeps no copy.
#
# Usage:  ./Scripts/verify-live.sh [--escalation | --on-call | --snooze]
# Exit:   0 all automated checks passed, 1 a check failed, 2 could not run or refused to

set -uo pipefail

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  \033[2m·\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ------------------------------------------------------------------- arguments
# The flag, without its dashes, is also the mode the refuse guard is given.

usage() {
    printf 'Usage: %s [--escalation | --on-call | --snooze]\n' "${0##*/}"
}

MODE=''
for arg in "$@"; do
    case "$arg" in
        --escalation|--on-call|--snooze)
            if [ -n "$MODE" ]; then
                printf 'Only one flag to a run: --%s was given first, and then %s\n' "$MODE" "$arg" >&2
                usage >&2
                exit 2
            fi
            MODE=${arg#--} ;;
        -h|--help)
            usage
            exit 0 ;;
        *)
            printf 'Unknown argument: %s\n' "$arg" >&2
            usage >&2
            exit 2 ;;
    esac
done

# ------------------------------------------------------------ text the app owns
# A word this script looks for, and that the app also shows, is not typed here.
# It is read out of the file in NotificationCore that declares it, so a window
# or a menu item's title cannot change in the app and be left behind in this
# script. Every declaration has the one shape `public static let NAME = "TEXT"`,
# which is what the helper `core_constant` reads, and `HarnessConstantsTests` holds
# each reference to it. The helper is defined once, in Scripts/harness-guards.sh,
# which this script sources and the guards' own script test proves.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GUARDS="$REPO_ROOT/Scripts/harness-guards.sh"
if [ ! -r "$GUARDS" ]; then
    head_ "Text the app owns"
    bad "could not read Scripts/harness-guards.sh, which holds the helper that reads the app's words and the guards a flag stands on"
    exit 2
fi
. "$GUARDS"

# The windows' titles, and the window of the on-call check, which a flag may open.
INSPECTOR_TITLE=$(core_constant WindowTitles.swift inspector)
RULE_EDITOR_TITLE=$(core_constant WindowTitles.swift ruleEditor)
SETTINGS_TITLE=$(core_constant WindowTitles.swift settings)
ON_CALL_CHECK_TITLE=$(core_constant WindowTitles.swift onCallCheck)

# The menu's items the checks choose or look for. The On Call item is also what the
# cause reading below has to step over.
INSPECTOR_ITEM=$(core_constant StatusMenuText.swift showInspectorTitle)
EDIT_RULES_ITEM=$(core_constant StatusMenuText.swift editRulesTitle)
RELOAD_RULES_ITEM=$(core_constant StatusMenuText.swift reloadRulesTitle)
SETTINGS_ITEM=$(core_constant SettingsText.swift menuTitle)
ON_CALL_ITEM=$(core_constant OnCall.swift menuTitle)
SNOOZE_ITEM=$(core_constant SnoozeText.swift menuTitle)
SNOOZE_FIFTEEN_ITEM=$(core_constant SnoozeText.swift fifteenMinutesTitle)
SNOOZE_END_ITEM=$(core_constant SnoozeText.swift endTitle)
DISMISS_ITEM=$(core_constant SnoozeText.swift dismissTitle)
# The title the menu gives Acknowledge while one alert is listed, which is the only
# one that is clicked. With more than one listed the item begins "Acknowledge All"
# and is never chosen.
ACKNOWLEDGE_ITEM=$(core_constant AlertMenuText.swift acknowledgeOneTitle)

# The beginnings of the menu's lines, and the whole lines, the checks look for.
CAPTURED_STEM=$(core_constant StatusMenuText.swift capturedStem)
RULES_STEM=$(core_constant RuleSetCodec.swift summaryStem)
LAST_MATCH_STEM=$(core_constant AlertMenuText.swift lastMatchStem)
NUDGE_STEM=$(core_constant SetupText.swift nudgeStem)
ON_CALL_SINCE_STEM=$(core_constant OnCall.swift sinceStem)
ESCALATING_STEM=$(core_constant AlertMenuText.swift singleEscalatingStem)
SNOOZE_ACTIVE_STEM=$(core_constant SnoozeText.swift activeStem)
OUTPUT_SILENT=$(core_constant AlertMenuText.swift outputSilentSentence)
MUTE_CONFIRMED_STEM=$(core_constant MuteWalkthrough.swift confirmedStem)
MUTE_NOT_CONFIRMED_STEM=$(core_constant MuteWalkthrough.swift notConfirmedStem)
FAIL_PLAY=$(core_constant InspectorEntry.swift couldNotPlay)
FAIL_SPEAK=$(core_constant InspectorEntry.swift couldNotSpeak)
FAIL_PLAYED_NOT_SPOKEN=$(core_constant InspectorEntry.swift butCouldNotSpeak)
FAIL_SPOKE_NOT_PLAYED=$(core_constant InspectorEntry.swift butCouldNotPlay)

# The five wordings of the health line. The first and third are what the line begins
# with, and an age follows; the others are the whole line.
HEALTH_VERIFIED=$(core_constant HealthTitle.swift verifiedStem)
HEALTH_CHECKING=$(core_constant HealthTitle.swift checkingLine)
HEALTH_UNVERIFIED=$(core_constant HealthTitle.swift unverifiedStem)
HEALTH_CANNOT_VERIFY=$(core_constant HealthTitle.swift cannotVerifyLine)
HEALTH_NOT_CAPTURING=$(core_constant HealthTitle.swift notCapturingLine)
HEALTH_SOME_UNREAD=$(core_constant HealthTitle.swift someBannersUnreadLine)

# What the flags write and post: the marker rule's name and id, and the title of the
# banners it matches. The key is the one the app saves the on-call state under.
MARKER_NAME=$(core_constant HarnessText.swift markerRuleName)
MARKER_TITLE=$(core_constant HarnessText.swift markerTitle)
MARKER_ESCALATION_ID=$(core_constant HarnessText.swift markerEscalationRuleID)
MARKER_SNOOZE_ID=$(core_constant HarnessText.swift markerSnoozeRuleID)
ON_CALL_KEY=$(core_constant OnCall.swift storageKey)

# An empty word would make every `grep -F` and every `case` below match any line at
# all, and an empty title would have a flag choose the wrong item, so none of them is
# allowed to be empty: a harness that cannot read the app's words does not run.
UNREAD=''
for name in INSPECTOR_TITLE RULE_EDITOR_TITLE SETTINGS_TITLE ON_CALL_CHECK_TITLE \
            INSPECTOR_ITEM EDIT_RULES_ITEM RELOAD_RULES_ITEM SETTINGS_ITEM ON_CALL_ITEM SNOOZE_ITEM \
            SNOOZE_FIFTEEN_ITEM SNOOZE_END_ITEM DISMISS_ITEM ACKNOWLEDGE_ITEM \
            CAPTURED_STEM RULES_STEM LAST_MATCH_STEM NUDGE_STEM ON_CALL_SINCE_STEM ESCALATING_STEM SNOOZE_ACTIVE_STEM \
            OUTPUT_SILENT MUTE_CONFIRMED_STEM MUTE_NOT_CONFIRMED_STEM \
            FAIL_PLAY FAIL_SPEAK FAIL_PLAYED_NOT_SPOKEN FAIL_SPOKE_NOT_PLAYED \
            HEALTH_VERIFIED HEALTH_CHECKING HEALTH_UNVERIFIED HEALTH_CANNOT_VERIFY HEALTH_NOT_CAPTURING HEALTH_SOME_UNREAD \
            MARKER_NAME MARKER_TITLE MARKER_ESCALATION_ID MARKER_SNOOZE_ID ON_CALL_KEY; do
    if [ -z "${!name}" ]; then UNREAD="$UNREAD $name"; fi
done
if [ -n "$UNREAD" ]; then
    head_ "Text the app owns"
    bad "could not read these from Sources/NotificationCore:$UNREAD"
    exit 2
fi

# The app's domain, for the one saved key a flag reads, and the program that posts the
# banners the log is counted for.
APP_DOMAIN=com.jamiewhite.signalladder
POSTER_APP=com.apple.ScriptEditor2
RULES_FILE="$HOME/Library/Application Support/$APP_DOMAIN/rules.json"

# -------------------------------------------------------------- the menu and the windows
# NSMenu content is rebuilt in menuNeedsUpdate, so the menu must actually be
# opened for the values to be current. Reading it without opening returns
# whatever was there at build time — the mistake that invalidated two rounds of
# the Focus spike.
#
# Each of these opens the status menu by pressing its item over the Accessibility API,
# and is a function because macOS ships bash 3.2, which mis-parses a heredoc containing an
# apostrophe (here, "AppleScript's text item delimiters") when the heredoc sits directly
# inside a `$(...)` command substitution — it loses track of the closing paren and
# reports "unexpected EOF while looking for matching `''". The heredoc stays in a
# function body and the caller substitutes the function CALL, which sidesteps the parser
# bug without changing the AppleScript. A title is passed as an argument and not typed
# into the AppleScript, so the script that clicks an item and the app that titles it
# cannot disagree.

read_menu() {
    osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  tell process "SignalLadder"
    -- The status item is found by its subrole, not as "menu bar 1": since the
    -- app gained a main menu (for Edit shortcuts), menu bar 1 is that menu,
    -- and its first item is the Apple menu.
    set itm to missing value
    repeat with bar in menu bars
      repeat with cand in menu bar items of bar
        if subrole of cand is "AXMenuExtra" then set itm to contents of cand
      end repeat
    end repeat
    if itm is missing value then return "NO_STATUS_ITEM"
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

# read_menu_retry: the menu's text, read again when a read comes back empty (a menu left
# open by an interrupted read is closed by the next press and gives nothing). Prints
# nothing and returns 1 when three reads in a row give none.
read_menu_retry() {
    local menu tries=0
    while [ "$tries" -lt 3 ]; do
        menu=$(read_menu)
        if [ -n "$menu" ] && [ "$menu" != "NO_STATUS_ITEM" ]; then
            printf '%s\n' "$menu"
            return 0
        fi
        tries=$((tries + 1))
        sleep 1
    done
    return 1
}

# choose_menu_item TITLE: opens the status menu and chooses the top-level item whose
# title is exactly TITLE. Prints "clicked", "could not click" (and closes the menu) or
# "NO_STATUS_ITEM".
choose_menu_item() {
    osascript - "$1" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wanted to item 1 of argv
  tell application "System Events"
    tell process "SignalLadder"
      set itm to missing value
      repeat with bar in menu bars
        repeat with cand in menu bar items of bar
          if subrole of cand is "AXMenuExtra" then set itm to contents of cand
        end repeat
      end repeat
      if itm is missing value then return "NO_STATUS_ITEM"
      perform action "AXPress" of itm
      delay 1.0
      try
        click menu item wanted of menu 1 of itm
      on error
        key code 53
        return "could not click"
      end try
      return "clicked"
    end tell
  end tell
end run
APPLESCRIPT
}

# choose_submenu_item PARENT TITLE: the same for an item in the submenu of the top-level
# item PARENT, which is opened first.
choose_submenu_item() {
    osascript - "$1" "$2" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set parentTitle to item 1 of argv
  set wanted to item 2 of argv
  tell application "System Events"
    tell process "SignalLadder"
      set itm to missing value
      repeat with bar in menu bars
        repeat with cand in menu bar items of bar
          if subrole of cand is "AXMenuExtra" then set itm to contents of cand
        end repeat
      end repeat
      if itm is missing value then return "NO_STATUS_ITEM"
      perform action "AXPress" of itm
      delay 1.0
      try
        click menu item parentTitle of menu 1 of itm
        delay 0.8
        click menu item wanted of menu 1 of menu item parentTitle of menu 1 of itm
      on error
        key code 53
        key code 53
        return "could not click"
      end try
      return "clicked"
    end tell
  end tell
end run
APPLESCRIPT
}

# window_titles: the title of each window the app has open, one to a line.
window_titles() {
    osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  tell process "SignalLadder"
    set acc to {}
    repeat with w in windows
      try
        set end of acc to (name of w as text)
      end try
    end repeat
    set AppleScript's text item delimiters to linefeed
    return acc as text
  end tell
end tell
APPLESCRIPT
}

# close_window TITLE: closes the window with that title by its close button. Prints
# "STILL_OPEN=" and true or false.
close_window() {
    osascript - "$1" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wanted to item 1 of argv
  tell application "System Events"
    tell process "SignalLadder"
      try
        click (first button of window wanted whose subrole is "AXCloseButton")
        delay 1.0
      end try
      set stillOpen to (exists window wanted)
      return "STILL_OPEN=" & stillOpen
    end tell
  end tell
end run
APPLESCRIPT
}

# post_marker_banner BODY: posts a banner with the marker's title and the body given,
# which the marker rule matches and nothing else does. The body is the script's own
# words, and a different one for each banner, since identical text within 1.5 seconds
# is collapsed as a repeat and macOS can replace a banner still on screen.
post_marker_banner() {
    osascript - "$MARKER_TITLE" "$1" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

# menu_has_item MENU TITLE: whether a line of the menu is exactly TITLE.
menu_has_item() {
    grep -qxF -- "$2" <<< "$1"
}

# menu_has_stem MENU STEM: whether a line of the menu begins with STEM.
menu_has_stem() {
    local line
    while IFS= read -r line; do
        case "$line" in
            "$2"*) return 0 ;;
        esac
    done <<< "$1"
    return 1
}

# rules_line_of MENU: the menu's line about the rules, which is the only line that BEGINS
# with the rules summary's word once any leading warning mark is skipped — the items
# that reload the rules, edit them or open their file all start with another word.
rules_line_of() {
    grep -E "^[^A-Za-z]*$RULES_STEM" <<< "$1" | head -1
}

# captured_count MENU: the number on the capture count's line, or nothing.
captured_count() {
    grep -o "$CAPTURED_STEM [0-9]*" <<< "$1" | grep -o '[0-9]*' | head -1
}

# rules_digest: the SHA-256 of rules.json, or the word absent, or unreadable.
rules_digest() {
    harness_digest "$RULES_FILE"
}

# ---------------------------------------------------------------- what the flags stand on
# Everything a flag does is behind these functions, which are defined here and run in the
# order the end of this file calls them. `begin_flag` comes first, before any other
# check, and sets the traps before anything is written. The run's state is in these
# variables, set BEFORE the step they stand for, so a run interrupted in the middle of
# a step is undone as though the step had finished: each undoing reads the menu first, and
# does nothing for a step that did not happen.

BACKUP=''                  # where a flag that changes rules.json keeps the original
RULES_DIGEST_START=''      # the digest of rules.json when the run began
RULES_TOUCHED=0            # 1 from just before the marker rule is written
RULES_WATCHED=0            # 1 from just before a flag that writes nothing to rules.json starts, which it must leave as it was
SNOOZE_STARTED=0           # 1 from just before a snooze is chosen, 0 once it is seen to have ended
ON_CALL_SWITCHED=0         # 1 from just before On Call is chosen, 0 once the mode is seen to be off
CHECK_WINDOW_AT_START=0    # 1 when the on-call check window was open before the run
MARKER_POSTED=0            # 1 from just before the first marker banner is posted
MARKER_SUMMARY=none        # none, pending (the marker's match may be held, and its summary on the menu) or done
ESCALATION_OPEN=0          # 1 from just before the first marker banner is posted until the run has acknowledged the marker's escalation
START_ON_CALL=0            # 1 when the menu showed the on-call line as the run began
START_SNOOZED=0            # 1 when the menu showed a running snooze as the run began
RELOAD_OWED=0              # 1 when the backup guard changed rules.json before the app was touched
CLEANED=0                  # 1 once the run has been undone

# The two marker rules, as one line of JSON each, with their id, name and title left as
# the three %s in that order. Both match a banner with the marker's title and nothing
# else. The escalation marker is silent at first, has a panel at 10 seconds and repeats a
# sound at -40 dB, the quietest the format allows (`AlertAction.gainRange`), every 30
# seconds for two repeats, and has no Shortcut, since a phone page cannot be proven
# without running one. The snooze marker has a sound, at the same gain, and the flag that
# lets a snooze hold it. `HarnessConstantsTests` reads these two lines and holds each
# to a rule the codec accepts at the version `install_marker` is told it needs.
MARKER_RULE_ESCALATION='{"id":"%s","name":"%s","enabled":true,"condition":{"field":"title","op":"equals","value":"%s"},"alert":"silent","escalation":{"tier2":{"delaySeconds":10},"tier3":{"action":{"sound":"Hero","gainDB":-40},"intervalSeconds":30,"maxRepeats":2,"maxDurationSeconds":600}}}'
MARKER_RULE_SNOOZE='{"id":"%s","name":"%s","enabled":true,"condition":{"field":"title","op":"equals","value":"%s"},"alert":{"sound":"Glass","gainDB":-40},"quietWhenSnoozed":true}'

# marker_rule_json KIND: the marker rule of that kind, escalation or snooze, as the text of
# one JSON object.
marker_rule_json() {
    local id shape
    case "$1" in
        escalation) id=$MARKER_ESCALATION_ID; shape=$MARKER_RULE_ESCALATION ;;
        snooze)     id=$MARKER_SNOOZE_ID;     shape=$MARKER_RULE_SNOOZE ;;
        *) return 1 ;;
    esac
    printf "$shape" "$id" "$MARKER_NAME" "$MARKER_TITLE"
}

# marker_in_rules: whether rules.json already holds a marker rule, by the id each is
# written with. One is there only if an earlier run left it, and a second beside it would
# make the rules ambiguous, so the flags that write one do not run until it is taken out.
marker_in_rules() {
    local id
    for id in "$MARKER_ESCALATION_ID" "$MARKER_SNOOZE_ID"; do
        if grep -qiF -- "$id" "$RULES_FILE" 2>/dev/null; then return 0; fi
    done
    return 1
}

# reload_rules: chooses Reload Rules, which is how the app reads rules.json again (it
# does not watch the file), and waits for it. Returns 1 when the item was not chosen.
reload_rules() {
    [ "$(choose_menu_item "$RELOAD_RULES_ITEM")" = "clicked" ] || return 1
    sleep 2
}

# begin_flag MODE: the first thing a flag run does, before any other check. It runs the
# backup guard, which puts a leftover backup of an earlier run back, only over a file
# that is still the one that run wrote, and says what it did; it refuses (exit 2),
# changing nothing, when the file differs. Then it sets the traps, so that they are in
# place before anything is written, and records the digest of rules.json to check it
# against at the end.
begin_flag() {
    local out rc
    BACKUP=$(harness_backup_path "$RULES_FILE")
    head_ "Before the --$1 run"
    out=$(harness_backup_guard "$RULES_FILE" "$BACKUP"); rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$out"
        note "the --$1 run does not go on until this is dealt with by hand"
        exit 2
    fi
    if [ -n "$out" ]; then
        ok "$out"
        RELOAD_OWED=1
    else
        ok "no backup of the rules file was left by an earlier run"
    fi
    trap 'on_signal 129' HUP
    trap 'on_signal 130' INT
    trap 'on_signal 143' TERM
    trap on_exit EXIT
    RULES_DIGEST_START=$(rules_digest)
}

# on_signal CODE: ends the run on INT, TERM or HUP. The EXIT trap, which `exit` runs,
# undoes whatever the run had started.
on_signal() {
    printf '\n'
    note "interrupted: undoing what the run had started"
    exit "$1"
}

on_exit() {
    local rc=$?
    # From here a signal is ignored: this is the EXIT trap, and a signal's trap that exited
    # again while it ran would end it before the run was undone.
    trap '' INT TERM HUP PIPE
    cleanup_run
    if [ "$rc" -eq 0 ] && [ "$FAIL" -gt 0 ]; then rc=1; fi
    exit "$rc"
}

# end_snooze_if_running: chooses End Snooze when the menu shows a running snooze, which is
# the only time the item is there, and checks the menu no longer does.
end_snooze_if_running() {
    local menu
    if ! menu=$(read_menu_retry); then
        bad "could not read the menu to see whether the snooze the run began has ended: end it by hand"
        return 1
    fi
    if menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then
        if [ "$(choose_submenu_item "$SNOOZE_ITEM" "$SNOOZE_END_ITEM")" != "clicked" ]; then
            bad "could not choose $SNOOZE_END_ITEM: end the snooze by hand"
            return 1
        fi
        sleep 1.5
        menu=$(read_menu_retry) || menu=''
        if [ -z "$menu" ] || menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then
            bad "the snooze the run began is still running, or the menu could not be read to see: end it by hand"
            return 1
        fi
        ok "the snooze the run began has ended"
    else
        ok "no snooze is running"
    fi
    SNOOZE_STARTED=0
}

# dismiss_marker_summary: dismisses the held summary only when it is exactly the marker's
# one match, so that no real match's trace is erased with it, and otherwise leaves it
# where it is and says so.
dismiss_marker_summary() {
    local menu why
    menu=$(read_menu_retry) || menu=''
    if why=$(harness_summary_guard "$menu"); then
        if [ "$(choose_menu_item "$DISMISS_ITEM")" != "clicked" ]; then
            bad "could not choose $DISMISS_ITEM: the marker's held summary is still on the menu"
            return 1
        fi
        sleep 1.5
        menu=$(read_menu_retry) || menu=''
        if why=$(harness_summary_guard "$menu"); then
            bad "the marker's held summary is still on the menu after $DISMISS_ITEM"
            return 1
        fi
        ok "the marker's held summary, which was nothing else, was dismissed"
    else
        note "$why"
    fi
    MARKER_SUMMARY=done
}

# switch_on_call_off_if_on: chooses On Call, which is one item for both directions, only
# when the menu shows the mode is on. Clicked on a menu that does not show it, it would
# switch the mode on, so a menu that cannot be read, or does not show the line, is not
# clicked.
switch_on_call_off_if_on() {
    local menu
    if ! menu=$(read_menu_retry); then
        bad "could not read the menu to see whether on-call mode is still on: check it, and switch it off, by hand"
        return 1
    fi
    if menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then
        if [ "$(choose_menu_item "$ON_CALL_ITEM")" != "clicked" ]; then
            bad "could not choose $ON_CALL_ITEM: switch on-call mode off by hand"
            return 1
        fi
        sleep 3
        menu=$(read_menu_retry) || menu=''
        if [ -z "$menu" ] || menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then
            bad "on-call mode is still on, or the menu could not be read to see: switch it off by hand"
            return 1
        fi
        ok "on-call mode, which the run switched on, is off"
    else
        ok "on-call mode is off"
    fi
    ON_CALL_SWITCHED=0
}

# close_check_window_if_run_opened: closes the on-call check window when it is open and was
# not open as the run began. The window opens by itself when a switch-on finds something
# urgent, and when the self-test the switch-on runs returns, which can be after it.
close_check_window_if_run_opened() {
    local titles
    [ "$CHECK_WINDOW_AT_START" -eq 0 ] || return 0
    titles=$(window_titles)
    if grep -qxF -- "$ON_CALL_CHECK_TITLE" <<< "$titles"; then
        if [ "$(close_window "$ON_CALL_CHECK_TITLE")" = "STILL_OPEN=false" ]; then
            ok "the on-call check window, which the run opened, is closed"
        else
            bad "the on-call check window is still open: close it by hand"
        fi
    fi
}

# cleanup_run: undoes whatever the run started, in an order that leaves each step what it
# needs: the snooze first, then the held summary while the marker rule still names it, then
# the on-call mode and its window, then rules.json. Runs once, from `finish` at the end of
# a run and from the EXIT trap when the run ends any other way, and does nothing for a run
# that started and wrote nothing. Each step is independent: one that fails does not stop
# the next, and a failure makes the run fail.
cleanup_run() {
    local out rc menu
    [ "$CLEANED" -eq 0 ] || return 0
    if [ "$RULES_TOUCHED" -eq 0 ] && [ "$RULES_WATCHED" -eq 0 ] && [ "$SNOOZE_STARTED" -eq 0 ] \
       && [ "$ON_CALL_SWITCHED" -eq 0 ] && [ "$MARKER_POSTED" -eq 0 ] && [ "$ESCALATION_OPEN" -eq 0 ]; then
        return 0
    fi
    # A second interrupt, or the loss of a pipe the output goes to, must not stop the
    # undoing half way. The programs started below inherit the setting. The signals are
    # ignored BEFORE the run is marked as undone: one that came in between would run
    # on_signal, whose exit runs this again, and this would then return at the line above
    # having undone nothing.
    trap '' INT TERM HUP PIPE
    CLEANED=1
    head_ "Putting back what the run changed"

    if [ "$SNOOZE_STARTED" -eq 1 ]; then end_snooze_if_running; fi
    if [ "$MARKER_SUMMARY" = "pending" ]; then dismiss_marker_summary; fi
    if [ "$ON_CALL_SWITCHED" -eq 1 ]; then
        switch_on_call_off_if_on
        close_check_window_if_run_opened
    fi
    if [ "$ESCALATION_OPEN" -eq 1 ]; then
        note "the run acknowledged nothing: an escalation its banners began, if one is on the menu, stays there, escalating, until you acknowledge it by hand; the marker is the first rule in rules.json, so it is the marker's unless a real page came in meanwhile or the file was edited during the run"
    fi

    if [ "$RULES_TOUCHED" -eq 1 ]; then
        out=$(harness_backup_guard "$RULES_FILE" "$BACKUP" "this run"); rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "${out:-the backup guard found nothing left to put back}"
        else
            bad "$out"
        fi
        if reload_rules; then
            ok "chose $RELOAD_RULES_ITEM, so the app holds the rules file as it now is"
        else
            bad "could not choose $RELOAD_RULES_ITEM: the app holds the marker rule until it is reloaded or relaunched"
        fi
    fi
    if [ "$RULES_TOUCHED" -eq 1 ] || [ "$RULES_WATCHED" -eq 1 ]; then
        out=$(rules_digest)
        if [ "$out" = "$RULES_DIGEST_START" ]; then
            ok "rules.json is byte for byte the file the run began with"
        else
            bad "rules.json is not the file the run began with ($RULES_DIGEST_START → $out)"
        fi
    fi

    if menu=$(read_menu_retry); then
        if menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then
            if [ "$START_SNOOZED" -eq 1 ]; then
                note "the menu shows a snooze, as it did before the run began"
            else
                bad "the menu shows a snooze that was not running before the run began"
            fi
        elif menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then
            if [ "$START_ON_CALL" -eq 1 ]; then
                note "the menu shows on-call mode, as it did before the run began"
            else
                bad "the menu shows on-call mode, which was not on before the run began"
            fi
        else
            ok "the menu shows neither the line of a snooze nor the line of on-call mode"
        fi
        if [ "$START_SNOOZED" -eq 1 ] && ! menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then
            note "the snooze the menu showed before the run began is not shown now"
        fi
        if [ "$START_ON_CALL" -eq 1 ] && ! menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then
            note "on-call mode, which the menu showed before the run began, is not shown now"
        fi
    else
        bad "could not read the menu to see what the run left: check that it shows no snooze and no on-call mode"
    fi
}

# refuse_on_shift MENU READ: runs the refuse guard for this run's flag on the menu it is given,
# and stops the run (exit 2), changing nothing, with the guard's reason when the Mac is in a
# state that belongs to a real shift. READ says which read of the menu this is, for the line it
# prints. For --snooze a held summary already on the menu is a refusal too, which the guard
# does not make: it is a real match's trace, the run would leave it alone, and the check that
# the marker's match was held could not tell the marker's from what is counted there. The
# menu has a Dismiss item exactly when it has one. The guard lets --escalation go on when the
# Mac is on call or snoozed, which that run leaves as it found it, so for that flag the line
# says which of the two was found and not that nothing was.
refuse_on_shift() {
    local why rc found=0
    why=$(harness_refuse_guard "$MODE" "$1"); rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$why"
        note "the --$MODE run does not go on, and nothing was changed"
        exit 2
    fi
    if [ "$MODE" = snooze ] && menu_has_item "$1" "$DISMISS_ITEM"; then
        bad "the menu already shows a held summary, which has a $DISMISS_ITEM item: it is from before the run, and the run would leave it alone and could not tell its own match from the ones counted there"
        note "the --$MODE run does not go on, and nothing was changed; look at the summary, dismiss it by hand, and run again"
        exit 2
    fi
    if menu_has_stem "$1" "$ON_CALL_SINCE_STEM"; then
        note "on-call mode is on ($2): the refuse guard lets the --$MODE run go on, and the run leaves the mode as it found it"
        found=1
    fi
    if menu_has_stem "$1" "$SNOOZE_ACTIVE_STEM"; then
        note "a snooze is running ($2): the refuse guard lets the --$MODE run go on, and the run leaves it as it found it"
        found=1
    fi
    if [ "$found" -eq 0 ]; then
        ok "the menu shows nothing that belongs to a real shift ($2), so the --$MODE run goes on"
    fi
}

# refuse_or_go: reads the menu afresh and runs the refuse guard on it, before the flag does
# anything, since a page can have come in since the menu was first read. It also records
# whether the menu showed a snooze or on-call mode, so that the check at the end can tell what
# the run left from what it found: only --escalation can begin on a Mac that is on call.
refuse_or_go() {
    local menu
    menu=$(read_menu_retry) || menu=''
    refuse_on_shift "$menu" "read again before the flag acts"
    if menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then START_SNOOZED=1; fi
    if menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then START_ON_CALL=1; fi
}

# install_marker KIND NEEDED: writes the marker rule of that kind into rules.json with the
# guards' writer, which copies the file aside first and records the digest of the one it
# writes. NEEDED is the version the rule needs: 4 for a rule with an escalation, 5 for one a
# snooze may hold. The writer refuses (2) a file it must not touch, and the run then does not
# go on: exit 2, with the writer's reason.
install_marker() {
    local rule out rc
    if ! rule=$(marker_rule_json "$1"); then
        bad "could not build the $1 marker rule"
        exit 2
    fi
    if marker_in_rules; then
        bad "rules.json already holds a marker rule, which an earlier run left; take it out in the rule editor before another run: this one would put a second beside it"
        exit 2
    fi
    RULES_TOUCHED=1
    out=$(harness_install_marker "$RULES_FILE" "$BACKUP" "$rule" "$2"); rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$out"
        # A refusal changed nothing and left no backup, so there is nothing to put back.
        if [ "$rc" -eq 2 ]; then RULES_TOUCHED=0; fi
        exit 2
    fi
    ok "$out"
}

# load_marker: chooses Reload Rules, so that the app takes the file with the marker rule in
# it, and checks the app took it: when the rules line was healthy before the run it is
# healthy after.
load_marker() {
    local menu line
    if ! reload_rules; then
        bad "could not choose $RELOAD_RULES_ITEM, so the app has not taken the marker rule"
        return 1
    fi
    menu=$(read_menu_retry) || menu=''
    line=$(rules_line_of "$menu")
    case "$RULES_LINE" in
        "$RULES_STEM"*)
            case "$line" in
                "$RULES_STEM"*) ok "the app took the file with the marker rule in it (\"$line\")" ;;
                *) bad "the app did not take the file with the marker rule in it; the menu's rules line is \"${line:-missing}\""; return 1 ;;
            esac ;;
        *) note "the rules line was not healthy before the run, so the marker rule's load is not judged by it" ;;
    esac
}

# presented_from_poster_since START [END]: how many banners macOS presented from the
# program that posts this script's banners between two moments, as the log counts them.
# It prints a number and nothing the log says.
presented_from_poster_since() {
    /usr/bin/log show --start "$1" ${2:+--end "$2"} --style compact \
        --predicate 'process == "usernoted" AND eventMessage CONTAINS "Presenting <NotificationRecord"' 2>/dev/null \
        | grep -c "Presenting <NotificationRecord app:\"$POSTER_APP\""
}

# --------------------------------------------------------------------------- --escalation
# What M4's Task 7 wrote and did not build (M5 plan, Task 9).

run_escalation() {
    local menu why tries burst_start settled shown_min shown_max n found i
    refuse_or_go
    install_marker escalation 4
    load_marker || return 0

    burst_start=$(date '+%Y-%m-%d %H:%M:%S')
    MARKER_POSTED=1
    ESCALATION_OPEN=1
    post_marker_banner "Escalation check, banner 1 of 5"

    # One alert escalating, and its Acknowledge item. It is polled for: capture reads the
    # banner as it is drawn, and the escalation begins as it is read.
    tries=0
    while [ "$tries" -lt 5 ]; do
        sleep 3
        menu=$(read_menu_retry) || menu=''
        if why=$(harness_marker_only_guard 1 "$menu"); then break; fi
        tries=$((tries + 1))
    done
    if ! why=$(harness_marker_only_guard 1 "$menu"); then
        bad "the marker did not make one alert escalate: $why"
        note "check that the health line is verified, that Script Editor may show notifications and that no Focus is on; the marker is the first rule in rules.json, so no rule of yours can take a banner with its title, but a real page may have come in meanwhile, and the menu's last match names the rule that took the latest banner"
        note "no more banners were posted and nothing was acknowledged; what is escalating, if the menu shows it, goes on, to its panel and its Shortcut if it has them, until you acknowledge it by hand"
        return 0
    fi
    ok "the menu says \"$ESCALATING_STEM\", shows $ACKNOWLEDGE_ITEM and names the marker rule as the last match"

    # Four more banners, each with its own text.
    for i in 2 3 4 5; do
        sleep 2
        post_marker_banner "Escalation check, banner $i of 5"
    done

    # A banner presented in the last few seconds may or may not be counted yet, so the
    # menu's count is checked against a range, as the check of two banners is: at least
    # everything presented up to 3 s ago, at most everything presented so far.
    sleep 8
    settled=$(date -v-3S '+%Y-%m-%d %H:%M:%S')
    menu=$(read_menu_retry) || menu=''
    shown_min=$(presented_from_poster_since "$burst_start" "$settled")
    shown_max=$(presented_from_poster_since "$burst_start")
    : "${shown_min:=0}"
    : "${shown_max:=0}"
    if [ "$shown_max" -lt 1 ]; then
        note "could not confirm that any marker banner was presented — the count of matches is not checked"
        found=''
    else
        found=''
        n=$shown_min
        [ "$n" -ge 1 ] || n=1
        while [ "$n" -le "$shown_max" ]; do
            if harness_marker_only_guard "$n" "$menu" >/dev/null; then found=$n; break; fi
            n=$((n + 1))
        done
        if [ -n "$found" ]; then
            ok "the menu counts $found matches of the marker's banners, within the $shown_min to $shown_max the log says were presented"
        else
            why=$(harness_marker_only_guard "$shown_max" "$menu")
            bad "the menu does not show only the marker's escalation with a count of matches within the $shown_min to $shown_max the log says were presented: $why"
        fi
    fi

    # Acknowledge, only when the menu shows nothing but the marker's own escalation, with
    # the count the run has just asserted. Without a count asserted, or if anything else is
    # escalating by now, nothing is touched.
    if [ -z "$found" ]; then
        bad "nothing was acknowledged, since the count of the marker's matches was not asserted: the marker's own row stays on the menu, escalating, until you acknowledge it by hand (a capped escalation stays listed)"
        return 0
    fi
    menu=$(read_menu_retry) || menu=''
    if ! why=$(harness_marker_only_guard "$found" "$menu"); then
        bad "$why"
        bad "nothing was acknowledged: the marker's own row stays on the menu, escalating, until you acknowledge it by hand (a capped escalation stays listed), and so does anything else that is escalating"
        return 0
    fi
    if [ "$(choose_menu_item "$ACKNOWLEDGE_ITEM")" != "clicked" ]; then
        bad "could not choose $ACKNOWLEDGE_ITEM: the marker's own row stays on the menu until you acknowledge it by hand"
        return 0
    fi
    sleep 2
    menu=$(read_menu_retry) || menu=''
    if why=$(harness_refuse_guard escalation "$menu"); then
        ESCALATION_OPEN=0
        ok "after $ACKNOWLEDGE_ITEM the menu no longer says anything is escalating"
    else
        bad "something is still escalating after $ACKNOWLEDGE_ITEM was chosen: $why"
    fi
}

# ------------------------------------------------------------------------------ --on-call

run_on_call() {
    local menu titles tries digest
    refuse_or_go
    titles=$(window_titles)
    if grep -qxF -- "$ON_CALL_CHECK_TITLE" <<< "$titles"; then CHECK_WINDOW_AT_START=1; fi

    RULES_WATCHED=1
    ON_CALL_SWITCHED=1
    if [ "$(choose_menu_item "$ON_CALL_ITEM")" != "clicked" ]; then
        bad "could not choose $ON_CALL_ITEM"
        return 0
    fi
    sleep 3
    menu=$(read_menu_retry) || menu=''
    if menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then
        ok "the menu shows the on-call line"
    else
        bad "the menu does not show the on-call line after $ON_CALL_ITEM was chosen"
    fi
    digest=$(rules_digest)
    if [ "$digest" = "$RULES_DIGEST_START" ]; then
        ok "switching on-call mode on left rules.json unchanged"
    else
        bad "rules.json changed when on-call mode was switched on ($RULES_DIGEST_START → $digest)"
    fi
    tries=0
    while [ "$tries" -lt 3 ] && ! on_call_key_written; do
        tries=$((tries + 1))
        sleep 1
    done
    if on_call_key_written; then
        ok "the saved key $ON_CALL_KEY is written"
    else
        bad "the saved key $ON_CALL_KEY is not written"
    fi

    switch_on_call_off_if_on
    tries=0
    while [ "$tries" -lt 3 ] && on_call_key_written; do
        tries=$((tries + 1))
        sleep 1
    done
    if on_call_key_written; then
        bad "the saved key $ON_CALL_KEY is still there after on-call mode was switched off"
    else
        ok "the saved key $ON_CALL_KEY is gone"
    fi
    close_check_window_if_run_opened
}

# on_call_key_written: whether the app's one saved key for the on-call state is there. It
# reads that key and no other, and prints nothing of what the key holds.
on_call_key_written() {
    defaults read "$APP_DOMAIN" "$ON_CALL_KEY" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------ --snooze

run_snooze() {
    local menu tries why
    refuse_or_go
    install_marker snooze 5
    load_marker || return 0

    SNOOZE_STARTED=1
    if [ "$(choose_submenu_item "$SNOOZE_ITEM" "$SNOOZE_FIFTEEN_ITEM")" != "clicked" ]; then
        bad "could not choose $SNOOZE_FIFTEEN_ITEM in the $SNOOZE_ITEM submenu"
        return 0
    fi
    sleep 2
    menu=$(read_menu_retry) || menu=''
    if menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then
        ok "the menu shows a running snooze"
    else
        bad "the menu does not show a running snooze after $SNOOZE_FIFTEEN_ITEM was chosen"
        return 0
    fi

    MARKER_POSTED=1
    MARKER_SUMMARY=pending
    post_marker_banner "Snooze check"
    # The marker's match is held when the menu's summary is exactly the marker's one match,
    # which the summary guard judges. The stem every summary has would not do: the last-match
    # line carries it too, for any match that was held, and a summary the run did not make
    # carries it, so a menu could say it with the marker never held. The run refused to begin
    # with a summary on the menu, so one that is there now is the run's.
    tries=0
    while [ "$tries" -lt 4 ]; do
        sleep 3
        menu=$(read_menu_retry) || menu=''
        if harness_summary_guard "$menu" >/dev/null; then break; fi
        tries=$((tries + 1))
    done
    if harness_summary_guard "$menu" >/dev/null; then
        ok "the menu says the marker's one match was held while snoozed"
    else
        bad "the menu does not show the marker's one match held while snoozed: the marker rule may not have been held, or was not captured, or something else was held with it"
    fi
    if why=$(harness_refuse_guard escalation "$menu"); then
        ok "no alert is escalating"
    else
        bad "an alert is escalating during the snooze: $why"
    fi

    # End it at once, so the window in which the snooze quiets the owner's own flagged
    # rules is as short as the run is.
    end_snooze_if_running
    dismiss_marker_summary
}

# ----------------------------------------------------------------------------- the run
# A flag's backup guard and traps come before everything else, even the check that the
# app is running, since the guard works on files and an earlier run may have left the
# rules file marked.

if [ -n "$MODE" ]; then
    begin_flag "$MODE"
fi

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

# The backup guard put an earlier run's backup back before the app was touched, so the
# app has not read the file it put back. It does now.
if [ "$RELOAD_OWED" -eq 1 ]; then
    if reload_rules; then
        note "chose $RELOAD_RULES_ITEM, so the app holds the rules file the backup guard put back"
    else
        bad "could not choose $RELOAD_RULES_ITEM: the app holds the rules file it had until it is reloaded or relaunched"
    fi
fi

# ------------------------------------------------------------------- menu state

head_ "Menu state"

MENU=$(read_menu)
if [ "$MENU" = "NO_STATUS_ITEM" ]; then
    bad "SignalLadder has no status item in the menu bar that the Accessibility API can see"
    exit 2
fi
if [ -z "$MENU" ]; then
    bad "could not read the menu over the Accessibility API"
    note "the process running this script needs Accessibility permission"
    exit 2
fi

# A flag is for a Mac that is off shift. When the menu already shows a state that belongs to a
# real shift the run stops here, before any default check posts a banner or opens a window.
# The flag's own check reads the menu again before it acts, since a page can come in meanwhile.
if [ -n "$MODE" ]; then
    refuse_on_shift "$MENU" "as the run first read it"
fi

# The health line is not always the first line: while an alert is escalating its
# lines head the menu. So it is found by what it says, as the rules line is, and
# its cause is the line after it, when it has one. The On Call item comes next
# in the menu whether or not there is a cause, and its own lines follow it (the
# since-line, the hold, the findings, the check window's item), so the cause is
# only a line that comes before the On Call item. While a required step of the setup is
# outstanding the menu carries one line about it, between the cause and the On Call
# item, and that line is no cause either. These are the wordings `HealthTitle` gives the
# health line, read from the file that declares them, and `HarnessConstantsTests` holds
# the function to those. The first and third are what the line begins with, and an age
# follows; the others are the whole line.
is_health_line() {
    case "$1" in
        "$HEALTH_VERIFIED"*|"$HEALTH_UNVERIFIED"*) return 0 ;;
        "$HEALTH_CHECKING"|"$HEALTH_CANNOT_VERIFY"|"$HEALTH_NOT_CAPTURING"|"$HEALTH_SOME_UNREAD") return 0 ;;
        *) return 1 ;;
    esac
}

# health_and_cause MENU: the menu's health line, then the line after it when
# there is one and it is neither the On Call item nor the setup line, which are not
# causes and which nothing after them can be. Prints nothing when no line says what a
# health line says.
health_and_cause() {
    local found=0 line
    while IFS= read -r line; do
        if [ "$found" -eq 1 ]; then
            if [ "$line" != "$ON_CALL_ITEM" ]; then
                case "$line" in
                    "$NUDGE_STEM"*) ;;
                    *) printf '%s\n' "$line" ;;
                esac
            fi
            return 0
        fi
        if is_health_line "$line"; then
            found=1
            printf '%s\n' "$line"
        fi
    done <<< "$1"
    return 0
}

HEALTH_AND_CAUSE=$(health_and_cause "$MENU")
HEALTH=$(printf '%s\n' "$HEALTH_AND_CAUSE" | sed -n '1p')
CAUSE=$(printf '%s\n' "$HEALTH_AND_CAUSE" | sed -n '2p')
COUNT_BEFORE=$(captured_count "$MENU")
: "${COUNT_BEFORE:=0}"

note "health: $HEALTH"
note "count:  $COUNT_BEFORE"

case "$HEALTH" in
    "$HEALTH_VERIFIED"*)             ok "health is verified" ;;
    "$HEALTH_CHECKING")              note "health not yet established (no self-test has completed)" ;;
    "$HEALTH_UNVERIFIED"*)           bad "health evidence is stale — a self-test that should have run has not" ;;
    "$HEALTH_CANNOT_VERIFY")         bad "degraded — see the cause line below" ;;
    "$HEALTH_NOT_CAPTURING")         bad "BLIND — the app believes it is capturing nothing" ;;
    "$HEALTH_SOME_UNREAD")           bad "degraded — a real banner in the last half hour had no readable text" ;;
    "")                              bad "no line in the menu says what a health line says" ;;
    *)                               bad "unrecognised health line: $HEALTH" ;;
esac

case "$CAUSE" in
    "$CAPTURED_STEM"*|"") : ;;
    *) note "cause:  $CAUSE" ;;
esac

# While a required step of the setup is outstanding, and the guide is not open, the
# menu carries one line that begins with the setup stem. A Mac whose guide is finished
# has none.
if menu_has_stem "$MENU" "$NUDGE_STEM"; then
    bad "the menu carries a setup line, so a required step of the setup is outstanding"
else
    ok "no setup line is on the menu"
fi

if menu_has_item "$MENU" "$INSPECTOR_ITEM"; then
    ok "Inspector is reachable from the menu"
else
    bad "no Inspector item in the menu"
fi

# The rules summary is the only menu line that BEGINS with its word once any leading
# warning mark is skipped — the items that reload the rules, edit them or open their
# file all start with another word.
RULES_LINE=$(rules_line_of "$MENU")
if [ -z "$RULES_LINE" ]; then
    bad "no rules status line in the menu"
else
    note "rules:  $RULES_LINE"
    # A rules file that did not load leaves the app as silent as a blind
    # pipeline, so it fails the harness for the same reason it claims the
    # warning glyph.
    case "$RULES_LINE" in
        "$RULES_STEM"*) ok "rules status is shown and healthy" ;;
        *)              bad "the rules file has a problem — the menu lists it" ;;
    esac
fi

if menu_has_item "$MENU" "$RELOAD_RULES_ITEM"; then
    ok "$RELOAD_RULES_ITEM is reachable from the menu"
else
    bad "no $RELOAD_RULES_ITEM item in the menu"
fi

# ------------------------------------------------------------------------ alerts
# An alert that could not play, or an output nobody can hear, means a rule that
# should wake someone will not. Both fail the run. The mute walkthrough must be
# offered whenever a rule that alerts aloud names an app: until that app's own sound is
# off, every alert plays on top of it.

head_ "Alerts"

# Counts enabled rules that alert aloud — a sound, speech or both — and name an app with `app equals`
# outside any `not`, which are exactly the rules that put an app into the
# walkthrough. Reads the rules file (the user's configuration), never any
# notification. In a function for the bash 3.2 heredoc bug described above.
count_named_alerting_rules() {
    osascript -l JavaScript - "$1" <<'JXA' 2>/dev/null
function run(argv) {
  ObjC.import('Foundation');
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (text.isNil()) return 0;
  let file;
  try { file = JSON.parse(ObjC.unwrap(text)); } catch (e) { return 0; }
  const named = c => !c ? [] : (c.field === 'app' && c.op === 'equals') ? [c.value]
                  : c.and ? c.and.flatMap(named) : c.or ? c.or.flatMap(named) : [];
  return (file.rules || []).filter(r => r.enabled !== false && r.alert && typeof r.alert === 'object'
                                        && named(r.condition).length > 0).length;
}
JXA
}

# Every failure line an alert can leave, whole or in part: "Could not play: …",
# "Could not speak: …", "…, but could not speak: …", "…, but could not play: …". Each
# is a stem the app builds the line from and a colon and a space, case and colon
# included, so a rule merely named for a failure does not fail the run.
if grep -qF -e "$FAIL_PLAY: " -e "$FAIL_SPEAK: " -e "$FAIL_PLAYED_NOT_SPOKEN: " -e "$FAIL_SPOKE_NOT_PLAYED: " <<< "$MENU"; then
    bad "an alert could not play or speak — the menu's ⚠︎ line says why"
else
    ok "no alert has failed to play or speak"
fi

if grep -qF -- "$OUTPUT_SILENT" <<< "$MENU"; then
    bad "the Mac's output is muted or at zero volume — rules that alert aloud cannot be heard"
fi

LAST_MATCH=$(grep -E "^[^A-Za-z]*$LAST_MATCH_STEM" <<< "$MENU" | head -1)
[ -n "$LAST_MATCH" ] && note "last:   $LAST_MATCH"

NAMED_SOUNDING=$(count_named_alerting_rules "$RULES_FILE")
: "${NAMED_SOUNDING:=0}"
# App names are not printed: some come from captured banners.
WALKTHROUGH=$(grep -E "^[^A-Za-z]*($MUTE_NOT_CONFIRMED_STEM|$MUTE_CONFIRMED_STEM):" <<< "$MENU" | head -1)

if [ -z "$WALKTHROUGH" ]; then
    if [ "$NAMED_SOUNDING" -gt 0 ]; then
        bad "$NAMED_SOUNDING rule(s) that alert aloud name an app, but the menu offers no mute walkthrough"
    else
        note "no mute walkthrough — no enabled rule that alerts aloud names an app"
    fi
else
    case "$WALKTHROUGH" in
        *"$MUTE_NOT_CONFIRMED_STEM"*) note "mute walkthrough offered; some apps are not yet confirmed muted" ;;
        *)                            ok "mute walkthrough offered; every app is confirmed muted" ;;
    esac
fi

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
        | grep -c "$APP_DOMAIN.*muted by DND")
[ "${MUTED:-0}" -gt 0 ] && bad "$MUTED of our own notifications were muted by DND in the last 5 minutes"

# ------------------------------------------------------------------ live capture
# Posts one notification and checks the count moves. This is the only positive
# evidence that capture works end to end.

head_ "Live capture"

# The log is read from the moment the banner was posted, and read again for a while,
# since the entry that says it was drawn can reach the log after the banner is on screen.
# The poster is matched whatever its case: NotificationCenter names it in lower case
# ("com.apple.scripteditor2") on macOS 27.2, where usernoted keeps "com.apple.ScriptEditor2",
# and a match of the case alone found nothing on every run against a signed build until
# 2026-10-13, so the check said inconclusive for banners the log showed drawn.
DRAWN_START=$(date '+%Y-%m-%d %H:%M:%S')
osascript -e 'display notification "Automated capture check" with title "SignalLadder Test" subtitle "verify-live.sh"' >/dev/null 2>&1

DRAWN=0
for _ in 1 2 3 4 5 6; do
    sleep 2
    DRAWN=$(/usr/bin/log show --start "$DRAWN_START" --predicate 'process == "NotificationCenter"' --style compact 2>/dev/null \
            | grep -iF -- "$POSTER_APP" | grep -c "canDisplayWhileCenterIsClosed: true")
    [ "${DRAWN:-0}" -gt 0 ] && break
done

if [ "${DRAWN:-0}" -gt 0 ]; then
    ok "test banner was drawn (not muted)"
else
    note "could not confirm the test banner was drawn — capture result below is inconclusive"
fi

COUNT_AFTER=$(captured_count "$(read_menu)")
: "${COUNT_AFTER:=0}"

if [ "$COUNT_AFTER" -gt "$COUNT_BEFORE" ]; then
    ok "capture count rose $COUNT_BEFORE → $COUNT_AFTER — capture is working live"
else
    bad "capture count did not move ($COUNT_BEFORE → $COUNT_AFTER) — the banner was not captured"
fi

# A banner arriving while another is still on screen replaces it inside the
# same window, and no window event fires. Capture missed every such banner
# until 2026-09-29; this is its regression check. The count must move by
# exactly the number of banners macOS presented meanwhile — ours, and any other
# app's that happen to arrive — leaving out SignalLadder's own self-tests,
# which are never counted. One fewer is a miss; one more, a banner captured
# twice.
presented_since() {  # presented_since START [END]
    /usr/bin/log show --start "$1" ${2:+--end "$2"} --style compact \
        --predicate 'process == "usernoted" AND eventMessage CONTAINS "Presenting <NotificationRecord"' 2>/dev/null \
        | grep 'Presenting <NotificationRecord app:' | grep -vc "app:\"$APP_DOMAIN\""
}
PAIR_START=$(date '+%Y-%m-%d %H:%M:%S')
osascript -e 'display notification "Replacement check, first" with title "SignalLadder Test" subtitle "verify-live.sh"' >/dev/null 2>&1
sleep 2
osascript -e 'display notification "Replacement check, second" with title "SignalLadder Test" subtitle "verify-live.sh"' >/dev/null 2>&1
sleep 10

# A banner presented in the last few seconds may or may not be counted yet,
# so the expected change is a range: everything shown up to 3 s ago, at
# least, and everything shown so far, at most.
SETTLED=$(date -v-3S '+%Y-%m-%d %H:%M:%S')
COUNT_PAIR=$(captured_count "$(read_menu)")
: "${COUNT_PAIR:=0}"
SHOWN_MIN=$(presented_since "$PAIR_START" "$SETTLED")
SHOWN_MAX=$(presented_since "$PAIR_START")
MOVED=$((COUNT_PAIR - COUNT_AFTER))
if [ "${SHOWN_MAX:-0}" -lt 2 ]; then
    note "could not confirm both test banners were presented — replacement check inconclusive"
elif [ "$MOVED" -lt "${SHOWN_MIN:-0}" ]; then
    bad "a banner arriving while another was on screen was missed: $SHOWN_MIN presented, count moved by $MOVED"
elif [ "$MOVED" -gt "$SHOWN_MAX" ]; then
    bad "a banner was captured twice: $SHOWN_MAX presented, count moved by $MOVED"
else
    ok "two banners 2 s apart were each captured once ($MOVED captured, $SHOWN_MAX presented)"
fi

# --------------------------------------------------------------------- contradiction
# Worth calling out loudly: if capture demonstrably works but health is not
# verified, the health display is stale or wrong. That combination is the exact
# failure this milestone exists to prevent, in its quietest form.

# The title carries the evidence's age ("Working — verified 3 min ago"), so
# it is matched by prefix. "Unverified" is left out: it claims only that the
# evidence is old, which a live capture does not disprove, and the health
# check above has already failed it.
case "$HEALTH" in
    "$HEALTH_VERIFIED"*|"$HEALTH_UNVERIFIED"*) CONTRADICTABLE=0 ;;
    *)                                         CONTRADICTABLE=1 ;;
esac
if [ "$COUNT_AFTER" -gt "$COUNT_BEFORE" ] && [ "$CONTRADICTABLE" -eq 1 ]; then
    head_ "Contradiction"
    bad "capture demonstrably works, yet health reports \"$HEALTH\""
    note "the app is telling the user something its own behaviour disproves"
fi

# --------------------------------------------------------------------- inspector

head_ "Inspector"

# In a function for the bash 3.2 heredoc bug described above. The menu item to choose is
# an argument, the one the app shows (see "text the app owns").
read_inspector_windows() {  # read_inspector_windows ITEM
    osascript - "$1" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set itemTitle to item 1 of argv
  tell application "System Events"
    tell process "SignalLadder"
      set itm to missing value
      repeat with bar in menu bars
        repeat with cand in menu bar items of bar
          if subrole of cand is "AXMenuExtra" then set itm to contents of cand
        end repeat
      end repeat
      if itm is missing value then return "NO_STATUS_ITEM"
      perform action "AXPress" of itm
      delay 1.0
      try
        click menu item itemTitle of menu 1 of itm
      on error
        key code 53
        return "could not click"
      end try
      delay 1.5
      set names to name of every window
      set AppleScript's text item delimiters to linefeed
      return names as text
    end tell
  end tell
end run
APPLESCRIPT
}

# In a function for the bash 3.2 heredoc bug described above. The menu item to choose and
# the window's title are arguments, the ones the app shows (see "text the app owns").
open_and_close_window() {  # open_and_close_window ITEM TITLE
    osascript - "$1" "$2" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set itemTitle to item 1 of argv
  set windowTitle to item 2 of argv
  tell application "System Events"
    tell process "SignalLadder"
      set itm to missing value
      repeat with bar in menu bars
        repeat with cand in menu bar items of bar
          if subrole of cand is "AXMenuExtra" then set itm to contents of cand
        end repeat
      end repeat
      if itm is missing value then return "NO_STATUS_ITEM"
      perform action "AXPress" of itm
      delay 1.0
      try
        click menu item itemTitle of menu 1 of itm
      on error
        key code 53
        return "could not click"
      end try
      delay 1.5
      set names to name of every window
      set AppleScript's text item delimiters to linefeed
      set opened to names as text
      try
        click (first button of window windowTitle whose subrole is "AXCloseButton")
        delay 1.0
      end try
      set stillOpen to (exists window windowTitle)
      return opened & linefeed & "STILL_OPEN=" & stillOpen
    end tell
  end tell
end run
APPLESCRIPT
}

# The run closes the window it opened, as it closes the editor and Settings; it left the
# Inspector open on every run against a signed build until 2026-10-13. A window that was
# open before the run is the user's, and is left as it was.
if window_titles | grep -qxF -- "$INSPECTOR_TITLE"; then
    INSPECTOR_WAS_OPEN=1
    INSPECTOR=$(read_inspector_windows "$INSPECTOR_ITEM")
else
    INSPECTOR_WAS_OPEN=0
    INSPECTOR=$(open_and_close_window "$INSPECTOR_ITEM" "$INSPECTOR_TITLE")
fi

if grep -qF -- "$INSPECTOR_TITLE" <<< "$INSPECTOR"; then
    ok "Inspector window opened"
else
    bad "Inspector window did not open (got: ${INSPECTOR:-nothing})"
fi
if [ "$INSPECTOR_WAS_OPEN" -eq 1 ]; then
    note "the Inspector was open before the run, so it is left open"
elif grep -q "STILL_OPEN=true" <<< "$INSPECTOR"; then
    bad "the Inspector window did not close"
fi

# ------------------------------------------------------------------ rule editor
# The editor can write rules.json, so the check that matters most is the one
# it must never fail: opening it and closing it without saving changes nothing
# on disk — not a byte. Its SwiftUI content cannot be read over the
# Accessibility API; the window title and the file can.

head_ "Rule editor"

BEFORE_RULES=$(rules_digest)
EDITOR=$(open_and_close_window "$EDIT_RULES_ITEM" "$RULE_EDITOR_TITLE")
AFTER_RULES=$(rules_digest)

if grep -qF -- "$RULE_EDITOR_TITLE" <<< "$EDITOR"; then
    ok "$EDIT_RULES_ITEM opened the rule editor"
else
    bad "the rule editor did not open (got: ${EDITOR:-nothing})"
fi
if grep -q "STILL_OPEN=true" <<< "$EDITOR"; then
    bad "the rule editor did not close — it may be asking about unsaved changes it should not have"
fi
if ! grep -qF -- "$RULE_EDITOR_TITLE" <<< "$EDITOR"; then
    note "rules.json not checked — the editor never opened"
elif [ "$BEFORE_RULES" = "$AFTER_RULES" ]; then
    ok "opening and closing the editor left rules.json unchanged"
else
    bad "rules.json changed just by opening and closing the editor ($BEFORE_RULES → $AFTER_RULES)"
fi

# --------------------------------------------------------------------- settings
# The Settings item opens a window with its own title. Opening it and closing it changes
# nothing, and its content, like the editor's, is not read: the title can be.

head_ "Settings"

SETTINGS_WINDOW=$(open_and_close_window "$SETTINGS_ITEM" "$SETTINGS_TITLE")

if grep -qF -- "$SETTINGS_TITLE" <<< "$SETTINGS_WINDOW"; then
    ok "$SETTINGS_ITEM opened a window titled \"$SETTINGS_TITLE\""
else
    bad "$SETTINGS_ITEM did not open the Settings window (got: ${SETTINGS_WINDOW:-nothing})"
fi
if grep -q "STILL_OPEN=true" <<< "$SETTINGS_WINDOW"; then
    bad "the Settings window did not close"
fi

# ------------------------------------------------------------------------ cost

head_ "Resource cost"

RSS=$(ps -o rss= -p "$PID" | tr -d ' ')
note "idle CPU ${IDLE_CPU}% (sampled over ${IDLE_WINDOW}s before this script touched the app)"
note "resident $((RSS / 1024)) MB"
awk -v c="$IDLE_CPU" 'BEGIN { exit !(c <= 2.0) }' \
    && ok "idle CPU within budget" \
    || bad "idle CPU ${IDLE_CPU}% is above 2%"

# ------------------------------------------------------------------------ flags
# The flag's check, if one was given. The refuse guard has already run on the menu the run
# first read, before the default checks. Each flag's check begins by reading the menu afresh
# and running it again, and nothing is changed before that.

case "$MODE" in
    escalation) head_ "The --escalation run"; run_escalation ;;
    on-call)    head_ "The --on-call run";    run_on_call ;;
    snooze)     head_ "The --snooze run";     run_snooze ;;
esac

# ------------------------------------------------------------------- still manual

head_ "Still requires you (system security settings)"
note "revoke/grant Accessibility          → tests live recovery without relaunch"
note "untick Desktop for SignalLadder       → tests delivery faults are not blamed on capture"
note "toggle Do Not Disturb               → tests the suppression path"

# finish: undoes what a flag run changed, which is nothing for the default run, and then
# prints the result. The undoing comes first so that what it checks is in the result.
finish() {
    cleanup_run
    head_ "Result"
    printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
    exit $?
}
finish
