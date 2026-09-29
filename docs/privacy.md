# Privacy and permissions

This page is for anyone deciding whether to let an app read every notification on a Mac: an on-call engineer, or the IT and security team who have to approve it. It says what SignalLadder reads, what it keeps and where, what it never does, and which permissions it needs. Where a guarantee rests on SignalLadder's own code rather than on macOS, it says so.

It describes the current source, version 0.1.0. SignalLadder is pre-release and there is no download yet, so you build it yourself and can read what you run ([getting started](getting-started.md)). When a change alters an answer here, this page changes with it.

## In short

- SignalLadder's own code contains no networking, telemetry, analytics, crash reporting or update checking, and it has no third-party dependencies.
- It reads notification banners through macOS Accessibility, from Notification Centre only. It only reads: it never clicks, dismisses, replies or types. The permission macOS gives it is broader than that, and only SignalLadder's code holds it to Notification Centre.
- Notification text is kept in memory only: the last 50 notifications, until newer ones replace them or you quit. SignalLadder does not write it to disk or to logs. The one exception is text you choose to put in a rule condition, which is saved in your rules file and its backups.
- The one preference it stores is a set of one-way hashes of the names of apps you have marked as muted.
- It needs two permissions: Accessibility, to read banners, and Notifications, so it can send itself a test banner to prove it still works. It does not use the microphone, camera, location, contacts, screen recording or full-disk access.
- It is not sandboxed, because the sandbox blocks Accessibility. That is also why it is not on the Mac App Store.
- What SignalLadder says and shows is visible to the room. Spoken alerts read notification text aloud, and the self-test banner is drawn on screen, screen shares included. The menu never shows a notification's title or body. The Inspector does.

## What SignalLadder reads, and how

SignalLadder learns about a notification one way. It asks macOS to tell it when Notification Centre, the macOS process that draws banners, opens or moves a window, removes an element, or changes its layout. When that happens, it reads the banner on screen.

- It connects to one process: Notification Centre (`com.apple.notificationcenterui`). No other app is opened through Accessibility.
- It searches Notification Centre's interface, to a limited depth, for banner elements, which it recognises by their Accessibility type (their subrole). It reads text only from the banners it finds: the description and the text of the banner's direct child elements. That gives the app's name (worked out from the banner, so a guess), the title, subtitle and body, and the raw text. Nothing else on screen is read.
- It only reads. Its Accessibility calls register for events and read attributes, each read with a 0.2-second timeout. None performs an action, sets a value, or sends a key press or a mouse click. It never dismisses, opens or replies to a notification, and it never types.
- It sees only what Notification Centre draws. A notification held back by Do Not Disturb, a Focus, or switched-off banners is never drawn, so it is never read.

> [!IMPORTANT]
> The permission is broader than the use. macOS has no Accessibility grant that means "notifications only": once you allow SignalLadder, macOS lets it read the interface of any app. Nothing in macOS holds SignalLadder to Notification Centre. Its code does. If that matters to you, read it. Everything that reads another app's interface is in [`Sources/NotificationCapture/`](../Sources/NotificationCapture/), and [architecture](architecture.md) maps the rest.

Opening Notification Centre shows old notifications in the same window as new banners. SignalLadder recognises that window as Notification Centre's list by how it is built, not by what it says. Whatever the list holds when it opens is treated as old: its text is not read, and nothing about it is kept. A notification that appears in the list after that is read like a banner. If it shows it is old, such as by a "1m ago"-style time at the end, it is dropped without being kept. Otherwise it is treated as new, because missing a real alert is the worse mistake. The list has only been checked on macOS 26. On a macOS where it is built differently, SignalLadder would not recognise it, and old notifications could be kept in memory and matched against your rules as if they had just arrived.

Some things it looks at need no permission:

- Its own notification settings, to tell whether its own banners would be shown.
- Whether the Mac's sound output is muted or at zero volume, so the Inspector can say an alert could not be heard.
- The names of running apps when you choose **Open Notification Settings for …** in the mute checklist. If that does not find the app, it reads the names and identifiers declared by the apps in `/Applications`, `/System/Applications` and `~/Applications`, one folder level deep. It does this only when you ask, and keeps nothing.

It does not read macOS's notification database, the Focus database or the old file of notification settings. The first two are protected, and the third was a year out of date when it was checked on macOS 26, so it would report old settings as current. No code in SignalLadder refers to any of them.

