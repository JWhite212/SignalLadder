#!/bin/bash
# Scripts/harness-guards.sh — the safety logic of the live-verification harness, in functions
#
# Scripts/verify-live.sh sources this file (M5 plan, Task 9). It stands between
# the harness and a real page or the owner's real rules, so each guard is a function
# that takes what it judges as arguments, prints its reason and returns a code, and
# Scripts/harness-guards-test.sh runs every one against the fixtures in
# Scripts/fixtures/ and a temporary folder. The harness never runs without them.
#
# This file holds functions and nothing else. Sourcing it defines them, runs nothing,
# sets no variable and touches no file, so a script can source it and the test can
# prove that it does.
#
# Every guard returns
#     0  go on
#     1  a check failed: the thing asked for is not so, or could not be done, and the
#        caller does not go on with it
#     2  refuse: the Mac is in a state that belongs to a real shift, or the rules file
#        is one the harness must not touch, and the caller stops the run
# and prints the reason on standard output, whatever it returns. A caller that gets
# anything but 0 stops the step it was about to take. No guard prints a line of the
# menu that holds the name of one of the owner's rules or says what a banner said:
# the harness reads only the menu, its own saved keys and the rules file, never a
# notification's content.
#
# What the app says is not typed here. Every word a guard looks for is read from the
# file in NotificationCore that declares it, through `core_constant` below, as
# Scripts/verify-live.sh reads its own, and HarnessConstantsTests holds each reference
# to the shape the declarations have (Ruling 18). `core_constant` is defined here, once,
# for the guards and for verify-live.sh, which sources this file and defines no copy of
# it; HarnessConstantsTests holds it to that.
#
# Tools: bash 3.2 and the BSD userland that ship with macOS, `shasum -a 256`, and
# `osascript -l JavaScript`, which verify-live.sh already reads the rules file with.

