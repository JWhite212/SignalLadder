#!/bin/bash
# Scripts/harness-guards-test.sh — proof that the live harness's guards work
#
# The guards in Scripts/harness-guards.sh stand between the harness and a real page or
# the owner's real rules, so each is run here against fixtures, case by case, before
# the harness is trusted with a Mac that may be on a shift (M5 plan, Task 9). This is a
# script and not an XCTest because it runs the shell functions as they will run:
# under the macOS system bash 3.2 and with the BSD userland.
#
# It starts no app, posts no notification and reads nothing but the files under
# Scripts/fixtures/, the constants in Sources/NotificationCore and the temporary folder it
# makes with mktemp -d and removes again. It never reads the owner's rules file or the
# app's preferences. The only program it starts that is not one of the shell's own tools
# is `osascript -l JavaScript`, which the marker writer parses JSON with and which sends
# no Apple event, and `plutil`, which it uses as a second opinion on the files the writer
# makes.
#
# The rules fixtures are the app's own layout and are exact to the byte: the app writes
# no newline after the last brace, and the digests beside them are the digests of those
# bytes. An editor that adds a final newline to one of them fails a case here, and not
# silently.
#
# An unreadable file cannot be committed (git keeps no read bit), so those cases make one
# in the temporary folder. A user who can read anything, root, cannot make one, and those
# cases are skipped and said to be.
#
# Usage:  ./Scripts/harness-guards-test.sh
# Exit:   0 every case passed, 1 a case failed, 2 could not run

set -uo pipefail

PASS=0
FAIL=0
SKIP=0

if [ -t 1 ]; then
    GOOD=$'\033[32m✓\033[0m'; BAD=$'\033[31m✗\033[0m'; DIM=$'\033[2m·\033[0m'
else
    GOOD='ok  '; BAD='FAIL'; DIM='skip'
fi
pass()  { printf '  %s %s\n' "$GOOD" "$1"; PASS=$((PASS+1)); }
fail()  { printf '  %s %s\n' "$BAD" "$1"; FAIL=$((FAIL+1)); }
skip()  { printf '  %s %s\n' "$DIM" "$1"; SKIP=$((SKIP+1)); }
head_() { printf '\n%s\n' "$1"; }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURES="$HERE/fixtures"

# The tree the cases read the app's words from is the one this script is in, whatever
# REPO_ROOT the shell that runs it has. The guards honour that variable (verify-live.sh sets
# it), and one left over from another checkout would be tested here without a word said.
# It is a variable of this shell and is not exported.
REPO_ROOT=$(cd "$HERE/.." && pwd)

