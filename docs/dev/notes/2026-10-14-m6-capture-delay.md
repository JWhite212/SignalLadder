# The Teams capture delay — what was seen, and how the next alerts are timed

**Date:** 2026-10-14
**Plan:** [M6, Task 2](../plans/2026-10-14-m6-one-point-one.md#task-2-time-the-delay-with-what-is-installed-no-code)
**Status:** day 1's check of the command was made on 2026-10-14 (What the runs found). No timing run has begun. The answers to the questions at the end are not in yet, and nor are any timings.

This note is Task 2's record. Its first version holds the sighting, the command, the conditions, how a result is read and what the owner is asked. It merges before any run, so the rules for reading a result are fixed before a result exists. A second version adds what the runs found.

What this note keeps is offsets from a run's first line, gaps, fixed labels and seconds of a minute. It keeps no time of day, no title, no body and no name, and no line of the system log.

---

## The sighting

On 2026-10-02, on macOS 26.7.1, two stacked Teams alerts each got one Inspector row, and nothing was added when Teams cleared them. The build was a Developer ID build of `48713f9` (`feat/ladder-editor`), made that morning. It had the stack fix of PR #30. It lacked `6d84068`, which keeps capture running while a menu or dialog is open, since that commit came 23 minutes after the sighting. That day's unified log was read with `log show` and kept as times and fixed labels only. It has since rolled over and cannot be read again.

| Offset from the first line | The line, by its fixed label                                                        | From               |
| -------------------------- | ----------------------------------------------------------------------------------- | ------------------ |
| +0.000 s                   | Notification Centre ordered its window in                                           | NotificationCenter |
| +0.072 s                   | alert audio started: the Outlook alert (Inspector row Microsoft Outlook, second 08) | SignalLadder       |
| +0.093 s                   | Presenting a `com.microsoft.teams2` record, as alert                                | usernoted          |
| +0.798 s                   | Presenting a second `com.microsoft.teams2` record, as alert                         | usernoted          |
| +1.156 s                   | alert audio started (Inspector row Microsoft Teams, second 09)                      | SignalLadder       |
| +4.566 s                   | alert audio started (Inspector row Microsoft Teams, second 12)                      | SignalLadder       |
| +6.036 s                   | brought Outlook forward (a click on its alert)                                      | usernoted          |
| +221.791 s and +221.793 s  | the two Teams alerts removed (Teams cleared them)                                   |                    |
| +222.116 s                 | Notification Centre ordered its window out                                          | NotificationCenter |

The first line fell 0.375 s into second 08 of its minute.

- The first Teams record: 1.06 s from its Presenting line to the audio start.
- The second Teams record: 3.77 s. This is the 3.8 s.
- The two Presenting lines were 0.71 s apart, so 3.77 s is not the gap between two posts.
- Both rows read Microsoft Teams, so they are paired with the Presenting lines by order. Crossed, the gaps would be 0.36 s and 4.47 s.
- The second alert's row reads second 12, which began at +3.625 s. So it was stamped between 2.83 s and 3.77 s after its Presenting line: at least 2.83 s of the gap came before the stamp, and at most 0.94 s after it.

What the figure leaves open: when the alert was drawn and its text could first be read, what happened between the stamp and the audio, and whether the pointer had a part. The plan's [What the 3.8 s was](../plans/2026-10-14-m6-one-point-one.md#what-the-38-s-was) sets out each, and [What could explain the delay](../plans/2026-10-14-m6-one-point-one.md#what-could-explain-the-delay) lists the eight readings A to H.

---

## How the next alerts are timed

The runs use the installed 1.0.0 or a Developer ID build of `main` at `0b378c0`. Their capture code is the same: `git diff --stat v1.0.0 0b378c0` shows only Settings sources changed, besides tests and pages. Each figure names the build it was timed on.

### What is read

Times and fixed labels only, from lines that already exist. SignalLadder logs no capture time of its own.

| Label                                                     | The line                                                                                                                                                    |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `teams-presented`, `control-presented`, `other-presented` | usernoted's `Presenting <NotificationRecord`, for `com.microsoft.teams2`, `com.apple.ScriptEditor2` or any other app. No other app's id is printed.         |
| `teams-drawn`, `control-drawn`                            | Notification Centre's `canDisplayWhileCenterIsClosed: true`. It can reach the log after the banner is drawn, so it bounds the drawing time from above only. |
| `audio-start`                                             | AVAudioEngine's `Engine@…: start` from the process SignalLadder. It is written only when the engine was not already running.                                |
| `speech-began` and N                                      | `speech began N ms after it was asked for`. Its time less N ms is when the alert began.                                                                     |
| `attached`, `exited`, `lifecycle`, `retrying`, `blind`    | The watcher's own lines, by their fixed words. They mark a window in which capture was not attached.                                                        |

The Inspector's rows are read on screen, as the app's name and the second of the row. Nothing is copied from them.

### The command

It was first run on 2026-10-14 on macOS 27.2, as day 1's check (What the runs found). Its lines come from the record of 2026-10-02 on macOS 26.7.1. Day 1 added the `lifecycle` label, for the watcher's other re-attach line (`AXBannerWatcher.swift:273`). Use the full path to `log`, since zsh has a builtin of that name.

```sh
umask 077
/usr/bin/log show --last 12h --style compact --info --predicate \
  '(process == "usernoted" AND eventMessage CONTAINS "Presenting <NotificationRecord") OR (process == "NotificationCenter" AND eventMessage CONTAINS "canDisplayWhileCenterIsClosed: true") OR (process == "SignalLadder" AND (eventMessage CONTAINS "Engine@" OR eventMessage CONTAINS "speech began")) OR (subsystem == "com.jamiewhite.signalladder" AND category == "watcher")' \
| awk '
    /usernoted/ && /Presenting <NotificationRecord/ {
        if ($0 ~ /app:"com\.microsoft\.teams2"/) print $1, $2, "teams-presented"
        else if ($0 ~ /app:"com\.apple\.ScriptEditor2"/) print $1, $2, "control-presented"
        else print $1, $2, "other-presented"
        next }
    /NotificationCenter/ && /canDisplayWhileCenterIsClosed: true/ {
        line = tolower($0)
        if (line ~ /com\.microsoft\.teams2/) print $1, $2, "teams-drawn"
        else if (line ~ /com\.apple\.scripteditor2/) print $1, $2, "control-drawn"
        next }
    /SignalLadder/ && /Engine@/ && /: start/ { print $1, $2, "audio-start"; next }
    /SignalLadder/ && /speech began/ && match($0, /began [0-9.]+ ms/) { print $1, $2, "speech-began", substr($0, RSTART + 6, RLENGTH - 9); next }
    /attached to notificationcenterui/ { print $1, $2, "attached"; next }
    /exited; scheduling re-attach/ { print $1, $2, "exited"; next }
    /lifecycle event; scheduling re-attach/ { print $1, $2, "lifecycle"; next }
    /retrying in/ { print $1, $2, "retrying"; next }
    /possible partial blindness/ { print $1, $2, "blind" }
  ' > "$TMPDIR/capture-delay.txt"
```

The raw lines stay in the pipe and are never written. The file holds times of day and fixed labels, so it lives in `$TMPDIR` and not in the repository or a synced folder. Each time it is scored, the numbers come here as offsets and gaps, and the file is deleted, within the day in any case.

**Day 1 first.** Post one control (below), run the command, and check that each label appears as often as it should. Run it again the next morning to learn whether the lines last. If they do not, run it after each staged session, and in the passive arm after each Teams burst and at least every two hours. If a label never appears on macOS 27.2, the Inspector's seconds are the fallback, and this note says so. Day 1 found every line at Default level, not Info, and SignalLadder's own lines reaching back only 8 hours, so the two-hour rule stands (What the runs found).

### Conditions, written once for each run

- The macOS build, Settings' version line and, for a build from source, its commit.
- Teams: the new client or the classic one, its version, whether message preview is on.
- The alert style of Teams and of Script Editor. Both are set to Alerts for the runs, since a Teams set to Banners takes another path.
- The owner's presence in Teams, and whether Teams was frontmost.
- Whether the display had slept or the screen was locked, whether a meeting or a screen share was on, that no Focus was on, and that Notification Centre's list was closed.
- Who or what sent the alerts: a second person or a second account.
- Whether a build, a test run or other heavy work was going on.
- Whether the Teams rule, and the controls' rule, have a ladder with a repeating tier 3, and whether a copy without it stood in.
- The output device, and whether it was Bluetooth.

### The runs

1. **Alert styles.** Teams and Script Editor set to Alerts in System Settings › Notifications.
2. **Three controls.** Two alerts 4 s apart, with neutral words:
   `osascript -e 'display notification "Control one" with title "Control"'`, then the same with "Control two". A control needs a rule that sounds for Script Editor, has no ladder, is of the same kind as the Teams rule (sound, speech or both), and comes before any catch-all, since the first enabled match wins.
3. **The staged arm, 20 scored pairs.** A second person, or a second Teams account in a private chat, sends two alerts with different neutral words typed beforehand. The same words within 1.5 s are suppressed as a repeat. If the Teams rule has a repeating tier 3, a copy without the ladder stands ahead of it for the session, and only while another device covers the pager. Dismiss everything between pairs and let Notification Centre settle for 30 s. A pair's cell is set by the gap between its two Presented lines in the log.

    | Cell                                                                                         | Pairs |
    | -------------------------------------------------------------------------------------------- | ----- |
    | Base: Mac in use, pointer away, about 4 s apart, Teams not frontmost, nothing else on screen | 4     |
    | Under 1 s apart, aiming for 0.7 s                                                            | 2     |
    | Another app's persistent alert already on screen                                             | 2     |
    | 2 s apart                                                                                    | 3     |
    | A clean build and a full test run of this package going on                                   | 3     |
    | The Mac idle for ten minutes first                                                           | 3     |
    | The pointer resting on the first alert when the second arrives                               | 3     |

    A pair counts only when both its alerts are scored. More are sent until there are 20. Spread them over at least two days.

4. **The passive arm.** SignalLadder runs through ordinary work with the real rule, and no staged pairs, until 30 second alerts are scored. A second alert is a Teams Presented line within 30 s of an earlier one with no dismissal by hand between. The Inspector keeps only the last 50, so read it, and run the command, after each Teams burst and at least every two hours.

### Scoring an alert

- Give each start line to an Inspector row first, by the second. The row's second is the start's second or the one before.
- A start whose row belongs to another app is left out.
- Pair the rest with this app's Presented lines in order. Each start takes the oldest unpaired Presented line of the app before it, no more than 10 s before. Do not pair by the nearest line, which crosses two alerts 0.7 s apart.
- For a rule that speaks, the start is the speech line's time less N ms. For a rule that only sounds, it is `audio-start`.
- A Presented line with no start inside 10 s, and a start with no Presented line, are written down as they are and not scored.
- An alert whose row names a joined match joined its escalation. A silent one has no start and is not scored. One that played its own alert is scored and marked.
- Test Sound and Test Speech start the engine too, and are not used during a run.

For each scored alert, write down G, the gap from Presented to the start; the lower bound on the part before the stamp, the row's second less the Presented time, or nothing if that is negative; and the upper bound on the part after it, the start less the row's second. For a rule that speaks, add the previous alert's N, as a pointer to reading H and not as proof.

**Late** is a G of at least 2 s and at least 1 s more than the largest control gap. If a control is late as well, the lateness is not Teams's.

---

## What a result picks

| Result                                                                                                                            | What follows                                                                                               |
| --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| No late alert in 20 scored staged pairs, none among at least 30 scored passive second alerts, and no Presented line without a row | Stop. O3 stands: the instrument is not built, Tasks 3 to 6 are recorded as not built, and Task 7 is built. |
| Any late alert, or a Presented line with no row                                                                                   | Task 3 is built.                                                                                           |
| Controls late as well                                                                                                             | Task 3 is built, and this note records that the lateness is not Teams-specific.                            |
| No start line can be found for the owner's rule                                                                                   | The owner chooses between the Inspector's seconds alone and Task 3.                                        |
| A drawn line close after the Presented line, for an alert whose start is late                                                     | Reading D is ruled out for that alert.                                                                     |
| A watcher line inside a pair's window                                                                                             | A blind-window candidate for that pair, and not a cause.                                                   |

With none late in 20 scored staged pairs, a per-pair rate above 14% is ruled out at 95% confidence, and a one-in-ten fault would have shown at least once 88% of the time. With none late in 30 scored passive second alerts, a per-alert rate above 10% is ruled out. The passive arm can add late alerts but cannot lower the bar the staged arm sets. A result on macOS 27.2 does not refute the sighting on macOS 26.7.1.

---

## Questions for the owner

The answers can settle readings E and F before any code exists. They are not in yet.

1. **At the sighting.** Was SignalLadder's status menu open, one of its dialogs up, or one of its windows being dragged? Was Notification Centre's list open? Where was the pointer, and when did it first move over the alerts? The click on Outlook's alert came about 6 s after the first line. The build lacked `6d84068`, so a menu or dialog of SignalLadder's held open would explain a pause (E). If this cannot be remembered, E and F stay open.
2. **Teams then.** The client, its version, whether message preview was on, the owner's presence, whether Teams was frontmost, whether the display had slept or the screen was locked, and whether a meeting or screen share was on.
3. **The rules and the output.** Does the Teams rule play a sound, speak, or both? Does it, or the rule the controls will use, have a ladder with a repeating tier 3? Was the output Bluetooth? If the Teams rule neither sounds nor speaks there is no start line, and the owner chooses between the Inspector's seconds alone (late when a row's second is 3 s or more after its Presented time) and going straight to Task 3.