# The repository root: the caller's REPO_ROOT when it has one, and otherwise the
# folder above the one this file is in.
harness_repo_root() {
    if [ -n "${REPO_ROOT:-}" ]; then
        printf '%s\n' "$REPO_ROOT"
    else
        (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    fi
}

# core_constant FILE NAME: the TEXT of NAME in Sources/NotificationCore/FILE, or
# nothing when there is no such declaration. Every declaration has the one shape
# `public static let NAME = "TEXT"`, which is what the sed reads.
core_constant() {
    sed -n 's/^[[:space:]]*public static let '"$2"' = "\(.*\)"[[:space:]]*$/\1/p' \
        "$(harness_repo_root)/Sources/NotificationCore/$1" 2>/dev/null | head -1
}

# The newest rules-file version this build of SignalLadder reads
# (`RuleSetCodec.currentVersion`), which is a number and not a text and so is not a
# `core_constant`. It is declared on one line as `public static let currentVersion = N`,
# and HarnessConstantsTests holds that line and this `sed` to it.
harness_current_version() {
    sed -n 's/^[[:space:]]*public static let currentVersion = \([0-9][0-9]*\)[[:space:]]*$/\1/p' \
        "$(harness_repo_root)/Sources/NotificationCore/RuleSetCodec.swift" 2>/dev/null | head -1
}

# harness_backup_path RULES: where a flag that changes the rules file keeps the
# original, beside the file. Every flag keeps it here, so the backup guard of any run
# finds the backup of any other. The digest of the file the run wrote is beside it, as
# this path with ".sha256" added, and the record that there was no rules file is this
# path with ".absent" added.
harness_backup_path() {
    printf '%s\n' "$1.harness-backup"
}

# harness_digest FILE: the SHA-256 of the file, as 64 hexadecimal digits, or the word
# "absent" when there is no such file (a dangling link is not absent), or the word
# "unreadable", with return 1, when there is one and it cannot be read.
harness_digest() {
    local sum
    if [ ! -e "$1" ] && [ ! -L "$1" ]; then
        printf 'absent\n'
        return 0
    fi
    if sum=$(shasum -a 256 "$1" 2>/dev/null) && [ -n "$sum" ]; then
        printf '%s\n' "${sum%% *}"
        return 0
    fi
    printf 'unreadable\n'
    return 1
}

# ------------------------------------------------------------------ the menu's lines
# The menu is the text the harness read over the Accessibility API, one item to a
# line (`read_menu` in verify-live.sh). The three guards below judge it.

# Escapes a text so that it is read literally inside an extended regular expression.
_harness_ere_escape() {
    printf '%s' "$1" | sed 's/[][\.*^$(){}?+|]/\\&/g'
}

# The regular expression for a line that says something is escalating: a count, one
# word, then the word the menu's escalation lines end their stem in ("1 alert
# escalating", "3 alerts escalating (14 matches)"). Anchored on the count, so that a
# line that merely has the word in it, such as the name of one of the owner's rules
# in the last-match line, is not taken for one. Prints nothing when the word cannot be
# read.
_harness_escalating_pattern() {
    local word
    word=$(core_constant AlertMenuText.swift escalatingWord)
    [ -n "$word" ] || return 1
    printf '%s\n' "^[0-9]+ [^ ]+ $(_harness_ere_escape "$word")( |\$)"
}

# harness_refuse_guard MODE MENU
#
# Refuses a run against a state that belongs to a real shift (M5 plan, Task 9). MODE
# is the flag without its dashes: on-call or snooze, which refuse when the menu shows
# the stem of the on-call line or of a running snooze's line, and escalation, which
# refuses when the menu shows any Acknowledge item or a line that says something is
# escalating, because the menu's Acknowledge is Acknowledge All and a run during a
# real page would end it silently. A menu that cannot be judged is refused: the harness
# does not run on a guess. That is a menu with no text, and a text that is not the whole of
# the menu, which is one without the On Call item and the Snooze item that every menu has,
# such as the word `read_menu` answers with when it finds no status item, or a read that
# came back short. Returns 0, 2, or 1 for a MODE it does not know.
harness_refuse_guard() {
    local mode=${1:-} menu=${2:-} line
    local on_call_stem snooze_stem acknowledge pattern
    local on_call_item snooze_item has_on_call=0 has_snooze=0

    case "$mode" in
        on-call|snooze|escalation) ;;
        *) printf '%s\n' "unknown mode \"$mode\": the refuse guard knows on-call, snooze and escalation"; return 1 ;;
    esac
    if [ -z "$(printf '%s' "$menu" | tr -d '[:space:]')" ]; then
        printf '%s\n' "the menu has no text, so there is nothing to tell whether the Mac is in a real shift: refusing to run"
        return 2
    fi
    on_call_item=$(core_constant OnCall.swift menuTitle)
    snooze_item=$(core_constant SnoozeText.swift menuTitle)
    if [ -z "$on_call_item" ] || [ -z "$snooze_item" ]; then
        printf '%s\n' "could not read the titles of the On Call item and the Snooze item from NotificationCore, so the menu cannot be told from text that is not its own: refusing to run"
        return 2
    fi
    while IFS= read -r line; do
        if [ "$line" = "$on_call_item" ]; then has_on_call=1; fi
        if [ "$line" = "$snooze_item" ]; then has_snooze=1; fi
    done <<< "$menu"
    if [ "$has_on_call" -eq 0 ] || [ "$has_snooze" -eq 0 ]; then
        printf '%s\n' "the text has no \"$on_call_item\" item or no \"$snooze_item\" item, which every menu of SignalLadder has, so it is not the whole of its menu and cannot tell whether the Mac is in a real shift: refusing to run"
        return 2
    fi

    case "$mode" in
        on-call|snooze)
            on_call_stem=$(core_constant OnCall.swift sinceStem)
            snooze_stem=$(core_constant SnoozeText.swift activeStem)
            if [ -z "$on_call_stem" ] || [ -z "$snooze_stem" ]; then
                printf '%s\n' "could not read the stems of the on-call line and the snooze line from NotificationCore, so the menu cannot be judged: refusing to run"
                return 2
            fi
            while IFS= read -r line; do
                case "$line" in
                    "$on_call_stem"*)
                        printf '%s\n' "the menu shows a line that begins \"$on_call_stem\": the app is already on call, which belongs to a real shift, and a run would switch it"
                        return 2 ;;
                    "$snooze_stem"*)
                        printf '%s\n' "the menu shows a line that begins \"$snooze_stem\": the app is already snoozed, which belongs to a real meeting, and a run would end it"
                        return 2 ;;
                esac
            done <<< "$menu"
            ;;
        escalation)
            acknowledge=$(core_constant AlertMenuText.swift acknowledgeOneTitle)
            pattern=$(_harness_escalating_pattern)
            if [ -z "$acknowledge" ] || [ -z "$pattern" ]; then
                printf '%s\n' "could not read the Acknowledge title or the word escalating from NotificationCore, so the menu cannot be judged: refusing to run"
                return 2
            fi
            while IFS= read -r line; do
                case "$line" in
                    "$acknowledge"*)
                        printf '%s\n' "the menu shows an item that begins \"$acknowledge\": something is waiting to be acknowledged, and its Acknowledge is Acknowledge All, so a run during a real page would end it silently"
                        return 2 ;;
                esac
                if [[ $line =~ $pattern ]]; then
                    printf '%s\n' "the menu shows a line that says something is escalating (\"$line\"): that may be a real page, and a run would sit beside it"
                    return 2
                fi
            done <<< "$menu"
            ;;
    esac
    return 0
}