BASE=${TMPDIR:-/tmp}
BASE=${BASE%/}
WORK=$(mktemp -d "$BASE/harness-guards-test.XXXXXX") || { echo "could not make a temporary folder in $BASE"; exit 2; }
cleanup() { chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ----------------------------------------------------------------------- sourcing
# The file under test is sourced in a subshell first, to see what sourcing does. It must
# print nothing, set no variable, define nothing but the guards' own functions, and
# leave the folder it was sourced in as it was.

head_ "Sourcing the guards"

mkdir "$WORK/sourced-in"
VARS_BEFORE="$WORK/vars-before.txt"
VARS_AFTER="$WORK/vars-after.txt"
FUNCS_BEFORE="$WORK/funcs-before.txt"
FUNCS_AFTER="$WORK/funcs-after.txt"
SOURCED_OUT=$( cd "$WORK/sourced-in" && {
    compgen -v | sort > "$VARS_BEFORE"
    declare -F | sed 's/^declare -f //' | sort > "$FUNCS_BEFORE"
    . "$HERE/harness-guards.sh"
    compgen -v | sort > "$VARS_AFTER"
    declare -F | sed 's/^declare -f //' | sort > "$FUNCS_AFTER"
} 2>&1 )
FUNCS_ADDED=$(comm -13 "$FUNCS_BEFORE" "$FUNCS_AFTER")

if [ -z "$SOURCED_OUT" ]; then
    pass "sourcing prints nothing"
else
    fail "sourcing printed: $SOURCED_OUT"
fi
if cmp -s "$VARS_BEFORE" "$VARS_AFTER"; then
    pass "sourcing sets no variable"
else
    fail "sourcing set variables: $(diff "$VARS_BEFORE" "$VARS_AFTER" | grep '^[<>]' | tr '\n' ' ')"
fi
if [ -n "$FUNCS_ADDED" ] && ! printf '%s\n' "$FUNCS_ADDED" | grep -qvE '^(harness_|_harness_|core_)'; then
    pass "sourcing defines only the guards' own functions ($(printf '%s\n' "$FUNCS_ADDED" | wc -l | tr -d ' ') of them)"
else
    fail "sourcing defined functions that are not the guards': $(printf '%s\n' "$FUNCS_ADDED" | grep -vE '^(harness_|_harness_|core_)' | tr '\n' ' ')"
fi
if [ -z "$(ls -A "$WORK/sourced-in")" ]; then
    pass "sourcing leaves the folder it was sourced in empty"
else
    fail "sourcing made files: $(ls -A "$WORK/sourced-in" | tr '\n' ' ')"
fi

. "$HERE/harness-guards.sh"

# ---------------------------------------------------------------------- the helpers

# check LABEL WANT COMMAND...: runs the command, and passes when it returns WANT and,
# for anything but 0, when it printed a reason.
OUT=''
check() {
    local label=$1 want=$2 rc
    shift 2
    OUT=$("$@" 2>&1)
    rc=$?
    if [ "$rc" -ne "$want" ]; then
        fail "$label (returned $rc, wanted $want)"
        [ -n "$OUT" ] && printf '        %s\n' "$OUT"
        return 1
    fi
    if [ "$want" -ne 0 ] && [ -z "$OUT" ]; then
        fail "$label (returned $want and printed no reason)"
        return 1
    fi
    pass "$label"
}

# assert LABEL COMMAND...: passes when the command succeeds.
assert() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

# The text of a fixture menu, as the harness would hold it in a variable.
m() { cat "$FIXTURES/menu-$1.txt"; }

# The marker rules, as the text of one JSON object each. A builtin and not cat, which some
# cases make fail.
rule_text() { printf '%s\n' "$(<"$FIXTURES/marker-rule-$1.json")"; }

# A fresh folder, in which a case plays out.
fresh() { mktemp -d "$WORK/case.XXXXXX"; }

# A fresh folder holding a copy of a leftover state under fixtures/backup-states/.
state() {
    local dir
    dir=$(fresh)
    cp "$FIXTURES/backup-states/$1/"* "$dir/"
    printf '%s\n' "$dir"
}

# A fresh folder holding the owner-shaped rules file as rules.json.
owner() {
    local dir
    dir=$(fresh)
    cp "$FIXTURES/rules-owner.json" "$dir/rules.json"
    printf '%s\n' "$dir"
}

same() { cmp -s "$1" "$2"; }
differs() { ! cmp -s "$1" "$2"; }
absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
lacks() { ! contains "$1" "$2"; }

# A value out of a JSON file, read by plutil, which is not the parser the writer uses.
json_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# What a folder holds besides rules.json, one name to a line.
others() { ls -A "$1" | grep -v '^rules.json$'; }

# The folder holds rules.json as the owner-shaped fixture has it, and nothing else.
unchanged() { [ -z "$(others "$1")" ] && same "$1/rules.json" "$FIXTURES/rules-owner.json"; }

# The marked file differs from the original in the one place the rule went in and in the
# digits of the version, and in nothing else. It finds where the two first differ, which is
# where the rule went in, and compares everything from there to the end of the original
# with the end of the marked file, the version aside. Everything before that point is
# the same by the meaning of "first".
only_the_rule_and_the_version() {  # only_the_rule_and_the_version ORIGINAL MARKED
    local first length
    first=$(cmp "$1" "$2" 2>/dev/null | sed -n 's/.* \([0-9][0-9]*\), line.*/\1/p')
    [ -n "$first" ] || return 1
    length=$(( $(wc -c < "$1") - first + 1 ))
    [ "$(tail -c "$length" "$1" | sed 's/"version" : [0-9]*/"version" : N/')" = \
      "$(tail -c "$length" "$2" | sed 's/"version" : [0-9]*/"version" : N/')" ]
}

# The marked file's first three rules are the original's, in the same order, by name and id,
# read by plutil. Byte for byte is the check above; this is a second opinion from a parser
# that is not the writer's.
same_rules() {  # same_rules ORIGINAL MARKED
    local i
    for i in 0 1 2; do
        [ "$(json_get "$1" "rules.$i.name")" = "$(json_get "$2" "rules.$i.name")" ] || return 1
        [ "$(json_get "$1" "rules.$i.id")" = "$(json_get "$2" "rules.$i.id")" ] || return 1
    done
}

guard() {  # guard DIR: the backup guard over DIR's rules.json
    harness_backup_guard "$1/rules.json" "$(harness_backup_path "$1/rules.json")"
}
own_guard() {  # own_guard DIR: the same, as the trap runs it at the end of the run whose backup it is
    harness_backup_guard "$1/rules.json" "$(harness_backup_path "$1/rules.json")" "this run"
}
mark() {  # mark DIR KIND NEEDED: the marker writer over DIR's rules.json
    harness_install_marker "$1/rules.json" "$(harness_backup_path "$1/rules.json")" "$(rule_text "$2")" "$3"
}

# The same, with one tool they call made to fail, in a subshell so that it fails nowhere
# else. Two more have something happen to the rules file while the marked one is being built:
# the owner saves a change as the original is copied aside, and a file appears where there was
# none. One puts a failed write right and then fails to put the original back. The last two
# are about the write itself: a run killed just after it, and a file that is not what was
# written when it is done, as when a Save lands as the write ends.
guard_when_cmp_fails()      ( cmp() { return 1; }; guard "$@" )
mark_when_cp_fails()        ( cp() { return 1; }; mark "$@" )
mark_when_cat_fails()       ( cat() { return 1; }; mark "$@" )
mark_when_shasum_fails()    ( shasum() { return 1; }; mark "$@" )
mark_when_the_file_changes() ( cp() { printf ' ' >> "$1"; command cp "$@"; }; mark "$@" )
mark_when_a_file_appears() (
    made=0
    rm() {
        if [ "$made" -eq 0 ]; then made=1; printf '%s' '{"version":1,"rules":[]}' > "$(dirname "${!#}")/rules.json"; fi
        command rm "$@"
    }
    mark "$@"
)
mark_when_killed_after_the_write() ( trap - EXIT; cat() { command cat "$@"; exit 137; }; mark "$@" )
mark_when_the_write_is_changed() ( cat() { command cat "$@"; printf ' '; }; mark "$@" )
mark_when_the_undoing_fails() (
    cat() { return 1; }
    copies=0
    cp() { copies=$((copies + 1)); if [ "$copies" -eq 1 ]; then command cp "$@"; else return 1; fi; }
    mark "$@"
)

# The id of the user running this, since a user who can read anything cannot make a
# file unreadable.
IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

# A tree with no NotificationCore in it, for the cases where a word cannot be read.
NO_CORE="$WORK/no-core"
mkdir -p "$NO_CORE/Sources/NotificationCore"

# A tree that holds the titles of the On Call and Snooze items and none of the other words,
# for the cases where a text is a menu and the words to judge it by cannot be read.
TITLES_ONLY="$WORK/titles-only"
mkdir -p "$TITLES_ONLY/Sources/NotificationCore"
printf '    public static let menuTitle = "%s"\n' "$(core_constant OnCall.swift menuTitle)" > "$TITLES_ONLY/Sources/NotificationCore/OnCall.swift"
printf '    public static let menuTitle = "%s"\n' "$(core_constant SnoozeText.swift menuTitle)" > "$TITLES_ONLY/Sources/NotificationCore/SnoozeText.swift"

# Two trees that hold the words of the escalation line and the Acknowledge item and lack one
# of the two words that say whose escalation it is: the marker rule's name, and the stem of the
# last-match line. The first has the app's AlertMenuText and no HarnessText; the second has both
# and an AlertMenuText with the declaration of the stem taken out.
NO_MARKER_NAME="$WORK/no-marker-name"
mkdir -p "$NO_MARKER_NAME/Sources/NotificationCore"
cp "$REPO_ROOT/Sources/NotificationCore/AlertMenuText.swift" "$NO_MARKER_NAME/Sources/NotificationCore/"
NO_LAST_MATCH_STEM="$WORK/no-last-match-stem"
mkdir -p "$NO_LAST_MATCH_STEM/Sources/NotificationCore"
cp "$REPO_ROOT/Sources/NotificationCore/HarnessText.swift" "$NO_LAST_MATCH_STEM/Sources/NotificationCore/"
grep -v 'public static let lastMatchStem = ' "$REPO_ROOT/Sources/NotificationCore/AlertMenuText.swift" > "$NO_LAST_MATCH_STEM/Sources/NotificationCore/AlertMenuText.swift"

# What the app calls the marker rule, and what its last-match line begins with, read from where
# the app declares them.
MARKER_NAME=$(core_constant HarnessText.swift markerRuleName)
LAST_MATCH_STEM=$(core_constant AlertMenuText.swift lastMatchStem)
BK=rules.json.harness-backup

# ------------------------------------------------------------------ small functions

head_ "The small functions"

assert "harness_repo_root is the caller's REPO_ROOT when it has one" test "$(REPO_ROOT=/a/b harness_repo_root)" = /a/b
assert "  and the folder above Scripts/ when it has none" test "$(unset REPO_ROOT; harness_repo_root)" = "$REPO_ROOT"
assert "  which has the app's sources in it" test -d "$REPO_ROOT/Sources/NotificationCore"

check "harness_backup_path puts the backup beside the file" 0 harness_backup_path "/a/b/rules.json"
if [ "$OUT" = "/a/b/rules.json.harness-backup" ]; then pass "  and names it the file's name with .harness-backup after it"; else fail "  the backup path was $OUT"; fi

printf 'abc' > "$WORK/abc.txt"
check "harness_digest of a file" 0 harness_digest "$WORK/abc.txt"
if [ "$OUT" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]; then
    pass "  is the SHA-256 of its bytes (the published digest of abc)"
else
    fail "  was $OUT"
fi
check "harness_digest of no file" 0 harness_digest "$WORK/nothing-here"
if [ "$OUT" = absent ]; then pass "  says absent"; else fail "  said $OUT"; fi
ln -s "$WORK/nothing-here" "$WORK/dangling"
check "harness_digest of a link to nowhere" 1 harness_digest "$WORK/dangling"
if [ "$OUT" = unreadable ]; then pass "  says unreadable, and not absent"; else fail "  said $OUT"; fi
if [ "$IS_ROOT" -eq 0 ]; then
    printf 'abc' > "$WORK/closed.txt"; chmod 000 "$WORK/closed.txt"
    check "harness_digest of a file that cannot be read" 1 harness_digest "$WORK/closed.txt"
    if [ "$OUT" = unreadable ]; then pass "  says unreadable"; else fail "  said $OUT"; fi
else
    skip "harness_digest of a file that cannot be read (running as root)"
fi

VERSION=$(harness_current_version)
case "$VERSION" in
    ''|*[!0-9]*) fail "harness_current_version read \"$VERSION\", which is not a number" ;;
    *) if [ "$VERSION" -ge 5 ]; then pass "harness_current_version reads a version, $VERSION, from RuleSetCodec.swift"; else fail "harness_current_version read $VERSION"; fi ;;
