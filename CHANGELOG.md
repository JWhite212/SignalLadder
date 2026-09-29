# Changelog

Notable changes to SignalLadder are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

SignalLadder has not made a tagged release yet; the app reports version 0.1.0. Until the first release, the sections below are development milestones, newest first, dated when the work reached the `main` branch. When 0.1.0 is released they will be folded into a single entry.

## Unreleased

### Added
- The project is released under the GNU General Public License v3.0.
- A user guide in [`docs/`](docs/README.md): getting started, privacy and permissions, troubleshooting, and how the app works. A new README, contributing guide, security policy, code of conduct, issue forms and continuous integration.

### Fixed
- A notification that arrives while another banner is still on screen is now captured. Previously the newer banner replaced the older one without any event SignalLadder listened for, so during a burst of alerts only the first was heard. Each banner is still read only once, however many times macOS redraws it. ([#12](https://github.com/JWhite212/SignalLadder/pull/12))
- Opening Notification Centre no longer replays notifications a minute old or more, so a rule no longer sounds again when you open the list to read something. Items under a minute old can still be replayed. ([#12](https://github.com/JWhite212/SignalLadder/pull/12))
- On macOS 15, a spoken alert whose voice is not installed is reported as not installed. It used to speak in the default voice instead. ([#14](https://github.com/JWhite212/SignalLadder/pull/14))
- The health line re-checks as soon as whatever blocked a self-test clears (Accessibility granted again, or SignalLadder's own banners switched back on) instead of waiting for the next scheduled test. ([#12](https://github.com/JWhite212/SignalLadder/pull/12))
- A banner read back with less text than before, because a read timed out, is no longer mistaken for a new notification. ([#12](https://github.com/JWhite212/SignalLadder/pull/12))

## M3d: alerts that speak - 2026-09-25

### Added
- A rule's alert can speak a line aloud, instead of or after a sound. ([#11](https://github.com/JWhite212/SignalLadder/pull/11))
- The line comes from a template using `{app}`, `{title}` and `{body}`; the default is `{app}: {title}`. A spoken line stops at 240 characters.
- Each spoken alert has its own voice, rate (0 to 1), pitch (0.5 to 2) and gain. The voice picker lists the voices installed on the Mac, with **More Voices…** to add others. Siri voices cannot be used by other apps, so they are never offered.
- Speech is level-matched per voice, so a spoken alert at 0 dB is about as loud as a sound at 0 dB.
- The rule editor has a Speech alert, an **Also speak it** option on sounds, and **Test Speech**, which reads a made-up notification rather than a real one.
- The Inspector shows exactly what was said. The menu never does, so message text is not on show at a glance.
- A rule naming a voice that is not installed is reported, by name, when the rules load.

### Changed
- A rules file with a spoken alert is written as `"version": 3`, so an older build refuses it rather than silently dropping the speech.
- A new alert cuts off one still playing, including its speech, so two alarms never sound together.
- Switching a rule's alert to another kind and back restores what you had set, rather than a default.

## M3 follow-ups - 2026-09-25

### Fixed
- Cut, copy, paste, select all and undo work in the rule editor's text fields. ([#6](https://github.com/JWhite212/SignalLadder/pull/6))
- The health line says how old its evidence is (_Working — verified 3 min ago_), and reads _Unverified — last verified …_ once a self-test is overdue, instead of claiming "verified" for as long as the app runs. A second self-test runs two minutes after launch. ([#8](https://github.com/JWhite212/SignalLadder/pull/8))
- When a save is refused because the file changed on disk, a rule renamed by hand is reported as a rename rather than as one rule removed and another added. ([#9](https://github.com/JWhite212/SignalLadder/pull/9))

## M3c: the rule editor - 2026-09-25

### Added
- A rule editor, **Edit Rules…** (⌘E). Rules can be added, duplicated, deleted, switched on and off, and dragged into priority order: the first enabled match wins. ([#4](https://github.com/JWhite212/SignalLadder/pull/4))
- A condition builder for nested _all of_, _any of_ and _not_ groups.
- A live dry-run that shows which of the notifications in memory a rule would match, which rule above it takes others first, and **Move Above** to fix that. It always says whether what you see is in effect yet.
- **Make a Rule from This…** on every Inspector row, and **Add Condition from This Notification**, so a rule starts from a real notification.
- **Test Sound** plays a rule's sound at its gain. It never interrupts a real alert.
- Safe saving: the file is written in one step, the version it replaces is kept as `rules.previous.json`, and a save is refused if the file changed on disk since it was read, with **Reload from Disk**, **Save Anyway** and **Cancel** offered. Save Anyway keeps a dated copy of what it replaces.
- A rules file the editor cannot fully represent opens read-only, with the reason, so nothing in it is lost.
- Closing the editor or quitting with unsaved changes asks whether to save.

### Changed
- **Open Rules File in Text Editor…** replaces the earlier menu item. SignalLadder now writes `rules.json`, but only when you press Save.

## M3b: the first alert you can hear - 2026-09-25

### Added
- A rule can have an alert: a sound, or `"silent"`, which claims a notification and keeps it quiet. Sounds are the macOS sounds or your own files in `~/Library/Application Support/com.jamiewhite.signalladder/Sounds/`, at a gain from −40 to +12 dB. ([#3](https://github.com/JWhite212/SignalLadder/pull/3))
- Every sound is level-matched, so at 0 dB every sound peaks at the same level whichever one you choose, with a limiter as a safety net. Sounds longer than 30 seconds are refused.
- The Inspector and menu say what was done without claiming it was heard, such as _Played Glass (+6 dB)_, and note when the Mac's output was muted or at zero volume.
- A sound that does not exist, cannot be read or is silent is reported when the rules load, naming the rule.
- A mute walkthrough in the menu. For each app a sounding rule reaches it offers **Open Notification Settings for …** and **I've Turned Its Sound Off**, and it points to Focus settings, because banners are not drawn during Do Not Disturb. SignalLadder cannot check that an app is muted, and says so.
- A menu warning when the Mac's output is muted while a rule has a sound.

### Changed
- A rules file with an alert is written as `"version": 2`, so an older build refuses it rather than dropping the alerts.
- Unknown keys in the rules file are errors, so a typo such as `"alrt"` cannot leave a rule quietly silent.

### Security
- The mute checklist stores a one-way hash of each app name, never the name, because a name can come from a notification.

## M3a: rules that match, silently - 2026-09-24

### Added
- Rules in `~/Library/Application Support/com.jamiewhite.signalladder/rules.json`. A rule matches on `app`, `title`, `subtitle`, `body`, `raw` or `subrole` with `equals`, `notEquals`, `contains` or `matches` (a pattern with `*` and `?`), combined with `and`, `or` and `not`. Matching ignores case and accents, and the first enabled rule wins. ([#2](https://github.com/JWhite212/SignalLadder/pull/2))
- The Inspector shows which rule each notification matched, or that none did. **Reload Rules** (⌘R) previews new rules against everything already captured without rewriting what happened.
- One bad rule never disables the others. Problems are listed by rule position and name, and a damaged file is reported, never overwritten.
- The menu shows the rules in effect, the last match, and how many recent notifications the current rules match.
- [`docs/rules-format.md`](docs/rules-format.md), a guide to writing rules by hand.

### Security
- The `signalladder-probe` developer tool no longer prints notification text unless run with `--show-content`.

## M2c: the Inspector - 2026-09-24

### Added
- The Inspector, **Show Inspector…** (⌘I): the last 50 captured notifications, newest first, with each field, the raw text on request, the banner type, and how many the same app sent in the last hour. Held in memory only, and gone when the app quits. ([#1](https://github.com/JWhite212/SignalLadder/pull/1))
- An empty Inspector says whether nothing has arrived or capture cannot be confirmed, and why.

## M2b: health and permissions - 2026-09-11

### Added
- A self-test: SignalLadder sends itself a silent notification and checks that it can read it back. The menu shows _Working — verified_, _Cannot verify itself_ or _NOT capturing notifications_.
- Problems are reported three ways that no single fault can silence together: the menu-bar icon, a beep, and a notification when banners are known to be shown.
- The app asks for Accessibility, then for notifications, and picks up a permission granted while it is running without a relaunch.
- Do Not Disturb is told apart from a capture failure, so Accessibility is not blamed for a notification that was never drawn.

## M2a: the app - 2026-09-11

### Added
- A signed menu-bar app with no Dock icon, built by `Scripts/make-app.sh`, that captures notifications and shows how many it has seen.
- Capture recovers when Notification Centre restarts, however often it does.

## M1: capture - 2026-09-11

### Added
- Reading notification banners from Notification Centre through the Accessibility API, splitting each into app, title, subtitle and body, and printing them from a command-line probe.
