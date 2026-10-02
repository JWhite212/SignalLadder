# Getting started

This guide takes you from a fresh clone to a first rule that sounds for the notifications you care about and stays quiet for the rest. It is written for a Mac user who is comfortable in Terminal, often someone on call, and does not need to know Swift.

SignalLadder is pre-release software (version 0.1.0). There is no download yet, no signed and notarised build and no installer, so you build the app from source. The build itself is quick. The step that takes thought is the first one: a code-signing identity, which macOS needs before it will keep SignalLadder's permission from one build to the next.

By the end you will have:

- SignalLadder running from **/Applications**, with the two permissions it needs.
- A look at what your apps really send, in the Inspector.
- One rule, proven against real notifications before you trust it to make a sound.
- The source app's own sound switched off, so your rule is its only voice.
- A check that Do Not Disturb and Focus modes are not hiding notifications from SignalLadder.
- If you are on call, [on-call mode](#on-call-mode) switched on for the hours you must be reached.

## What you need

- **An Apple silicon Mac running macOS 14 Sonoma or later.** SignalLadder is built for Apple silicon only: there is no Intel or universal build, and an Intel Mac is not supported. It declares macOS 14 as its minimum, but it is developed and tested on macOS 26, and every live check so far ran on one Apple silicon Mac. macOS 14 and 15 are supported targets that have not yet been verified. This guide uses macOS 26's wording for System Settings; earlier versions name some switches differently.
- **Xcode, or the Xcode command-line tools, with a Swift 6 toolchain.** The project is built with a recent Xcode and does not promise a specific minimum version. Run `swift --version` to see what you have. If the command is not found, `xcode-select --install` installs the command-line tools. SignalLadder has no third-party dependencies, so building it fetches no packages.
- **git.** It comes with the command-line tools.
- **A code-signing identity.** The next section explains why, and how to find one.

### The signing identity

SignalLadder reads notifications through macOS Accessibility, and macOS ties that permission to the app's code signature. An ad-hoc signature is only a hash of one build's code, so it is different every time you build. macOS would see each rebuild as a new app and forget the grant, and you would have to grant Accessibility again after every build. A signature made with a real identity stays the same from build to build, so the grant survives.

So [`Scripts/make-app.sh`](../Scripts/make-app.sh) refuses ad-hoc signing. It also refuses an identity given by name. It accepts only the identity's 40-character SHA-1 hash, and it stops with an error rather than build an app that would lose its permission a build later.

To find your identity:

```sh
security find-identity -v -p codesigning
```

The output looks like this, with your own hash and name:

```
  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Your Name (TEAMID1234)"
     1 valid identities found
```

Copy the 40-character hexadecimal string at the start of the line, not the name in quotes. You will pass it to the build as `SIGNALLADDER_IDENTITY`.

If the command reports `0 valid identities found`, make one. In Xcode, open **Settings › Accounts**, sign in with an Apple ID (a free one is enough), choose **Manage Certificates…** and add an **Apple Development** certificate. Then run the command again.

Only Developer ID signing has been tested. A Developer ID Application identity, which comes with a paid Apple Developer Program membership, is what the maintainer builds with. An Apple Development certificate should work, because the script asks only for a stable signature, but nobody has confirmed it yet. If you try one and macOS forgets the Accessibility grant after a rebuild, please [open an issue](https://github.com/JWhite212/SignalLadder/issues/new/choose).

## Build the app

1. Clone the repository:

   ```sh
   git clone https://github.com/JWhite212/SignalLadder.git
   cd SignalLadder
   ```

2. Optionally, run the tests:

   ```sh
   swift test
   ```

   This needs no signing identity. The audio tests render offline, so nothing plays. Some speech tests skip themselves on a Mac that lacks particular voices, and a skip is not a failure. A Mac with no audio output device can fail one output-state test.

3. Build, sign and assemble the app, with your own hash in place of the placeholder:

   ```sh
   SIGNALLADDER_IDENTITY=<your 40-character SHA-1> ./Scripts/make-app.sh release
   ```

   Do not leave the variable out. The script has no default identity, because a hash only works on the Mac whose keychain holds it, so without the variable it stops at once with an error, before it builds anything.

4. Copy the result to Applications and launch that copy. Drag **build/SignalLadder.app** into **/Applications** in Finder, or run:

   ```sh
   cp -R build/SignalLadder.app /Applications/
   ```

### What the script does

1. Builds the `SignalLadder` product with Swift Package Manager.
2. Assembles the app in a staging folder: the executable, `Info.plist` and the app icon (`Resources/AppIcon.icns`), nothing else. The app bundles no audio; it uses the macOS sounds and any files you add.
3. Signs it with your identity, with Hardened Runtime switched on and the bundle identifier from `Resources/Info.plist`.
4. Verifies the signature.
5. Only then replaces `build/SignalLadder.app`. A failure at any step leaves the previous good build where it was.

It ends with `Built build/SignalLadder.app`, followed by a note that it does not read the signature's requirement back, because `codesign -d` has been seen to hang on the maintainer's Mac. The note is informational.

`make-app.sh` deletes and recreates `build/SignalLadder.app` on every build, which is why you run the copy in **/Applications**: an app running from `build/` would have its bundle replaced beneath it. Because you built the app on this Mac, macOS does not treat it as a download from the internet.

A `release` build asks Apple's timestamp service for a secure timestamp, so it needs an internet connection. If the service is unavailable the build fails rather than produce an app without one, and you run it again. A `debug` build skips the timestamp and is signed the same way in every other respect.

### If the build stops

| You see | It means |
| --- | --- |
| `error: SIGNALLADDER_IDENTITY is not set.` | The script has no default identity. Pass yours as shown above, or add `export SIGNALLADDER_IDENTITY=<your SHA-1>` to your shell profile. |
| `error: SIGNALLADDER_IDENTITY must be the 40-character SHA-1 of a signing identity.` | You passed a name, `-`, or a string of the wrong length. Use the hash. |
| `<hash>: no identity found` | The hash is not in your keychain, often because of a typo. The compile has already finished; fix the hash and run the script again. |
| `A timestamp was expected but was not found` | The timestamp service did not answer during a `release` build. Run it again. |
| `swift: command not found`, or errors about the Swift version | The toolchain is missing or too old. See [What you need](#what-you-need). |

For anything else, see [troubleshooting](troubleshooting.md).

## First launch

Open the app:

```sh
open /Applications/SignalLadder.app
```

1. **Find the bell.** SignalLadder lives in the menu bar. It has no Dock icon and no window. Its app icon is a bell built from ladder rungs. If you cannot see the bell, the menu bar may be full: on a Mac with a notch, items that do not fit are hidden.

2. **Accessibility.** SignalLadder asks for Accessibility first. This is how it reads notification banners: it attaches to Notification Centre and reads the text of each banner as macOS draws it. It only reads. It never clicks, dismisses or types, and it looks at Notification Centre only. macOS offers Accessibility as one broad permission and cannot limit an app to a single use, so the limit is in SignalLadder's code, which you can read in [`Sources/NotificationCapture`](../Sources/NotificationCapture). [Privacy](privacy.md) has the detail.

3. **Notifications.** Straight after, it asks to show notifications, and you may see both dialogs together. It asks for alerts only, not sounds or badges. The permission is for one purpose: SignalLadder posts a test banner to itself to prove it can still read banners (see [The self-test banner](#the-self-test-banner)). It is not needed to read your other apps' notifications. If you say no, capture still works, but SignalLadder can no longer prove it, and the health line says so.

4. **Grant Accessibility.** The Accessibility dialog has a button that opens System Settings. If you closed it, click the advice line in the SignalLadder menu, which opens the same place. In **System Settings › Privacy & Security › Accessibility**, switch **SignalLadder** on. macOS may ask you to authenticate.

5. **Open the menu again.** Capture starts the next time you open the menu after you grant Accessibility, or when you answer the Notifications prompt if that comes later. A background check does not start it, so open the menu once. You do not need to relaunch. Starting capture triggers an immediate self-test. Give it a few seconds, then open the menu once more: the top line should read _Working — verified just now_.

If it does not, the line beneath the health line says what to do. [Troubleshooting](troubleshooting.md) covers the cases by symptom.

### What the menu says

Before you grant Accessibility, the top line reads _Checking…_ until you answer the Notifications prompt. After that the bell gets a slash through it, and the menu shows:

- _NOT capturing notifications_.
- A clickable advice line beneath it: _Grant Accessibility to SignalLadder in System Settings — without it no notifications can be read._ Clicking it opens the Accessibility pane.

You also hear a system beep and, if you allowed notifications, see a banner titled _SignalLadder is not capturing_. Each happens once when the state changes, not repeatedly. While you are on call the beep does repeat, for as long as the fault stands: see [On-call mode](#on-call-mode).

After you grant it, the bell returns to normal, and the health line is one of these:

| Health line | Means |
| --- | --- |
| _Checking…_ | No self-test has finished yet. You see this just after launch. |
| _Working — verified just now_, or _Working — verified 3 min ago_ | The last self-test read its own banner back, this long ago. |
| _Unverified — last verified 34 min ago_ | That evidence is older than a self-test cycle plus a minute, counting any time the Mac was asleep. Nothing has been seen to fail; a self-test that should have run has not. |
| _Cannot verify itself_ | Something stops SignalLadder proving it works: Notifications denied, its own banners switched off, a Focus hiding them, or a self-test that failed. A line beneath says what to do. |
| _NOT capturing notifications_ | SignalLadder is not reading banners: Accessibility is not granted, it is not attached to Notification Centre, or self-tests keep failing although Notification Centre showed activity while they ran. A line beneath says what to do. |

Below the health line comes the **On Call** item, which [on-call mode](#on-call-mode) is switched on with. Then the menu counts what it has read (_Captured 0 notifications_ to start with) and shows the state of your rules. The bell changes to the slashed one for a rules-file problem, a sound that could not play, a Shortcut that could not run or a Shortcut name the Shortcuts app does not list, as well as for a capture fault. While you are on call it changes to the slashed bell for three more things: capture that has stayed unverified, a muted output while a rule sounds, and an Alert volume of zero.

### The self-test banner

Silence proves nothing: a quiet Mac and a broken reader look the same. So SignalLadder sends itself a real notification and checks that it can read it back.

- The banner is titled _SignalLadder self-test_. Its body is _SignalLadder canary_ followed by a random code. It has no sound and carries none of your data.
- It runs when SignalLadder starts, about two minutes later, and then every 30 minutes, or every 5 while you are on call. If one fails, it tries again after a minute, then less often, up to every 30 minutes, or every 5 on call. It also runs soon after something that was blocking it clears, such as granting Accessibility, and, while you are on call, when the Mac wakes.
- SignalLadder waits up to five seconds to read it back, then removes it from Notification Centre. It is not counted in _Captured N notifications_, it does not appear in the Inspector, and no rule sees it.
- It is an ordinary banner while it is on screen, so it shows on a shared screen too. While you are on call that is about 12 times an hour.

### Keep SignalLadder's own banners on

The self-test is a real banner, so it has to be drawn. In **System Settings › Notifications › SignalLadder**, leave notifications allowed and shown as banners: on macOS 26, the **Desktop** checkbox; before macOS 26, an alert style other than None. Do not set them to Deliver Quietly or a Scheduled Summary either.

If SignalLadder's own banners are off, it cannot prove it is working, and the health line reads _Cannot verify itself_. Capture of your other apps is unaffected. The switch takes away only the proof.

## See what your apps actually send

A rule can only match text SignalLadder has read, and apps do not all put things in the same place. So look before you write anything. Open the menu and choose **Show Inspector…** (⌘I). The window is titled SignalLadder Inspector.

![The Inspector listing captured notifications, some matched by a rule and some not](assets/screenshots/inspector.png)

When nothing has arrived yet, it says so. _Nothing captured yet. Capture is verified working, so this is simply quiet._ means capture is fine and nothing has come in. If it says SignalLadder cannot confirm it is capturing, read the health line and advice under it first.

To see a row straight away, post a practice notification from Terminal:

```sh
osascript -e 'display notification "Placeholder body" with title "Test title" subtitle "Test subtitle"'
```

It arrives as **Script Editor**. If no banner appears, check that Script Editor is allowed to show notifications in System Settings › Notifications.

The Inspector lists the last 50 notifications, newest first. Nothing in it is saved: it is held in memory and is gone when SignalLadder quits. Each row shows:

| On the row | What it shows |
| --- | --- |
| App name | The app's display name, as SignalLadder read it from the banner, or _(no app name)_. It is a heuristic. |
| Time | When the banner was captured, as HH:mm:ss. |
| Title, subtitle, body | The banner's text lines. Many banners have no subtitle. |
| Banner kind | The banner's accessibility type, such as `AXNotificationCenterBanner` or `AXNotificationCenterAlert`. It follows whether the app is set to Banner or Alert in System Settings › Notifications. |
| _N in the last hour_ | How many notifications that app has sent in the hour up to this one. It reads _N+_ when the 50-row memory overflowed and the true count may be higher. This is how you spot the chatty app. |
| _N suppressed_ | Identical copies that arrived within about a second and a half and were folded into this row. Shown only when there are some. |
| Match line | _Matched_ and the rule's name, _Matched no rule_, or _Not evaluated — no rules loaded_. |
| Alert line | What the app did about a match, such as _Played Glass (+6 dB)_ or _Silent by rule_. It is orange when you were not alerted as the rule intended. See [what the app records](rules-format.md#what-the-app-records). |
| Escalation line | Shown only when the rule that matched has an escalation: _Escalating_, _Acknowledged at 14:05:12_ or _Missed while asleep, found on waking at 14:20:31_, then how far it got, such as _reached tier 3 — repeated 2 of 20_. It never shows what a repeat said. See [Alerts that keep going until you answer](#alerts-that-keep-going-until-you-answer). |
| Blue line | What your current rules _would_ do with this notification, shown only when that differs from what happened. It never plays anything. See [testing a rule](rules-format.md#testing-a-rule-before-you-trust-it). |
| **Raw** | The banner's unparsed text. Open it when you are not sure which field something landed in. |
| **Make a Rule from This…** | Starts a rule from this notification. See the next section. |

Some things to keep in mind as you read it:

- **SignalLadder sees only what macOS draws.** A notification appears in the Inspector only if macOS shows it as a banner or alert on screen. One that macOS sends straight to Notification Centre never does: with Do Not Disturb or a Focus on, banners switched off for the app, Deliver Quietly, or a Scheduled Summary. Both the Banner and Alert styles are seen.
- **Look; do not assume.** The project has not yet recorded what a real Microsoft Teams @mention looks like in these fields, so there is no ready-made "mentions me" rule. Build yours from what your own Inspector shows.
- **The fields you can match** are App, Title, Subtitle, Body, Any text (the raw text) and Banner kind. [Rules format](rules-format.md#fields) says what each holds.

## Make your first rule

![The rule editor with a rule selected, showing its conditions, its alert, its ladder and the dry-run](assets/screenshots/rule-editor.png)

1. **Start from a real notification.** In the Inspector, find one you would want to hear about and choose **Make a Rule from This…** on its row. The editor, titled SignalLadder Rules, opens with a new rule named “New rule for Microsoft Teams” (or whichever app it came from). Its condition is App is Microsoft Teams, it is **switched off**, and it has **no alert**. It is placed just above the first rule that would already take that notification, or last if none would. You can also open the editor from the menu with **Edit Rules…** (⌘E) and add a rule with the **+** button.

2. **Name it.** Change the **Rule name** to something you will recognise in the Inspector and menu.

3. **Narrow the condition.** _App is Microsoft Teams_ matches everything Teams sends, which is the noise you are trying to cut through. Under **When a notification matches**, choose **Add Condition from This Notification**. It offers one condition per field, taken from the notification you started from. Pick one, then shorten its value to the part that matters. A new condition joins the first one, so the rule matches only when all of them do.

   Each condition has a field (App, Title, Subtitle, Body, Any text or Banner kind), an operator (**is**, **is not**, **contains** or **matches pattern**) and a value. Matching ignores case and accents. In a pattern, `*` stands for any run of characters and `?` for exactly one, and the pattern must cover the whole field. **All of these** and **Any of these** switch a group between requiring every condition and requiring any one. The circled-ellipsis menus beside a group or a condition add, group, negate and remove.

   For example, keep _App is Microsoft Teams_ and add _Any text contains "incident"_.

4. **Watch the dry-run.** Under **Tried on recent notifications**, the editor tries the rule on every notification SignalLadder is holding as you edit. While the rule is off it reads _In this draft: would match 2 of the last 6 notifications when switched on._ Once it is on, _In this draft: matches 2 of the last 6 notifications._ The matches are listed beneath. If nothing matches, or too much does, adjust the condition until the list is what you meant.

5. **Move it above a rule that takes its notifications.** Rules are tried from the top and the first enabled rule that matches wins, so a notification only ever sets off one rule. If another rule takes some of yours, the dry-run says so: _1 more is taken first by “Rule”, above it._ Choose **Move Above “Rule”**, or drag the rule by its handle in the list. The label under the list reads _Top rule wins_.

6. **Choose an alert.** Under **Then**, pick one:

   | Choice | What the editor says it does |
   | --- | --- |
   | **No Alert** | Matching notifications are marked in the Inspector. Nothing plays. |
   | **Silent** | Matching notifications are claimed and stay quiet: no rule below can sound for them. |
   | **Sound** | Plays this sound when a notification matches. |
   | **Speech** | Speaks a line built from the notification when one matches. |

   - **For a sound**, choose it from the list (the macOS sounds, plus any files you add yourself) and press **Test Sound** to hear it exactly as the alert will play it. Set the **Gain** from −40 to +12 dB. Every sound is level-matched, so at 0 dB each one peaks at the same level, however loud its file is. A very quiet file is boosted by at most 24 dB, so it can stay quieter than the rest. Turn on **Also speak it** to play the sound and then speak.
   - **For speech**, pick a **Voice**, adjust what it **Says** (`{app}: {title}` unless you change it) and press **Test Speech**. It reads a made-up notification, so nothing real is spoken aloud.
   - **If you hear nothing**, the editor warns you when the Mac's output is muted or at zero volume.

   [Rules format](rules-format.md#alerts) has the rest.

7. **Decide what happens if you do not acknowledge.** A rule that only needs to sound once can skip this. Beneath the alert, **If I don't acknowledge** is a choice of four, and the sentence under it says in words what you chose:

   | Choice | What it does |
   | --- | --- |
   | **Off** | Nothing happens after the first alert. |
   | **Gentle** | After 10 seconds a panel stays on screen until you acknowledge it. |
   | **On call** | The panel after 10 seconds, then the first alert's sound again every 30 seconds, up to 20 times or 10 minutes. |
   | **Wake me** | The panel after 5 seconds, then the same every 15 seconds, with no limit on repeats or time. It keeps sounding until you acknowledge it, and asks macOS to keep the Mac awake meanwhile. That request has not yet been tested on a Mac that can sleep: see [Things to know](#things-to-know). |

   The three that do something are offered once the rule has a first alert, and a **Silent** one counts. **Customise…** opens every control: a switch for each of tiers 2 to 4, their delays, the repeat's alert, interval and limits, and the last step. To page your phone, open **Customise…**, switch on **Tier 4**, choose **Shortcut**, type its name exactly as it is in the Shortcuts app and press **Test Shortcut**. That really runs the Shortcut, with a test notification, so if it pages you, you will be paged. [Alerts that keep going until you answer](#alerts-that-keep-going-until-you-answer) says what each tier does, and [In the rule editor](rules-format.md#in-the-rule-editor) has the rest. These controls were drawn and driven in a test program outside the app, and have since been opened in SignalLadder itself. Their live checks are still to do.

8. **Switch the rule On.** Use the **On** switch beside the rule name, or the checkbox in the list.

9. **Save.** Press **Save** (⌘S). The bar at the top changes from _Unsaved changes — not in effect until you save_ to _Saved and in effect_. Saving takes effect at once. You do not need **Reload Rules**. The menu's rules line now counts it, for example _Rules: 1 active_.

An orange triangle beside a rule, or _Saved and in effect — except that 1 rule has problems and does not run_, means a rule has something to fix. The problem is written under its name.

When a matching notification arrives, its Inspector row reads _Matched_ and the rule's name, then what was done, such as _Played Glass_. The menu shows the last one as _Last match: … at 14:02 — Played Glass_.

### Prove it before you trust it

A rule with no alert is a safe way to check its matches against real traffic. Save it switched on with **No Alert**, let a few notifications arrive, and read the Inspector. Matching rows say _Matched_ and the rule's name, then _Silent — this rule has no alert_. Nothing plays. When the matches are right, choose **Sound** and save again.

If you practise on the Script Editor notification from earlier, delete the practice rule afterwards: select it and press Delete, or use the **−** button.

### Alerts that keep going until you answer

A match sounds its alert once. If you cannot afford to miss it, give the rule an **escalation**, and SignalLadder keeps going until you acknowledge it. The rule's own alert is tier 1. Up to three more tiers follow, each optional, and each timed from the match, not from the tier before:

2. **A panel** appears over every app after a delay.
3. **An alert repeats** on a timer, up to a cap. It can be a different sound from the first.
4. **A last alert plays, or a Shortcut runs**, after a delay of its own. A Shortcut can reach your phone.

Only one alert plays at a time, so a new one cuts off one still playing.

The rule editor sets one up: see step 7 of [Make your first rule](#make-your-first-rule). You can also write it in the rules file (see [Writing rules by hand](#writing-rules-by-hand)) and choose **Reload Rules**. The editor shows what you wrote and keeps it when you save. In the file, put the rule in the `"rules"` list of a file that starts with `"version": 4`. This rule uses all three later tiers:

```json
{
  "name": "On-call mentions",
  "condition": { "field": "title", "op": "contains", "value": "mentioned you" },
  "alert": { "sound": "Glass" },
  "escalation": {
    "tier2": { "delaySeconds": 10 },
    "tier3": { "action": { "sound": "Hero" }, "intervalSeconds": 30 },
    "tier4": { "afterSeconds": 120, "shortcut": "Page me" }
  }
}
```

For a notification titled _Alex Example mentioned you_, Glass plays at once. After 10 seconds the panel appears. Hero repeats every 30 seconds. Two minutes after the match, the Shortcut named _Page me_ runs. The rule sets no caps, so the default caps apply: the repeats stop after 20 of them or after ten minutes, whichever comes first. [Rules format](rules-format.md#escalation) has every key, its default and how to change a cap.

The Shortcut's name must match one in the Shortcuts app exactly, capitals included, and SignalLadder checks it when the rules load. If no Shortcut has that name, the rule is not refused. It stays in effect, first alert included, and tier 4 still tries the name when it fires. But the menu shows a ⚠︎ line, the bell turns to the slashed one and the editor says so beside the name, so you find a typo now and not when the page matters. Make the Shortcut first, and press **Test Shortcut** in the editor to run it with a test notification. It runs with four fields of the notification (app name, title, subtitle and body) as JSON in a temporary file. The file is deleted as soon as the Shortcut ends. This is the one place SignalLadder itself writes a notification's text to disk; the only other is text you put into a rule yourself. **Test Shortcut** writes the same file, holding a made-up test notification and none of yours. What the Shortcut does with it is up to you. See [Privacy](privacy.md). Try the Shortcut yourself in the Shortcuts app before you rely on it.

#### Acknowledging

Acknowledging stops every step still to come. There are three ways to do it:

- **In the panel**, for a rule that has a panel step. It sits over every app and every Space, full-screen apps included, and does not take focus; over full-screen apps and other Spaces, that was seen in a test program on macOS 26.7 and has not yet been checked in the app itself. It has one row for each escalation, up to six, with a last line counting the rest, newest first, such as _On-call mentions — since 14:02 — tier 3, repeat 2 of 20_, and each row has an **Acknowledge** button. It names the rule and never what the notification said.
- **In the menu.** While anything is listed, **Acknowledge** is the top item, or **Acknowledge All (3)** when there are several. Beneath it, the menu counts them, as _1 alert escalating_. The menu does not change while it is open, so an item cannot move under your pointer, and the item acts on the alerts it listed when you opened the menu. An alert that began while the menu was open stays escalating, with its sound, and the next time you open the menu it is listed. That was tested and tried on a menu in a test program, and has not been seen in the app itself.
- **With the keyboard.** ⌃⌥⌘A (Control-Option-Command-A) acknowledges everything listed, from any app, including an alert that began while the menu was open. It does nothing when nothing is listed. It needed no permission prompt on macOS 26.7, and other versions have not been checked. If it does not work on yours, the menu and the panel still do.

Acknowledging the last one also stops an escalation's sound that is still playing. It never cuts off the alert of an ordinary rule.

While an escalation is live, and nothing is wrong, the bell in the menu bar alternates between two shapes. A row in the Inspector for a rule that escalates gains a line that says how far it got and whether you acknowledged it.

#### Things to know

- **Failures are reported.** A repeat, a last alert or a Shortcut that fails is reported the way a failed first alert is: a ⚠︎ line in the menu and the slashed bell. A Shortcut that is not installed reads _⚠︎ On-call mentions at 14:04: the Shortcut "Page me" is not installed_. It stays until that same Shortcut starts again, from a later escalation or from **Test Shortcut**, or until you quit. Another Shortcut starting does not clear it. Nor does changing the rule to name a different Shortcut: testing the new name leaves the old name's failure where it is. SignalLadder never waits for a Shortcut. It counts one as started if it is still running after a second or exits successfully.
- **Keeping the Mac awake.** While a tier is still to come, SignalLadder asks macOS not to let the Mac sleep on its own. It does not keep the display awake. That request has not yet been tested on a Mac that can sleep. While you are on call SignalLadder makes the same kind of request for as long as the mode is on, a separate one that an escalation ending does not release: see [On-call mode](#on-call-mode).
- **A long sleep.** If the Mac does sleep for more than five minutes during an escalation, the escalation ends as _missed while asleep_ when the Mac wakes, rather than sounding alerts that are hours old. It stays in the menu, and on the panel if the panel had appeared, until you acknowledge it. After a shorter sleep the ladder resumes. Sleep is measured as the time on the clock less the time the Mac was awake. Apple documents that awake time stops during sleep, but that has not yet been checked on a Mac that sleeps.
- **Quitting.** While anything is listed, or while you are on call, quitting asks first. It stops every alert still escalating, or, with only missed alerts listed, forgets them: nothing more will sound or show, and a Shortcut not yet run will not run. While you are on call it also ends on-call alerting and the faster self-test, and nothing is captured until SignalLadder is running again. If another alert begins while the question is up, choosing **Quit** asks again and names the new count. That question is not asked at a log out, a restart or a shut down, nor at a quit that comes within 2 minutes of the system saying one is under way. An unsaved rule draft still asks whether to save it first, and that holds a log out until you answer it. Which of those the system really sends has not yet been seen on a real log out or restart: see [On-call mode](#on-call-mode).
- **Focus still applies.** An escalation starts only from a notification SignalLadder read. If a Focus hid the banner, nothing escalates. See [Check Do Not Disturb and Focus](#check-do-not-disturb-and-focus).

### Writing rules by hand

Rules live in a JSON file you can edit yourself: choose **Open Rules File in Text Editor…** in the menu, then **Reload Rules** (⌘R) after saving. [Rules format](rules-format.md) is the complete reference: every key, operator, alert and error message.

## Mute the source app

SignalLadder reads notifications. It does not stop the app that sent one from playing its own sound. Until you switch that sound off, every alert plays on top of the app's own ping, and that ping, one for every message, is the noise that taught you to stop listening. Turn the app's own sound off and SignalLadder becomes its only voice: silent by default, and sounding only for the notifications your rules pick out.

Once a rule with a **Sound** or **Speech** alert is on and saved, and it names an app with _App is_, the menu gains a walkthrough:

1. **Open the walkthrough.** The menu item reads _⚠︎ Not confirmed muted: Microsoft Teams_, with up to three names and then _and N more_. It covers every app such a rule names, and any app that has set one off since SignalLadder started, which is how apps a rule reaches by a pattern get listed. Its submenu explains the steps and lists each app as _Microsoft Teams — not confirmed muted_.

2. **Open the app's notification settings.** Choose the app, then **Open Notification Settings for Microsoft Teams…**. System Settings opens at that app's own Notifications page. If SignalLadder cannot find the app it says _SignalLadder couldn't find “Microsoft Teams” among your apps._ If two apps share a name it says _More than one app is called “Microsoft Teams”._ In either case it opens the Notifications list and shows you the name to look for.

3. **Turn off the app's sound.** Switch off the sound for its notifications. Leave the banners on. SignalLadder reads banners, so an app whose banners are off cannot be captured. Some apps also have a sound setting of their own inside the app; check there too if you still hear one.

4. **Tick it in the menu.** Back in the walkthrough, choose the app again and then **I've Turned Its Sound Off**. The app now reads _Microsoft Teams — confirmed muted_, and the top item reads _Confirmed muted: Microsoft Teams_. SignalLadder remembers the tick between launches.

> [!NOTE]
> SignalLadder cannot check that the app is muted. macOS keeps notification settings where other apps cannot read them, so the tick records your word, and the menu says _confirmed muted_, not _muted_. If you ever hear two sounds for one notification, the Inspector row shows which was SignalLadder's: it says what it played. The other was the source app's.

## Check Do Not Disturb and Focus

SignalLadder reads banners, and Focus modes decide whether macOS draws them.

> [!IMPORTANT]
> While Do Not Disturb or another Focus is on, macOS does not draw banners, so SignalLadder captures nothing and no rule can fire. For an on-call Mac this matters most: the hours you most want an alert can be the hours a Focus is on.

Check this once, and again whenever you change a Focus:

1. **Look at your Focus modes.** Open **System Settings › Focus**, or choose **Open Focus Settings…** at the bottom of the mute walkthrough. Look at Do Not Disturb and any other Focus you use, and at any that turn on by themselves.

2. **See whether one turns on when your screen locks.** This has been seen in practice: on the Mac SignalLadder was developed on, Do Not Disturb was on while the screen was locked. Lock the screen, wait a moment, unlock it, and check whether a Focus is showing as on.

3. **Allow the source app through.** In each Focus you use, allow the app you are muting to notify you. An app allowed through a Focus still draws its banners, so SignalLadder can still see them.

4. **Test it once with the real app.** Turn the Focus on, have the source app send you a notification, and check that it reaches the Inspector.

SignalLadder cannot read whether a Focus is on. What it can do is notice that its own self-test banner never appeared. Then the health line reads _Cannot verify itself_, and the advice beneath it usually lists Do Not Disturb and Focus modes among the causes. Self-tests run every 30 minutes, or every 5 while you are on call, so that warning can take that long to show. While you are on call, the [check window](#the-on-call-check-window) always carries a note that a Focus hides banners and that SignalLadder cannot read whether one is on.

## On-call mode

Everything above sets SignalLadder up. On-call mode is for the hours when you are the one who must be reached. It makes SignalLadder check itself more often, keep beeping while something is wrong, ask the Mac not to sleep, and list what it cannot see. It changes nothing a rule does or matches. It is also not the **On call** choice in the rule editor, which is a ladder that applies whenever its rule matches, whether or not you are on call.

> [!NOTE]
> On-call mode is built, and what it decides is tested, but SignalLadder itself has not been run with it. Its live checks are still to do, so read all of this as what it is built to do and not as something seen. Among them: that the status menu holds still, and capture keeps reading, while a menu or the quit prompt is up; that a real log out and a real restart complete without a prompt of SignalLadder's own; that the Mac stays awake while you are on call; and what only a real screen shows, such as the **On Call** item, how the check window opens over the app in front, the beeps at the Alert volume, a Focus turning the health line, a sleep and a wake, and the icon at menu-bar size. [On-call mode](architecture.md#on-call-mode) in the architecture page lists what was and was not seen.

### Switch it on

Open the menu and choose **On Call**. It gets a tick. From then on:

- **It is saved.** SignalLadder keeps the time you switched it on, so the mode is still on after a relaunch. It never switches itself off, and the menu says since when, as _On call since Mon 09:00_, so a switch you forgot is there to be seen.
- **A self-test runs at once**, and, if it passes, another about two minutes later. Each is a real banner, drawn on whatever your screen shows, a shared screen included.
- **Self-tests run every 5 minutes**, in place of every 30. That is about 12 banners an hour. The health line reads _Unverified_ once the last success is more than 6 minutes old, in place of 31. There is no setting for the interval, because a setting could hide an outage behind a long one.
- **A fault keeps beeping.** Off call, a change to _Cannot verify itself_ or _NOT capturing notifications_ beeps once. On call it beeps at once, then six more times 5 minutes apart, so seven times in the first half hour, and then every 30 minutes for as long as the fault stands. The banner still comes once, and only when SignalLadder's own banners can be shown.
- **Capture that stays unverified is a fault.** The health line can read _Checking…_ or _Unverified_ while nothing has failed, and off call that never sounds. On call, capture that has stayed unverified for 10 minutes beeps on the same schedule, with no banner. If the Mac has woken since the last self-test that was verified, the limit is 2 minutes from the wake.
- **A wake runs a self-test**, and, if it passes, another two minutes later. A self-test just after a sleep can fail once on a healthy app, so you may hear one _did not complete_ beep, and the retry a minute later clears it. That has not yet been seen on a Mac that sleeps.
- **The Mac is asked not to idle-sleep.** SignalLadder holds a request of its own for as long as the mode is on, and an escalation ending does not release it. It costs battery. It is not a lid close: a closed lid, or a sleep you choose, still sleeps the Mac, and the display is not held. Whether the request keeps a Mac that can sleep awake has not yet been tested.
- **The icon has a state for it.** A bell with a filled badge, described as _SignalLadder — on call_, with _self-test every 5 minutes_ added only while self-tests are running. A problem's slashed bell outranks an escalation's pulsing bell, and that outranks this one. The normal bell already has a badge, so the difference is small, and whether it is easy to see at menu-bar size has not been judged on a real menu bar.
- **Quitting asks first.** See [Quitting](#things-to-know).

The beeps follow the Mac's **Alert volume** (System Settings › Sound), which is a setting of its own and apart from the output volume and the mute switch. That is what macOS is reported to do, and it has not yet been tested. SignalLadder reads the setting. When it reads zero, the menu and the check window say that its beeps cannot be heard, whatever the output is doing.

### What the menu shows

While you are on call, beneath the health line and its cause:

- **On Call**, ticked. Choose it again to switch off.
- _On call since Mon 09:00 — self-test every 5 min_. The cadence is named only while self-tests are running. When one cannot run, it reads _— self-tests are paused, see the health line_, and before the first health check has said, it names neither.
- _Keeping this Mac awake: costs battery; a closed lid still sleeps it_, while the request is held.
- One short line for each thing the menu's other lines do not already say, with a ⚠︎ before the urgent ones. They are _⚠︎ Alert volume is zero, so beeps are silent — see On-Call Check_, _⚠︎ No rule is enabled, so nothing will alert you_, _A match only shows the panel: no rule sounds or runs a Shortcut_, and the two notes, _A Focus hides banners and cannot be read — see On-Call Check_ and _A Mac that sleeps captures nothing; SignalLadder cannot wake it_. The menu already says the rest, in its health line, its rules lines and its mute line, so it does not say it twice.
- **Show On-Call Check…**

### The On-Call Check window

**Show On-Call Check…** opens an ordinary window, titled SignalLadder On-Call Check, that lists everything SignalLadder can read about whether you are ready to be reached. It has a heading, _Nothing urgent_, _1 thing needs your attention_ or _3 things need your attention_, then one line for each finding, the urgent ones first. _Nothing urgent_ does not mean all is well. It means nothing SignalLadder can read needs you, and the two notes at the end, which always stand, say what it cannot read.

The urgent findings, each in words and counts and never naming a rule, an app or a Shortcut:

- Capture has not been verified yet, or the cause the health line gives.
- The sound output is muted or at zero volume, when a rule sounds.
- SignalLadder's beeps cannot be heard, because Alert volume is at zero. This is urgent whether or not a rule sounds, since the beeps are SignalLadder's own channel and not a rule's.
- Some rules are not in effect, or none are, because the rules file could not be read or was written by a newer SignalLadder.
- No rule is enabled, so nothing will alert you.
- A Shortcut name was not found.
- Some apps are not confirmed muted.

And the notes: that no enabled rule makes a sound or runs a Shortcut, so a match will only show the panel; that a Focus hides banners and SignalLadder cannot read whether one is on; and that a Mac that sleeps, with its lid closed or put to sleep by hand, captures nothing and SignalLadder cannot wake it. [Troubleshooting](troubleshooting.md#the-on-call-check-window-and-its-findings) says what to do about each.

The one button, **Check Now**, runs one self-test, which shows a banner, and checks everything again. It does not start the two-minute follow-up that switching on does, and it is not the window's default button, so a Return meant for something else cannot post a banner.

**When it opens.** At switch-on, once the self-test it starts has come back, if any finding is urgent. After that it opens by itself, with one beep, when something new turns up that the health alarm cannot see: a rule that is no longer in effect, no rule enabled, or a Shortcut name that was not found, as shown by a launch, a **Reload Rules** or a save. A finding that goes and comes back sounds again, and so does one already standing when you relaunch while on call. When the output becomes muted, or Alert volume reads zero, it opens with no beep, since a beep could not be heard through either. Whenever it comes to the front it brings its list up to date from what can be read at once, without running a self-test. It is never a dialog: nothing waits for you to answer it, and capture goes on behind it. How it opens over the app in front, and whether it can take a keystroke meant for something else, has not been seen on a real screen.

### What it cannot see

- **A Focus.** SignalLadder cannot read whether one is on, so no line says one is. The note says a Focus hides banners, and that letting the source app break through keeps its banners showing.
- **A Mac that is asleep.** The request not to idle-sleep stops that, and nothing else. A closed lid or a sleep you choose sleeps the Mac, and while it sleeps nothing is captured.
- **Whether you muted the source app.** The check counts the apps you have not ticked as muted, and never names them.
- **Whether SignalLadder starts at login.** It has no Launch at login setting yet, and on-call mode does not check for a Login Items entry. Read [Keep it running](#keep-it-running).
- **Whether you can hear a beep.** It reads Alert volume, and cannot tell whether you are in the room or the speaker is connected.

### Switch it off

Choose **On Call** again. Self-tests go back to every 30 minutes, the request not to idle-sleep is let go, and the check stops watching. An escalation already running carries on, since ending one would end a page you did not answer. A retry that a failed self-test promised stays.

## Keep it running

SignalLadder alerts you only while it is running. It has no launch-at-login setting yet, so a restart or a log out leaves it off until you start it. That holds on call too. SignalLadder saves that you are on call and comes back on call when you start it, but nothing starts it for you, so after a restart or a log out nothing is watching until you do.

1. **Start it at login.** Open **System Settings › General › Login Items** (called Login Items & Extensions on newer versions of macOS) and add **/Applications/SignalLadder.app** to the apps that open at login. This is macOS's own mechanism, not a setting of SignalLadder's, and the project has not yet tried it with a SignalLadder build.

2. **Glance at the health line.** Open the menu now and then. _Working — verified 3 min ago_ is what you want. The age matters: a self-test runs every 30 minutes, or every 5 while you are on call, so a number much above that means one did not run, and past about 31 minutes (6 on call) the line reads _Unverified — last verified 34 min ago_.

   ![The SignalLadder menu on a healthy app with rules loaded](assets/screenshots/menu.png)

3. **Notice the alarms.** When capture or the self-test fails, SignalLadder tells you three ways, so no single fault silences all of them: the bell changes to the slashed one and stays that way, the Mac beeps, and a banner appears once if SignalLadder's own banners can still be shown. Off call it beeps once. While you are on call it keeps beeping while the fault stands: six more times 5 minutes apart, then every 30 minutes. Off call, a rules-file problem, a sound that could not play, a Shortcut that could not run or a Shortcut name that was not found changes the bell and the menu and does not beep. While you are on call, a rules file or rule that is not in effect, or a Shortcut name that was not found, gives one beep when it is new and opens the check window ([the On-Call Check window](#the-on-call-check-window) says when). A sound that could not play and a Shortcut that could not run still do not beep.

4. **Quit and relaunch from the menu.** **Quit SignalLadder** (⌘Q) is at the bottom. If you have an unsaved rule draft it asks whether to save it first, and if an escalation is still listed, or you are on call, it asks whether to quit anyway. That question is not asked at a log out, a restart or a shut down, but the unsaved-draft question still is, and it holds one until you answer it. Alerts stop while it is quit, and on-call mode is still on when you start it again.

### Updating

There is no updater. To move to a newer version, pull the changes, build again with the same identity, quit the running copy and replace it:

```sh
git pull
SIGNALLADDER_IDENTITY=<your 40-character SHA-1> ./Scripts/make-app.sh release
```

Then move the old **/Applications/SignalLadder.app** to the Bin, copy the new **build/SignalLadder.app** into **/Applications**, and launch it. SignalLadder has no guard against a second copy running, so quit the old one first. Your rules and sounds live outside the app, in `~/Library/Application Support/com.jamiewhite.signalladder/`, and a rebuild does not touch them. With the same signing identity the Accessibility grant survives the rebuild. That is the point of the identity, and it has been checked with Developer ID signing only.

## Next

- [Rules format](rules-format.md): every key, operator, alert and error message, for writing rules by hand.
- [Troubleshooting](troubleshooting.md): nothing captured, no sound, two sounds at once, and other symptoms.
- [Privacy](privacy.md): what SignalLadder reads, what it stores, and the permissions it asks for.