---

## What the runs found

No timing run yet. Day 1's check is below.

### Day 1, 2026-10-14: the command on macOS 27.2

macOS 27.2 (26B5101f). The command was run once over the last 12 hours, with the predicate and `awk` above, before the `lifecycle` label was added. Over those hours SignalLadder was the installed 1.0.0 release and then a Developer ID build of `main` at `0b378c0`, whose version line reads "Version 1.0.0, built from 0b378c0 on 14 Oct 2026". The two have the same capture code. No control was posted. A control's start needs a rule that sounds for Script Editor (step 2 of the runs), which the owner sets up, and the 14 control lines already in the log showed the Presented and drawn lines. The file was scored for this section and deleted.

| Label               | Lines | What it showed                                                                                                                                                             |
| ------------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `teams-presented`   | 1     | Read "as alert". It is the one Teams record of the 12 hours, and is set out below.                                                                                         |
| `control-presented` | 14    | Script Editor's banners from the evening before, when the live check was run. Their lines carry neither "as alert" nor "as banner".                                        |
| `other-presented`   | 112   | Other apps. Most lines read "as alert" or "as banner".                                                                                                                     |
| `control-drawn`     | 42    | Three lines for each control, within 31 ms of each other. The first came 1 to 2 ms after its Presented line, for all 14. The poster is named in lower case.                |
| `teams-drawn`       | 0     | None, as below.                                                                                                                                                            |
| `audio-start`       | 42    | Every one reads `Engine@…: start, was running 0`. The engine also writes pause and stop lines, which the `awk` leaves out.                                                 |
| `speech-began`      | 0     | No alert in the app spoke. The line's form, `speech began N ms after it was asked for (voice measured)` or `(voice not yet measured)`, was seen from the test runner only. |
| `attached`          | 4     | No other watcher line, so no `exited`, `lifecycle`, `retrying` or `blind`.                                                                                                 |