esac
assert "harness_current_version reads nothing from a tree with no NotificationCore" test -z "$(REPO_ROOT="$NO_CORE" harness_current_version)"
assert "the helper that reads the app's words reads the marker rule's name" test -n "$MARKER_NAME"
assert "the helper reads nothing from a tree with no NotificationCore" \
    test -z "$(REPO_ROOT="$NO_CORE" core_constant HarnessText.swift markerRuleName)"

# --------------------------------------------------------------------- refuse guard

head_ "The refuse guard: on-call and snooze"

for mode in on-call snooze; do
    check "$mode runs on a quiet menu" 0 harness_refuse_guard "$mode" "$(m quiet)"
    check "$mode refuses a menu that is already on call" 2 harness_refuse_guard "$mode" "$(m on-call)"
    check "$mode refuses a menu that is already snoozed" 2 harness_refuse_guard "$mode" "$(m snoozed)"
    check "$mode runs beside a held summary that nothing is snoozing" 0 harness_refuse_guard "$mode" "$(m held-summary-other)"
    check "$mode runs beside an escalation, which it does not touch" 0 harness_refuse_guard "$mode" "$(m escalating-one)"
    check "$mode refuses a menu with no text, which cannot be judged" 2 harness_refuse_guard "$mode" ""
    check "$mode refuses a menu of blank lines" 2 harness_refuse_guard "$mode" "$(printf '  \n\n\t\n')"
    REPO_ROOT="$NO_CORE" check "$mode refuses when the titles of the items every menu has cannot be read" 2 harness_refuse_guard "$mode" "$(m quiet)"
    assert "  and says so" contains "$OUT" "titles of the"
    REPO_ROOT="$TITLES_ONLY" check "$mode refuses when the stems cannot be read" 2 harness_refuse_guard "$mode" "$(m quiet)"
    assert "  and says it is the stems" contains "$OUT" "stems"
done
check "the refuse guard takes no mode it was not given" 1 harness_refuse_guard soon "$(m quiet)"
check "the refuse guard takes no mode for a mode" 1 harness_refuse_guard "" "$(m quiet)"

head_ "The refuse guard: escalation"

check "escalation runs on a quiet menu" 0 harness_refuse_guard escalation "$(m quiet)"
check "escalation runs on a menu that is on call" 0 harness_refuse_guard escalation "$(m on-call)"
check "escalation runs on a menu that is snoozed" 0 harness_refuse_guard escalation "$(m snoozed)"
check "escalation runs beside a held summary" 0 harness_refuse_guard escalation "$(m held-summary-marker)"
check "escalation is not refused by a rule whose name has the word in it" 0 harness_refuse_guard escalation "$(m quiet-rule-named-escalating)"
check "escalation refuses one alert escalating, which may be a real page" 2 harness_refuse_guard escalation "$(m escalating-one)"
check "escalation refuses a burst on one alert" 2 harness_refuse_guard escalation "$(m escalating-burst)"
check "escalation refuses two alerts escalating" 2 harness_refuse_guard escalation "$(m escalating-two)"
check "escalation refuses an escalation beside one missed while asleep" 2 harness_refuse_guard escalation "$(m escalating-beside-missed)"
check "escalation refuses an alert missed while asleep, which has an item to acknowledge it" 2 harness_refuse_guard escalation "$(m missed-alone)"
# Each of the two is enough alone.
check "escalation refuses the line alone" 2 harness_refuse_guard escalation "$(m escalating-one | sed 1d)"
check "escalation refuses the item alone" 2 harness_refuse_guard escalation "$(m escalating-one | sed 2d)"
check "escalation refuses a menu with no text" 2 harness_refuse_guard escalation ""
REPO_ROOT="$NO_CORE" check "escalation refuses when the titles of the items every menu has cannot be read" 2 harness_refuse_guard escalation "$(m quiet)"
REPO_ROOT="$TITLES_ONLY" check "escalation refuses when the words it judges by cannot be read" 2 harness_refuse_guard escalation "$(m quiet)"
assert "  and says it could not read them" contains "$OUT" "Acknowledge title"

head_ "The refuse guard: a text that is not the whole of a menu"

# The word read_menu answers with when it finds no status item, one line of a menu, and a
# read that came back short each have text, and none of them can say that the Mac is quiet.
for mode in on-call snooze escalation; do
    check "$mode refuses the word for no status item, which is not a menu" 2 harness_refuse_guard "$mode" NO_STATUS_ITEM
    assert "  and says it is not the whole of its menu" contains "$OUT" "not the whole of its menu"
    check "$mode refuses a menu that is only its last item" 2 harness_refuse_guard "$mode" "Quit SignalLadder"
    check "$mode refuses the capture count alone" 2 harness_refuse_guard "$mode" "Captured 3 notifications"
    check "$mode refuses a menu cut short after its first line" 2 harness_refuse_guard "$mode" "$(m quiet | sed -n 1p)"
    check "$mode refuses a menu cut short before its snooze item" 2 harness_refuse_guard "$mode" "$(m quiet | sed -n 1,2p)"
    check "$mode refuses a menu that has lost its on-call item" 2 harness_refuse_guard "$mode" "$(m quiet | sed 2d)"
    check "$mode refuses a menu that has lost its snooze item" 2 harness_refuse_guard "$mode" "$(m quiet | sed 3d)"
    check "$mode refuses a menu whose on-call item only begins with its title" 2 harness_refuse_guard "$mode" "$(m quiet | sed '2s/$/ now/')"
    check "$mode refuses a menu whose snooze item only begins with its title" 2 harness_refuse_guard "$mode" "$(m quiet | sed '3s/$/ for a while/')"
    check "$mode refuses a real page's menu that has been cut short" 2 harness_refuse_guard "$mode" "$(m escalating-one | sed -n 1,2p)"