# harness_marker_only_guard COUNT MENU
#
# Passes only when the one thing escalating can be the marker's, so that the harness
# acknowledges nothing of the owner's (M5 plan, Task 9). COUNT is the number of matches
# the harness itself asserted a moment before. The menu must have
#   - exactly one line that says something is escalating, and it is the stem for one
#     escalation ("1 alert escalating") when COUNT is 1, and that stem followed by
#     " (COUNT matches)" otherwise, because the menu adds the count only once matches
#     outnumber escalations. "2 alerts escalating (6 matches)", the stem with another
#     count, and the bare stem when COUNT is more than 1 do not pass: a bare stem then
#     is an escalation the burst did not join, which is not the marker's;
#   - exactly one item that begins with the Acknowledge title, and it is exactly that
#     title, which the menu has only when one alert is listed. "Acknowledge All (2)" is
#     what the menu shows for an escalation beside one missed while asleep, and a click
#     on it would acknowledge the miss unseen;
#   - exactly one last-match line, and it names the marker rule: after its warning mark,
#     if it has one, the stem of the line, the marker rule's name and " at ". The
#     escalation line does not say whose rule it is, but the last match does, and the
#     marker's escalation begins as its match is made. The marker rule is appended after
#     the owner's rules and the first rule to match wins, so an earlier rule of the
#     owner's that matches a banner with the marker's title takes it, and the escalation
#     the menu then shows, the same line with the same count, is that rule's: it names
#     that rule as the last match. So does a real page that came in after the banners. A
#     line that names any other rule, none, or more than one line, does not pass. The
#     reason does not print the line, which names the owner's rules.
# A COUNT of 1 alone cannot tell the marker's escalation from a real page that is alone
# on the menu; the last-match line can, and the harness also uses the guard after a
# burst, with the count the burst gave. Returns 0 or 1.
harness_marker_only_guard() {
    local count=${1:-} menu=${2:-} line
    local stem acknowledge pattern expected last_stem marker last_any last_marker
    local escalating=0 escalating_line='' acknowledgements=0 acknowledgement_line=''
    local last_lines=0 last_markers=0

    case "$count" in
        ''|*[!0-9]*) printf '%s\n' "the count of matches must be a whole number, and was \"$count\""; return 1 ;;
    esac
    count=$((10#$count))
    if [ "$count" -lt 1 ]; then
        printf '%s\n' "the count of matches must be 1 or more, and was $count"
        return 1
    fi

    stem=$(core_constant AlertMenuText.swift singleEscalatingStem)
    acknowledge=$(core_constant AlertMenuText.swift acknowledgeOneTitle)
    pattern=$(_harness_escalating_pattern)
    if [ -z "$stem" ] || [ -z "$acknowledge" ] || [ -z "$pattern" ]; then
        printf '%s\n' "could not read the escalation line's stem and the Acknowledge title from NotificationCore, so nothing is acknowledged"
        return 1
    fi
    last_stem=$(core_constant AlertMenuText.swift lastMatchStem)
    marker=$(core_constant HarnessText.swift markerRuleName)
    if [ -z "$last_stem" ] || [ -z "$marker" ]; then
        printf '%s\n' "could not read the last-match line's stem and the marker rule's name from NotificationCore, so nothing is acknowledged"
        return 1
    fi
    if [ "$count" -eq 1 ]; then
        expected=$stem
    else
        expected="$stem ($count matches)"
    fi
    # A last-match line is one that begins with the stem once any warning mark is skipped,
    # as the harness finds it elsewhere, and the marker's is that stem, the name and " at ".
    last_any="^[^A-Za-z]*$(_harness_ere_escape "$last_stem")"
    last_marker="$last_any $(_harness_ere_escape "$marker") at "

    while IFS= read -r line; do
        if [[ $line =~ $pattern ]]; then
            escalating=$((escalating + 1))
            escalating_line=$line
        fi
        case "$line" in
            "$acknowledge"*)
                acknowledgements=$((acknowledgements + 1))
                acknowledgement_line=$line ;;
        esac
        if [[ $line =~ $last_any ]]; then
            last_lines=$((last_lines + 1))
            if [[ $line =~ $last_marker ]]; then
                last_markers=$((last_markers + 1))
            fi
        fi
    done <<< "$menu"

    if [ "$escalating" -eq 0 ]; then
        printf '%s\n' "the menu has no line that says something is escalating, so there is nothing of the marker's to acknowledge"
        return 1
    fi
    if [ "$escalating" -gt 1 ]; then
        printf '%s\n' "the menu has $escalating lines that say something is escalating, so more than the marker's may be: touching nothing"
        return 1
    fi
    if [ "$escalating_line" != "$expected" ]; then
        printf '%s\n' "the line that says something is escalating is \"$escalating_line\" and the marker's would be \"$expected\": something else may be escalating, so touching nothing"
        return 1
    fi
    if [ "$acknowledgements" -ne 1 ]; then
        printf '%s\n' "the menu has $acknowledgements items that begin \"$acknowledge\" and one is expected: touching nothing"
        return 1
    fi
    if [ "$acknowledgement_line" != "$acknowledge" ]; then
        printf '%s\n' "the Acknowledge item is \"$acknowledgement_line\" and not exactly \"$acknowledge\", which means more than one alert is listed, one of them perhaps missed while asleep: touching nothing"
        return 1
    fi
    # The checks below are the ones that say whose escalation it is. They come last so that
    # each check above is the one that refuses a menu it was written for.
    if [ "$last_lines" -eq 0 ]; then
        printf '%s\n' "the menu has no last-match line, so there is no telling whose rule the escalation is, and it may be a real page's: touching nothing"
        return 1
    fi
    if [ "$last_lines" -gt 1 ]; then
        printf '%s\n' "the menu has $last_lines last-match lines and one is expected: touching nothing"
        return 1
    fi
    if [ "$last_markers" -ne 1 ]; then
        printf '%s\n' "the menu's last match is not the marker rule's, so the escalation may be a rule of the owner's that comes before the marker in the rules file and took the banner first, or a real page that came in since: touching nothing"
        return 1
    fi
    return 0
}

