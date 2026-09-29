# Changelog

Notable changes to SignalLadder are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The rules file can hold an escalation ladder beside a rule's alert: a panel, a capped repeat, and a final alert or a Shortcut. It is written as `"version": 4`. It is checked when the rules load but not acted on yet, so a rule with one still sounds once. See [Escalation](docs/rules-format.md#escalation).
- A rule naming a Shortcut that is not in the Shortcuts app is reported when the rules load.

## [0.1.0] - 2026-09-29

The first tagged release. It is source only: there is no signed download yet, so you build it yourself ([getting started](docs/getting-started.md)).

### Added

**Capture**
- Reads notification banners from Notification Centre through the Accessibility API, and splits each into app, title, subtitle and body. It only reads: it never clicks, dismisses or replies.
- A notification that arrives while another banner is still on screen is captured, and each banner is read only once, however many times macOS redraws it. A banner read back with less text than before, because a read timed out, is not mistaken for a new notification.
- A second persistent alert from the same app, which macOS stacks with the first, is captured, and so is every alert after it in the stack. Teams alerts are persistent when Teams is set to Alert in System Settings.
- Opening Notification Centre does not replay the notifications it lists, however recent. SignalLadder recognises the list by how its window is built, checked on macOS 26.7, and a notification that arrives while the list is open is still captured. One that arrives at the very moment the list opens is taken for history, and may be missed.
- Capture recovers when Notification Centre restarts, however often it does.

**Health**
- A self-test: SignalLadder sends itself a silent notification and checks that it can read it back, at launch, two minutes later and then every 30 minutes. The menu shows _Working — verified 3 min ago_, _Unverified — last verified …_ once a self-test is overdue, _Cannot verify itself_ or _NOT capturing notifications_.
- Problems are reported three ways that no single fault can silence together: the menu-bar icon, a beep, and a notification when banners are known to be shown.
- The health line re-checks as soon as whatever blocked a self-test clears, such as Accessibility granted again or SignalLadder's own banners switched back on.
- Do Not Disturb is told apart from a capture failure, so Accessibility is not blamed for a notification that was never drawn.
- The app asks for Accessibility, then for notifications, and picks up a permission granted while it is running without a relaunch.

**The Inspector**
- **Show Inspector…** (⌘I): the last 50 captured notifications, newest first, with each field, the raw text on request, the banner type, how many the same app sent in the last hour, which rule matched and what was done. Held in memory only, and gone when the app quits.
- An empty Inspector says whether nothing has arrived or capture cannot be confirmed, and why.

**Rules**
- Rules in `~/Library/Application Support/com.jamiewhite.signalladder/rules.json`. A rule matches on `app`, `title`, `subtitle`, `body`, `raw` or `subrole` with `equals`, `notEquals`, `contains` or `matches` (a pattern with `*` and `?`), combined with `and`, `or` and `not`. Matching ignores case and accents, and the first enabled rule wins.
- One bad rule never disables the others. Problems, including a sound or voice that is missing, are listed by rule when the rules load, and a damaged file is reported, never overwritten. Unknown keys are errors, so a typo cannot leave a rule quietly silent.
- A rules file is written at the oldest version that can hold it (`1`, `2` with an alert, `3` with speech), so an older build refuses a file it cannot fully read rather than dropping part of it.
- **Reload Rules** (⌘R) previews new rules against everything already captured. The menu shows the rules in effect, the last match, and how many recent notifications the current rules match.
- [`docs/rules-format.md`](docs/rules-format.md), a guide to writing rules by hand.

**The rule editor**
- **Edit Rules…** (⌘E). Rules can be added, duplicated, deleted, switched on and off, and dragged into priority order. A condition builder handles nested _all of_, _any of_ and _not_ groups.
- A live dry-run shows which notifications in memory a rule would match, which rule above it takes others first, and **Move Above** to fix that. It always says whether what you see is in effect yet.
- **Make a Rule from This…** on every Inspector row, and **Add Condition from This Notification**, so a rule starts from a real notification.
- Safe saving: the file is written in one step, the version it replaces is kept as `rules.previous.json`, and a save is refused if the file changed on disk since it was read, with **Reload from Disk**, **Save Anyway** and **Cancel** offered. Save Anyway keeps a dated copy of what it replaces.
- A rules file the editor cannot fully represent opens read-only, with the reason. Closing the editor or quitting with unsaved changes asks whether to save. **Open Rules File in Text Editor…** opens the file itself.

**Alerts**
- A rule's alert can be a sound, a spoken line, both, or `"silent"`, which claims a notification and keeps it quiet.
- Sounds are the macOS sounds or your own files in `~/Library/Application Support/com.jamiewhite.signalladder/Sounds/`, up to 30 seconds long, at a gain from −40 to +12 dB. Every sound is level-matched, so at 0 dB each one peaks at the same level, with a limiter as a safety net.
- A spoken line comes from a template using `{app}`, `{title}` and `{body}`; the default is `{app}: {title}`, and it stops at 240 characters. Each spoken alert has its own voice, rate, pitch and gain, and speech is level-matched per voice. A voice that is not installed is reported, never replaced by another.
- **Test Sound** and **Test Speech** play an alert as it will sound. Test Speech reads a made-up notification, and neither interrupts a real alert.
- A new alert cuts off one still playing, including its speech, so two alarms never sound together.
- The Inspector and menu say what was done without claiming it was heard, such as _Played Glass (+6 dB)_, and note when the Mac's output was muted or at zero volume. The Inspector shows exactly what was said; the menu never does.
- A mute walkthrough in the menu offers **Open Notification Settings for …** and **I've Turned Its Sound Off** for each app a sounding rule reaches, and points to Focus settings. SignalLadder cannot check that an app is muted, and says so.

**The project**
- Released under the GNU General Public License v3.0, with a [contributor licence agreement](CLA.md) for contributions.
- A user guide in [`docs/`](docs/README.md): getting started, privacy and permissions, troubleshooting, and how the app works. A README, contributing guide, security policy, code of conduct, issue forms and continuous integration on macOS 15 and 26.

### Security
- Notification text is held in memory only, and never written to disk or to the logs. The only text on disk is what you put in a rule yourself.
- The mute checklist stores a one-way hash of each app name, never the name, because a name can come from a notification.
- The `signalladder-probe` developer tool prints notification text only when run with `--show-content`.

[Unreleased]: https://github.com/JWhite212/SignalLadder/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JWhite212/SignalLadder/releases/tag/v0.1.0