done

# ---------------------------------------------------------------- marker-only guard

head_ "The marker-only guard"

check "passes the line its own burst makes" 0 harness_marker_only_guard 5 "$(m escalating-burst)"
check "passes the line of one match, which has no count" 0 harness_marker_only_guard 1 "$(m escalating-one)"
check "passes a count written with a leading zero" 0 harness_marker_only_guard 05 "$(m escalating-burst)"
check "passes another count when the line says that count" 0 harness_marker_only_guard 4 "$(m escalating-burst-four)"
check "refuses the stem with another count" 1 harness_marker_only_guard 5 "$(m escalating-burst-four)"
check "refuses the line when the count has risen since" 1 harness_marker_only_guard 4 "$(m escalating-burst)"
check "refuses a count that is higher than the line's" 1 harness_marker_only_guard 6 "$(m escalating-burst)"
check "refuses a count of one against a line that has matches" 1 harness_marker_only_guard 1 "$(m escalating-burst)"
check "refuses the bare stem when the burst's count is more than one" 1 harness_marker_only_guard 5 "$(m escalating-one)"
check "refuses two alerts escalating, the marker's and a real page's" 1 harness_marker_only_guard 6 "$(m escalating-two)"
check "refuses two alerts escalating whatever the count" 1 harness_marker_only_guard 2 "$(m escalating-two)"
check "refuses an escalation beside one missed while asleep" 1 harness_marker_only_guard 1 "$(m escalating-beside-missed)"
check "refuses an alert missed while asleep, with nothing escalating" 1 harness_marker_only_guard 1 "$(m missed-alone)"
check "refuses a quiet menu" 1 harness_marker_only_guard 5 "$(m quiet)"
assert "  and says that no line says something is escalating" contains "$OUT" "no line"
check "refuses a menu that is on call and quiet" 1 harness_marker_only_guard 1 "$(m on-call)"
check "refuses a menu with no text" 1 harness_marker_only_guard 5 ""
check "refuses two lines that say something is escalating, each the marker's" 1 harness_marker_only_guard 5 "$(m escalating-burst; m escalating-burst)"
check "refuses the same line twice beside one item to acknowledge" 1 harness_marker_only_guard 5 "$(m escalating-burst | sed 2p)"
assert "  and says there are two" contains "$OUT" "2 lines"
check "refuses two items that acknowledge, each exact" 1 harness_marker_only_guard 5 "$(m escalating-burst; m escalating-burst | sed -n 1p)"
check "refuses the line with no item to acknowledge it" 1 harness_marker_only_guard 5 "$(m escalating-burst | sed 1d)"
check "refuses the line beside an item that is not exact" 1 harness_marker_only_guard 5 "$(m escalating-burst | sed '1s/$/ (1)/')"
check "refuses a rule named for the word, which is not a line that says so" 1 harness_marker_only_guard 1 "$(m quiet-rule-named-escalating)"
for count in "" x -1 5x 1.5; do
    check "refuses a count that is \"$count\"" 1 harness_marker_only_guard "$count" "$(m escalating-burst)"
    assert "  and says it must be a whole number" contains "$OUT" "whole number"
done
check "refuses a count of nothing" 1 harness_marker_only_guard 0 "$(m escalating-burst)"
assert "  and says it must be 1 or more" contains "$OUT" "1 or more"
REPO_ROOT="$NO_CORE" check "refuses when the words cannot be read" 1 harness_marker_only_guard 5 "$(m escalating-burst)"
REPO_ROOT="$NO_MARKER_NAME" check "refuses when the marker rule's name cannot be read" 1 harness_marker_only_guard 5 "$(m escalating-burst)"
assert "  and says it could not read it" contains "$OUT" "could not read the last-match line's stem and the marker rule's name"
REPO_ROOT="$NO_LAST_MATCH_STEM" check "refuses when the stem of the last-match line cannot be read" 1 harness_marker_only_guard 5 "$(m escalating-burst)"
assert "  and says it could not read it" contains "$OUT" "could not read the last-match line's stem and the marker rule's name"

# Whose escalation it is. The marker rule is appended after the owner's, and the first rule to
# match wins, so a rule of the owner's before it that matches a banner with the marker's title
# takes the banner, and the escalation line and the Acknowledge item are the same as the
# marker's own. Only the last-match line says which rule matched.
head_ "The marker-only guard: whose escalation it is"

assert "the burst's menu has the marker rule as its last match" contains "$(m escalating-burst)" "$LAST_MATCH_STEM $MARKER_NAME at "
check "refuses a burst that one of the owner's rules took before the marker did" 1 harness_marker_only_guard 5 "$(m escalating-burst-other-rule)"
assert "  and says the last match is not the marker rule's" contains "$OUT" "last match is not the marker rule's"
assert "  and prints no rule name" lacks "$OUT" "On-call mentions"
check "refuses one alert escalating whose last match is a real page's rule" 1 harness_marker_only_guard 1 "$(m escalating-one-other-rule)"
assert "  and says the last match is not the marker rule's" contains "$OUT" "last match is not the marker rule's"
assert "  and prints no rule name" lacks "$OUT" "On-call mentions"
check "refuses an escalation whose menu has no last-match line" 1 harness_marker_only_guard 5 "$(m escalating-burst | grep -v "^$LAST_MATCH_STEM")"
assert "  and says there is none" contains "$OUT" "no last-match line"
check "refuses one alert escalating whose menu has no last-match line" 1 harness_marker_only_guard 1 "$(m escalating-one | grep -v "^$LAST_MATCH_STEM")"
check "refuses two last-match lines, each the marker's" 1 harness_marker_only_guard 5 "$(m escalating-burst; m escalating-burst | grep "^$LAST_MATCH_STEM")"
assert "  and says there are two" contains "$OUT" "2 last-match lines"
check "refuses two last-match lines, the marker's and another rule's" 1 harness_marker_only_guard 5 "$(m escalating-burst; m escalating-burst-other-rule | grep "^$LAST_MATCH_STEM")"
check "refuses a rule whose name is the marker's and more" 1 harness_marker_only_guard 5 "$(m escalating-burst | sed "s/ $MARKER_NAME at / $MARKER_NAME two at /")"
check "refuses a rule whose name has the marker's after other words" 1 harness_marker_only_guard 5 "$(m escalating-burst | sed "s/^$LAST_MATCH_STEM /$LAST_MATCH_STEM Not /")"
check "refuses a line that has the words of the last match after text of its own" 1 harness_marker_only_guard 5 "$(m escalating-burst | sed "s/^$LAST_MATCH_STEM /A line that says $LAST_MATCH_STEM /")"
check "passes the marker's last match after a warning mark" 0 harness_marker_only_guard 5 "$(m escalating-burst | sed "s/^$LAST_MATCH_STEM/⚠︎ $LAST_MATCH_STEM/")"
check "refuses another rule's last match after a warning mark" 1 harness_marker_only_guard 5 "$(m escalating-burst-other-rule | sed "s/^$LAST_MATCH_STEM/⚠︎ $LAST_MATCH_STEM/")"
check "passes the marker's last match at another time of day" 0 harness_marker_only_guard 5 "$(m escalating-burst | sed 's/ at 10:42 / at 23:59 /')"
check "passes the last-match line wherever the menu has it" 0 harness_marker_only_guard 5 "$({ m escalating-burst | grep "^$LAST_MATCH_STEM"; m escalating-burst | grep -v "^$LAST_MATCH_STEM"; })"