# harness_summary_guard MENU
#
# Passes only when the held summary is exactly the marker's one match, so that
# dismissing it erases no real match's trace (M5 plan, Task 9): the line is the stem for
# one match held, then ": ", then the marker rule's name and " ×1". A summary of
# anything else, the marker's with another rule's, a record that could not be read, or
# no summary at all, returns 1, and the harness leaves the summary where it is and says
# so. The reason does not print the line, which names the owner's rules.
harness_summary_guard() {
    local menu=${1:-} line stem name expected

    stem=$(core_constant SnoozeText.swift heldOneMatchStem)
    name=$(core_constant HarnessText.swift markerRuleName)
    if [ -z "$stem" ] || [ -z "$name" ]; then
        printf '%s\n' "could not read the held summary's stem or the marker rule's name from NotificationCore, so the summary is left where it is"
        return 1
    fi
    expected="$stem: $name ×1"

    while IFS= read -r line; do
        if [ "$line" = "$expected" ]; then
            return 0
        fi
    done <<< "$menu"
    printf '%s\n' "the menu has no held summary that is exactly the marker rule's one match, so the summary is left where it is: it may be a real match's trace"
    return 1
}

# ------------------------------------------------------------------ the rules file
# A flag that changes the rules file copies it aside first, records the SHA-256 of the
# file it then writes, and puts the original back from a trap. A trap cannot run after a
# kill, a power loss or a crashed terminal, so the next run of any flag begins with the
# backup guard, and it is the guard, and not the trap, that keeps the owner's file safe:
# it puts the backup back only over a file that is still the one the run wrote, and never
# over one the owner has changed since (M5 plan, Task 9).
#
# What a run leaves beside the file, with BACKUP the path `harness_backup_path` gives:
#   BACKUP           a copy of rules.json, made first
#   BACKUP.sha256    the digest of the file the run is about to write, taken from the file
#                    built for it and recorded just before rules.json is written
#   BACKUP.absent    in place of BACKUP, when there was no rules.json and the run
#                    created one: the record that there was none to copy
#   BACKUP.new       the file being built, which is gone again before the writer returns
# The order is the order of the steps, so that a run killed between two of them leaves a
# state the guard can read and does not guess at. The digest comes before the write and not
# after it for that reason: recorded after, it would leave a gap in which a kill leaves the
# marked file with a backup and no digest, which the guard cannot tell from a file the owner
# changed. Recorded before, a kill at any point leaves rules.json either as it was, which is
# the backup, or as the run wrote it, which has the digest.

# The 64 hexadecimal digits a digest file holds, or nothing when the file is missing, is
# empty or holds anything else, which is read as no digest.
_harness_recorded_digest() {
    local recorded=''
    [ -f "$1" ] || return 1
    read -r recorded < "$1" 2>/dev/null
    case "$recorded" in
        ''|*[!0-9a-f]*) return 1 ;;
    esac
    [ "${#recorded}" -eq 64 ] || return 1
    printf '%s\n' "$recorded"
}

# Whether something is there at all, a link that goes nowhere included.
_harness_present() {
    [ -e "$1" ] || [ -L "$1" ]
}

