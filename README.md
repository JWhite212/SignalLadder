<p align="center">
  <img src="docs/assets/logo.svg" width="128" height="128" alt="SignalLadder">
</p>

<h1 align="center">SignalLadder</h1>

<p align="center">
  <strong>Hear the one alert that matters.</strong><br>
  A macOS menu-bar app that reads your notifications and sounds, or speaks, only for the ones your rules pick out,<br>
  so the page you are waiting for never drowns in channel chatter.
</p>

<p align="center">
  <a href="https://github.com/JWhite212/SignalLadder/actions/workflows/ci.yml"><img src="https://github.com/JWhite212/SignalLadder/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6%20toolchain-F05138?logo=swift&logoColor=white" alt="Built with a Swift 6 toolchain">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-GPL--3.0-2F6FEB" alt="Licence: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/status-pre--release-E8890C" alt="Status: pre-release">
</p>

<p align="center">
  <a href="#getting-started">Get started</a> ·
  <a href="docs/rules-format.md">Write rules</a> ·
  <a href="docs/privacy.md">Privacy</a> ·
  <a href="docs/troubleshooting.md">Troubleshooting</a> ·
  <a href="#roadmap">Roadmap</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hero-dark.png">
  <img src="docs/assets/hero.png" alt="The SignalLadder rule editor showing a rule for production incidents that plays Glass and speaks, the menu-bar menu reporting that capture is working and the last match, and the Inspector listing recent notifications with what each one set off">
</picture>