**The levels, and how long the lines last.** Every line the command found was at Default level, not Info. SignalLadder's own lines, its engine starts and its watcher lines, reached back about 8 hours, and the same engine lines from the test runner about 12 and a half. usernoted's and Notification Centre's lines reached back about 14 and a half. The evening before had the live check's runs, but whether SignalLadder started its engine in them is not known, so 8 hours is how far its lines reached and not a measured limit. The next morning's read is still to do. Until it is done, the command runs after each staged session, and in the passive arm after each Teams burst and at least every two hours.

**The gap in the `awk`.** The watcher logs a re-attach in two ways: when Notification Centre's process exits (`AXBannerWatcher.swift:206`), and when the workspace reports a lifecycle event for it (`:273`). The command labelled only the first. It now labels the second `lifecycle`, and the plan's copy of the command does the same.

**The night's Teams record.** One Teams Presented line came in the night, during the 1.0.0 release and before this note merged, so it is not part of any run and is not scored. No drawn line for Teams followed it within 60 s, and no start came within 10 s. Its row cannot be checked, since the Inspector keeps the last 50 and many came after. Whether the banner was not drawn, or was drawn without that line, cannot be told from the lines alone. This raises a question for the staged pairs: does the second alert of a stack get a drawn line of its own? Until a pair shows it, the rule for a Presented line with no row stands as written.

**Other apps' alerts, not scored.** Of the 42 starts, 25 had no Presented line in the 10 s before them. 23 of those came 30 s after the start before, which is the spacing of a ladder's repeating tier 3. One came 17.8 s after the start before, and one was the first start of the 12 hours. The other 17 followed another app's Presented line: 15 by 0.068 to 0.119 s, one by 0.442 s and one by 0.889 s. None came 2 s or more after. They are not scored, because they were paired with the nearest Presented line before them and no rows were read. They are a rough sense of this Mac's usual gap on macOS 27.2, and not the controls.

**Still to do before the runs.** The owner's answers to the three questions. A rule that sounds for Script Editor, for the controls. Script Editor set to Alerts. A second Teams sender for the staged arm. The next morning's read.
