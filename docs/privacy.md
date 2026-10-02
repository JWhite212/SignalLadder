# Privacy and permissions

This page is for anyone deciding whether to let an app read every notification on a Mac: an on-call engineer, or the IT and security team who have to approve it. It says what SignalLadder reads, what it keeps and where, what it never does, and which permissions it needs. Where a guarantee rests on SignalLadder's own code rather than on macOS, it says so.

It describes the current source, version 0.1.0. SignalLadder is pre-release and there is no download yet, so you build it yourself and can read what you run ([getting started](getting-started.md)). When a change alters an answer here, this page changes with it.

## In short

- SignalLadder's own code contains no networking, telemetry, analytics, crash reporting or update checking, and it has no third-party dependencies.
- It reads notification banners through macOS Accessibility, from Notification Centre only. It only reads: it never clicks, dismisses, replies or types. The permission macOS gives it is broader than that, and only SignalLadder's code holds it to Notification Centre.
- Notification text is kept in memory: the last 50 notifications, until newer ones replace them or you quit. An alert that is still escalating keeps its notification for as long as it needs it. SignalLadder does not write notification text to logs.
- Notification text reaches disk in two cases only. One is text you choose to put in a rule condition, which is saved in your rules file and its backups. The other is a rule whose last step runs a Shortcut: while that Shortcut runs, a temporary file holds the notification's app name, title, subtitle and body for it to read. SignalLadder deletes the file the moment the Shortcut ends. What the Shortcut does with the text is up to the Shortcut you wrote. The rule editor's **Test Shortcut** button writes the same file when you press it, holding a made-up test notification and none of yours.
- It stores two preferences, and neither holds notification text: a set of one-way hashes of the names of apps you have marked as muted, and the time you switched on-call mode on.
- It needs two permissions: Accessibility, to read banners, and Notifications, so it can send itself a test banner to prove it still works. It does not use the microphone, camera, location, contacts, screen recording or full-disk access. Its hotkey for acknowledging an alert needed no permission on macOS 26.7, the only version it has been checked on.
- It is not sandboxed, because the sandbox blocks Accessibility. That is also why it is not on the Mac App Store.
- What SignalLadder says and shows is visible to the room. Spoken alerts read notification text aloud, and the self-test banner is drawn on screen, screen shares included. The escalation panel is drawn over every app, but it names the rule and never what the notification said. The menu never shows a notification's title or body either, and neither does the on-call check window. The Inspector does.

## What SignalLadder reads, and how

SignalLadder learns about a notification one way. It asks macOS to tell it when Notification Centre, the macOS process that draws banners, opens or moves a window, removes an element, or changes its layout. When that happens, it reads every window Notification Centre has.

- It connects to one process: Notification Centre (`com.apple.notificationcenterui`). No other app is opened through Accessibility.
- It searches each of those windows, to a limited depth, for banner elements, which it recognises by their Accessibility type (their subrole). It reads text only from the banners it finds: the description and the text of the banner's direct child elements. That gives the app's name (worked out from the banner, so a guess), the title, subtitle and body, and the raw text. From everything else in those windows it reads only structure, such as the type of each element and whether a window has keyboard focus, which is how it tells Notification Centre's list from a banner. It reads no other text.
- It only reads. Its Accessibility calls register for events and read attributes, each read with a 0.2-second timeout. None performs an action, sets a value, or sends a key press or a mouse click. It never dismisses, opens or replies to a notification, and it never types.
- It sees only what Notification Centre draws. A notification held back by Do Not Disturb, a Focus, or switched-off banners is never drawn, so it is never read.

> [!IMPORTANT]
> The permission is broader than the use. macOS has no Accessibility grant that means "notifications only": once you allow SignalLadder, macOS lets it read the interface of any app. Nothing in macOS holds SignalLadder to Notification Centre. Its code does. If that matters to you, read it. Everything that reads another app's interface is in [`Sources/NotificationCapture/`](../Sources/NotificationCapture/), and [architecture](architecture.md) maps the rest.

Opening Notification Centre shows old notifications in the same window as new banners. SignalLadder recognises that window as Notification Centre's list by how it is built, not by what it says. Whatever the list holds when it opens is treated as old: its text is not read, so none of its text is kept. A notification that appears in the list after that is read like a banner. If it shows it is old, such as by a "1m ago"-style time at the end, it is dropped without being kept. Otherwise it is treated as new, because missing a real alert is the worse mistake. The list has only been checked on macOS 26.7. On a macOS where it is built differently, SignalLadder would not recognise it, and old notifications could be kept in memory and matched against your rules as if they had just arrived.

