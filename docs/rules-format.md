# Writing rules by hand

Most rules are easiest to make in the rule editor: **Edit Rules…** (⌘E), or **Make a Rule from This…** on a notification in the Inspector. This guide is for the file underneath, which you can also edit yourself. A rule marks the notifications it matches in the Inspector and, if you give it an alert, plays a sound or speaks a line when one arrives. A rule with no alert stays quiet, so you can prove it against real traffic before you trust it to wake you.

## Where the file is

```
~/Library/Application Support/com.jamiewhite.signalladder/rules.json
```

To edit it by hand, use **Open Rules File in Text Editor…** in the menu. If the file does not exist it is created with one example rule, switched off. After saving, choose **Reload Rules** (⌘R).

Apart from creating it when it is missing, SignalLadder writes this file only when you press **Save** in the rule editor: never on its own, never to tidy it, never to replace one that is damaged. When it saves:

- The version it replaces is kept beside it as `rules.previous.json`.
- The file is written in one step, so it is never missing or half-written, even if the Mac loses power mid-save.
- If the file changed since the editor opened it (you edited it by hand, say), the save stops and tells you what changed. You can reload what is on disk, or save anyway; saving anyway keeps the version it replaces as a dated `rules.replaced-….json`.
- It is rewritten in a standard layout (keys sorted, indented), and each rule gains an `"id"`. Your own formatting survives only in `rules.previous.json`.
- It is written at the oldest version that can hold your rules: `4` if a rule escalates, `3` if a rule speaks, `2` if a rule has any other alert, and `1` otherwise.

If the file cannot be read, is from a newer version of SignalLadder, or holds an entry that is not a valid rule, the editor shows why and does not let you save over it: fix it here first.

## The shape

```json
{
  "version": 2,
  "rules": [
    {
      "name": "Weather stays quiet",
      "condition": { "field": "app", "op": "equals", "value": "Weather" },
      "alert": "silent"
    },
    {
      "name": "Prod and incident channels",
      "enabled": true,
      "condition": {
        "or": [
          { "field": "title", "op": "matches", "value": "#prod-*" },
          { "field": "title", "op": "matches", "value": "#incident-*" }
        ]
      },
      "alert": { "sound": "Glass", "gainDB": 6 }
    }
  ]
}
```