## What it keeps, and where

### In memory

Notification text is held in memory and nowhere else. SignalLadder keeps the last 50 notifications: the app, title, subtitle, body, raw text, banner type, time, the rule that matched and what the alert did. The Inspector shows them, and the rule editor tries a rule on them. When a 51st arrives, the oldest goes.

There is no time limit. On a quiet Mac a notification stays until 50 newer ones replace it or you quit. There is no clear-history command. **Quit SignalLadder** clears everything in this table.

| Held | What it is | For how long |
| ---- | ---------- | ------------ |
| The last 50 notifications | Everything listed above | Until 50 newer ones arrive, or you quit |
| The Inspector and the rule editor | Copies of those same entries. The rule editor also keeps the notification you started a rule from | The copies follow the 50. The one you started from goes when you close the editor |
| The duplicate filter | The raw text of recent banners, so one banner is counted once | Until the next banner arrives, so on a quiet Mac the last banner's raw text waits there |
| The last alert | What the latest match did. For a spoken alert, that includes the line it said | Until a later match replaces it. An alert that failed is held until a later alert succeeds. Either can outlive its row in the 50 |

"In memory" means SignalLadder writes none of this anywhere. What macOS does with a running app's memory, such as paging it out to swap, is macOS's own business, and SignalLadder cannot control it.

### On disk

SignalLadder is not sandboxed, so its files are real paths in your own Library folder, not a container. This is every place it writes, and the one folder it only reads:

| Path | What it holds | Written when |
| ---- | ------------- | ------------ |
| `~/Library/Application Support/com.jamiewhite.signalladder/rules.json` | Your rules | You press **Save** in the rule editor. Also created once, with one example rule switched off, if you choose **Open Rules File in Text Editor…** and no file exists. Never on load, never to tidy it |
| `rules.previous.json`, beside `rules.json` | The version the last ordinary save replaced | Each ordinary save. The next one overwrites it |
| `rules.replaced-….json`, beside `rules.json` | The version a **Save Anyway** replaced after the file changed under the editor. The name carries the date and time, for example `rules.replaced-2026-09-29-142702.json` | Each **Save Anyway**. SignalLadder never rotates or deletes these |
| `Sounds/`, beside `rules.json` | Your own alert sounds | You make this folder. SignalLadder only reads it |
| `~/Library/Preferences/com.jamiewhite.signalladder.plist` | One key of its own, `confirmedMutedAppDigests`: SHA-256 hashes of the names of apps you have marked as muted | You tick or untick **I've Turned Its Sound Off** in the mute checklist |

The hash is of the app's name with case and accents folded, and it is stored instead of the name. It has two limits. It is unsalted, so anyone holding the file can test a guess such as `microsoft teams` against it. And an app's name is worked out from the banner's text, so on a banner that parses oddly it can be a fragment of a message. The second limit is the reason it stores a hash rather than the name.

If `rules.json` is a symbolic link, SignalLadder saves through it to the file it points to, and keeps its backups beside the link. Pointing it into a synced or versioned folder is your choice, and it syncs your rules.

The rules file is written with default file permissions. SignalLadder does not tighten them.

> [!WARNING]
> Text you put in a rule condition is saved. **Make a Rule from This…** in the Inspector starts a rule from the app's name alone. But the rule editor's **Add Condition from This Notification** can offer the title, subtitle, body or raw text as a condition's value, and says beside it: _The text you add is saved in your rules file._ Once you save, that text is in `rules.json`. Removing the condition and saving again does not take it back: the earlier version stays in `rules.previous.json` until your next save replaces it, and in any `rules.replaced-….json` until you delete that file. Time Machine, or a synced home folder, carries these files too. Trim a condition to the part that matters, such as `deploy failed`, and leave out names and message text you would not want on disk.

SignalLadder's code writes nothing else: no cache, no Keychain entry, no clipboard content and no export.

## What it never does

SignalLadder's own code:

- Makes no network connection. It contains no networking, telemetry, analytics, crash reporting or update checking, so there is nothing to allow-list on a firewall. Updates are manual.
- Has no third-party dependencies. `Package.swift` declares none, and the app imports only Apple frameworks: Foundation, AppKit, SwiftUI, Combine, UserNotifications, ApplicationServices, AVFoundation, AudioToolbox, CoreAudio, CryptoKit and os.
- Runs no shell commands or scripts. The only other programs it opens are System Settings, and the text editor for your rules file (or Finder, if nothing on your Mac opens JSON), and only when you choose them.
- Never writes to the clipboard.
- Does not start itself. There is no login item, background service or helper. You open it.