# harness_backup_guard RULES BACKUP [WHO]
#
# Run at the start of every run, and by the trap at its end. With nothing left by an
# earlier run it does nothing and returns 0. WHO is how its messages name the run that
# left what it finds: "an earlier run" at the start of a run, and "this run" when the trap
# runs it at the end of its own, since the backup it then puts back is the run's own.
# Otherwise:
#   - a backup and the digest of the file the run wrote: if rules.json still has that
#     digest, it is the file the run wrote, and the guard puts the backup back byte for
#     byte, checks it, removes both files and says so; if rules.json differs, which after
#     a killed run means the owner has edited and saved it since (the app runs on the
#     marked file, and the editor can write to it), or is gone, the guard returns 2,
#     leaves both files where they are and says which differs and where the backup is.
#     The one difference it does not refuse is a rules.json that is already byte for byte
#     the backup, which is what a restore killed before it cleaned up leaves, and what a
#     run killed after it recorded the digest and before it wrote leaves too: there is
#     nothing to put back and nothing of the owner's to overwrite, so the two files are
#     removed;
#   - a backup with no digest, which a run killed between the copy and the record of the
#     digest leaves: removed without a restore when rules.json is byte for byte the
#     backup, and otherwise refused in the same way;
#   - the record that there was no rules.json, with the digest of the file the run
#     created: the file is removed, with the record, only if it still has that digest. If
#     it differs it is left, with the record, and the guard returns 2, because there is no
#     backup to put back and the file may be the owner's. If it is already gone the record
#     alone is removed, which is also what a run killed after it recorded the digest and
#     before it wrote leaves. With no digest recorded, which a run killed between the
#     record that there was no file and the record of the digest leaves, the record is
#     removed when there is no file, and otherwise the file is left and the guard
#     returns 2, since nothing says it is the run's;
#   - anything else, such as a digest with no backup or a backup beside the record that
#     there was none, is a state no run leaves, and returns 2 and leaves it.
# Returns 1 when it decided to restore or remove and the step failed, having left the
# files it could not deal with. A leftover BACKUP.new is the run's own and is removed.
harness_backup_guard() {
    local rules=${1:-} backup=${2:-} who=${3:-an earlier run}
    local digest_file="$backup.sha256" absent_file="$backup.absent"
    local have_backup=0 have_absent=0 recorded='' current=''

    if [ -z "$rules" ] || [ -z "$backup" ]; then
        printf '%s\n' "the backup guard needs the rules file's path and the backup's"
        return 1
    fi
    rm -f "$backup.new"

    if _harness_present "$backup"; then have_backup=1; fi
    if _harness_present "$absent_file"; then have_absent=1; fi
    recorded=$(_harness_recorded_digest "$digest_file")
    if [ "$have_backup" -eq 0 ] && [ "$have_absent" -eq 0 ] && ! _harness_present "$digest_file"; then
        return 0
    fi

    if [ "$have_backup" -eq 1 ] && [ "$have_absent" -eq 1 ]; then
        printf '%s\n' "$backup and $absent_file are both there, which no run leaves: they are left where they are, and $rules was not touched"
        return 2
    fi

    if [ "$have_absent" -eq 1 ]; then
        # The run found no rules file and made one.
        if ! _harness_present "$rules"; then
            rm -f "$digest_file" "$absent_file" || { printf '%s\n' "could not remove $absent_file"; return 1; }
            printf '%s\n' "$who found no rules file and made one, and there is none now: only its record was left, and it is removed"
            return 0
        fi
        if [ -z "$recorded" ]; then
            printf '%s\n' "$who found no rules file and may have made $rules, but no digest of it was recorded, so there is no telling it from a file made since: left where it is, with $absent_file"
            return 2
        fi
        current=$(harness_digest "$rules")
        if [ "$current" != "$recorded" ]; then
            printf '%s\n' "$who made $rules, and its digest is no longer the one recorded in $digest_file, so it has been changed since and may be the owner's: left where it is, and there is no backup to put back"
            return 2
        fi
        rm -f "$rules" || { printf '%s\n' "could not remove $rules"; return 1; }
        rm -f "$digest_file" "$absent_file" || { printf '%s\n' "removed $rules but could not remove its records beside it"; return 1; }
        printf '%s\n' "removed $rules, which $who made when there was none, and which was still the file it wrote"
        return 0
    fi

    if [ "$have_backup" -eq 0 ]; then
        printf '%s\n' "$digest_file is there with no backup beside it and no record that there was no rules file, which no run leaves: left where it is, and $rules was not touched"
        return 2
    fi

    # A backup of the owner's rules file is there.
    if [ -n "$recorded" ]; then
        current=$(harness_digest "$rules")
        if [ "$current" != "$recorded" ]; then
            # A restore that was killed after it copied and before it cleaned up leaves the
            # original in place beside its backup. There is nothing to put back, and nothing
            # of the owner's to overwrite.
            if _harness_present "$rules" && cmp -s "$backup" "$rules"; then
                rm -f "$digest_file" "$backup" || { printf '%s\n' "$rules is the backup's copy, but $backup could not be removed"; return 1; }
                printf '%s\n' "$who left a backup and its digest beside a rules file that is already byte for byte the backup, so there was nothing to put back, and the backup and its digest are removed"
                return 0
            fi
            if [ "$current" = absent ]; then
                printf '%s\n' "$who left a backup of the rules file, and $rules is gone: nothing was restored, and the backup is at $backup"
            else
                printf '%s\n' "$who left a backup of the rules file, and $rules differs from the file $who wrote, so it has been edited since: nothing was restored, both files are left where they are, and the backup is at $backup"
            fi
            return 2
        fi
        if ! cp "$backup" "$rules" 2>/dev/null || ! cmp -s "$backup" "$rules"; then
            printf '%s\n' "could not put the backup back over $rules: both files are left where they are, and the backup is at $backup"
            return 1
        fi
        rm -f "$digest_file" "$backup" || { printf '%s\n' "put the backup back, but could not remove $backup and its digest"; return 1; }
        printf '%s\n' "put the rules file back from the backup $who left, byte for byte, and removed the backup and its digest"
        return 0
    fi

    # A backup with no digest.
    if _harness_present "$rules" && cmp -s "$backup" "$rules"; then
        rm -f "$digest_file" "$backup" || { printf '%s\n' "$rules is the backup's copy, but $backup could not be removed"; return 1; }
        printf '%s\n' "$who left a backup with no digest beside a rules file that is byte for byte the same, so there was nothing to put back, and the backup is removed"
        return 0
    fi
    printf '%s\n' "$who left a backup with no digest, and $rules differs from it, so it cannot be told from a file the owner changed: nothing was restored, both files are left where they are, and the backup is at $backup"
    return 2
}