| Key         | Required | Meaning                                                                        |
| ----------- | -------- | ------------------------------------------------------------------------------ |
| `version`   | yes      | `1` to `4`. A rule with an alert needs `2`, one that speaks `3`, and one that escalates `4` |
| `name`      | yes      | Shown in the Inspector and menu when the rule matches                          |
| `enabled`   | no       | Defaults to **true**: a rule you wrote runs unless you say otherwise           |
| `id`        | no       | Generated if absent                                                            |
| `condition` | yes      | See [Conditions](#conditions)                                                  |
| `alert`     | no       | What happens on a match. See [Alerts](#alerts). Leave it out and nothing plays |
| `escalation` | no      | What happens after the alert if it is not acknowledged. See [Escalation](#escalation) |

Any other key is an error, not ignored. A misspelt `"alrt"` would otherwise leave a rule quietly silent, and a misspelt `"enabeld": false` would leave it quietly on.

One thing cannot be caught: a key written twice in the same object, such as `"gainDB": 6, "gainDB": 0`. The JSON reader keeps the last one without saying so.

**Order is priority.** The first enabled rule that matches wins, and a notification only ever matches one rule. Put narrow rules above broad ones.

## Conditions

A condition is exactly one of these:

```json
{ "field": "title", "op": "contains", "value": "deploy" }
{ "and": [ condition, condition, ... ] }
{ "or":  [ condition, condition, ... ] }
{ "not": condition }
```

### Fields

Open the Inspector to see what each field actually holds for a given app. That is what it is for.

| Field      | Holds                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------- |
| `app`      | The app's display name, e.g. `Microsoft Teams`. Recovered heuristically from the banner            |
| `title`    | The banner's first line                                                                            |
| `subtitle` | The second line when there is one; empty otherwise                                                 |
| `body`     | The message text                                                                                   |
| `raw`      | Everything the banner said, unparsed. Use it when you are not sure which field something lands in  |
| `subrole`  | The banner's accessibility type, e.g. `AXNotificationCenterBanner` or `AXNotificationCenterAlert`. A persistent alert that arrives while another from the same app is still on screen reads as `AXNotificationCenterAlertStack` |

### Operators

All comparisons ignore case and accents: `microsoft teams` matches `Microsoft Teams`, `equipe` matches `Équipe`.

| `op`        | Matches when the field…                                                                | Example                                                                         |
| ----------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `equals`    | is exactly the value                                                                   | `{"field": "app", "op": "equals", "value": "Weather"}`                          |
| `notEquals` | is anything but the value                                                              | `{"field": "subrole", "op": "notEquals", "value": "AXNotificationCenterAlert"}` |
| `contains`  | contains the value anywhere                                                            | `{"field": "body", "op": "contains", "value": "rollback"}`                      |
| `matches`   | matches the whole field as a pattern: `*` is any run of characters, `?` is exactly one | `{"field": "title", "op": "matches", "value": "#prod-*"}`                       |

`matches` covers the **whole** field: `#prod-*` means "starts with `#prod-`", and `*deploy*` means "contains `deploy`". There is no way to match a literal `*` or `?`. A wildcard never splits a character: `?` is one whole character, so `s?` does not match `ß`, even though `ß` compares equal to `ss` when written out in full.

`equals` with an empty value is allowed and useful: `{"field": "subtitle", "op": "equals", "value": ""}` means "has no subtitle".

## Alerts

```json
"alert": { "sound": "Glass", "gainDB": 6 }
"alert": { "sound": "Glass" }
"alert": { "speak": { "voice": "com.apple.voice.compact.en-GB.Daniel" } }
"alert": { "sound": "Glass", "speak": { "voice": "com.apple.voice.compact.en-GB.Daniel" } }
"alert": "silent"
```

| Alert                       | On a match                                                                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `{"sound": …, "gainDB": …}` | Plays the sound. `gainDB` may be left out for 0                                                                                                              |
| `{"speak": {…}}`            | Speaks a line built from the notification. See [Speech](#speech)                                                                                             |
| `{"sound": …, "speak": {…}}` | Plays the sound, then speaks. The sound never waits for the speech                                                                                          |
| `"silent"`                  | Nothing plays, deliberately. Because the first match wins, a silent rule placed first claims its notifications, so no broader rule below can sound for them |
| _(no `alert` key)_          | Nothing plays, and the Inspector says the rule has no alert, so a rule you have not finished is never mistaken for one you meant to be quiet                 |

### Sounds

A sound is named without its extension, ignoring case. The macOS sounds are always there: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine and Tink.

To use your own, put the file in

```
~/Library/Application Support/com.jamiewhite.signalladder/Sounds/
```

and name it by its file name: `Pager.caf` is `"sound": "Pager"`. AIFF, WAV, CAF, MP3 and M4A all work, up to 30 seconds long. A file of yours with the same name as a macOS sound replaces it.

Sounds are checked when the rules load, not when an alert fires. Each rule's sound is looked up, decoded and measured. A rule whose sound does not exist, cannot be read, is silent or runs over 30 seconds is refused on the spot and listed with the reason, rather than staying silent at the incident it was written for. **Reload Rules** reads the sound files again, so a sound you have replaced is picked up.

### Loudness

Every sound is level-matched: at `gainDB` 0, each one peaks at the same level, however loud or quiet its file is. (A very quiet recording is raised by at most 24 dB, so its own hiss does not become the alert. A file with no audible sound in it at all is refused when the rules load.) `gainDB` adjusts from there, from −40 to +12 dB. Each 6 dB doubles or halves the signal; to most ears, about 10 dB sounds twice as loud. A limiter keeps every setting from clipping.

Sounds play through the Mac's current output, at its volume. One plays at a time: a new alert cuts off one still playing, because two alarms at once are noise.

### Speech

```json
"speak": {
  "voice": "com.apple.voice.compact.en-GB.Daniel",
  "template": "{app}: {title}",
  "rate": 0.5,
  "pitch": 1,
  "gainDB": 0
}
```

| Key        | Required | Meaning                                                                                  |
| ---------- | -------- | ---------------------------------------------------------------------------------------- |
| `voice`    | yes      | An installed voice's identifier. The rule editor's voice picker lists them               |
| `template` | no       | What to say. Defaults to `{app}: {title}`                                                |
| `rate`     | no       | 0 to 1. Defaults to 0.5, the system's normal rate                                        |
| `pitch`    | no       | 0.5 to 2. Defaults to 1                                                                  |
| `gainDB`   | no       | −40 to +12 dB, like a sound's. Beside a sound, the sound's `gainDB` stays outside `speak` |

A rule that speaks needs `"version": 3`, so an older SignalLadder says the file needs a newer version rather than turning the rule away without saying why. The rule editor writes the version for you.

The template's `{app}`, `{title}` and `{body}` are filled from the notification. The default leaves out `{body}`: bodies are often long, and a long recitation is not an alert. Whatever the template, a spoken line stops at 240 characters. Anything else in braces is refused when the rules load, as is a `{` that is never closed.

Speech is level-matched like a sound, so at `gainDB` 0 a spoken alert is about as loud as a sound. Each voice is measured once, in the background, when a rule that uses it loads. Until then it speaks slightly quieter, never louder. A spoken alert usually starts within tens of milliseconds (at most about 130 ms in the recorded trials), because SignalLadder keeps its speech synthesiser ready rather than starting one per alert, which can take seconds.

The line is built from the notification, so it is as private as the notification: it is said aloud and shown in the Inspector, and never written to disk, logged or shown in the menu or the panel. A later tier that speaks builds its line the same way, from the notification SignalLadder keeps in memory while the escalation is going. The log records only how long each spoken alert took to start, and a fixed sentence when one produced no audio or did not finish in time.

To add voices, use **More Voices…** in the rule editor, which opens System Settings › Accessibility › Read & Speak (Spoken Content before macOS 26). Siri voices cannot be used by other apps, so they are never offered. A rule naming a voice that has since been removed is reported when the rules load.

### What the app records

Each matched notification in the Inspector says what was done:

| Line                                                                    | Means                                                                           |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| _Played Glass (+6 dB)_                                                  | The sound played, at the gain the rule asked for. At 0 dB the gain is not shown |
| _Played Glass — but the Mac's sound output was muted or at zero volume_ | It played, and the Mac reported that nothing could be heard                     |
| _Silent by rule_                                                        | The rule's alert is `"silent"`                                                  |
| _Silent — this rule has no alert_                                       | The rule has no `alert` key                                                     |
| _Could not play: …_                                                     | A sound was meant to play and did not, and why                                  |
| _Spoke (Daniel)_                                                        | The line was spoken in that voice. The Inspector also shows what was said       |
| _Played Glass and spoke (Daniel)_                                       | Both parts of a sound-and-speech alert happened                                 |
| _Could not speak: …_                                                    | A line was meant to be spoken and was not, and why                              |
| _Played Glass, but could not speak: …_                                  | The sound played; the speech after it did not                                   |
| _Spoke (Daniel), but could not play: …_                                 | The speech was said; the sound before it did not play                           |

"Played" and "spoke" mean the app did it, not that you heard it. The app knows only whether the output reported itself muted or at zero volume.

A sound that could not play says why. Problems with the file itself are caught when the rules load, so at the moment of an alert this is almost always that the file `was not found` because it was removed since, or that `the audio engine failed`.

The menu shows the last match with the same wording. An alert that could not play or speak, in whole or in part, also turns the status icon to its warning state and keeps its own ⚠︎ line in the menu until a later alert plays or speaks in full. A quieter match afterwards does not hide it, and reloading rules does not clear it: a file can exist, pass the check at load, and still fail to play. While any enabled rule has a sound or speaks, the menu also warns whenever the Mac's output is muted.

## Escalation

An alert sounds once. A rule can also escalate: its own alert is tier 1, and up to three more tiers follow it, each optional. Tier 2 shows a panel, tier 3 repeats an alert, and tier 4 plays a final alert or runs a Shortcut. They go on until you [acknowledge](#acknowledging) the escalation. The rule editor sets one up from four presets or step by step ([In the rule editor](#in-the-rule-editor)), and the file below is what it writes.

```json
"alert": "silent",
"escalation": {
  "tier2": { "delaySeconds": 10 },
  "tier3": { "action": { "sound": "Hero" }, "intervalSeconds": 30, "maxRepeats": 20, "maxDurationSeconds": 600 },
  "tier4": { "afterSeconds": 120, "shortcut": "Page the on-call phone" }
}
```

| Key                        | Required    | Meaning                                                                                              |
| -------------------------- | ----------- | ---------------------------------------------------------------------------------------------------- |
| `tier2.delaySeconds`       | no          | Seconds after the match before a panel appears on screen. Defaults to 10                             |
| `tier3.action`             | yes         | The alert to repeat, in the same shape as `alert`. It cannot be `"silent"`                           |
| `tier3.intervalSeconds`    | no          | Seconds between repeats. The first comes this long after the match. Defaults to 30                   |
| `tier3.maxRepeats`         | no          | The most times it repeats. Defaults to 20. `null` means no limit                                     |
| `tier3.maxDurationSeconds` | no          | How long it keeps repeating, counted from the match, in seconds. Defaults to 600. `null` means no limit |
| `tier4.afterSeconds`       | no          | Seconds after the match before the final alert. Defaults to 120                                      |
| `tier4.action`             | one of them | A final alert, in the same shape as `alert`. It cannot be `"silent"`                                 |
| `tier4.shortcut`           | one of them | The name of a Shortcut to run instead. See [Shortcuts](#shortcuts)                                   |

Every delay counts from the match, not from the tier before it, so tier 4 does not wait for tier 3's repeats to end. Repeats stop at whichever cap is reached first, and a `maxDurationSeconds` shorter than one interval allows no repeat at all. When the repeats stop, the escalation stays listed until you acknowledge it, and tier 4 still runs if its time has not come.

**A cap you leave out is the default, never no limit.** A repeat you forgot to limit stops after 20 repeats or ten minutes. To remove a cap, write `null` for it, which is the only way to say it. A `null` on one cap leaves the other in force, so to repeat with no limit at all, write `null` for both. When the rule editor saves, it writes every key, `null` included, so the file says exactly what the rule does.

A rule that escalates needs `"version": 4`, and an `alert` of its own, even `"silent"`: without one, nothing would announce the match until a later tier fires. A silent alert is fine, and the ladder still starts. An escalation with no tiers is refused too.

### Acknowledging

Acknowledging an escalation stops every tier still to come for it: no more repeats, no final alert, and a Shortcut that has not started will not. A Shortcut already running is not stopped. There are three ways:

- **The panel.** Each row has an **Acknowledge** button, which acknowledges that escalation.
- **The menu.** While anything is listed, its top item is **Acknowledge** when one escalation is listed, and **Acknowledge All (3)** when there are more. It acknowledges every one listed.
- **The hotkey.** ⌃⌥⌘A, from any app, acknowledges all of them. It does nothing when nothing is listed. If SignalLadder cannot register it, it logs the status code (never any text), and the menu and the panel still work. On macOS 26.7 registering it needed no permission prompt.

When you acknowledge the last escalation still going, a sound that is playing stops, but only if the last alert to play was an escalation's, so acknowledging never cuts off an ordinary rule's alert. While others are still going, a sound that is playing finishes.

### What you see

**The panel** is a borderless window that appears over every app and every Space, full-screen apps included, in the top right corner of the screen your pointer is on. Over full-screen apps and other Spaces, that was seen in a test program on macOS 26.7, and has not yet been checked in the app itself. It does not take keyboard focus from the app in front. It is headed _SignalLadder: waiting for you to acknowledge_ and has one row per escalation, newest first, each with its own **Acknowledge** button:

```
On-call mentions — since 10:42 — tier 2
On-call mentions — since 10:42 — tier 3, repeat 3 of 20
On-call mentions — since 10:42 — tier 4, repeat 20 of 20, no longer repeating, its Shortcut failed
On-call mentions — since 10:42 — missed while asleep
```

A row names the rule and how far it has climbed, and never what the notification said: the panel can be seen by anyone who can see your screen. Without a limit on repeats, a row reads _repeat 3_. The panel appears when a rule's tier 2 fires, so a ladder with no tier 2 has no panel, and the menu still lists it. It shows the six newest rows, and counts any more on a last line that says how to acknowledge them all. It stays until every row on it is acknowledged.

**The menu.** While anything is listed, **Acknowledge** heads the menu. Beneath it come the lines that apply, the ⚠︎ line first: _⚠︎ On-call mentions at 10:44: the Shortcut "Page me" is not installed_ for a Shortcut that did not run, then _2 alerts escalating_ and _1 alert missed while asleep_. The ⚠︎ line stays until that same Shortcut starts again, even with nothing listed, and then it heads the menu on its own. A later escalation can start it, or **Test Shortcut** in the rule editor can. A different Shortcut starting does not clear it, nor does reloading the rules, nor does changing the rule to name another Shortcut. Quitting SignalLadder does, because the line is held in memory. See [Shortcuts](#shortcuts). The menu never shows what a notification said.

**The icon.** While an alert is escalating, the menu-bar icon alternates every 0.8 seconds between a bell with sound waves and a filled version of it. A problem's slashed bell takes precedence.

**A repeat or a final alert that could not sound** is reported exactly like a first alert that could not: a ⚠︎ line in the menu and the slashed bell, until a later alert plays. A Shortcut that did not run is held apart, so a repeat that plays later does not clear it.

**The Inspector.** A row whose rule escalated gains a line under its alert line, such as:

- _Escalating — reached tier 3 — repeated 3 of 20_
- _Acknowledged at 10:45:12 — reached tier 3 — repeated 4 of 20_
- _Escalating, no longer repeating since 10:52:30 — reached tier 3 — repeated 20 of 20_
- _Missed while asleep, found on waking at 03:12:44 — reached tier 2_, with _, seen at 07:30:01_ once you have acknowledged it

It goes on to say what the last tier did: _final alert: Played Hero_, _Shortcut “Page me” started_, or _Shortcut did not run: the Shortcut "Page me" is not installed_. When the latest repeat could not sound, or sounded into a muted output, it adds _last repeat: Could not play: …_. The line is orange when something in it needs your attention. Like the alert line, it never shows what was spoken.

### Missed while asleep

If the Mac sleeps for more than 5 minutes while an escalation is going, the escalation ends as _missed while asleep_ when the Mac wakes. No later tier fires: after hours asleep, a repeat or a final alert would be stale. It stays on the menu, and on the panel where its tier 2 had appeared, until you acknowledge it. A shorter sleep resumes the ladder.

SignalLadder works out how long the Mac slept as the time that passed on the clock, less the time the Mac was awake. Apple documents that the awake time does not count sleep, but this has not yet been checked on a Mac that sleeps. A clock set forward by more than 5 minutes would look the same.

### Keeping the Mac awake

While any tier is still to fire, SignalLadder asks macOS not to let the Mac sleep on its own, and lets go once none is. An escalation that is only still listed, with nothing left to fire, does not hold it. It does not keep the display awake. That request has not yet been tested on a Mac that can sleep.

### Shortcuts

Tier 4 runs a Shortcut with `/usr/bin/shortcuts run`. The Shortcut is given a file, `input.json`, that holds exactly four fields of the notification, and nothing else: no raw text, no time and no banner type.

```json
{
  "appNameGuess": "Example Chat",
  "title": "Alex Example mentioned you",
  "subtitle": "",
  "body": "Placeholder body text"
}
```

The file is the one place SignalLadder itself writes notification text to disk. It sits in a folder of its own that only you can open, inside `com.jamiewhite.signalladder.shortcut-input` in the Mac's temporary folder, and only you can read or write the file. It is deleted the moment the Shortcut's process ends, however long that takes. Anything a crash or a quit left behind is removed when SignalLadder starts and when it quits. What the Shortcut then does with the text is up to the Shortcut you wrote.

**Test Shortcut** in the rule editor runs the Shortcut the same way, and for real: a Shortcut that messages someone will message them. It writes the same file, but with a made-up notification whose four fields say plainly that it is a test: the app name is _SignalLadder (test)_ and the title is _TEST: not a real notification_. No notification you received reaches it. Your Shortcut can tell a test from a page by those fields.

SignalLadder never waits for a Shortcut. It counts one as started if it is still running after 1 second, or if it exits without an error. If it stops with an error within that second, the run is reported as failed, in SignalLadder's own words, such as _the Shortcut "Page me" is not installed_ or _the Shortcut "Page me" stopped with exit code 1_. A missing Shortcut is recognised from the English wording of the `shortcuts` command, so on a Mac set to another language it is reported by its exit code instead. What the Shortcut itself printed is never shown or logged. A failure is not retried, and one after the first second is not reported.

A Shortcut's name is checked when the rules load, against the Shortcuts app's own list, and must match a Shortcut there exactly, including capitals, spaces and punctuation. A rule naming one that is not there is not refused. It stays in effect, first alert and repeats included, and tier 4 still tries the name when it fires. The check says so where you will see it, so a misspelt name is found now rather than when it is needed:

- The menu shows _⚠︎ 1 Shortcut name was not found — the rule using it is still in effect_ under the rules summary, with a line for each rule beneath it, such as _Rule "On-call mentions": its final alert's Shortcut "Page me" was not found in the Shortcuts app — …_.
- The status icon turns to the slashed bell, as it does for a problem.
- The rule editor says so beside the name field, as advice and not as a problem.

If the name really is wrong, the run fails when it is needed, and the failure is held as _Shortcut did not run_ (see [What you see](#what-you-see)). The check is exact because whether `shortcuts run` forgives a difference in capitals was not measured. So it can warn about a name that would have worked, which is why the warning says the rule is still in effect. A Shortcut you make afterwards is found when you choose **Reload Rules** (⌘R) or **Save**, which also updates the menu, and in the rule editor when you press **Test Shortcut**, which lists them again for the editor only and leaves the menu's line where it is. The Shortcuts are listed, with `/usr/bin/shortcuts list`, only when a rule names one, and the list is never logged. If it cannot be read within a second, the name is not checked, nothing in the menu says so, and SignalLadder finds out whether the Shortcut exists by running it. A blank name is always refused, and the whole rule is off until it is fixed.

A held _Shortcut did not run_ is cleared only by a start of that Shortcut, with the same name to the letter, capitals and spaces included: _Page Me_ is not _Page me_. Another Shortcut starting is no evidence about it, so it does not clear it, and neither does reloading the rules. A successful **Test Shortcut** of that name clears it, and so does a later escalation that starts it. If you fixed the failure by changing the name in the rule, the failure was recorded under the old name, so testing the new name does not clear it. The ⚠︎ line and the slashed bell stay until the old name starts again, or until you quit SignalLadder. A record of a page that did not reach your phone goes only with a start, or with a quit.

`/usr/bin/shortcuts` is the only other program SignalLadder runs, and only for a Shortcut that a rule names, in the file or in the rule editor: to list the Shortcuts, to run one as a rule's last step, and to run one when you press **Test Shortcut**.

### In the rule editor

The editor shows and edits a rule's ladder. Under the first alert, in **Then**, **If I don't acknowledge** is a choice of four:

| Choice      | The ladder it writes                                                                                                   |
| ----------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Off**     | None. Nothing happens after the first alert, and the rule has no `escalation` key                                      |
| **Gentle**  | Tier 2 only: after 10 seconds a panel stays on screen until you acknowledge it                                         |
| **On call** | The defaults above: the panel after 10 seconds, then the first alert's sound again every 30 seconds, up to 20 times or 10 minutes |
| **Wake me** | The panel after 5 seconds, then the same every 15 seconds, with no limit on repeats and no time limit, until you acknowledge it |

A sentence under the choice says what the ladder does, in words, whatever the ladder is. For Wake me, and for any repeat with neither limit, it adds that the repeat keeps sounding, and keeps the Mac awake, until you acknowledge it. Those are the editor's own words. The part about the Mac is a request to macOS that has not yet been tested on a Mac that can sleep: see [Keeping the Mac awake](#keeping-the-mac-awake).

A preset is only a quick way to fill in the ladder. The file always holds the explicit ladder, written as above, and never a preset's name. The editor works out which preset a ladder is from its numbers, and ignores which alert the repeat plays and whether tier 4 is there, so choosing another sound or adding a Shortcut does not turn **On call** into **Custom**. Any other ladder shows as **Custom**, which is offered only while the ladder is custom or you have set a custom one aside. A preset keeps a repeat you have already chosen. Failing that, it repeats the first alert's sound without its speech, or its speech if the alert only speaks, or the default sound at 0 dB if the first alert is silent. It never adds a Shortcut, and choosing one leaves a Shortcut you have added where it was. Choosing a preset is not offered while the rule has no first alert, because it would either make a rule the loader refuses or choose Silent for you. Choose what plays first, and Silent is fine.

**Customise…** holds every control of tiers 2 to 4. It starts open only when the ladder is Custom. Each tier has a switch:

- **Tier 2** has its delay.
- **Tier 3** has the alert it repeats, a sound or speech, with **Test Sound** or **Test Speech**, and the interval and the two limits, each with a **No limit** box.
- **Tier 4** has its delay and a choice of **Alert** or **Shortcut**. A Shortcut has its name, **Test Shortcut** and the result of the test.

Delays and intervals are typed in seconds, with a caption in minutes once they reach a minute. What you type is written only when you edit it: a value you did not touch is never rewritten, even one the controls would not write, such as an interval of 0 from a hand-written file, which the editor shows as it is and lists as a problem. Switching a tier off, or a limit to **No limit**, keeps what it held, so switching it back on restores your numbers and not defaults. That is remembered while the rule is selected and the editor is open, and is not saved.

**Off** removes the ladder at once, and the sentence says how to bring it back: a preset, or **Custom** if it was a custom ladder. When the ladder holds a Shortcut, **Off** asks first: the sentence becomes _Remove this ladder, including the Shortcut “Page me”?_, with **Remove** and **Keep** beneath it, and the choice stays where it was until you answer. It is not a dialog. The phone page is the alert that matters most, and a Shortcut's name is easy to lose. **Remove** sets the whole ladder aside as the Custom ladder, so choosing **Custom** brings it back with its Shortcut.

**Test Shortcut** runs the named Shortcut for real, with a test notification (see [Shortcuts](#shortcuts)), and shows beside the button _Started “Page me”_ or the reason it did not start. It tests the name in the field, saved or not. It is not offered while a test is running or the name is blank. A start clears a held _Shortcut did not run_ of the same name and of no other. A test that fails is shown beside the button and never held in the menu, since it may be a typo in a draft you are still editing.

A ladder's problems are listed under the rule, as for any other, in the loader's words, which use file terms such as `tier3` and `null`. A ladder the editor cannot read at all, such as a misspelt key or a tier 4 with neither an action nor a Shortcut, makes the editor open read-only, with the reason, as any rule it cannot read does. To change that ladder, edit `rules.json` (**Open Rules File in Text Editor…**) and choose **Reload Rules** (⌘R).

**A file that declares too old a version.** If `rules.json` says `"version": 3` and holds a ladder, the loader refuses that rule, and the editor says the same under it, in the loader's words. The same holds for an alert in a `"version": 1` file and for speech in a `"version": 2` file. **Save** is available although you changed nothing, because without it the rule could not be fixed from here. The bar reads _rules.json declares version 3 but holds a rule that needs 4, so that rule is not running — Save writes version 4 and puts it into effect_. For a rule that is switched on, and for a rule below it, the dry-run says _Not in effect until you save_. Once the rule is edited, or the file saved, the problem goes with its cause.

What the controls decide and say is tested. The controls were drawn and driven in a test program outside the app, and have since been seen in SignalLadder itself, but their live checks are still to do, so read what they write in `rules.json` the first time you use them.

## Muting the source app

An alert is only useful if it is the app's only voice. Until Teams' own notification sound is off, every Teams alert plays on top of Teams' ping.

Whenever an enabled rule has a sound or speaks, the menu lists the apps it reaches: every app such a rule names with `app equals`, plus any app that has set one off since SignalLadder started. The item is titled with the apps still to do, _⚠︎ Not confirmed muted: Microsoft Teams_. For each app:

1. **Open Notification Settings for …** goes straight to that app in System Settings. If SignalLadder cannot find the app, or finds two apps with that name, it shows the name to look for and opens the Notifications list instead.
2. Turn off the app's notification sound there.
3. Back in the menu, choose **I've Turned Its Sound Off**.

Nothing can check that last step. macOS keeps notification settings where other apps cannot read them. So the tick records your word, and the menu calls it that: _confirmed muted_, not _muted_. If you ever hear two sounds for one notification, the Inspector row shows which one was SignalLadder's.

The same menu covers **Do Not Disturb** and other Focus modes. Banners are not drawn while one is on, so nothing can be captured. Check whether one turns on when your screen locks.

## When something is wrong

A broken rule never silences the others. The menu shows a warning, the status icon changes, and each problem is listed by position and name:

```
⚠︎ Rules: 2 active — 1 could not be used
    Rule 3 ("Typo"): Cannot initialize Operator from invalid String value startsWith at rules[2].condition.op
```

| Message                                                          | Means                                                                                               |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `not valid JSON: …`                                              | A syntax error; the detail includes the line and column. **No rules are active** until it is fixed  |
| `missing "op" at rules[0].condition.and[1]`                      | That condition has no `op` key                                                                      |
| `a condition needs exactly one of "and", "or", "not" or "field"` | An object mixes two kinds of condition, or is neither                                               |
| `an "and" group is empty, so it would match everything`          | Rejected: a half-written rule would fire on every notification                                      |
| `an "or" group is empty, so it could never match`                | Rejected: the rule could never fire                                                                 |
| `"body contains" has an empty value`                             | Rejected: an empty `contains` or `matches` never does what was meant                                |
| `it has no name`                                                 | Rejected: nothing could say which rule matched                                                      |
| `unknown key "alrt" in a rule — expected …`                      | A misspelt or unsupported key. Rejected rather than ignored                                         |
| `unknown key "afterSeconds" in "tier2" — expected …`             | Tier 2's key is `delaySeconds`. `afterSeconds` is tier 4's                                          |
| `alerts need "version": 2 — …`                                   | The file says `"version": 1` and this rule has an alert. Change the version to `2`, or press **Save** in the rule editor, which writes the version the rules need |
| `sound "Glas" was not found — available: …`                      | No sound of that name, in either the macOS sounds or your Sounds folder                             |
| `sound "Pager" could not be read: …`                             | The file is there but is not audio SignalLadder can decode                                          |
| `sound "Pager" is silent`                                        | The file has nothing audible in it                                                                  |
| `sound "Pager" is longer than 30 seconds`                        | An alert is a sound, not a recording. Trim it                                                       |
| `gainDB 20 is outside -40…+12 dB`                                | Rejected rather than clamped: a rule should play at the level you read in it                        |
| `its alert names no sound`                                       | `"sound": ""`                                                                                       |
| `an alert is "silent", {"sound": …} or {"speak": …} — found "loud"` | The only word an alert can be is `"silent"`                                                      |
| `an alert needs "sound", "speak" or both`                        | The alert object has neither                                                                        |
| `"gainDB" sets a sound's level, and this alert has no sound — …` | A spoken alert's gain goes inside `"speak"`                                                         |
| `speech needs "version": 3 — …`                                  | The file says `"version": 1` or `2` and this rule speaks. Change the version to `3`, or press **Save** in the rule editor |
| `voice "…" is not installed — …`                                 | Choose another voice in the rule editor, or add it in System Settings                               |
| `its spoken alert names no voice`                                | `"voice": ""`                                                                                       |
| `its spoken template is empty`                                   | `"template": ""`                                                                                    |
| `its spoken template has {sender}, which is not a placeholder — …` | Only `{app}`, `{title}` and `{body}` are filled in                                                |
| `its spoken template has a "{" that is never closed`             | Most likely a placeholder missing its `}`                                                           |
| `speech rate 1.5 is outside 0…1`                                 | Rate runs from 0 to 1; pitch from 0.5 to 2                                                          |
| `escalation needs "version": 4 — …`                              | The file says a lower version and this rule escalates. Change the version to `4`, or press **Save** in the rule editor |
| `it has an escalation but no alert — …`                          | Give the rule an `alert`, even `"silent"`                                                          |
| `its escalation has no tiers, so it would start and never climb — …` | `"escalation": {}`                                                                             |
| `delaySeconds in "tier2" must be more than 0, found 0`           | Every delay and interval must be more than 0                                                        |
| `maxRepeats in "tier3" must be at least 1, found 0 — …`          | A cap must be more than 0, and so must `maxDurationSeconds`. Write `null` for no limit             |
| `its repeat is silent, so it would repeat nothing — …`           | A repeat must sound or speak. To have no repeat, leave `"tier3"` out                              |
| `its final alert is silent, so it would do nothing — …`          | The same for tier 4                                                                                 |
| `"tier4" needs "action" or "shortcut" at …`                      | Tier 4 does one or the other: give it exactly one                                                   |
| `"tier4" has both "action" and "shortcut" — it does one or the other at …` | Remove one of them                                                                    |
| `missing "action" at rules[0].escalation.tier3`                  | A repeat needs the alert it repeats                                                                 |
| `maxRepeats must be a whole number, or null for no limit — found 2.5 at …` | A number of repeats has no fraction                                                       |
| `its final alert names no Shortcut`                              | `"shortcut": ""`                                                                                    |
| `its final alert's Shortcut "Page me" was not found in the Shortcuts app — …` | A warning, not a refusal: no Shortcut has exactly that name, and the rule stays in effect. The menu lists it as `Rule "On-call mentions": …` under a ⚠︎ line. Check the spelling and capitals in the Shortcuts app, and press **Test Shortcut** in the rule editor |
| `its repeat's sound "Glas" was not found — …`                    | A later tier's alert is checked like the first, and the message says which tier. So are its voice and levels |
| `Rules file needs a newer SignalLadder (format 5)`               | The file was written by a newer build. Nothing is loaded rather than misread                        |

## Testing a rule before you trust it

**In the rule editor**, every rule is tried as you edit it on the notifications SignalLadder is holding in memory, up to the last 50. Under the rule you see:

- _In this draft: matches 3 of the last 50 notifications_, and which ones.
- Any that a rule higher in the list would take first (first match wins), with **Move Above** to put this rule ahead of it.
- Whether any of it is in effect yet: _Not in effect until you save_, _this rule is switched off_, or _this rule has problems_.

**Test Sound** plays the rule's sound exactly as the alert would, at its gain. It never plays over a real alert, and it is not recorded anywhere.

**Test Shortcut**, in tier 4 of a ladder, really runs the Shortcut you named, with a test notification, so that you find out before an incident whether its name is right. See [In the rule editor](#in-the-rule-editor).

**By hand**:

1. Let some real notifications arrive, or open the Inspector (⌘I) to see what is already there.
2. Write or edit a rule and save.
3. **Reload Rules** (⌘R).

Every notification already in the Inspector is re-checked against the new rules. The menu shows **Current rules match _n_ of the last _m_**, and each row whose verdict changed shows a blue line: _Current rules would match …_ or _Current rules would match nothing_.

That blue line is a preview. The line above it still says what actually happened when the notification arrived. A preview never rewrites the record, and it never plays anything or starts a ladder: only a match on arrival sets off an alert.

To try a sound safely, write the rule without an `alert` first and watch what it matches. Add the alert once the matches are right.