You can check the first two claims yourself. From a copy of the source:

```sh
# Anything that could open a connection: prints nothing
grep -rnE 'URLSession|URLRequest|NWConnection|CFNetwork|WebKit|Sparkle|import Network' Sources

# Any external package: prints nothing
grep -nE '\.package|\.product' Package.swift
```

Two limits apply. First, a search of the source cannot rule out what Apple's own frameworks do, since Foundation and AppKit can reach the network for their own reasons. A firewall such as Little Snitch, or a look at a running copy with `lsof -i -a -p "$(pgrep -x SignalLadder)"`, shows what the app is actually doing at that moment. Second, these statements are about SignalLadder's code, not the systems it hands data to. A spoken line goes to macOS's speech synthesis, and **Open Rules File in Text Editor…** opens the file in whichever app you use for JSON. What they do is up to them. SignalLadder offers only voices already installed on your Mac, and never Siri voices.

One automated test backs part of this. It fails the test suite if the matching and health logic in `Sources/NotificationCore` refers to the file system or `URLSession`. It covers that one module. For the rest, the guarantee is the source itself and code review.

## Logs

SignalLadder writes to the macOS unified log, under the subsystem `com.jamiewhite.signalladder`, in two categories.

| Category | What it records |
| -------- | --------------- |
| `watcher` | Whether it attached to Notification Centre, and the process ID it attached to. Retry delays. Accessibility error codes. When a banner has no readable text, the banner's type (its subrole) |
| `speech` | How many milliseconds a spoken alert took to start, and whether its voice had been measured yet. Two fixed sentences, for a line that produced no audio or did not finish in time |

Those are the only things it logs. Notification text never appears in the log, and neither does what a spoken alert said.

The `watcher` lines are marked public, so macOS does not redact them when you read them. The `speech` lines hold only a number and one fixed label. Both are written at the default level rather than the info level, which macOS keeps in memory only. How long macOS keeps them is its decision.

To read them:

```sh
/usr/bin/log show --last 30m --predicate 'subsystem == "com.jamiewhite.signalladder"'
```

Use the full path. In zsh, `log` on its own is a built-in and does something else.

Nothing enforces "never notification text" automatically. It is upheld by convention and review. A comment on the watcher's log function says the public marking is safe only because notification content never passes through it, and that callers must pass a process ID, a subrole or a count, never a notification's text. The pull request checklist asks every contributor to confirm that no notification text reaches a log, a file, a fixture or a screenshot. The automated test above does not look at logging.

SignalLadder installs no crash handler and sends no crash reports. macOS's own crash reporting works for it as it does for any app, and is outside SignalLadder's control.

## Permissions

At launch SignalLadder asks macOS to show its two standard permission prompts, Accessibility first. It has no set-up wizard of its own. [Getting started](getting-started.md) walks through granting them.

| Permission | Required | What it is for |
| ---------- | -------- | -------------- |
| Accessibility (System Settings › Privacy & Security › Accessibility) | Yes | Reading banner text. Accessibility is how SignalLadder reads banners |
| Notifications (System Settings › Notifications) | For the self-test and the health alarm only | Posting SignalLadder's own test banner and its own alarm. It asks for alerts only: no sound, no badge |

SignalLadder does not need, and its code does not use, the microphone, camera, screen recording, full-disk access, location, contacts or automation. Speech is text-to-speech only: nothing is recorded.

### If Accessibility is missing

Nothing is captured, and SignalLadder says so in four places.

- The menu's first line reads _NOT capturing notifications_. Beneath it is _Grant Accessibility to SignalLadder in System Settings — without it no notifications can be read._ Choosing that line opens the Accessibility pane.
- The menu-bar icon becomes a bell with a line through it.
- The Mac beeps.
- If SignalLadder's own banners can be shown, a banner titled _SignalLadder is not capturing_ appears.

Granting it while the app runs takes effect the next time you open the menu, with no relaunch. If it is revoked while the app runs, the menu shows the problem as soon as you open it. The beep and banner come with the next health check. By design that runs every 30 minutes and whenever you open the menu, though the delay has not been timed on a real revocation.

### If Notifications is denied

Capture still works, but SignalLadder can no longer prove that it does. Allow it: the self-test is how you find out that capture has stopped.