# ------------------------------------------------------------------- summary guard

head_ "The summary guard"

check "passes the marker's one match" 0 harness_summary_guard "$(m held-summary-marker)"
check "passes it among other lines" 0 harness_summary_guard "$(m quiet; m held-summary-marker)"
check "refuses a real match held, alone" 1 harness_summary_guard "$(m held-summary-other)"
case "$OUT" in
    *"Prod and incident"*) fail "  and its reason printed a rule name: $OUT" ;;
    *) pass "  and its reason prints no rule name" ;;
esac
check "refuses the marker's match held beside a real one" 1 harness_summary_guard "$(m held-summary-mixed)"
check "refuses a quiet menu, with no summary" 1 harness_summary_guard "$(m quiet)"
check "refuses a menu that is snoozed and has held nothing" 1 harness_summary_guard "$(m snoozed)"
check "refuses a menu with no text" 1 harness_summary_guard ""
check "refuses two of the marker's matches" 1 harness_summary_guard "$(m held-summary-marker | sed 's/ ×1/ ×2/')"
check "refuses the marker's one match with a record that could not be read" 1 harness_summary_guard "$(m held-summary-marker | sed 's/ ×1/ ×1 and some others/')"
check "refuses a rule named like the marker with more in its name" 1 harness_summary_guard "$(m held-summary-marker | sed 's/ marker ×1/ marker two ×1/')"
check "refuses a count of matches that is not one" 1 harness_summary_guard "$(m held-summary-marker | sed 's/^1 match held/2 matches held/')"
check "refuses the last-match line alone, which is not a summary" 1 harness_summary_guard "$(m held-summary-marker | grep "^$LAST_MATCH_STEM")"
REPO_ROOT="$NO_CORE" check "refuses when the words cannot be read" 1 harness_summary_guard "$(m held-summary-marker)"

# ------------------------------------------------------------------- backup guard

head_ "The backup guard"

D=$(fresh)
check "does nothing when there is nothing left" 0 guard "$D"
assert "  and says nothing" test -z "$OUT"
assert "  and leaves the folder as it was" test -z "$(ls -A "$D")"

D=$(state written)
assert "the fixture's digest is the digest of the file beside it" test "$(cat "$D/$BK.sha256")" = "$(harness_digest "$D/rules.json")"
check "puts the backup back over the file the run wrote" 0 guard "$D"
assert "  and the file is the original, byte for byte" same "$D/rules.json" "$FIXTURES/rules-owner.json"
assert "  and the backup and its digest are gone" unchanged "$D"
assert "  and says that an earlier run left the backup" contains "$OUT" "the backup an earlier run left"
check "does nothing the second time" 0 guard "$D"
assert "  and says nothing" test -z "$OUT"

D=$(state written)
check "puts the backup back for the run whose own it is" 0 own_guard "$D"
assert "  and the file is the original, byte for byte" same "$D/rules.json" "$FIXTURES/rules-owner.json"
assert "  and the backup and its digest are gone" unchanged "$D"
assert "  and says that this run left the backup" contains "$OUT" "the backup this run left"
assert "  and does not say that an earlier run did" lacks "$OUT" "earlier run"

D=$(state edited)
check "refuses a file the owner has edited since" 2 guard "$D"
assert "  and leaves the edited file alone" same "$D/rules.json" "$FIXTURES/backup-states/edited/rules.json"
assert "  and leaves the backup where it is" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and leaves its digest" test -f "$D/$BK.sha256"
assert "  and says where the backup is" contains "$OUT" "$D/$BK"

D=$(state edited)
check "refuses a file the owner has edited since, to the run whose own backup it is" 2 own_guard "$D"
assert "  and leaves the edited file alone" same "$D/rules.json" "$FIXTURES/backup-states/edited/rules.json"
assert "  and says that this run left the backup" contains "$OUT" "this run left a backup"
assert "  and does not say that an earlier run did" lacks "$OUT" "earlier run"

D=$(state no-digest-differs)
check "refuses a backup with no digest beside a file that differs" 2 guard "$D"
assert "  and leaves the file alone" same "$D/rules.json" "$FIXTURES/backup-states/no-digest-differs/rules.json"
assert "  and leaves the backup alone" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and says where the backup is" contains "$OUT" "$D/$BK"

D=$(state no-digest-equal)
check "removes a backup with no digest beside a file that is the same" 0 guard "$D"
assert "  and does not touch the file" unchanged "$D"

D=$(state no-digest-equal)
printf 'not a digest\n' > "$D/$BK.sha256"
check "reads a digest that is not one as no digest, and removes the backup of an equal file" 0 guard "$D"
assert "  and removes the junk with it" unchanged "$D"

D=$(state written)
printf 'not a digest\n' > "$D/$BK.sha256"
check "reads a digest that is not one as no digest, and refuses a file that differs" 2 guard "$D"
assert "  and says there is no digest" contains "$OUT" "no digest"
assert "  and leaves both files" test -f "$D/$BK" -a -f "$D/rules.json"

D=$(state written)
printf '%064d\n' 0 > "$D/$BK.sha256"
check "refuses a file that does not have the digest recorded" 2 guard "$D"
assert "  and leaves the backup" same "$D/$BK" "$FIXTURES/rules-owner.json"

D=$(state written)
rm "$D/rules.json"
check "refuses when the file is gone and a backup is left" 2 guard "$D"
assert "  and keeps the backup" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and says where the backup is" contains "$OUT" "$D/$BK"

D=$(state written)
rm "$D/$BK"
check "refuses a digest with no backup and no record of an absent file" 2 guard "$D"
assert "  and leaves both" test -f "$D/$BK.sha256" -a -f "$D/rules.json"

D=$(state written)
: > "$D/$BK.absent"
check "refuses a backup beside the record that there was none" 2 guard "$D"
assert "  and leaves all three" test -f "$D/$BK.absent" -a -f "$D/$BK" -a -f "$D/rules.json"

D=$(state written)
cp "$FIXTURES/rules-owner.json" "$D/rules.json"
check "removes a backup and its digest beside a file that is already the backup, as a restore killed before it cleaned up leaves" 0 guard "$D"
assert "  and does not touch the file" unchanged "$D"

