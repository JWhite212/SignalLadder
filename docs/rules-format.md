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

The line is built from the notification, so it is as private as the notification: it is said aloud and shown in the Inspector, and never written to disk, logged or shown in the menu. The log records only how long each spoken alert took to start, and a fixed sentence when one produced no audio or did not finish in time.

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

An alert sounds once. A rule can also escalate: after the alert come up to three more tiers, each optional, and acknowledging the escalation stops those still to come.

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
| `tier3.intervalSeconds`    | no          | Seconds between repeats. Defaults to 30                                                              |
| `tier3.maxRepeats`         | no          | The most times it repeats. Defaults to 20. `null` means no limit                                     |
| `tier3.maxDurationSeconds` | no          | How long it keeps repeating, in seconds. Defaults to 600. `null` means no limit                      |
| `tier4.afterSeconds`       | no          | Seconds after the match before the final alert. Defaults to 120                                      |
| `tier4.action`             | one of them | A final alert, in the same shape as `alert`. It cannot be `"silent"`                                 |
| `tier4.shortcut`           | one of them | The name of a Shortcut to run instead                                                                |

Every delay counts from the match, not from the tier before it, so tier 4 does not wait for tier 3's repeats to end. Repeats stop at whichever cap is reached first.

**A cap you leave out is the default, never no limit.** A repeat you forgot to limit stops after 20 repeats or ten minutes. To remove a cap, write `null` for it, which is the only way to say it. A `null` on one cap leaves the other in force, so to repeat with no limit at all, write `null` for both. When the rule editor saves, it writes every key, `null` included, so the file says exactly what the rule does.

A rule that escalates needs `"version": 4`, and an `alert` of its own, even `"silent"`: without one, nothing would announce the match until a later tier fires. An escalation with no tiers is refused too.

A Shortcut's name is not checked when the rules load: SignalLadder finds out whether it exists by running it. Only a blank name is refused.

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
| `alerts need "version": 2 — …`                                   | The file says `"version": 1` and this rule has an alert. Change the version to `2`                  |
| `sound "Glas" was not found — available: …`                      | No sound of that name, in either the macOS sounds or your Sounds folder                             |
| `sound "Pager" could not be read: …`                             | The file is there but is not audio SignalLadder can decode                                          |
| `sound "Pager" is silent`                                        | The file has nothing audible in it                                                                  |
| `sound "Pager" is longer than 30 seconds`                        | An alert is a sound, not a recording. Trim it                                                       |
| `gainDB 20 is outside -40…+12 dB`                                | Rejected rather than clamped: a rule should play at the level you read in it                        |
| `its alert names no sound`                                       | `"sound": ""`                                                                                       |
| `an alert is "silent", {"sound": …} or {"speak": …} — found "loud"` | The only word an alert can be is `"silent"`                                                      |
| `an alert needs "sound", "speak" or both`                        | The alert object has neither                                                                        |
| `"gainDB" sets a sound's level, and this alert has no sound — …` | A spoken alert's gain goes inside `"speak"`                                                         |
| `speech needs "version": 3 — …`                                  | The file says `"version": 1` or `2` and this rule speaks. Change the version to `3`                 |
| `voice "…" is not installed — …`                                 | Choose another voice in the rule editor, or add it in System Settings                               |
| `its spoken alert names no voice`                                | `"voice": ""`                                                                                       |
| `its spoken template is empty`                                   | `"template": ""`                                                                                    |
| `its spoken template has {sender}, which is not a placeholder — …` | Only `{app}`, `{title}` and `{body}` are filled in                                                |
| `its spoken template has a "{" that is never closed`             | Most likely a placeholder missing its `}`                                                           |
| `speech rate 1.5 is outside 0…1`                                 | Rate runs from 0 to 1; pitch from 0.5 to 2                                                          |
| `escalation needs "version": 4 — …`                              | The file says a lower version and this rule escalates. Change the version to `4`                    |
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
| `its repeat's sound "Glas" was not found — …`                    | A later tier's alert is checked like the first, and the message says which tier. So are its voice and levels |
| `Rules file needs a newer SignalLadder (format 5)`               | The file was written by a newer build. Nothing is loaded rather than misread                        |

## Testing a rule before you trust it

**In the rule editor**, every rule is tried as you edit it on the notifications SignalLadder is holding in memory, up to the last 50. Under the rule you see:

- _In this draft: matches 3 of the last 50 notifications_, and which ones.
- Any that a rule higher in the list would take first (first match wins), with **Move Above** to put this rule ahead of it.
- Whether any of it is in effect yet: _Not in effect until you save_, _this rule is switched off_, or _this rule has problems_.

**Test Sound** plays the rule's sound exactly as the alert would, at its gain. It never plays over a real alert, and it is not recorded anywhere.

**By hand**:

1. Let some real notifications arrive, or open the Inspector (⌘I) to see what is already there.
2. Write or edit a rule and save.
3. **Reload Rules** (⌘R).

Every notification already in the Inspector is re-checked against the new rules. The menu shows **Current rules match _n_ of the last _m_**, and each row whose verdict changed shows a blue line: _Current rules would match …_ or _Current rules would match nothing_.

That blue line is a preview. The line above it still says what actually happened when the notification arrived. A preview never rewrites the record, and it never plays anything: only a match on arrival sets off an alert.

To try a sound safely, write the rule without an `alert` first and watch what it matches. Add the alert once the matches are right.