# JSON editing needs a parser, so it uses the one the harness already reads the rules file
# with: osascript -l JavaScript. In a function because macOS's bash 3.2 mis-parses a
# heredoc that sits inside $(...) (see verify-live.sh), and the caller substitutes the
# function's output instead.
#
# _harness_json_edit MODE RULES OUT RULE NEEDED MAX writes the new file to OUT and prints
# one line: "ok version N", "refuse: REASON" for a file that must not be touched, or
# "error: REASON". In mode append the file is RULES. The rule is spliced in after the last
# element of its "rules" array, in the file's own layout and with its own line endings, and
# the version's digits are replaced if they are lower than NEEDED: every other byte of the
# file is the owner's, and the file is not parsed and printed again, which would reorder and
# reformat it. In mode create there is no file, and OUT is a file of the one rule.
_harness_json_edit() {
    osascript -l JavaScript - "$@" <<'JXA' 2>/dev/null
    function run(argv) {
      ObjC.import('Foundation');
      var mode = argv[0], path = argv[1], outPath = argv[2];
      var needed = Number(argv[4]), maxVersion = Number(argv[5]);
      var rule;
      try { rule = JSON.parse(argv[3]); } catch (e) { return 'error: the rule given is not JSON'; }
      if (rule === null || typeof rule !== 'object' || Array.isArray(rule)) return 'error: the rule given is not a JSON object';
      if (!(needed >= 1) || !(maxVersion >= needed)) return 'error: the version the rule needs is not one this build reads';

      function save(text) {
        return $.NSString.stringWithString(text)
          .writeToFileAtomicallyEncodingError(outPath, true, $.NSUTF8StringEncoding, null);
      }

      if (mode === 'create') {
        var created = '{\n  "rules": [\n    ' + JSON.stringify(rule, null, 2).split('\n').join('\n    ')
          + '\n  ],\n  "version": ' + needed + '\n}';
        return save(created) ? 'ok version ' + needed : 'error: could not write ' + outPath;
      }

      // A byte-order mark is dropped when the text is read, and a splice must not drop a byte.
      var bytes = $.NSData.dataWithContentsOfFile(path);
      if (bytes.isNil()) return 'refuse: it could not be read';
      if (bytes.length >= 3) {
        var head = ObjC.unwrap(bytes.subdataWithRange($.NSMakeRange(0, 3)).base64EncodedStringWithOptions(0));
        if (head === '77u/') return 'refuse: it starts with a byte-order mark, which a splice would not keep';
      }
      var read = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
      if (read.isNil()) return 'refuse: it could not be read as UTF-8 text';
      var text = ObjC.unwrap(read);
      var data;
      try { data = JSON.parse(text); } catch (e) { return 'refuse: it is not JSON'; }
      if (data === null || typeof data !== 'object' || Array.isArray(data)) return 'refuse: it is not a rules file, since its top level is not an object';
      if (typeof data.version !== 'number' || !Number.isInteger(data.version)) return 'refuse: it is not a rules file, since "version" is not a whole number';
      if (data.version > maxVersion) return 'refuse: it declares version ' + data.version + ', and this build of SignalLadder reads up to ' + maxVersion;
      if (data.version < 1) return 'refuse: it declares version ' + data.version + ', and "version" must be 1 or higher';
      if (!Array.isArray(data.rules)) return 'refuse: it is not a rules file, since it has no "rules" array';

      // The text is valid JSON, so this walks it by position: it finds the top-level "rules"
      // array and "version" number and the end of the array's last element, and changes
      // nothing else. The walk relies on the checks above, that the text is an object and
      // "rules" is an array: without them its loops would not move on at every step.
      var n = text.length;
      function isWs(c) { return c === ' ' || c === '\t' || c === '\n' || c === '\r'; }
      function skipWs(i) { while (i < n && isWs(text[i])) i++; return i; }
      function skipString(i) {
        i++;
        while (i < n && text[i] !== '"') i += text[i] === '\\' ? 2 : 1;
        return i + 1;
      }
      function skipValue(i) {
        var c = text[i];
        if (c === '"') return skipString(i);
        if (c === '{' || c === '[') {
          var depth = 0;
          while (i < n) {
            var d = text[i];
            if (d === '"') { i = skipString(i); continue; }
            if (d === '{' || d === '[') depth++;
            else if (d === '}' || d === ']') { depth--; if (depth === 0) return i + 1; }
            i++;
          }
        }
        while (i < n && !isWs(text[i]) && ',]}'.indexOf(text[i]) < 0) i++;
        return i;
      }

      var rulesAt = null, versionAt = null;
      var i = skipWs(skipWs(0) + 1);
      while (i < n && text[i] !== '}') {
        var keyEnd = skipString(i);
        var key = JSON.parse(text.slice(i, keyEnd));
        i = skipWs(skipWs(keyEnd) + 1);
        var valueEnd = skipValue(i);
        if (key === 'rules') rulesAt = [i, valueEnd];
        if (key === 'version') versionAt = [i, valueEnd];
        i = skipWs(valueEnd);
        if (text[i] === ',') i = skipWs(i + 1);
      }
      if (rulesAt === null || versionAt === null) return 'error: could not find the rules array and the version in the file';

      var last = null;
      var j = skipWs(rulesAt[0] + 1);
      while (j < n && text[j] !== ']') {
        var elementEnd = skipValue(j);
        last = [j, elementEnd];
        j = skipWs(elementEnd);
        if (text[j] === ',') j = skipWs(j + 1);
      }

      var eol = text.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
      var multiline = text.indexOf('\n') >= 0;
      function indentOf(pos) {
        var lineStart = text.lastIndexOf('\n', pos - 1) + 1;
        var before = text.slice(lineStart, pos);
        return /^[ \t]*$/.test(before) ? before : null;
      }

      var cut, replacement;
      if (last !== null) {
        var indent = multiline ? indentOf(last[0]) : null;
        var body = indent === null ? JSON.stringify(rule) : JSON.stringify(rule, null, 2).split('\n').join(eol + indent);
        cut = [last[1], last[1]];
        replacement = ',' + (indent === null ? '' : eol + indent) + body;
      } else if (multiline) {
        var close = indentOf(rulesAt[0]);
        if (close === null) close = /^[ \t]*/.exec(text.slice(text.lastIndexOf('\n', rulesAt[0] - 1) + 1))[0];
        var inner = close + '  ';
        cut = [rulesAt[0] + 1, rulesAt[1] - 1];
        replacement = eol + inner + JSON.stringify(rule, null, 2).split('\n').join(eol + inner) + eol + close;
      } else {
        cut = [rulesAt[0] + 1, rulesAt[1] - 1];
        replacement = JSON.stringify(rule);
      }

      var edits = [{ at: cut, text: replacement }];
      var newVersion = data.version;
      if (data.version < needed) {
        newVersion = needed;
        edits.push({ at: versionAt, text: String(needed) });
      }
      edits.sort(function (a, b) { return b.at[0] - a.at[0]; });
      var out = text;
      edits.forEach(function (e) { out = out.slice(0, e.at[0]) + e.text + out.slice(e.at[1]); });
      return save(out) ? 'ok version ' + newVersion : 'error: could not write ' + outPath;
    }
JXA
}