D=$(state written)
printf 'leftover' > "$D/$BK.new"
check "removes a half-built file of its own" 0 guard "$D"
assert "  as it puts the original back" unchanged "$D"

if [ "$IS_ROOT" -eq 0 ]; then
    D=$(state written)
    chmod 444 "$D/rules.json"
    check "returns 1 when the file cannot be written back" 1 guard "$D"
    assert "  and leaves the backup" same "$D/$BK" "$FIXTURES/rules-owner.json"
    assert "  and its digest" test -f "$D/$BK.sha256"
else
    skip "returns 1 when the file cannot be written back (running as root)"
fi

D=$(state written)
check "returns 1 when what was put back does not match the backup" 1 guard_when_cmp_fails "$D"
assert "  and leaves the backup" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and its digest" test -f "$D/$BK.sha256"

check "needs the rules file's path" 1 harness_backup_guard "" "$WORK/x"
check "needs the backup's path" 1 harness_backup_guard "$WORK/x" ""

head_ "The backup guard: when there was no rules file"

D=$(state absent-written)
assert "the fixture's digest is the digest of the file beside it" test "$(cat "$D/$BK.sha256")" = "$(harness_digest "$D/rules.json")"
check "removes the file a run made, which is still the one it wrote" 0 guard "$D"
assert "  and the file and its records are gone" test -z "$(ls -A "$D")"

D=$(state absent-written)
printf ' ' >> "$D/rules.json"
check "refuses a file made by a run that has been changed since" 2 guard "$D"
assert "  and leaves it" test -s "$D/rules.json"
assert "  and leaves the records" test -f "$D/$BK.absent" -a -f "$D/$BK.sha256"

D=$(state absent-written)
rm "$D/rules.json"
check "removes only the records when the file is gone already" 0 guard "$D"
assert "  and nothing is left" test -z "$(ls -A "$D")"

D=$(fresh)
: > "$D/$BK.absent"
check "removes a record with no file and no digest, which a run killed first leaves" 0 guard "$D"
assert "  and nothing is left" test -z "$(ls -A "$D")"

D=$(fresh)
: > "$D/$BK.absent"
cp "$FIXTURES/rules-owner.json" "$D/rules.json"
check "refuses a record with no digest beside a file, which may be the owner's" 2 guard "$D"
assert "  and says no digest was recorded" contains "$OUT" "no digest"
assert "  and leaves the file" same "$D/rules.json" "$FIXTURES/rules-owner.json"
assert "  and the record" test -f "$D/$BK.absent"

# ------------------------------------------------------------------- marker writer

head_ "The marker writer: appending"

D=$(owner)
check "puts the escalation marker into the owner's file, which needs version 4" 0 mark "$D" escalation 4
assert "  the file is the one the guards' fixtures hold for it" same "$D/rules.json" "$FIXTURES/backup-states/written/rules.json"
assert "  the version is 4" test "$(json_get "$D/rules.json" version)" = 4
assert "  there are four rules" test "$(json_get "$D/rules.json" rules)" = 4
assert "  the owner's three are first, in order" same_rules "$FIXTURES/rules-owner.json" "$D/rules.json"
assert "  the fourth is the marker, by name" test "$(json_get "$D/rules.json" rules.3.name)" = "$MARKER_NAME"
assert "  every other byte of the file is the owner's" only_the_rule_and_the_version "$FIXTURES/rules-owner.json" "$D/rules.json"
assert "  the backup is the original, byte for byte" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  the digest recorded is the digest of the marked file" test "$(cat "$D/$BK.sha256")" = "$(harness_digest "$D/rules.json")"
assert "  nothing else is left beside it" test -z "$(others "$D" | grep -v -e "^$BK\$" -e "^$BK.sha256\$")"
check "  and the guard then puts the original back" 0 guard "$D"
assert "  byte for byte, with nothing left beside it" unchanged "$D"

D=$(owner)
check "puts the snooze marker into the owner's file, which needs version 5" 0 mark "$D" snooze 5
assert "  the version is 5" test "$(json_get "$D/rules.json" version)" = 5
assert "  there are four rules" test "$(json_get "$D/rules.json" rules)" = 4
assert "  the owner's three are first, in order" same_rules "$FIXTURES/rules-owner.json" "$D/rules.json"
assert "  the marker is held by a snooze" test "$(json_get "$D/rules.json" rules.3.quietWhenSnoozed)" = true
assert "  every other byte of the file is the owner's" only_the_rule_and_the_version "$FIXTURES/rules-owner.json" "$D/rules.json"
check "  and the guard then puts the original back" 0 guard "$D"
assert "  byte for byte, with nothing left beside it" unchanged "$D"

head_ "The marker writer: the version"

# The owner's fixture is version 3. These are the same file at the other versions.
for have in 4 5; do
    sed "s/\"version\" : 3/\"version\" : $have/" "$FIXTURES/rules-owner.json" > "$WORK/at-$have.json"
    for pair in "escalation 4" "snooze 5"; do
        read -r kind needed <<< "$pair"
        D=$(fresh)
        cp "$WORK/at-$have.json" "$D/rules.json"
        check "a version $have file with the $kind marker, which needs $needed" 0 mark "$D" "$kind" "$needed"
        want=$have
        [ "$have" -lt "$needed" ] && want=$needed
        assert "  is at version $want, and never lowered" test "$(json_get "$D/rules.json" version)" = "$want"
        assert "  and every other byte of the file is the owner's" only_the_rule_and_the_version "$WORK/at-$have.json" "$D/rules.json"
        guard "$D" >/dev/null
        assert "  and the guard puts it back" same "$D/rules.json" "$WORK/at-$have.json"
    done
done

head_ "The marker writer: other layouts"

D=$(fresh)
printf '{"version":1,"rules":[]}' > "$D/rules.json"
check "an empty array in a file on one line" 0 mark "$D" escalation 4
assert "  has the marker and nothing else" test "$(json_get "$D/rules.json" rules)" = 1
assert "  at version 4" test "$(json_get "$D/rules.json" version)" = 4
assert "  and stays on one line" test "$(wc -l < "$D/rules.json" | tr -d ' ')" = 0

D=$(fresh)
printf '{"rules":[{"name":"a [x] {y} \\"} z","condition":{"field":"app","op":"equals","value":"q"}}],"version":3,"note":"rules"}' > "$D/rules.json"
check "brackets and quotes inside a rule, and a key after the array, on one line" 0 mark "$D" snooze 5
assert "  keep the owner's rule" test "$(json_get "$D/rules.json" rules.0.name)" = 'a [x] {y} "} z'
assert "  add the marker after it" test "$(json_get "$D/rules.json" rules.1.name)" = "$MARKER_NAME"
assert "  raise the version, which comes after the array" test "$(json_get "$D/rules.json" version)" = 5
assert "  and leave the key after it" test "$(json_get "$D/rules.json" note)" = rules