Some things it looks at need no permission:

- Its own notification settings, to tell whether its own banners would be shown.
- Whether the Mac's sound output is muted or at zero volume, so the Inspector can say an alert could not be heard.
- The Mac's Alert volume, which is the global preference `com.apple.sound.beep.volume`. It is read as a number, so that while you are on call SignalLadder can say when its own beeps cannot be heard. It is read and never written.
- The reason a quit carries, and the system's notice that a log out, a restart or a shut down was requested, so that SignalLadder does not hold one up with a question of its own. Of the notice, only the awake time of the latest is kept, in memory, until the next. It holds no notification content.
- The names of running apps when you choose **Open Notification Settings for …** in the mute checklist. If that does not find the app, it reads the names and identifiers declared by the apps in `/Applications`, `/System/Applications` and `~/Applications`, one folder level deep. It does this only when you ask, and keeps nothing.
- The names of your Shortcuts, only when a rule names a Shortcut, and only when your rules load or the rule editor checks them, which it does again after each **Test Shortcut**. It asks the `shortcuts` command for the list, to check that the name exists. The names are used for that check and are never logged.
- The time and how long the Mac has been awake, when an escalation starts, before each of its tiers acts, and when the Mac wakes, so an escalation can tell that the Mac slept. Apple documents that the awake time stops during sleep; that has not yet been measured on a Mac that sleeps. Only the latest reading is held, in memory, until the next.

It does not read macOS's notification database, the Focus database or the old file of notification settings. The first two are protected, and the third was a year out of date when it was checked on macOS 26, so it would report old settings as current. No code in SignalLadder refers to any of them.

## What it keeps, and where

### In memory