> [!NOTE]
> SignalLadder is pre-release. There is no signed build yet, so you [build it from source](#getting-started). Everything described on this page works on the `main` branch today. Anything that doesn't is marked as planned.

## Why SignalLadder

If you are on call, you have probably missed a page because it sounded exactly like the forty channel messages before it. Chatty apps teach you to tune their sound out, and the one alert that matters gets tuned out with the rest.

SignalLadder gives that one alert a voice of its own. It watches the notification banners macOS shows, checks each against your rules, and plays a distinct sound or speaks a line only when a rule matches. Everything else stays quiet.

It **replaces** an app's sound rather than adding another one. You switch off the chatty app's own notification sound in System Settings, and SignalLadder becomes its only voice: silent by default, and heard only when one of your rules earns it. Adding a louder sound on top of a firehose would only make the problem worse.

Every feature is judged by one question: **does it help you not miss the critical one?**

## How it works

```mermaid
flowchart LR
    A["A notification banner<br/>appears on screen"] --> B["SignalLadder reads it<br/>through Accessibility"]
    B --> C{"Your rules, top to bottom:<br/>the first match wins"}
    C -- "a rule with an alert" --> D["A sound, a spoken line,<br/>or both"]
    C -- "a silent rule" --> E["Claimed, and kept quiet"]
    C -- "no match" --> F["Nothing plays"]
    D --> G["Recorded in the Inspector"]
    E --> G
    F --> G
```

1. **It reads banners.** SignalLadder reads the text of each banner from Notification Centre through the macOS Accessibility API. It only reads. It never clicks, dismisses or replies.
2. **Your rules decide.** A rule matches on the app, title, subtitle, body or the banner's whole text, using _is_, _is not_, _contains_ or a pattern with `*` and `?`, combined with _all of_, _any of_ and _not_. Rules are checked in order and the first enabled match wins.
3. **The alert plays.** The alert can be one of the 14 macOS sounds or your own file, level-matched so every sound peaks at the same level at the same setting. It can also speak a line such as _"Microsoft Teams: #prod-payments"_ in a voice you choose. A silent rule claims a notification so that no broader rule below it can sound.
4. **It can keep going until you answer.** A rule can escalate. If you have not acknowledged the alert, SignalLadder can show a panel over your other windows, repeat an alert on a timer and, as a last resort, run a Shortcut you choose. Acknowledging stops whatever is still to come. [Escalation](docs/rules-format.md#escalation) explains how to set it up.
5. **It checks itself.** Every 30 minutes SignalLadder sends itself a silent test banner and makes sure it can read it back. The menu always says how recently that worked. If capture has stopped, it tells you in three separate ways.

## Features

**Rules you can prove before you trust them**
- Choose **Make a Rule from This…** on any notification in the Inspector to start a rule from what the app actually sent.
- As you edit, every rule is tried against the notifications SignalLadder is holding, up to the last 50: _In this draft: matches 2 of the last 9 notifications._
- It shows which rule higher in the list would take a notification first, and offers to move yours above it.
- Nothing takes effect until you save, and the editor says so in words.

**Alerts you can tell apart**
- Sounds: the 14 macOS sounds, or your own AIFF, WAV, CAF, MP3 or M4A files up to 30 seconds long.
- Level matching brings every sound to the same peak level at 0 dB, so the sound you pick doesn't decide how loud the alert is. A very quiet file is boosted by 24 dB at most. Gain runs from −40 to +12 dB, with a limiter so nothing clips.
- Spoken alerts come from a template built with `{app}`, `{title}` and `{body}`, in any installed voice, with its own rate, pitch and gain. They can play on their own or after a sound.
- **Test Sound** and **Test Speech** let you hear an alert before it happens for real. Test Speech reads a made-up notification, never a real one.
- One alert plays at a time, so two alarms never sound over each other.

**Alerts that keep going until you answer**
- A rule can escalate. After its alert come up to three more tiers, each optional and each on its own timer, counted from the match: a panel on screen, an alert repeated, and a last alert or a Shortcut you choose, for example to reach your phone. [How to write one](docs/rules-format.md#escalation).
- The panel is a borderless window that stays over every app and every Space, full-screen apps included. It does not take focus from the app you are in. Over full-screen apps and other Spaces, that was seen in a test program on macOS 26.7, and has not yet been checked in the app itself.
- Acknowledge from the panel, from the top of the menu or with ⌃⌥⌘A. Acknowledging stops every tier still to come.
- Repeats stop after 20 repeats or ten minutes, whichever comes first, unless you set other limits. The panel and the Inspector say when they have stopped.
- The panel and the menu name the rule, never what the notification said.
- A repeat, a last alert or a Shortcut that fails is reported the way a failed first alert is: a line in the menu and the slashed bell.
- While a tier is still to come, SignalLadder asks macOS not to let the Mac sleep on its own. It does not keep the display awake. That request has not yet been tested on a Mac that can sleep.

**Quiet on purpose**
- A `"silent"` rule claims matching notifications, so a catch-all such as _everything else from Teams_ stays quiet while the narrow rules above it still sound.
- A menu walkthrough takes you to each chatty app's notification settings so you can switch its own sound off.

**Honest about its own health**
- A real round-trip self-test, not a guess. The menu reads _Working — verified 3 min ago_, _Cannot verify itself_ or _NOT capturing notifications_.
- Stale evidence is never presented as current.
- If capture stops, you get a changed menu-bar icon, a beep and, when banners can be shown, a notification. That is three channels, so no single fault can silence all of them.

**Loud about broken rules, never silent**
- A misspelt sound, a missing voice or an unknown key is reported when the rules load, by rule name, not discovered at 3 a.m.
- One broken rule never switches the others off.

**Careful with your data and your rules file**
- SignalLadder's own code makes no network connections, and the app has no third-party dependencies.
- Notification text stays in memory and is gone when you quit. There are two exceptions: text you choose to put in a rule, and the four fields of a notification that a Shortcut receives when you make one an escalation's last step. That file is deleted as soon as the Shortcut ends. [Details](docs/privacy.md).
- Rules live in a readable JSON file. Saves are atomic and keep the previous version, and SignalLadder never silently overwrites a file you changed by hand: it asks first, and if you save anyway it keeps your edited file as a dated copy.

**Small and native**
- Swift and SwiftUI, about 2 MB, and event-driven. Nothing polls except the self-test: half-hourly, plus a few one-off checks after a launch, after a failure or while one is blocked. An escalation adds timers of its own only while it is live.

## Screenshots

<table>
  <tr>
    <td width="58%" valign="top">
      <a href="docs/assets/screenshots/inspector.png"><picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/inspector-dark.png">
        <img src="docs/assets/screenshots/inspector.png" alt="The Inspector listing recent notifications, each with the rule it matched and what was done">
      </picture></a>
    </td>
    <td width="42%" valign="top">
      <a href="docs/assets/screenshots/menu.png"><picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/menu-dark.png">
        <img src="docs/assets/screenshots/menu.png" alt="The menu-bar menu showing health, capture count, rule status and the last match">
      </picture></a>
    </td>
  </tr>
  <tr>
    <td><strong>The Inspector.</strong> The last 50 notifications, what each field holds, which rule matched and what played.</td>
    <td><strong>The menu.</strong> Health first, unless an alert is waiting, then the rules in effect and the last thing that sounded.</td>
  </tr>
  <tr>
    <td colspan="2">
      <a href="docs/assets/screenshots/rule-editor.png"><picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/rule-editor-dark.png">
        <img src="docs/assets/screenshots/rule-editor.png" alt="The rule editor with a rule selected, showing its conditions, a Glass sound at +6 dB followed by speech, and the notifications it matches">
      </picture></a>
    </td>
  </tr>
  <tr>
    <td colspan="2"><strong>The rule editor.</strong> Conditions, the alert and a live dry-run against real traffic, before anything is saved.</td>
  </tr>
</table>

<sub>Screenshots show made-up notifications.</sub>

## Getting started

**You need** a Mac running macOS 14 Sonoma or later, Xcode with its Swift 6 toolchain, and a code-signing identity. SignalLadder is developed and tested on macOS 26. macOS 14 and 15 are supported targets but have not yet been checked on a real Mac.

```bash
git clone https://github.com/JWhite212/SignalLadder.git
cd SignalLadder
security find-identity -v -p codesigning        # copy the 40-character SHA-1 of an identity
SIGNALLADDER_IDENTITY=<that SHA-1> ./Scripts/make-app.sh release
open build/SignalLadder.app
```

A real signing identity is required because macOS ties the Accessibility permission to the app's signature. An ad-hoc signature changes on every build, so macOS would forget the permission each time. An Apple Development certificate, which Xcode creates for any Apple ID, should do. [Getting started](docs/getting-started.md) has the details.

Then:

1. **Grant Accessibility** when asked, in System Settings › Privacy & Security › Accessibility, and **allow notifications**. SignalLadder needs its own banners to test itself.
2. **Open the Inspector** from the bell in the menu bar (**Show Inspector…**) and let a few notifications arrive.
3. **Make a rule** with **Make a Rule from This…**. Watch the dry-run, pick a sound, switch the rule **On** and **Save**.
4. **Mute the source app.** The menu's walkthrough opens its notification settings. Turn its sound off there so SignalLadder is its only voice.
5. **Check Focus.** Banners are not drawn during Do Not Disturb or a Focus, so nothing can be read while one is on.

The full walkthrough is in **[docs/getting-started.md](docs/getting-started.md)**.

## Rules in a file

Most people build rules in the editor. Underneath, they are plain JSON that you can read, diff and edit by hand:

```json
{
  "version": 3,
  "rules": [
    {
      "name": "Production incidents",
      "condition": {
        "and": [
          { "field": "app", "op": "equals", "value": "Microsoft Teams" },
          { "or": [
              { "field": "title", "op": "matches", "value": "#prod-*" },
              { "field": "title", "op": "matches", "value": "#incident-*" }
          ] }
        ]
      },
      "alert": {
        "sound": "Glass",
        "gainDB": 6,
        "speak": { "voice": "com.apple.voice.compact.en-GB.Daniel", "template": "{app}: {title}" }
      }
    },
    {
      "name": "Everything else from Teams",
      "condition": { "field": "app", "op": "equals", "value": "Microsoft Teams" },
      "alert": "silent"
    }
  ]
}
```

Every key, operator, alert and error message is explained in **[docs/rules-format.md](docs/rules-format.md)**.

## Privacy

- SignalLadder reads banners from Notification Centre and nothing else, and it only reads.
- Its own code has no networking, telemetry, analytics or update checks, and the app has no third-party dependencies.
- The one other program it runs is Apple's `/usr/bin/shortcuts`, and only for a rule that names a Shortcut: to check that the name exists when the rules load, and to run it as an escalation's last step.
- It keeps the last 50 notifications in memory, never writes their text to its logs, and forgets them when you quit. A notification that is still escalating stays in memory until it is acknowledged and finished with, even after it drops out of those 50.
- Notification text reaches disk in two places only. One is text you put into a rule condition yourself, which is saved in your rules file. The other is the temporary file a Shortcut reads when an escalation's last step runs one. It holds four fields of the notification (app name, title, subtitle and body) and is deleted as soon as the Shortcut ends. What the Shortcut then does with that text is up to the Shortcut you wrote.
- It needs two permissions: Accessibility, to read banners, and Notifications, to test itself. It does not use the microphone, camera, screen recording or full disk access. The global acknowledge shortcut needed no permission prompt on macOS 26.7. Other versions have not been checked.

The full account, including what is stored where and how to remove it all, is in **[docs/privacy.md](docs/privacy.md)**.

## What it can't do (yet)

SignalLadder is honest about its limits, because an on-call tool that overstates itself is worse than none.

- **It can only read banners that macOS draws.** During Do Not Disturb or a Focus, or for an app whose banners are switched off, there is nothing to read, and so nothing to escalate either. Check whether a Focus turns on when your screen locks.
- **Health can be up to about 30 minutes old.** If capture stops between self-tests, the menu still shows the last success until the next test runs. That is why it always says how long ago the last one was.
- **Notification Centre's list has only been checked on macOS 26.7.** There, opening it does not sound old notifications again. But a notification that arrives at the very moment you open it is taken for an old one, and may not sound. On other versions, including macOS 14 and 15, the list may be built differently, and old notifications could sound again when you open it.
- **It can't check that you muted the source app.** macOS doesn't let other apps read notification settings, so the walkthrough records your word and says so.
- **The rule editor cannot set up an escalation yet.** You write it in `rules.json` and choose **Reload Rules**. The editor keeps an escalation you wrote by hand when you save, and shows its problems. See [Escalation](docs/rules-format.md#escalation).
- **A long sleep ends an escalation.** If the Mac sleeps for more than five minutes while an alert is escalating, SignalLadder marks it _missed while asleep_ when the Mac wakes, instead of sounding alarms that are hours old. It stays on the menu, and on the panel if the panel had appeared, until you acknowledge it. After a shorter sleep the ladder resumes. SignalLadder works out how long the Mac slept from the clock and the Mac's awake time. Apple documents that awake time stops during sleep, but this has not yet been measured on a Mac that sleeps.
- **The acknowledge shortcut is fixed.** ⌃⌥⌘A acknowledges everything listed, and does nothing when nothing is. There is no setting to change it. If SignalLadder cannot register it, it logs that and carries on, and the menu and the panel's buttons still work.
- **It cannot see what a Shortcut does.** A Shortcut counts as started if it is still running a second after it launches, or if it exits successfully, and as failed otherwise. SignalLadder never waits for one and never shows or logs what it prints. Whether it then reaches your phone is up to the Shortcut.

More symptoms and fixes are in **[docs/troubleshooting.md](docs/troubleshooting.md)**.

## Roadmap

**Working today**
- [x] Capture of notification banners through Accessibility, with a self-testing health monitor and three alarm channels
- [x] The Inspector: the last 50 notifications, what matched and what played
- [x] Rules with nested conditions, glob patterns, first-match-wins order and silent rules
- [x] The rule editor, with a live dry-run, **Make a Rule from This…** and safe saving
- [x] Level-matched sounds, custom sounds and spoken alerts
- [x] The mute walkthrough and output-muted warnings
- [x] Alerts that keep going until acknowledged: a panel over every app, a repeating alert with caps and a Shortcut as a last resort, written in `rules.json` ([Escalation](docs/rules-format.md#escalation))
- [x] Acknowledging from the panel, the menu or a global shortcut

**Next: escalation in the rule editor** (planned)
- [ ] Setting up an escalation in the rule editor, instead of writing it in `rules.json` by hand

**Release**
- [ ] Signed, notarised builds, sold directly, with building from source still free

**Later** (ideas, not yet planned in detail)
- [ ] Conditions on time of day, an on-call switch, screen lock and how often an app is sending
- [ ] Snooze
- [ ] A Settings window, including launch at login
- [ ] A guided first-run setup

The [changelog](CHANGELOG.md) records what has shipped. Design notes and milestone plans live in [`docs/dev/`](docs/dev/).

## FAQ

<details>
<summary><strong>Why isn't it on the Mac App Store?</strong></summary>

Apps on the Mac App Store must run in Apple's sandbox, and the sandbox blocks the Accessibility API that SignalLadder uses to read banners. The plan is to sell signed, notarised builds directly from this project instead.
</details>

<details>
<summary><strong>Does it send my notifications anywhere?</strong></summary>

No. SignalLadder's own code contains no networking at all, and it has no third-party dependencies that could add any. You can check this in the source. The one way a notification's text can leave your Mac is a Shortcut you name as an escalation's last step: it is handed four fields of the notification, and what it does with them, including sending them anywhere, is up to the Shortcut you wrote. A spoken alert goes to macOS's own speech synthesis. [docs/privacy.md](docs/privacy.md) covers what it keeps and where.
</details>

<details>
<summary><strong>Why does it need Accessibility access?</strong></summary>

It is the only way for one app to read another app's notification banners on macOS. The permission itself is broad. SignalLadder uses it only to read Notification Centre's banners, and the code that does so is in [`Sources/NotificationCapture`](Sources/NotificationCapture) for anyone who wants to audit it.
</details>

<details>
<summary><strong>Why do I see a "SignalLadder self-test" banner?</strong></summary>

That is how SignalLadder proves it can still read notifications. It posts a silent banner to itself, checks that it captured it, and removes it. This happens at launch, again two minutes later, and then every 30 minutes, with retries sooner if one fails. If you switch SignalLadder's own banners off, it can no longer verify itself and says so.
</details>

<details>
<summary><strong>Which apps does it work with?</strong></summary>

Any app whose notifications appear as banners. It was built for Microsoft Teams, where busy channels bury the messages that matter, but rules can match any app. Open the Inspector to see exactly what an app sends before you write a rule for it.
</details>

<details>
<summary><strong>Will it read my messages aloud?</strong></summary>

Only if you give a rule a spoken alert. The default line is the app and the title, such as _"Microsoft Teams: #prod-payments"_. The message body is left out unless you add `{body}`, and a spoken line is capped at 240 characters. The menu never shows notification text.
</details>

<details>
<summary><strong>Is it free?</strong></summary>

Yes, if you build it yourself. The source code is free software under the GNU General Public License v3.0, and the plan is to keep it that way. You can build it, read and change the code, and share it under the same licence.

Once SignalLadder is released, the plan is to sell ready-to-run builds, signed and notarised, directly from this project. A bought build saves you installing Xcode and setting up a signing identity, and the money funds the work. There is no paid build yet.
</details>

## Contributing

Bug reports, ideas and pull requests are welcome. Please read **[CONTRIBUTING.md](CONTRIBUTING.md)** first. It covers setting up, the conventions the code follows and the one question every change is judged by. [docs/architecture.md](docs/architecture.md) explains how the pieces fit together. Pull requests also need the [contributor licence agreement](CLA.md): CLA Assistant asks on your first one.

When you report a bug, replace any names, channels and message text with placeholders. Notifications carry other people's words.

Have a question rather than a bug? **[SUPPORT.md](SUPPORT.md)** says where to look first.

Found a security problem? Please report it privately, as described in **[SECURITY.md](SECURITY.md)**.

Everyone taking part is expected to follow the **[Code of Conduct](CODE_OF_CONDUCT.md)**.

## Licence

SignalLadder is free software, released under the **[GNU General Public License v3.0](LICENSE)**. You may use, study, change and share it. If you distribute it, changed or not, you must do so under the same licence and make its source available.

Contributions are accepted under a [contributor licence agreement](CLA.md), which lets the maintainer offer SignalLadder on other terms as well as the GPL. [CONTRIBUTING.md](CONTRIBUTING.md#licensing-of-your-contribution) explains why.

Copyright © 2026 Jamie White.