# Puts back what a writer that failed halfway had changed: the backup over the rules file,
# or, when there was no rules file, no rules file. Returns 0 when it is as it was.
_harness_undo_install() {  # _harness_undo_install MODE RULES BACKUP
    if [ "$1" = create ]; then
        rm -f "$2" "$3.absent" "$3.sha256" "$3.new"
        return 0
    fi
    if cp "$3" "$2" 2>/dev/null && cmp -s "$3" "$2"; then
        rm -f "$3.sha256" "$3" "$3.new"
        return 0
    fi
    return 1
}

# harness_install_marker RULES BACKUP RULE NEEDED
#
# The marker writer (M5 plan, Task 9): puts the marker rule into the rules file for the
# length of a run, and arranges that the guard above can take it out again.
#   RULES   the rules file's path
#   BACKUP  the backup's path, `harness_backup_path RULES`
#   RULE    the marker rule, as the text of one JSON object
#   NEEDED  the version the rule needs: 4 for a rule with an escalation, 5 for one with
#           quietWhenSnoozed
# It only appends the rule to the end of the rules array and raises "version" to NEEDED if
# it is lower. It never removes or reorders the owner's rules and never lowers the
# version, and every byte of the file that is not the new rule, a comma and the version's
# digits is the owner's, so the original is a copy away. The order of its steps is: build
# the new file beside the backup's path, copy the original to BACKUP, record the digest of
# the new file in BACKUP.sha256, write the new file over RULES, check that RULES is the new
# file. With no rules file it records BACKUP.absent in place of the copy and goes on the
# same way, from a file of the one rule. The digest is recorded before the write so that a
# run killed after the write leaves a file with the digest recorded and not one with none,
# which the backup guard could not tell from a file the owner had changed.
#
# Returns 2, having changed nothing and left no backup, when the rules file is a link to
# nowhere, is not a file, cannot be read or written, is not UTF-8 text or not JSON, is not
# an object with a whole number "version" and a "rules" array, or declares a version above
# `RuleSetCodec.currentVersion`; and also when a backup or a record from an earlier run is
# still there, which the backup guard must deal with first, since copying over it would
# lose the owner's original. Returns 1 for a call it cannot make sense of or a step that
# failed, after putting back what it had changed when it could; if it could not, it says
# where the backup is.
harness_install_marker() {
    local rules=${1:-} backup=${2:-} rule=${3:-} needed=${4:-}
    local digest_file="$backup.sha256" absent_file="$backup.absent" staged="$backup.new"
    local mode max result version digest read_as

    if [ -z "$rules" ] || [ -z "$backup" ] || [ -z "$rule" ]; then
        printf '%s\n' "the marker writer needs the rules file's path, the backup's and the rule"
        return 1
    fi
    case "$needed" in
        4|5) ;;
        *) printf '%s\n' "the version the marker rule needs must be 4 or 5, and was \"$needed\""; return 1 ;;
    esac
    max=$(harness_current_version)
    case "$max" in
        ''|*[!0-9]*) printf '%s\n' "could not read the newest rules version from NotificationCore, so no file is marked"; return 2 ;;
    esac

    if _harness_present "$backup" || _harness_present "$digest_file" || _harness_present "$absent_file"; then
        printf '%s\n' "a backup or a record from an earlier run is still beside $rules, and the backup guard has to deal with it first: copying over it would lose the original"
        return 2
    fi

    if [ -e "$rules" ]; then
        mode=append
        if [ ! -f "$rules" ]; then printf '%s\n' "$rules is not a file: nothing was changed and no backup was made"; return 2; fi
        if [ ! -r "$rules" ]; then printf '%s\n' "$rules cannot be read: nothing was changed and no backup was made"; return 2; fi
        if [ ! -w "$rules" ]; then printf '%s\n' "$rules cannot be written: nothing was changed and no backup was made"; return 2; fi
    elif [ -L "$rules" ]; then
        printf '%s\n' "$rules is a link to a file that cannot be found: nothing was changed and no backup was made"
        return 2
    else
        mode=create
        if [ ! -d "$(dirname "$rules")" ] || [ ! -w "$(dirname "$rules")" ]; then
            printf '%s\n' "there is no rules file at $rules and its folder cannot be written: nothing was changed and no backup was made"
            return 2
        fi
    fi

    rm -f "$staged"
    read_as=$(harness_digest "$rules")
    result=$(_harness_json_edit "$mode" "$rules" "$staged" "$rule" "$needed" "$max")
    case "$result" in
        ok*) ;;
        "refuse: "*)
            rm -f "$staged"
            printf '%s\n' "$rules cannot be marked, because ${result#refuse: }: nothing was changed and no backup was made"
            return 2 ;;
        *)
            rm -f "$staged"
            printf '%s\n' "could not build the marked rules file: ${result:-osascript gave no answer}"
            return 1 ;;
    esac
    version=${result#ok version }
    if [ ! -s "$staged" ]; then
        rm -f "$staged"
        printf '%s\n' "could not build the marked rules file: it is empty"
        return 1
    fi

    if [ "$mode" = append ]; then
        if ! cp "$rules" "$backup" 2>/dev/null || ! cmp -s "$rules" "$backup"; then
            rm -f "$backup" "$staged"
            printf '%s\n' "could not copy $rules aside: nothing was changed"
            return 1
        fi
        # The new file was built from the file as it was read. If it changed since, by an
        # editor's Save, writing the new file would overwrite what the owner just saved.
        if [ "$(harness_digest "$backup")" != "$read_as" ]; then
            rm -f "$backup" "$staged"
            printf '%s\n' "$rules changed while the marked file was being built, so nothing was written and no backup was kept"
            return 1
        fi
    elif ! : > "$absent_file" 2>/dev/null; then
        rm -f "$absent_file" "$staged"
        printf '%s\n' "could not record that there was no rules file: nothing was changed"
        return 1
    elif _harness_present "$rules"; then
        # Made by the app or by hand while the marked file was being built.
        rm -f "$absent_file" "$staged"
        printf '%s\n' "$rules appeared while the marked file was being built, so nothing was written and no record was kept"
        return 1
    fi

    # The digest is of the file about to be written, which is the staged file, and it is
    # recorded before the write. Nothing has been written to RULES yet, so a failure here
    # takes away only what this run made.
    digest=$(harness_digest "$staged")
    case "$digest" in
        absent|unreadable|'') digest='' ;;
    esac
    if [ -z "$digest" ] || ! printf '%s\n' "$digest" > "$digest_file" 2>/dev/null || [ "$(_harness_recorded_digest "$digest_file")" != "$digest" ]; then
        rm -f "$digest_file" "$backup" "$absent_file" "$staged"
        printf '%s\n' "could not record the digest of the marked file: nothing was written to $rules, and the backup is removed"
        return 1
    fi

    if ! cat "$staged" > "$rules" 2>/dev/null; then
        if _harness_undo_install "$mode" "$rules" "$backup"; then
            printf '%s\n' "could not write $rules: it is as it was, and the backup is removed"
        else
            printf '%s\n' "could not write $rules, and could not put it back: the original is at $backup"
        fi
        return 1
    fi
    # Not undone when it is not the file that was written: a Save that landed since is the
    # owner's, and the backup put over it would lose it. Both files are left, the digest
    # recorded is of the file that was written and so is not this one's, and the backup guard
    # refuses it and names the backup.
    if ! cmp -s "$staged" "$rules" 2>/dev/null; then
        printf '%s\n' "$rules is not the file that was written to it, so it was changed as it was written: it is left as it is, with the original at $backup, and the backup guard will refuse it until it has been dealt with by hand"
        return 1
    fi
    rm -f "$staged"

    if [ "$mode" = append ]; then
        printf '%s\n' "appended the marker rule to $rules at version $version; the original is kept at $backup"
    else
        printf '%s\n' "there was no rules file, so $rules was made with the marker rule alone, at version $version; it is recorded in $absent_file"
    fi
    return 0
}