Notification text is held in memory, apart from the two cases under [On disk](#on-disk). SignalLadder keeps the last 50 notifications: the app, title, subtitle, body, raw text, banner type, time, the rule that matched, what the alert did and, for a rule that escalates, how far its escalation got. The Inspector shows them, and the rule editor tries a rule on them. When a 51st arrives, the oldest goes.

There is no time limit. On a quiet Mac a notification stays until 50 newer ones replace it or you quit. There is no clear-history command. **Quit SignalLadder** clears everything in this table.

| Held | What it is | For how long |
| ---- | ---------- | ------------ |
| The last 50 notifications | Everything listed above. For a rule that escalates, the record of its latest repeat and of its final alert includes the line either said, if it spoke. The Inspector does not show those lines | Until 50 newer ones arrive, or you quit |
| The Inspector and the rule editor | Copies of those same entries. The rule editor also keeps the notification you started a rule from | The copies follow the 50. The one you started from goes when you close the editor |
| An escalation's notification | A copy of the notification an escalation started from, kept so a later step can speak a line built from it or hand its four fields to a Shortcut | Until the escalation is finished with: acknowledged, and any Shortcut it started has reported. That can be after its row has left the 50. An escalation nobody acknowledges is kept until you quit |
| The duplicate filter | The raw text of recent banners, so one banner is counted once | Until the next banner arrives, so on a quiet Mac the last banner's raw text waits there |
| The last alert | What the latest match did. For a spoken alert, that includes the line it said | Until a later match replaces it. An alert that failed, a repeat or a final alert included, is held until a later alert succeeds. Either can outlive its row in the 50 |

"In memory" means SignalLadder writes none of this anywhere, apart from the two cases under [On disk](#on-disk). What macOS does with a running app's memory, such as paging it out to swap, is macOS's own business, and SignalLadder cannot control it.

### On disk

SignalLadder is not sandboxed, so its files are real paths, not a container. All but one are in your own Library folder. This is every place it writes, and the one folder it only reads:

| Path | What it holds | Written when |
| ---- | ------------- | ------------ |
| `~/Library/Application Support/com.jamiewhite.signalladder/rules.json` | Your rules | You press **Save** in the rule editor. Also created once, with one example rule switched off, if you choose **Open Rules File in Text Editor…** and no file exists. Never on load, never to tidy it |
| `rules.previous.json`, beside `rules.json` | The version the last ordinary save replaced | Each ordinary save. The next one overwrites it |
| `rules.replaced-….json`, beside `rules.json` | The version a **Save Anyway** replaced after the file changed under the editor. The name carries the date and time, for example `rules.replaced-2026-09-29-142702.json` | Each **Save Anyway**. SignalLadder never rotates or deletes these |
| `Sounds/`, beside `rules.json` | Your own alert sounds | You make this folder. SignalLadder only reads it |
| `~/Library/Preferences/com.jamiewhite.signalladder.plist` | Two keys of its own. `confirmedMutedAppDigests`: SHA-256 hashes of the names of apps you have marked as muted. `onCallSince`: the time you switched on-call mode on, as a number of seconds since 1970 | You tick or untick **I've Turned Its Sound Off** in the mute checklist, and you choose **On Call**: switching on saves `onCallSince` and switching off removes it. SignalLadder reads `onCallSince` once, when it starts |
| `com.jamiewhite.signalladder.shortcut-input/<random>/input.json`, in your account's temporary folder (the one `$TMPDIR` names in Terminal) | One notification's `appNameGuess`, `title`, `subtitle` and `body`, as JSON. Never the raw text, the time or the banner type | Each time a rule's last step runs a Shortcut, and each time you press **Test Shortcut** in the rule editor, when it holds the four fields of a made-up test notification and no real one. The folder is mode 0700 and the file 0600. Both are deleted the moment the Shortcut's process ends |

`onCallSince` is a date and nothing else, and it is the whole of what on-call mode saves. A value there that cannot be read as a time reads as on-call mode being on, with the time not known, because SignalLadder fails towards alerting. It does not keep anyone covered while SignalLadder is not running.

The hash is of the app's name with case and accents folded, and it is stored instead of the name. It has two limits. It is unsalted, so anyone holding the file can test a guess such as `microsoft teams` against it. And an app's name is worked out from the banner's text, so on a banner that parses oddly it can be a fragment of a message. The second limit is the reason it stores a hash rather than the name.

If `rules.json` is a symbolic link, SignalLadder saves through it to the file it points to, and keeps its backups beside the link. Pointing it into a synced or versioned folder is your choice, and it syncs your rules.

The rules file is written with default file permissions. SignalLadder does not tighten them.

The Shortcut's input file is the one place SignalLadder writes notification text to disk on its own, rather than because you put the text in a rule. It exists only for a rule whose last step runs a Shortcut, and only once that step fires, or once you press **Test Shortcut** in the rule editor, when it holds a made-up test notification and not one you received. It holds those four fields and nothing else, and its modes keep other accounts on the Mac out of it, though an administrator can read any file. SignalLadder deletes it the moment the Shortcut's process ends, however long that takes, and never waits for the Shortcut itself. It deletes the file. It does not overwrite it first. If you quit while a Shortcut is still running, the file is removed as SignalLadder quits. After a crash, anything left in that folder is removed the next time SignalLadder starts.

What the Shortcut does with that text is up to the Shortcut. SignalLadder hands it over and does not see or control what follows. A Shortcut can save the text, pass it to another app or send it off your Mac. Give a rule only a Shortcut you wrote or have read. **Test Shortcut** really runs the Shortcut, so one that sends a message will send it, with the test text. The test goes through the same code that writes and deletes the file for a rule's last step, which is tested against real folders. The button itself has not yet been run in the app.

> [!WARNING]
> Text you put in a rule condition is saved. **Make a Rule from This…** in the Inspector starts a rule from the app's name alone. But the rule editor's **Add Condition from This Notification** can offer the title, subtitle, body or raw text as a condition's value, and says beside it: _The text you add is saved in your rules file._ Once you save, that text is in `rules.json`. Removing the condition and saving again does not take it back: the earlier version stays in `rules.previous.json` until your next save replaces it, and in any `rules.replaced-….json` until you delete that file. Time Machine, or a synced home folder, carries these files too. Trim a condition to the part that matters, such as `deploy failed`, and leave out names and message text you would not want on disk.

SignalLadder's code writes nothing else: no cache, no Keychain entry, no clipboard content and no export.

## What it never does

SignalLadder's own code:

- Makes no network connection. It contains no networking, telemetry, analytics, crash reporting or update checking, so there is nothing to allow-list on a firewall. Updates are manual. A Shortcut you name in a rule is a separate matter: it may use the network, and that is the Shortcut's connection, not SignalLadder's.
- Has no third-party dependencies. `Package.swift` declares none, and the app imports only Apple frameworks: Foundation, AppKit, SwiftUI, Combine, UserNotifications, ApplicationServices, AVFoundation, AudioToolbox, CoreAudio, CryptoKit, Carbon (for the acknowledge hotkey) and os.
- Runs no scripts and no shell. The one program it runs itself is `/usr/bin/shortcuts`, and only for a rule that names a Shortcut: `shortcuts list`, to check that the name exists when your rules load or the rule editor checks them, and `shortcuts run`, when the rule's last step fires or you press **Test Shortcut** in the rule editor. It never logs what `shortcuts` prints. It also opens System Settings, and the text editor for your rules file (or Finder, if nothing on your Mac opens JSON), but only when you choose them.
- Never writes to the clipboard.
- Does not start itself. There is no login item, background service or helper. You open it.

You can check the first two claims yourself. From a copy of the source:

```sh
# Anything that could open a connection: prints nothing
grep -rnE 'URLSession|URLRequest|NWConnection|CFNetwork|WebKit|Sparkle|import Network' Sources

# Any external package: prints nothing
grep -nE '\.package|\.product' Package.swift
```

Two limits apply. First, a search of the source cannot rule out what Apple's own frameworks do, since Foundation and AppKit can reach the network for their own reasons. A firewall such as Little Snitch, or a look at a running copy with `lsof -i -a -p "$(pgrep -x SignalLadder)"`, shows what the app is actually doing at that moment. Second, these statements are about SignalLadder's code, not the systems it hands data to. A spoken line goes to macOS's speech synthesis, **Open Rules File in Text Editor…** opens the file in whichever app you use for JSON, and a Shortcut is handed a notification's app name, title, subtitle and body. What they do is up to them. A Shortcut does whatever you built it to do, including send that text off your Mac. SignalLadder offers only voices already installed on your Mac, and never Siri voices.

One automated test backs part of this. It fails the test suite if the matching, health and escalation logic in `Sources/NotificationCore` refers to the file system or `URLSession`. It covers that one module. The module that writes the Shortcut's input file, `Sources/ShortcutRunner`, has tests of its own, run against real folders. For the rest, the guarantee is the source itself and code review.

## Logs

SignalLadder writes to the macOS unified log, under the subsystem `com.jamiewhite.signalladder`, in four categories.

| Category | What it records |
| -------- | --------------- |
| `watcher` | Whether it attached to Notification Centre, and the process ID it attached to. Retry delays. Accessibility error codes. When a banner has no readable text, the banner's type (its subrole) |
| `speech` | How many milliseconds a spoken alert took to start, and whether its voice had been measured yet. Two fixed sentences, for a line that produced no audio or did not finish in time |
| `hotkey` | Only if the acknowledge hotkey could not be set up: one of two fixed sentences, and the status code macOS returned |
| `quit` | One line for every quit SignalLadder is asked about, a log out and a restart included: the four characters of the quit's reason code, or none, and the age of any power-off notice, or none |

Those are the only things it logs. Notification text never appears in the log, and neither does what a spoken alert said. A Shortcut's own output is never logged either, and neither is the list of your Shortcuts' names.

The `watcher` lines are marked public, so macOS does not redact them when you read them. The `speech` lines hold only a number and one fixed label. Both are written at the default level rather than the info level, which macOS keeps in memory only. The `hotkey` lines hold only a status code, marked public, and are written at the error level. The `quit` lines hold only a code and an age, marked public, and are written at the default level so that a log out or a restart that has finished can still be read afterwards. How long macOS keeps any of them is its decision.

To read them:

```sh
/usr/bin/log show --last 30m --predicate 'subsystem == "com.jamiewhite.signalladder"'
```

Use the full path. In zsh, `log` on its own is a built-in and does something else.

Nothing enforces "never notification text" automatically. It is upheld by convention and review. A comment on the watcher's log function says the public marking is safe only because notification content never passes through it, and that callers must pass a process ID, a subrole or a count, never a notification's text. The pull request checklist asks every contributor to confirm that no notification text reaches a log, a file, a fixture or a screenshot, apart from the Shortcut's input file, which [On disk](#on-disk) describes. The automated test above does not look at logging.

SignalLadder installs no crash handler and sends no crash reports. macOS's own crash reporting works for it as it does for any app, and is outside SignalLadder's control.

## Permissions

At launch SignalLadder asks macOS to show its two standard permission prompts, Accessibility first. It has no set-up wizard of its own. [Getting started](getting-started.md) walks through granting them.

| Permission | Required | What it is for |
| ---------- | -------- | -------------- |
| Accessibility (System Settings › Privacy & Security › Accessibility) | Yes | Reading banner text. Accessibility is how SignalLadder reads banners |
| Notifications (System Settings › Notifications) | For the self-test and the health alarm only | Posting SignalLadder's own test banner and its own alarm. It asks for alerts only: no sound, no badge |

SignalLadder does not need, and its code does not use, the microphone, camera, screen recording, full-disk access, location, contacts or automation. Speech is text-to-speech only: nothing is recorded.

Two things need no permission:

- **The acknowledge hotkey.** Control-Option-Command-A acknowledges every alert still waiting to be acknowledged, from any app. SignalLadder registers it with macOS through Carbon, which tells it when that one combination is pressed. It reads no other key press. On macOS 26.7, the only version it has been checked on, it needed no permission and showed no prompt. Another version could behave differently. If macOS refuses the hotkey, SignalLadder logs the status code and carries on: the menu's Acknowledge and the panel's buttons work without it.
- **Keeping the Mac awake.** While an escalation still has a step to fire, SignalLadder asks macOS not to let the Mac go to sleep on its own, and stops asking once no step is left. While you are on call it makes a second request of its own, for as long as the mode is on, so that an escalation ending does not release it. Whether macOS honours either has not yet been checked on a Mac that can sleep. Neither keeps the display awake.

### If Accessibility is missing

Nothing is captured, and SignalLadder says so in four places.

- The menu's health line reads _NOT capturing notifications_. Beneath it is _Grant Accessibility to SignalLadder in System Settings — without it no notifications can be read._ Choosing that line opens the Accessibility pane.
- The menu-bar icon becomes a bell with a line through it.
- The Mac beeps. While you are on call it keeps beeping while the fault stands.
- If SignalLadder's own banners can be shown, a banner titled _SignalLadder is not capturing_ appears.

Granting it while the app runs takes effect the next time you open the menu, with no relaunch. If it is revoked while the app runs, the menu shows the problem as soon as you open it. The beep and banner come with the next health check. By design that runs every 30 minutes, or every 5 while you are on call, and whenever you open the menu, though the delay has not been timed on a real revocation.

### If Notifications is denied

Capture still works, but SignalLadder can no longer prove that it does. Allow it: the self-test is how you find out that capture has stopped.

- The menu's health line reads _Cannot verify itself_. Beneath it is _Allow notifications for SignalLadder in System Settings — without it the app cannot verify it is working._
- The icon changes and the Mac beeps, but no banner is posted, because none could be shown.

### Not sandboxed, and what that means

The App Sandbox blocks the Accessibility API from reading another app's interface. An app that does what SignalLadder does cannot be sandboxed, and the Mac App Store requires the sandbox, so SignalLadder cannot be offered there. The plan is to sell signed, notarised builds directly from this project instead. Until then, you build it yourself.

The build script, `Scripts/make-app.sh`, signs the app with the Hardened Runtime and passes no entitlements. It refuses an ad-hoc signature, because that would break the Accessibility grant on every rebuild. There is no notarised download yet. To check a build you have made:

```sh
codesign -dv --verbose=2 build/SignalLadder.app          # flags include (runtime)
codesign -d --entitlements - build/SignalLadder.app      # prints no entitlements
```

## What you and others may see or hear

- **The self-test banner.** To prove capture still works, SignalLadder posts a banner titled _SignalLadder self-test_ and reads it back. It does this at launch, again about two minutes later, then every 30 minutes, and more often for a while after a failed check. While you are on call it runs every 5 minutes instead, about 12 times an hour, and once when the Mac wakes. Its text is a fixed marker followed by a random identifier: no notification text, none of your data. It is drawn like any banner, so anyone watching your screen sees it, and so does a screen share that includes banners. SignalLadder removes it from Notification Centre afterwards. A Focus or Do Not Disturb hides it, and SignalLadder then reports that it cannot verify itself. [Troubleshooting](troubleshooting.md) covers that.
- **The health alarm.** If capture stops, or SignalLadder cannot verify itself, it beeps and, where its own banners can be shown, posts a banner titled _SignalLadder is not capturing_ or _SignalLadder cannot verify itself_, with the advice line as its text. You did not write a rule for this. It is the one alert SignalLadder raises on its own, and it stays in Notification Centre until you clear it. The beep is the Mac's alert sound, which anyone in earshot hears, and while you are on call it repeats for as long as the fault stands. The banner comes once.
- **Spoken alerts.** A rule that speaks reads a line built from the notification aloud, through the Mac's current sound output. The default line is `{app}: {title}`, the app's name and the title without the body, and a spoken line stops at 240 characters whatever the template. Anyone in earshot hears it. A repeat or a final alert can speak too, and reads a line built the same way. [Speech](rules-format.md#speech) explains the template.
- **The escalation panel.** A rule with a panel step shows one after the delay you set, 10 seconds by default. It is a borderless window in the top-right corner of the screen the pointer is on, over every app and every Space, full-screen apps included, and it does not take focus. Over full-screen apps and other Spaces, that was seen in a test program on macOS 26.7, and has not yet been checked in the app itself, so assume it shows there. It stays until each escalation on it is acknowledged, so anyone looking at your screen sees it, and so does a share of the whole screen. Its title is _SignalLadder: waiting for you to acknowledge_. Each row has its own Acknowledge button and names the rule, when it started and how far it has got, for example _On-call mentions — since 10:42 — tier 3, repeat 2 of 20_. It never shows what the notification said. It does show your rule's name, so give rules names you would not mind a shared screen showing.
- **The menu.** It never shows a notification's title or body, or what was spoken. It shows the number captured and, for the last match, the rule's name, the time and what the alert did. While an alert is escalating it also shows how many are, such as _2 alerts escalating_, and how many were missed while asleep. A Shortcut that did not run appears with its rule's name, the time and the Shortcut's name, in SignalLadder's own words and never the Shortcut's output. A Shortcut name the Shortcuts app does not list appears the same way, with its rule's name and the Shortcut's name, as a warning. While you are on call it also shows when you went on call, as _On call since Mon 09:00_, and a line for each finding that the other lines do not already say, in words and counts and never a name. The mute checklist names apps: those your sounding rules name, and those that have set one off. An app's name is read from the banner, so it is not always exact. The rules section names your rules.
- **The on-call check window.** While you are on call, **Show On-Call Check…** opens an ordinary window, and it can open by itself when something new turns up. It lists findings as sentences and counts. It names no rule, app or Shortcut and holds no notification text. It is drawn on screen, so a shared screen shows it, and it shows your own state, such as a rule that is not in effect or a muted output.
- **The Inspector.** It shows the notification in full: app, title, subtitle, body, the raw text and, for a spoken alert, _Said: “…”_. A row for a rule that escalated adds a line saying how far it got, without what any repeat or final alert spoke. Keep it closed on a shared screen. The raw text and the spoken line can be selected and copied, and a clipboard manager would keep what you copy. The rule editor's dry run also lists the time, app and title of the notifications a rule matches.

## Removing everything

1. Quit SignalLadder with **Quit SignalLadder** in the menu. That clears the notification history from memory, and removes any Shortcut input file still on disk. If an alert is still waiting to be acknowledged, or you are on call, it asks first, because quitting stops it. A log out, a restart or a shut down does not ask.
2. Delete the folder `~/Library/Application Support/com.jamiewhite.signalladder/`. It holds your rules, their backups and your `Sounds` folder, so copy out anything you want to keep first.
3. Delete `~/Library/Preferences/com.jamiewhite.signalladder.plist`. It holds the mute checklist's hashes and the time you went on call.
4. In System Settings, remove SignalLadder from Privacy & Security › Accessibility, and from Notifications. Optionally, reset the Accessibility entry from Terminal: `tccutil reset Accessibility com.jamiewhite.signalladder`.
5. Delete `SignalLadder.app`, wherever you put it.

That is all of it. SignalLadder installs no login item, background service or helper, and stores nothing in the Keychain. Three things are outside its reach: the lines it wrote to the macOS log stay until macOS ages them out, copies of your rules file in Time Machine or a sync service stay until you delete them there, and anything a Shortcut you wrote did with a notification's text stays wherever that Shortcut put it.

One more case: if SignalLadder crashed while a Shortcut was running, that Shortcut's input file stays in the `com.jamiewhite.signalladder.shortcut-input` folder in your temporary folder until you open SignalLadder again, or delete it yourself.

## Future changes

Escalation is built, and so is its editor, and so is on-call mode, and this page describes all three above. The editor's ladder controls were drawn and driven in a test program, and have since been seen in the app itself; their live checks are still to do. On-call mode is built and its decisions are tested, but SignalLadder itself has not been run with it, so what this page says of it is what the code does and not something seen in the running app. When a change alters what SignalLadder stores, logs, sends or asks for, this page changes with it.

If SignalLadder does something this page says it does not, please report it privately. See [SECURITY.md](../SECURITY.md).