- The menu's first line reads _Cannot verify itself_. Beneath it is _Allow notifications for SignalLadder in System Settings — without it the app cannot verify it is working._
- The icon changes and the Mac beeps, but no banner is posted, because none could be shown.

### Not sandboxed, and what that means

The App Sandbox blocks the Accessibility API from reading another app's interface. An app that does what SignalLadder does cannot be sandboxed, and the Mac App Store requires the sandbox, so SignalLadder cannot be offered there. The plan is to sell signed, notarised builds directly from this project instead. Until then, you build it yourself.

The build script, `Scripts/make-app.sh`, signs the app with the Hardened Runtime and passes no entitlements. It refuses an ad-hoc signature, because that would break the Accessibility grant on every rebuild. There is no notarised download yet. To check a build you have made:

```sh
codesign -dv --verbose=2 build/SignalLadder.app          # flags include (runtime)
codesign -d --entitlements - build/SignalLadder.app      # prints no entitlements
```

## What you and others may see or hear

- **The self-test banner.** To prove capture still works, SignalLadder posts a banner titled _SignalLadder self-test_ and reads it back. It does this at launch, again about two minutes later, then every 30 minutes, and more often for a while after a failed check. Its text is a fixed marker followed by a random identifier: no notification text, none of your data. It is drawn like any banner, so anyone watching your screen sees it, and so does a screen share that includes banners. SignalLadder removes it from Notification Centre afterwards. A Focus or Do Not Disturb hides it, and SignalLadder then reports that it cannot verify itself. [Troubleshooting](troubleshooting.md) covers that.
- **The health alarm.** If capture stops, or SignalLadder cannot verify itself, it beeps and, where its own banners can be shown, posts a banner titled _SignalLadder is not capturing_ or _SignalLadder cannot verify itself_, with the advice line as its text. You did not write a rule for this. It is the one alert SignalLadder raises on its own, and it stays in Notification Centre until you clear it.
- **Spoken alerts.** A rule that speaks reads a line built from the notification aloud, through the Mac's current sound output. The default line is `{app}: {title}`, the app's name and the title without the body, and a spoken line stops at 240 characters whatever the template. Anyone in earshot hears it. [Speech](rules-format.md#speech) explains the template.
- **The menu.** It never shows a notification's title or body, or what was spoken. It shows the number captured and, for the last match, the rule's name, the time and what the alert did. The mute checklist names apps: those your sounding rules name, and those that have set one off. An app's name is read from the banner, so it is not always exact. The rules section names your rules.
- **The Inspector.** It shows everything held: app, title, subtitle, body, the raw text and, for a spoken alert, _Said: “…”_. Keep it closed on a shared screen. The raw text and the spoken line can be selected and copied, and a clipboard manager would keep what you copy. The rule editor's dry run also lists the time, app and title of the notifications a rule matches.

## Removing everything

1. Quit SignalLadder with **Quit SignalLadder** in the menu. That clears the notification history from memory.
2. Delete the folder `~/Library/Application Support/com.jamiewhite.signalladder/`. It holds your rules, their backups and your `Sounds` folder, so copy out anything you want to keep first.
3. Delete `~/Library/Preferences/com.jamiewhite.signalladder.plist`.
4. In System Settings, remove SignalLadder from Privacy & Security › Accessibility, and from Notifications. Optionally, reset the Accessibility entry from Terminal: `tccutil reset Accessibility com.jamiewhite.signalladder`.
5. Delete `SignalLadder.app`, wherever you put it.

That is all of it. SignalLadder installs no login item, background service or helper, and stores nothing in the Keychain. Two things are outside its reach: the lines it wrote to the macOS log stay until macOS ages them out, and copies of your rules file in Time Machine or a sync service stay until you delete them there.

## Future changes

Escalation is planned and not built: a persistent panel, a repeating sound, an acknowledge hotkey and a Shortcut action. The Shortcut action would hand a notification's app name, title, subtitle and body to a Shortcut you choose, which could then send them wherever that Shortcut sends things. It would be opt-in, used only by a rule you give a Shortcut, and this page would change with it, including the statements above about disk and networking. Nothing of this is in the code today. The plan is in [`docs/dev/plans/2026-09-25-m4-escalation.md`](dev/plans/2026-09-25-m4-escalation.md).

If SignalLadder does something this page says it does not, please report it privately. See [SECURITY.md](../SECURITY.md).