D=$(fresh)
printf '{\n  "rules" : [\n  ],\n  "version" : 2\n}' > "$D/rules.json"
check "an empty array in a file on several lines" 0 mark "$D" escalation 4
assert "  gives the marker lines of its own, in the file's layout" test "$(wc -l < "$D/rules.json" | tr -d ' ')" -gt 10
assert "  has the marker" test "$(json_get "$D/rules.json" rules.0.name)" = "$MARKER_NAME"
assert "  at version 4" test "$(json_get "$D/rules.json" version)" = 4

D=$(fresh)
awk '{ printf "%s\r\n", $0 }' "$FIXTURES/rules-owner.json" > "$D/rules.json"
cp "$D/rules.json" "$WORK/crlf.json"
check "a file with Windows line endings" 0 mark "$D" escalation 4
assert "  has four rules" test "$(json_get "$D/rules.json" rules)" = 4
assert "  keeps every line ending a pair" test "$(grep -vc $'\r$' "$D/rules.json")" = 0
guard "$D" >/dev/null
assert "  and the guard puts it back" same "$D/rules.json" "$WORK/crlf.json"

D=$(fresh)
printf '{"rules":[{"name":"é 🙂 ü","condition":{"field":"app","op":"equals","value":"q"}}],"version":3}' > "$D/rules.json"
check "a rule with characters outside ASCII" 0 mark "$D" escalation 4
assert "  keeps them as they were" test "$(json_get "$D/rules.json" rules.0.name)" = "é 🙂 ü"

head_ "The marker writer: when there is no rules file"

D=$(fresh)
check "makes the file with the marker alone when there is none" 0 mark "$D" escalation 4
assert "  which has the one rule" test "$(json_get "$D/rules.json" rules)" = 1
assert "  named for the marker" test "$(json_get "$D/rules.json" rules.0.name)" = "$MARKER_NAME"
assert "  at version 4" test "$(json_get "$D/rules.json" version)" = 4
assert "  records that there was none" test -f "$D/$BK.absent"
assert "  records the digest of what it made" test "$(cat "$D/$BK.sha256")" = "$(harness_digest "$D/rules.json")"
assert "  and makes no backup" absent "$D/$BK"
check "  and the guard then removes the file it made" 0 guard "$D"
assert "  with nothing left" test -z "$(ls -A "$D")"

D=$(fresh)
check "makes the snooze marker's file at version 5" 0 mark "$D" snooze 5
assert "  at version 5" test "$(json_get "$D/rules.json" version)" = 5
guard "$D" >/dev/null
assert "  and the guard removes it" test -z "$(ls -A "$D")"

head_ "The marker writer: files it must not touch"

# Each of these refuses with 2, says why, and changes nothing: the file is as it was, and
# there is no backup, no record and no half-built file beside it.
refuses() {  # refuses LABEL DIR
    check "refuses $1" 2 mark "$2" escalation 4
    assert "  and leaves no backup, no record and no half-built file" test -z "$(others "$2")"
}

D=$(fresh); cp "$FIXTURES/rules-not-json.json" "$D/rules.json"
refuses "a file that is not JSON" "$D"
assert "  and leaves the file alone" same "$D/rules.json" "$FIXTURES/rules-not-json.json"

D=$(fresh); cp "$FIXTURES/rules-too-new.json" "$D/rules.json"
refuses "a file with a version above the newest this build reads" "$D"
assert "  and leaves the file alone" same "$D/rules.json" "$FIXTURES/rules-too-new.json"
assert "  and says the newest version it reads" contains "$OUT" "reads up to $VERSION"

D=$(owner); sed "s/\"version\" : 3/\"version\" : $((VERSION + 1))/" "$FIXTURES/rules-owner.json" > "$D/rules.json"
refuses "a file with a version one above the newest" "$D"

D=$(owner); sed "s/\"version\" : 3/\"version\" : $VERSION/" "$FIXTURES/rules-owner.json" > "$D/rules.json"
check "accepts a file at the newest version" 0 mark "$D" snooze 5

if [ "$IS_ROOT" -eq 0 ]; then
    D=$(owner); chmod 000 "$D/rules.json"
    refuses "a file that cannot be read" "$D"
    assert "  and says it cannot be read" contains "$OUT" "cannot be read"
    chmod 644 "$D/rules.json"
    assert "  and leaves the file alone" unchanged "$D"

    D=$(owner); chmod 444 "$D/rules.json"
    refuses "a file that cannot be written" "$D"
    chmod 644 "$D/rules.json"
    assert "  and leaves the file alone" unchanged "$D"

    D=$(fresh); chmod 555 "$D"
    check "refuses to make a file in a folder that cannot be written" 2 mark "$D" escalation 4
    assert "  and makes nothing" test -z "$(ls -A "$D")"
    chmod 755 "$D"
else
    skip "refuses a file that cannot be read, or written, and a folder that cannot be written (running as root)"
fi

D=$(fresh); ln -s "$D/elsewhere.json" "$D/rules.json"
check "refuses a link to a file that cannot be found" 2 mark "$D" escalation 4
assert "  and leaves the link" test -L "$D/rules.json"
assert "  and makes nothing beside it" test -z "$(others "$D")"

D=$(fresh); mkdir "$D/rules.json"
check "refuses a folder where the file should be" 2 mark "$D" escalation 4
assert "  and says it is not a file" contains "$OUT" "is not a file"
assert "  and makes nothing beside it" test -z "$(others "$D")"

D=$(fresh); mkdir "$D/real"; cp "$FIXTURES/rules-owner.json" "$D/real/target.json"; ln -s real/target.json "$D/rules.json"
check "writes through a link to the file it names" 0 mark "$D" escalation 4
assert "  the link is still a link" test -L "$D/rules.json"
assert "  and the file it names holds the marker" test "$(json_get "$D/real/target.json" rules)" = 4
guard "$D" >/dev/null
assert "  and the guard puts the original back through it" same "$D/real/target.json" "$FIXTURES/rules-owner.json"
assert "  and the link is still a link" test -L "$D/rules.json"

D=$(fresh); : > "$D/rules.json"
refuses "an empty file" "$D"
D=$(fresh); printf '[]' > "$D/rules.json"
refuses "JSON whose top level is not an object" "$D"
assert "  and says so" contains "$OUT" "top level"
D=$(fresh); printf '{"rules":[]}' > "$D/rules.json"
refuses "JSON with no version" "$D"
D=$(fresh); printf '{"version":"3","rules":[]}' > "$D/rules.json"
refuses "a version that is a string" "$D"
D=$(fresh); printf '{"version":3.5,"rules":[]}' > "$D/rules.json"
refuses "a version that is not a whole number" "$D"
D=$(fresh); printf '{"version":0,"rules":[]}' > "$D/rules.json"
refuses "a version below 1" "$D"
D=$(fresh); printf '{"version":3}' > "$D/rules.json"
refuses "JSON with no rules array" "$D"
D=$(fresh); printf '{"version":3,"rules":{}}' > "$D/rules.json"
refuses "JSON whose rules are not an array" "$D"
D=$(fresh); printf '\357\273\277{"version":3,"rules":[]}' > "$D/rules.json"
refuses "a file that starts with a byte-order mark, which a splice would drop" "$D"
D=$(fresh); printf '\377\376{"version":3}' > "$D/rules.json"
refuses "a file that is not UTF-8 text" "$D"

