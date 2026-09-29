# Troubleshooting

This page is for the moment an alert did not sound, sounded when it should not have, or SignalLadder says it cannot see your notifications. It is organised by what you noticed, not by how SignalLadder works. Text in _italics_ is what the app shows, so you can search this page for what your menu says.

> [!NOTE]
> The System Settings wording here is macOS 26's. SignalLadder declares macOS 14 as its minimum, but every live check so far was run on macOS 26, so treat the wording on earlier versions as approximate. Before macOS 26, banners switched off is an alert style of None rather than the **Desktop** checkbox, and **Read & Speak** was called Spoken Content.

## Start with the menu and the Inspector

SignalLadder has no Dock icon and no main window. Everything is in its icon in the menu bar, and two places there answer most questions.

**The health line.** Click the icon. The first line says whether SignalLadder can read notifications and how recently it proved it. When something is wrong, the line beneath it says what to do, and clicking that line opens the right pane of System Settings. The icon changes from a bell to a slashed bell whenever SignalLadder has a problem: capture health, rules that did not load, or an alert that could not sound.

The line _Captured 3 notifications_ counts what SignalLadder has read since it started. It does not count SignalLadder's own banners.

**The Inspector.** Choose **Show Inspector…** (⌘I). It lists the last 50 notifications SignalLadder read, newest first, and shows each one as SignalLadder saw it. Under every row are two lines that matter here:

- The **match line** says which rule took the notification: _Matched Prod and incident channels_, or _Matched no rule_. If no rules were loaded it says _Not evaluated — no rules loaded_ or _Arrived while no rules were loaded_.
- The **outcome line** says what SignalLadder did about a match: _Played Glass (+6 dB)_, _Silent by rule_, _Could not play: …_. A notification that matched no rule has none.

The Inspector is held in memory. It is empty after a relaunch, and the 51st notification pushes out the first.

![The SignalLadder menu with a healthy status line and rules loaded](assets/screenshots/menu.png)

![The Inspector listing captured notifications, some matched and some not](assets/screenshots/inspector.png)

Then find your symptom:

- [Nothing appears in the Inspector](#nothing-appears-in-the-inspector)
- [A notification is in the Inspector, but no sound played](#a-notification-is-in-the-inspector-but-no-sound-played)
- [I hear two sounds for one notification](#i-hear-two-sounds-for-one-notification)
- [An alert sounded again when I opened Notification Centre](#an-alert-sounded-again-when-i-opened-notification-centre)
- [The menu shows a warning about rules](#the-menu-shows-a-warning-about-rules)
- [Accessibility is on, but SignalLadder says it is not capturing](#accessibility-is-on-but-signalladder-says-it-is-not-capturing)
- [The self-test banner keeps appearing](#the-self-test-banner-keeps-appearing)
- [The health line says verified, but capture has stopped](#the-health-line-says-verified-but-capture-has-stopped)
- [A spoken alert is silent or cannot find its voice](#a-spoken-alert-is-silent-or-cannot-find-its-voice)
- [A menu shortcut does nothing](#a-menu-shortcut-does-nothing)

## What the health line says

SignalLadder cannot know that capture works from silence: a quiet channel and a blind app look identical. So it sends itself a real notification, the self-test, and reads it back. The health line is the result of that, and how old the result is.

| The line says | What it means | What to do |
| --- | --- | --- |
| _Working — verified just now_, _Working — verified 3 min ago_ | A self-test banner went through the whole path and was read back that long ago. It is the only positive evidence SignalLadder has, and it describes that moment, not this one. | Nothing. If you doubt it, see [the health line says verified, but capture has stopped](#the-health-line-says-verified-but-capture-has-stopped). |
| _Checking…_ | SignalLadder has not finished its first check since it started. This lasts seconds. | Wait a moment. If it stays, a permission prompt is probably waiting for an answer, so look for one, then quit and relaunch. |
| _Unverified — last verified 34 min ago_ | The last successful self-test is more than 31 minutes old (the 30-minute interval plus a minute's grace), so one that should have run has not. Nothing has been seen to fail, and it does not sound an alarm. After the Mac has been asleep, you can see this until the next self-test runs. | Usually nothing: the next self-test corrects it, and quitting and relaunching runs one at once. To check now, see [the symptom below](#the-health-line-says-verified-but-capture-has-stopped). |
| _Cannot verify itself_ | SignalLadder cannot prove it can read notifications, because its own self-test banner was not shown, or was shown and did not come back. Capture may be working. If real notifications are still reaching the Inspector, it is. | Read the advice line beneath it: [the delivery side](#the-delivery-side-cannot-verify-itself). |
| _NOT capturing notifications_ | SignalLadder has no Accessibility permission, is not attached to Notification Centre, or two self-tests in a row failed although banners were drawn. Nothing is being read, so no rule can sound. | Read the advice line beneath it: [the capture side](#the-capture-side-not-capturing-notifications). |

The age reads _just now_, _3 min ago_, _1 hr 5 min ago_ or _2 hr ago_.

When the health line changes to _Cannot verify itself_ or _NOT capturing notifications_, SignalLadder tells you three ways, so that no single fault silences all of them: the icon changes, the Mac beeps once, and, if SignalLadder's own banners can still be drawn, a banner appears titled _SignalLadder cannot verify itself_ or _SignalLadder is not capturing_. It alarms once per change, not repeatedly. Those banners are not counted, listed or matched by rules.

### The advice line under the health line

The menu shows one advice line: the first cause, when several apply. There are two sides to a fault, and the difference matters. If SignalLadder's banner was never drawn, Accessibility had nothing to read, and granting Accessibility again would fix nothing. So a failed self-test is not blamed on capture until delivery has been ruled out, and delivery faults read _Cannot verify itself_, not _NOT capturing notifications_.

#### The capture side: _NOT capturing notifications_

SignalLadder is not reading banners, so one that is drawn goes unseen. Clicking the advice line opens Accessibility in System Settings.

- _Grant Accessibility to SignalLadder in System Settings — without it no notifications can be read._

  The Accessibility permission is missing, or the grant no longer matches this copy of the app. Open System Settings › Privacy & Security › Accessibility and switch SignalLadder on, then open the menu once: capture starts when the menu opens, so no relaunch is needed. If SignalLadder is already switched on there, see [Accessibility is on, but SignalLadder says it is not capturing](#accessibility-is-on-but-signalladder-says-it-is-not-capturing).

- _Not attached to Notification Centre. It may be restarting; this usually recovers within seconds._

  SignalLadder listens to Notification Centre's process and has not made that connection, or has lost it. It reconnects on its own, retrying after 1 second and then at growing intervals up to 30 seconds, and runs a self-test when it succeeds. Wait a minute. If the line stays, quit and relaunch. The [log](#collecting-information-for-a-bug-report) records each attempt.

- _macOS is not exposing notifications to assistive apps. Turning on Full Keyboard Access in System Settings › Keyboard is the known workaround._

  Two self-tests in a row failed although Notification Centre drew something, and no real notification has been read since. Banners appear, but SignalLadder cannot read them. Quit and relaunch first: during development a relaunch cleared this. If it comes back, do what the line says. Full Keyboard Access changes how the Tab key moves between controls across macOS, which is why a relaunch comes first.

#### The delivery side: _Cannot verify itself_

SignalLadder's own self-test banner was not drawn, or was not seen. Capture may be working fine; SignalLadder cannot prove it. Clicking the advice line opens Notifications in System Settings.

- _Allow notifications for SignalLadder in System Settings — without it the app cannot verify it is working._

  SignalLadder's own notification permission is denied, or its prompt was never answered. Open System Settings › Notifications › SignalLadder and allow notifications. SignalLadder asks for alerts only, with no sound and no badge. Capture does not depend on it.

- _Do Not Disturb, a Focus, or SignalLadder's banners being switched off (Desktop, in System Settings › Notifications) is suppressing its own alerts, so it cannot verify itself. Capture is unaffected while banners are still shown for other apps._

  SignalLadder's own notification settings say its banner would not be drawn: banners switched off (**Desktop** on macOS 26), Notification Centre switched off for it, or Scheduled Summary holding its notifications. Switch them back on. A Focus cannot be read from settings, so the next line is how SignalLadder finds one.

- _SignalLadder's self-test alert was never seen. Either it was not shown — Do Not Disturb, a Focus, or its banners switched off (Desktop, in System Settings › Notifications) — or SignalLadder is not seeing banners at all. Rule out Do Not Disturb first; if it is off, turn on Full Keyboard Access in System Settings › Keyboard, the known workaround for macOS not exposing notifications._

  A self-test failed and Notification Centre created no window at all while SignalLadder waited. Two different faults leave exactly that evidence: the banner was never drawn, or it was drawn and not seen. SignalLadder cannot tell them apart, so it names both. Check Control Centre for a Focus first. If none is on, quit and relaunch, and only then try Full Keyboard Access.

- _Capture is working — notifications from other apps are being captured — but SignalLadder's own alerts are not being shown, so it cannot self-test. Check SignalLadder in System Settings › Notifications, including Deliver Quietly._

  Real notifications have been read since the last self-test, so capture works. The fault is with SignalLadder's own banner. Its settings can read as fine while the banner is still not drawn, and Deliver Quietly is one thing to check.

- _A self-test did not complete, and SignalLadder cannot tell whether its alert was shown. It will retry in a minute._

  One self-test failed. One failure is not evidence of blindness: a Focus, a brief system hiccup or waking from sleep can each cause one on a healthy app. SignalLadder retries after a minute, then at growing intervals up to 30 minutes while it keeps failing. Wait. A second failure in a row turns this into one of the lines above.

## Symptoms

### Nothing appears in the Inspector

You expected a notification in the list and it is not there, so SignalLadder did not read it, or was not running when it arrived. The Inspector's empty message says which kind of empty it is:

- _Nothing captured yet. Capture is verified working, so this is simply quiet._ Nothing has arrived, and the health line backs that up.
- _Nothing captured yet — and SignalLadder has no recent confirmation that it can capture anything._ It has not verified capture, or the evidence is stale. The health line and its advice follow.
- _Nothing captured — and SignalLadder cannot confirm it is capturing._ Health is _Cannot verify itself_ or _NOT capturing notifications_. The health line and its advice follow.

Work down this list.

1. **Read the health line.** If it says _NOT capturing notifications_, deal with that first: [the capture side](#the-capture-side-not-capturing-notifications). The usual cause is Accessibility.

2. **Post a test banner.** It separates SignalLadder from the app you were waiting for. In Terminal:

   ```
   osascript -e 'display notification "Placeholder body" with title "Capture test"'
   ```

   It posts as Script Editor, so Script Editor's own notification settings apply. If a row appears in the Inspector, SignalLadder can read banners, and the problem is that the source app's banner was never drawn: read on. If nothing appears, either SignalLadder cannot read banners (steps 1 and 7) or no banner was drawn for anyone, which is what a Focus does (step 3).

3. **Check Do Not Disturb and Focus.** While one is on, macOS draws no banner and sends the notification straight to Notification Centre's history. There is nothing to read, so SignalLadder captures nothing. This is a limit of how SignalLadder reads notifications, not a fault in it, and nothing in SignalLadder can get round it. An app allowed to break through a Focus still draws its banners, so allow the source app to notify you through that Focus. The mute checklist in the menu has **Open Focus Settings…** when a rule needs it, and reminds you to check whether a Focus turns on when your screen locks.

4. **Check the source app's banners.** SignalLadder reads banners drawn on screen. In System Settings › Notifications › the app, banners must be on (the **Desktop** checkbox on macOS 26). Both the Banners and Alerts styles are read. If the notification was set to **Deliver Quietly**, it goes to Notification Centre without a banner. If the app is in **Scheduled Summary**, it is held for later. Neither draws a banner now, so neither is read.

5. **Check that the app posted a notification at all.** Some apps do not raise one when you are already looking at that conversation. A popup an app draws for itself is not a notification banner. SignalLadder reads only Notification Centre.

6. **Think whether you were opening Notification Centre just then.** Whatever Notification Centre's list holds when it opens is taken for old notifications, so one that arrives at the very moment you open it may not be read. If so, it is in Notification Centre, but not in the Inspector. See [An alert sounded again when I opened Notification Centre](#an-alert-sounded-again-when-i-opened-notification-centre) for how the list is recognised.

7. **Quit and relaunch.** A relaunch reattaches to Notification Centre from scratch and clears a stuck observer. Capture has stopped while Notification Centre kept drawing banners during development, and a relaunch cleared it. Try this before [starting over](#starting-over), and see [the health line says verified, but capture has stopped](#the-health-line-says-verified-but-capture-has-stopped) for why the health line may not have warned you.

One missed alert has not been explained. During a test on 2026-09-29, a persistent Outlook alert was not captured, and nothing was logged. If an alert of yours goes missing and nothing above explains it, please report it: see [collecting information for a bug report](#collecting-information-for-a-bug-report).

### A notification is in the Inspector, but no sound played

SignalLadder read it. Now find out what it did. Read the row's match line and outcome line, and find them here.

| The row says | What happened | What to do |
| --- | --- | --- |
| _Matched no rule_ | No rule that can run matched. | [Work through the causes below](#if-the-row-says-matched-no-rule). |
| _Not evaluated — no rules loaded_ or _Arrived while no rules were loaded_ | No rules were loaded when it arrived: none written yet, or the file could not be read. | Look at the menu's Rules line. See [The menu shows a warning about rules](#the-menu-shows-a-warning-about-rules). |
| _Matched …_ naming a rule you did not expect | A rule higher in the list matched first. **The first enabled rule that matches wins**, and a notification only ever sets off one rule. | In **Edit Rules…**, select the rule you expected. Its dry run says _N more are taken first by “Rule”, above it_, with a **Move Above “Rule”** button. Or narrow the higher rule's condition. |
| _Silent by rule_ | The rule that matched has the alert Silent. That is deliberate: a silent rule claims its notifications, so no broader rule below it can sound for them. | If you meant it to sound, change its alert. If a silent rule is claiming what a rule below should sound for, move the narrower rule above it. |
| _Silent — this rule has no alert_ | The rule that matched has no alert. A rule made with **Make a Rule from This…** starts like this on purpose, switched off and with no alert, so a rule you have not finished is never mistaken for one you meant to be quiet. | In **Edit Rules…**, choose Sound or Speech for the rule, try **Test Sound**, switch the rule on and press **Save**. |
| _Played Glass_ | SignalLadder played it. That means it did the work, not that you heard it. | [Played, but not heard](#played-but-not-heard). |
| _Played Glass — but the Mac's sound output was muted or at zero volume_ | It played, and the Mac reported that nothing could be heard. While the output stays muted, the menu also warns _⚠︎ Sound output is muted or at zero volume — alerts will not be heard_. | Unmute the Mac or raise its volume. |
| _Could not play: …_ | A sound was meant to play and did not, and the text says why. At the moment of an alert this is almost always `was not found`, because the file was removed after the rules loaded, or `the audio engine failed`. | Put the file back and choose **Reload Rules** (⌘R), or check System Settings › Sound and try **Test Sound** in the rule editor. Relaunch if it persists. |
| _Could not speak: …_, _Played Glass, but could not speak: …_ or _Spoke (Daniel), but could not play: …_ | One part of a sound-and-speech alert did not happen. | See [A spoken alert is silent or cannot find its voice](#a-spoken-alert-is-silent-or-cannot-find-its-voice). |

A sound that could not play also puts its own ⚠︎ line in the menu and turns the icon to the slashed bell. Both stay until a later sound plays. A quieter match afterwards does not hide it, and reloading rules does not clear it.

#### If the row says _Matched no rule_

- **The rule is switched off.** The menu's rules line says _Rules: 2 active, 1 off_. In the editor, a rule that is off says _Not in effect: this rule is switched off._ A rule made with **Make a Rule from This…** starts switched off.
- **The rule has problems, so it does not run.** The editor marks it with an orange triangle and says _Not in effect: this rule has problems, and will not run until they are fixed._ The menu's rules line starts with ⚠︎ and lists it. One bad rule never stops the others. See [The menu shows a warning about rules](#the-menu-shows-a-warning-about-rules).
- **The rule is not in effect yet.** The editor's bar says _Unsaved changes — not in effect until you save_ until you press **Save**, which takes effect at once. If you edited `rules.json` by hand, it says _rules.json has changed since it was put into effect — these rules are not running yet_, and **Put into Effect** or **Reload Rules** (⌘R) applies it. A blue line on a row, _Current rules would match …_, means the rules you have now would have taken that notification, but were not in effect when it arrived. It is a preview. Only a match on arrival sounds.
- **The condition does not fit what the notification holds.** Compare the rule with the row in the Inspector, field by field.
  - `app` is recovered heuristically from the banner's description, so it can be wrong or empty (the row then says _(no app name)_).
  - `matches` covers the whole field: `#prod-*` means "starts with `#prod-`", and `*deploy*` means "contains `deploy`".
  - Comparisons ignore case and accents.
  - If you are unsure which field some text lands in, use **Any text**, which is the `raw` field.
  - The rule editor's dry run, _In this draft: matches 3 of the last 50 notifications._, tells you at once whether the condition matches anything. If it says none, the condition is the problem. **Add Condition from This Notification** builds a condition from the row itself.

  The [rules format](rules-format.md#conditions) lists every field and operator.

#### Played, but not heard

- **The output.** Sounds play through the Mac's current output, at its volume. If that is not where you are listening, such as a display or a headset in a bag, it played there. SignalLadder can only tell when the device says it is muted or at zero volume. A device with no volume control, such as some external interfaces, cannot be judged, so no warning appears even if it is turned down on the device.
- **The gain.** _Played Glass (−12 dB)_ means the rule asked for a quiet sound. The range is −40 to +12 dB.
- **A burst.** One alert plays at a time, and a new alert cuts off one still playing, because two alarms at once are noise. In a burst, only the last sound plays in full.
- **It plays once.** An alert sounds once per notification. It does not repeat, and nothing waits for you to acknowledge it. Alerts that keep going until acknowledged, with a persistent panel and a repeating sound, are planned and not built.
- **Try it.** **Test Sound** in the rule editor plays the rule's sound exactly as the alert would, at its gain. If that is silent too, the fault is the Mac's output, not the rules.

### I hear two sounds for one notification

Open the Inspector and read the row's outcome line. _Played Glass_ tells you which sound was SignalLadder's, so the other belongs to something else.

1. **The source app's own sound is still on.** This is the usual cause. SignalLadder is a replacement voice: it does not silence the app, you do. Until the app's own notification sound is off, its ping plays on top of every alert. Whenever an enabled rule has a sound or speaks, the menu lists the apps it reaches, titled with the ones still to do, _⚠︎ Not confirmed muted: Microsoft Teams_. For each app:

   1. Choose **Open Notification Settings for …**. It goes straight to that app in System Settings. If SignalLadder cannot find the app, or finds two with that name, it shows the name to look for and opens the Notifications list instead.
   2. Turn off the app's notification sound there.
   3. Back in the menu, choose **I've Turned Its Sound Off**.

   Nothing can check that last step. macOS keeps notification settings where other apps cannot read them, so the tick records your word, and the menu says _confirmed muted_, not _muted_. If an app is missing from the list, note that the list holds the apps a rule names with `app equals`, plus any app that has set one off since SignalLadder started. An app matched only by a pattern shows up after its first alert. Some apps also have sound settings of their own inside the app, which the Notifications pane does not control. The [rules format](rules-format.md#muting-the-source-app) has the full walkthrough.

2. **The notification is in the Inspector twice.** Then SignalLadder read it twice, and each row that matched a rule set off its own alert. Either the app posted two notifications, or SignalLadder read one banner twice, as it can in the cases the next symptom describes. A repeat that arrives within 1.5 seconds is folded into the first row instead, shown as _1 suppressed_, and does not sound again.

3. **You set a sound and a spoken line.** An alert with both plays the sound, then speaks. That is one alert.

4. **Two copies of SignalLadder are running.** Nothing stops a second copy launching, such as an older build in another folder. Each reads banners and plays its own alerts. Look for more than one SignalLadder in Activity Monitor and quit the extra.

### An alert sounded again when I opened Notification Centre

It should not. Notification Centre shows its history in the same window, and with the same kind of element, that a live banner uses. SignalLadder recognises Notification Centre's list by how its window is built, and treats everything the list holds when it opens as old, however recent. A notification that arrives while the list is open is still read as new. The list was checked on macOS 26.7. If an alert does sound again, the Inspector shows a second row for it, timed to the moment it was read again. These are the known causes:

- **You are on a macOS other than 26.7, such as 14 or 15.** The list may be built differently there. If SignalLadder does not recognise it, it reads what the list holds as new, and a rule that matched an old notification sounds again. Please report it, with your macOS version: see [collecting information for a bug report](#collecting-information-for-a-bug-report).
- **A large stack of persistent alerts from one app.** Once, with seven alerts from one app stacked, a new alert arriving while the list was open made macOS lay the stack out again, and three old alerts were read again as new, so a rule that matched them would have sounded again. It did not happen with two, and was not seen again.
- **A time label in another language.** A notification that appears in the list after it opens, such as one scrolled into view, is recognised as old by a time label like _1m ago_ or _yesterday_. Only English wording is recognised. A numeric time such as _12:04_ is recognised in any language.

When SignalLadder is unsure it treats a notification as new. That repeats an alert now and then, and the other error would miss one.

The opposite can happen too. A notification that arrives at the very moment you open Notification Centre is taken for an old one, and may not sound.

### The menu shows a warning about rules

One rejected rule never silences the others, and the menu says when a rule was rejected. So does the icon.

| The menu says | What it means | Effect |
| --- | --- | --- |
| _⚠︎ Rules: 2 active — 1 could not be used_ | One or more rules loaded but were rejected. Each is listed beneath by position and name, such as `Rule 3 ("Typo"): …`. | The other rules run. Only the rejected ones do not. |
| _⚠︎ Rules file could not be read — no rules are active_ | The file is not valid JSON, or not the shape of a rules file. The reason is listed beneath, with the line and column. | No rule runs until it is fixed. |
| _⚠︎ Rules file needs a newer SignalLadder (format 5) — no rules are active_ | The file was written by a newer build, or its `"version"` is above 4. | Nothing is loaded rather than misread. No rule runs. |

The reason listed under a rejected rule is one of the messages in [When something is wrong](rules-format.md#when-something-is-wrong), which lists every one with what it means. A misspelt sound, a voice that is not installed and a `"gainDB"` out of range are all caught when the rules load, not at the incident. Fix the rule in the rule editor, where it shows an orange triangle and its problems, or in a text editor. **Save** in the editor takes effect at once. After a hand edit, choose **Reload Rules** (⌘R).

**The editor opens read-only.** The editor refuses to open a file it cannot represent in full, because saving would have to drop what it could not read. It says why:

- _The rules file can't be read, so it can't be edited here._ The file is not valid JSON.
- _The rules file was written by a newer SignalLadder (format 5)._
- _1 rule in the file can't be read, so saving here would drop it. Fix it in a text editor._ An entry has a misspelt or unknown key, or an operator that is not one of the four. Every such rule is listed with its reason.

Choose **Open Rules File in Text Editor…**, fix the file, then **Reload Rules** (⌘R). SignalLadder never rewrites a file it cannot fully understand. A rule that reads correctly but has a problem, such as an empty group or a sound that does not exist, does not make the editor read-only. You fix those in the editor.

### Accessibility is on, but SignalLadder says it is not capturing

macOS ties an Accessibility grant to the app's code signature. An entry in the list can look switched on and no longer match the copy of SignalLadder that is running. Try these in order.

1. **Open the menu.** Capture starts when the menu opens and Accessibility is granted. The line should change.
2. **Quit and relaunch** SignalLadder.
3. **Switch its entry off and on** in System Settings › Privacy & Security › Accessibility.
4. **If you rebuilt it with a different signing identity,** the old grant no longer matches. Select the entry and remove it with the **−** button, relaunch SignalLadder, and grant Accessibility again. Rebuilding with the same identity keeps the grant. That is why `Scripts/make-app.sh` refuses ad-hoc signing: an ad-hoc signature changes with every build, and the grant would be lost each time. [Getting started](getting-started.md) covers building.
5. **Reset the permission and grant it afresh.** Quit SignalLadder, then run:

   ```
   tccutil reset Accessibility com.jamiewhite.signalladder
   ```

   Relaunch it. macOS asks again.

### The self-test banner keeps appearing

It is meant to. Every half hour, and more often around a launch, a banner titled _SignalLadder self-test_ appears for a few seconds, with a body that reads "SignalLadder canary" and a random identifier.

**Why.** Absence of notifications proves nothing. A quiet channel and an app that cannot see banners look the same, and an on-call tool that cannot tell them apart will reassure you at the moment it is blind. The only way to know capture works is to send a real banner through the whole path and read it back. The self-test does that. Without it, the health line would have nothing to be based on.

**When.** A self-test runs at launch, whenever SignalLadder reattaches to Notification Centre, and when capture starts. If it passes, another runs about two minutes later, because capture has failed soon after a launch before. After that, one runs every 30 minutes. After a failure it retries after a minute, then at growing intervals up to 30 minutes. It also runs as soon as SignalLadder notices that whatever blocked it has cleared. Each waits up to 5 seconds for the banner to be read back, then removes it from Notification Centre. It has no sound. It is never listed in the Inspector, counted or matched by a rule.

**What you can change.** Nothing. There is no setting for its interval or to hide it. If you share your screen, it is visible like any other banner.

**If you switch SignalLadder's banners off,** the self-test cannot be drawn. The health line becomes _Cannot verify itself_, and the icon and a beep report it. Capture from other apps carries on, but SignalLadder can no longer tell you whether it is working. Switching the banners off trades a few seconds of banner every half hour for an app that cannot say when it is blind.

### The health line says verified, but capture has stopped

_Working — verified 12 min ago_ is a claim about one moment: the last time a self-test banner was read back. That is why the line says how old the evidence is. Capture has stopped without warning during development, shortly after a passing self-test, while Notification Centre carried on drawing banners. The cause is not settled.

An outage that starts between two self-tests reads _Working — verified N min ago_ until the next one, which can be up to about half an hour. Past 31 minutes the line becomes _Unverified — last verified N min ago_. Opening the menu re-evaluates what SignalLadder can read at that moment, which is the permission, the attachment to Notification Centre and the age of the evidence. It does not run a self-test. There is no setting for a shorter interval.

To check now:

- Post a test banner (see [Nothing appears in the Inspector](#nothing-appears-in-the-inspector)). _Captured N notifications_ in the menu goes up, and a row appears in the Inspector.
- Or quit and relaunch. A self-test runs at once, and another about two minutes later, so expect two banners.

If capture has stopped, quit and relaunch: that has cleared it so far. If you are willing to report it, note these before you relaunch, because a relaunch destroys the evidence: whether another copy of SignalLadder was running, whether a banner with the same title was already on screen, and how long SignalLadder had been running.

### A spoken alert is silent or cannot find its voice

- **The voice is not installed.** When the rules load, a rule naming a voice that is not installed is rejected and listed in the menu: _voice "…" is not installed — choose another in the rule editor, or add it in System Settings › Accessibility › Read & Speak (Spoken Content before macOS 26)_. The rule does not run. If a voice is removed after the rules loaded, the row says _Could not speak: voice "…" is not installed_.
- **Add a voice.** In the rule editor, the voice picker lists every installed voice, and **More Voices…** opens the Read & Speak pane of System Settings. After adding one, choose **Reload Rules** (⌘R): the rules are checked against the installed voices again.
- **Siri voices cannot be used.** macOS does not let other apps use them, so SignalLadder never offers them.
- **The row says _Spoke (Daniel)_ and you heard nothing.** "Spoke" means SignalLadder asked for the line, not that you heard it. Check the Mac's output, as in [Played, but not heard](#played-but-not-heard). The log records _spoken line produced no playable audio_ if a line produced nothing to play.
- **The line is not what you expected.** The template defaults to `{app}: {title}` and leaves out `{body}`, because a long recitation is not an alert. A spoken line stops at 240 characters. **Test Speech** in the rule editor says the template filled from a made-up notification, so it never reads a real one aloud.
- **What was said.** The Inspector row shows _Said: “…”_ for a spoken alert. The menu never does.

### A menu shortcut does nothing

⌘I (**Show Inspector…**), ⌘E (**Edit Rules…**), ⌘R (**Reload Rules**) and ⌘Q (**Quit SignalLadder**) are shortcuts of menu items, so they work while the menu is open. Click the icon first, then press the keys. SignalLadder has no global keyboard shortcuts. A hotkey to acknowledge an escalating alert is planned with the escalation work, which is not built.

Two more are deliberate:

- ⌘S saves in the rule editor.
- ⌘Q does nothing in the rule editor. Its menu has no Quit, so a keystroke meant for something else cannot end your alerting. Quit from the menu-bar icon, where you choose it on purpose.

## Collecting information for a bug report

A missed alert is the most serious bug SignalLadder can have, and a report that says what the app saw and did is easy to act on. The [bug report form](https://github.com/JWhite212/SignalLadder/issues/new?template=bug_report.yml) asks for these.

1. **The health line**, word for word, from the top of the menu. Include the age, as in _Working — verified 3 min ago_.
2. **What the Inspector says.** Open it (⌘I), find the notification, and copy the match line and the outcome line under it. If the notification is not in the Inspector at all, say so. That is the most important detail there is.
3. **The rule involved.** Choose **Open Rules File in Text Editor…** and copy the rule from `rules.json`.
4. **The versions.** Your macOS version, the source app and its version, and SignalLadder's own: in Finder, select SignalLadder.app and choose Get Info, which shows a version such as 0.1.0 (1). If you built it yourself, give the commit from `git rev-parse --short HEAD`.
5. **The log.** SignalLadder logs under the subsystem `com.jamiewhite.signalladder`. To collect the last hour:

   ```
   /usr/bin/log show --last 1h --predicate 'subsystem == "com.jamiewhite.signalladder"'
   ```

   Use the full path: in zsh, `log` on its own is a different command. Change `1h` to cover the incident. The log holds process ids, error codes, banner kinds and timings, and SignalLadder does not write notification text to it. A spoken alert never logs what it said: the log records how long it took to start, and a note if the line produced no audio or did not finish. [Privacy](privacy.md#logs) lists what each log category records. Read what you paste before you post it all the same.

> [!IMPORTANT]
> Notifications carry other people's names and messages. Before you post anything, replace every name, channel and message with a placeholder, such as `Alex Example`, `#placeholder-channel` or `Placeholder body text`. Keep app names as they are, because they matter. Check the Inspector's **Raw** text, the _Said: “…”_ line of a spoken alert, and the values in your rules. Text you added to a rule with **Add Condition from This Notification** is saved in `rules.json`, and copies of it are kept in `rules.previous.json` and any `rules.replaced-….json`.

A screenshot of the Inspector shows the same text, so cover it or leave it out. If capture stopped and you relaunched, add the three facts listed under [the health line says verified, but capture has stopped](#the-health-line-says-verified-but-capture-has-stopped).

A security problem does not belong in a public issue. Report it privately through [GitHub's private vulnerability reporting](https://github.com/JWhite212/SignalLadder/security/advisories/new).

## Starting over

When you want a clean slate, take these steps in order. None deletes your rules.

1. **Quit SignalLadder.** Choose **Quit SignalLadder** in the menu.

2. **Move your rules aside.** Rename the file instead of deleting it. Your rules are the one thing SignalLadder cannot rebuild for you.

   ```
   cd "$HOME/Library/Application Support/com.jamiewhite.signalladder"
   mv rules.json rules.aside.json
   ```

   The menu then reads _Rules: none yet_. Any name that is not `rules.json` works. To bring the rules back, quit SignalLadder and rename the file back. **Edit Rules…** starts a new file when you save, and **Open Rules File in Text Editor…** creates a starter file with one example rule, switched off, only if none exists. The backups `rules.previous.json` and any `rules.replaced-….json` stay where they are. Your `Sounds` folder is untouched.

3. **Reset the Accessibility permission**, if the trouble was about permission or a stale grant:

   ```
   tccutil reset Accessibility com.jamiewhite.signalladder
   ```

   SignalLadder cannot read notifications until you grant it again when it asks. Notification permission is separate. Change it in System Settings › Notifications › SignalLadder.

4. **Clear the mute checklist**, if you want every app to read _not confirmed muted_ again. The ticks are stored in the app's preferences, as hashes of app names, not the names:

   ```
   defaults delete com.jamiewhite.signalladder confirmedMutedAppDigests
   ```

5. **Launch SignalLadder** and check that the health line reads _Working — verified just now_.

[Privacy](privacy.md#removing-everything) lists everything SignalLadder stores on your Mac and how to remove all of it.

## See also

- [Getting started](getting-started.md): building, first run, permissions, your first rule and muting.
- [Writing rules by hand](rules-format.md): every key, operator, alert and error message.
- [Privacy](privacy.md): what SignalLadder reads, holds and stores.
