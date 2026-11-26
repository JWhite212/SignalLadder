# 1.3: what it is, what was run, and the checks before its tag

> **Status:** written on 2026-11-26 from `main` at a773a46. Everything in 1.3 is built and merged. Nothing here is ticked. The release is not made.

**Mode:** a record and a checklist, not a plan of work. The work was done in pull requests #259 to #265, each of which says what it did and why.

## What 1.3 is

Version 1.2 was built on `main` and never published. On 2026-11-26 the owner chose to release its work with three additions as 1.3.0.

| Part                                                                                                                                   | Where it was planned or decided                                  | Merged as                   |
| -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | --------------------------- |
| The Night watch redesign                                                                                                               | [The M7 plan](2026-11-25-m7-night-watch.md)                      | #242, #244 to #255 and #258 |
| **Add Sound…** in the rule editor, a drop on the sound, **Show Sounds Folder**                                                         | Owner's answers, 2026-11-26                                      | #259                        |
| Conditions on the time of day, the screen lock and how often an app is sending; rules file version 6                                   | Owner's answers, 2026-11-26                                      | #260                        |
| The editor's warning that a locked-screen condition may never match, and the measurement behind it                                     | Owner's answer, 2026-11-26: keep the condition and warn          | #261                        |
| The version set to 1.3.0, and "1.2" in the pages made 1.3                                                                              |                                                                  | #262                        |
| A sound a stopped replace left set aside is put back                                                                                   | Found planning [the sound editor](2026-11-26-m8-sound-editor.md) | #264                        |
| Add Sound reads and checks off the main actor; time conditions follow a change of time zone; a replaced sound is decoded again at once | Found in the audit before release                                | #265                        |

## Owner decisions

Each was the owner's answer to a question put on 2026-11-26.

- **O1. Add Sound has a button, a drop target and Show Sounds Folder, and no remove or rename.** Those stay in the Finder.
- **O2. A time condition is a start, an end and days of the week, in the Mac's own time.** Not named schedules.
- **O3. A send-rate condition is per app, "at least N in the last M minutes".** Not "at most", and not a count of one rule's own matches.
- **O4. The screen-lock condition stays, with a warning in the editor when "locked" is chosen.** It was measured to match nothing on the owner's Mac.
- **O5. The full soak that 1.2 was to have is not needed, and 1.3 is released in its place.** No other bar was named: see [the release bar](../releasing.md#before-any-public-release-the-gono-go-bar).

## What was run

The owner's running copy, each a signed build installed in `/Applications`, with the default `Scripts/verify-live.sh` passing 17 of 17 after each swap:

| From                    | Commit                                    | What it had                                    |
| ----------------------- | ----------------------------------------- | ---------------------------------------------- |
| 2026-11-25 20:50        | `d0d7cbf`, then `ad51f17`, then `c3a388a` | The redesign, as 1.2.0                         |
| 2026-11-26 18:43        | `448c34c`                                 | With Add Sound, the conditions and the warning |
| 2026-11-26, later       | `dd66092`                                 | The same, as 1.3.0                             |
| 2026-11-26, later still | `fe27111`                                 | With #264                                      |

No count of on-call shifts on any of these was recorded here. The commit that is released should be run by the owner before its tag, and the release notes should say for how long.

## What was measured

- **Capture with the screen locked**, 2026-11-26, macOS 27.3, with `signalladder-probe` beside the app: one notification posted with the screen unlocked was captured within 0.1 seconds, and five posted over the next four minutes with it locked were not captured. Whether a Focus was on was not read. Whether they were captured after the unlock was not seen.
- **The new controls are there**, in the running copy at `448c34c`: **Add Sound…**, **Show Sounds Folder**, and **Add Condition on…** with its three items, read by their accessibility titles. Nothing was chosen or added.

Nothing else of 1.3 has been seen in the app.

## Human checks

For the owner, on the build that would be released. A box is ticked only for a check someone did. No test presses a file chooser, hears a sound or locks a screen.

**Add Sound**

- [ ] **Add Sound…** with a file chosen: one each of AIFF, WAV, CAF, MP3 and M4A is added, chosen for the alert, and plays with **Test Sound**.
- [ ] A file dropped on the sound is added the same way.
- [ ] A file that is not audio, a silent one and one over 30 seconds are each refused, with the reason beneath the sound, and nothing is left in the sounds folder, hidden files included (`ls -a`).
- [ ] A file named for a macOS sound is refused.
- [ ] A second file of a name you have asks before replacing, **Cancel** changes nothing, and after **Replace** a rule that names it plays the new one at its next alert.
- [ ] A file kept in iCloud and not on the Mac: the button says **Adding…**, and a test banner sent meanwhile still sets its rule off.
- [ ] **Show Sounds Folder** opens the folder, and makes it on a Mac that has none.

**Conditions**

- [ ] A rule with **Time of Day** matches a test banner inside its stretch and not outside it, and one that runs past midnight matches after midnight on the day after the one chosen.
- [ ] A rule with **How Often the App Is Sending**, at least 3 in 5 minutes: the third banner from one app matches and the first two do not, and a banner from another app in between is not counted.
- [ ] A rule with **Screen Lock** set to _not locked_ matches with the screen unlocked.
- [ ] A rule with **Screen Lock** set to _locked_: with the screen locked for a minute and banners sent, the Inspector afterwards says whether any row is marked _screen locked_. Either answer is a result, and the release notes say which.
- [ ] The Inspector's row says _screen locked_ or _screen lock not read_ when that is so, and nothing of the lock when it was not locked.
- [ ] Each of the three rows with the keyboard alone, and with VoiceOver: every control is reached and named.
- [ ] A rule with one of the three saved from the editor: `rules.json` says `"version": 6`. The 1.1.0 download, opened on that file, says the file needs a newer SignalLadder and runs no rule.

**The redesign**, from [the M7 plan](2026-11-25-m7-night-watch.md): its own checks, and the three flagged modes of the live check (`--escalation`, `--on-call`, `--snooze`), each when off shift.

**The release**

- [ ] The 1.1.0 download replaced by the 1.3.0 one, by the steps in [Updating](../../getting-started.md#updating): Accessibility is still granted with no new prompt, the rules and the sounds are as they were, and the Setup Guide does not open.
- [ ] The DMG on a clean account, by step 5 of [Each release](../releasing.md#each-release).

## Not in 1.3

- The sound editor: [the M8 plan](2026-11-26-m8-sound-editor.md), for 1.4.
- New pictures. The rule editor's pictures in the pages were taken before Add Sound and the conditions, and do not show them.
- Removing or renaming a sound in the app.