head_ "The marker writer: a run's leftovers, and calls it cannot use"

D=$(owner); printf 'an earlier original' > "$D/$BK"
check "refuses to copy over a backup an earlier run left" 2 mark "$D" escalation 4
assert "  and leaves that backup" test "$(cat "$D/$BK")" = "an earlier original"
assert "  and the file" same "$D/rules.json" "$FIXTURES/rules-owner.json"

D=$(owner); printf 'x\n' > "$D/$BK.sha256"
check "refuses beside a digest an earlier run left" 2 mark "$D" escalation 4
assert "  and leaves the file" same "$D/rules.json" "$FIXTURES/rules-owner.json"

D=$(owner); : > "$D/$BK.absent"
check "refuses beside a record an earlier run left" 2 mark "$D" escalation 4
assert "  and leaves the file" same "$D/rules.json" "$FIXTURES/rules-owner.json"

D=$(owner)
REPO_ROOT="$NO_CORE" check "refuses when the newest version cannot be read" 2 mark "$D" escalation 4
assert "  and changes nothing" unchanged "$D"

D=$(owner)
for needed in "" 3 6 x; do
    check "needs a version of 4 or 5, and not \"$needed\"" 1 mark "$D" escalation "$needed"
done
check "needs a rule" 1 harness_install_marker "$D/rules.json" "$D/$BK" "" 4
check "needs a rules file's path" 1 harness_install_marker "" "$D/$BK" "$(rule_text escalation)" 4
check "needs a backup's path" 1 harness_install_marker "$D/rules.json" "" "$(rule_text escalation)" 4
check "does not take text that is not JSON for a rule" 1 harness_install_marker "$D/rules.json" "$D/$BK" "this is not a rule" 4
check "does not take a list for a rule" 1 harness_install_marker "$D/rules.json" "$D/$BK" "[1, 2]" 4
assert "  and has changed nothing in any of those" unchanged "$D"

head_ "The marker writer: a step that fails"

D=$(owner)
check "returns 1 when the original cannot be copied aside" 1 mark_when_cp_fails "$D" escalation 4
assert "  and has changed nothing, and left no backup" unchanged "$D"

D=$(owner)
check "returns 1 when the file changed after it was read, and does not write over the change" 1 mark_when_the_file_changes "$D" escalation 4
assert "  the owner's change is still there" test "$(cat "$D/rules.json")" = "$(cat "$FIXTURES/rules-owner.json") "
assert "  and no backup or half-built file is left" test -z "$(others "$D")"

D=$(owner)
check "returns 1 when the file cannot be written, and puts it back" 1 mark_when_cat_fails "$D" escalation 4
assert "  the file is the original again, and no backup is left" unchanged "$D"

D=$(owner)
check "returns 1 when the digest cannot be taken, before it has written anything" 1 mark_when_shasum_fails "$D" escalation 4
assert "  the file was never touched, and no backup is left" unchanged "$D"

D=$(owner)
check "says where the original is when it cannot put it back" 1 mark_when_the_undoing_fails "$D" escalation 4
assert "  the backup is left" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and the reason names it" contains "$OUT" "$D/$BK"

D=$(fresh)
check "returns 1 when a rules file appears where there was none, and does not write over it" 1 mark_when_a_file_appears "$D" escalation 4
assert "  the file that appeared is still there" test "$(cat "$D/rules.json")" = '{"version":1,"rules":[]}'
assert "  and no record or half-built file is left" test -z "$(others "$D")"

D=$(fresh)
check "makes no file when it cannot take the digest of the file it would make" 1 mark_when_shasum_fails "$D" escalation 4
assert "  and nothing is left" test -z "$(ls -A "$D")"

D=$(owner)
check "returns 1 when the file is not the one written to it, and does not put the backup over it" 1 mark_when_the_write_is_changed "$D" escalation 4
assert "  the file is left as it was found, which is not the original" differs "$D/rules.json" "$FIXTURES/rules-owner.json"
assert "  the backup is the original" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and the reason names it" contains "$OUT" "$D/$BK"
check "  and the guard then refuses the file, and says where the backup is" 2 guard "$D"
assert "  with both files where they were" test -f "$D/$BK" -a -f "$D/rules.json"
assert "  and the backup still the original" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and the file still not the original" differs "$D/rules.json" "$FIXTURES/rules-owner.json"

head_ "The marker writer: a run that is killed"

# The writer is killed in a subshell just after it has written the rules file, which is the
# one moment at which the file is marked and nothing else has been done. The digest of the
# marked file is already recorded then, so the file is the one the run wrote and the guard
# puts the original back. Were the digest recorded after the write, a run killed between the
# two would leave a marked file with no digest, which the guard refuses as the owner's.
D=$(owner)
mark_when_killed_after_the_write "$D" escalation 4 >/dev/null 2>&1
assert "a run killed just after it wrote leaves the marked file" test "$(json_get "$D/rules.json" rules)" = 4
assert "  the backup, which is the original" same "$D/$BK" "$FIXTURES/rules-owner.json"
assert "  and the digest of the marked file, already recorded" test "$(cat "$D/$BK.sha256")" = "$(harness_digest "$D/rules.json")"
check "  and the guard of the next run puts the original back" 0 guard "$D"
assert "  byte for byte, with nothing left beside it, the half-built file included" unchanged "$D"

D=$(owner)
mark_when_killed_after_the_write "$D" snooze 5 >/dev/null 2>&1
check "the same for the snooze marker" 0 guard "$D"
assert "  and the original is back" unchanged "$D"

D=$(fresh)
mark_when_killed_after_the_write "$D" escalation 4 >/dev/null 2>&1
assert "a run killed just after it made a file where there was none leaves the file and the record that there was none" test -f "$D/rules.json" -a -f "$D/$BK.absent"
assert "  and the digest of the file it made" test "$(cat "$D/$BK.sha256")" = "$(harness_digest "$D/rules.json")"
check "  and the guard of the next run removes the file it made" 0 guard "$D"
assert "  with nothing left" test -z "$(ls -A "$D")"

# Killed before the write, the rules file is the original beside its backup and the digest of
# the file that was about to be written: the state the guard removes without a restore.
D=$(state written)
cp "$FIXTURES/rules-owner.json" "$D/rules.json"
check "a run killed after it recorded the digest and before it wrote: the guard removes the backup, and the file is the original" 0 guard "$D"
assert "  with nothing left beside it" unchanged "$D"

# ----------------------------------------------------------------------- the result

head_ "Result"
if [ "$SKIP" -gt 0 ]; then
    printf '  %d passed, %d failed, %d skipped\n\n' "$PASS" "$FAIL" "$SKIP"
else
    printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
fi
[ "$FAIL" -eq 0 ]
