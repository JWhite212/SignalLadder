# Security policy

SignalLadder reads the notification banners on your Mac, so it should be held to a higher standard than most apps. This page says which versions get fixes, how to report a problem privately, what counts as a security problem, and where the app's own limits are. For what it reads, keeps and never does, see [Privacy and permissions](docs/privacy.md).

## Supported versions

SignalLadder is pre-release. Its first tagged release is [v0.1.0](https://github.com/JWhite212/SignalLadder/releases/tag/v0.1.0), and it is source only: there is no signed download yet.

| Version | Supported |
| ------- | --------- |
| `main` | Yes. Fixes land here |
| The latest release | Yes |
| Older releases | No. Build the latest release or `main` |

There is no auto-update. A fix reaches you when you build the new version yourself.

## Reporting a vulnerability

Report it privately, through GitHub: [report a vulnerability](https://github.com/JWhite212/SignalLadder/security/advisories/new). You need a GitHub account.

> [!IMPORTANT]
> Never report a security problem in a public issue, pull request or discussion, and do not post its details anywhere public. A public report tells everyone before there is a fix.

Please include:

- What you found, and what it lets someone do.
- The version or commit, and your macOS version.
- The steps to reproduce it, and a proof of concept if you have one.
- Any notification text or rules file involved, with names and messages replaced by placeholders such as `Alex Example`. Do not send real notifications.

Test only on your own Mac, with your own notifications.

What happens next:

- The maintainer, @JWhite212, aims to acknowledge your report within a week. SignalLadder has one maintainer, so this is an aim, not a guarantee.
- You will be told whether it is confirmed, and kept informed while it is fixed. If a fix will take longer than expected, you will be told why.
- Disclosure is coordinated. Please give time for a fix before you publish anything. When it is fixed, the details are published as a GitHub security advisory.
- You are credited in the advisory if you want to be. Say how you would like to be named, or that you would rather not be.

## What counts

These are security problems. Report them privately:

- Anything that could leak notification content: to another process, another user, the network, or a screen where it should not appear.
- Anything that writes notification text to logs, or to disk anywhere but the two [documented](docs/privacy.md#on-disk) places: text you choose to put in a rule condition, which is saved in your rules file, and the input file a Shortcut reads.
- The Shortcut's input file lasting longer than it should, or open to more people than it should. It counts if the file is still there after the Shortcut's process has ended, unless SignalLadder crashed, or after SignalLadder next starts or quits. It counts if the file holds more than a notification's app name, title, subtitle and body. It counts if its folder is wider than mode 0700, or the file wider than 0600.
- Any network connection made by SignalLadder's own code. There should be none.
- Crafted notification text that makes SignalLadder do more than match and carry out the steps of the rule it matches: run anything that rule does not name, open something, read or write files, or crash.
- A crafted rules file that does more than define rules. Naming a Shortcut to run is defining a rule.
- Anything that weakens code signing or the Hardened Runtime, such as an entitlement the app does not need, or a build that ships unsigned or ad-hoc signed.
- Anything that damages a user's rules file: losing, corrupting or silently overwriting it, despite the backups and the check for changes described in [rules format](docs/rules-format.md#where-the-file-is).

These are not, or are handled another way:

- **Missed alerts and capture bugs.** A missed alert is the most serious kind of bug SignalLadder can have, because avoiding one is why it exists. But it is a reliability problem, not a security one. Use the [bug report form](https://github.com/JWhite212/SignalLadder/issues/new/choose), with names and messages replaced by placeholders.
- **A notification that matches a rule.** Anyone who can send you a notification can make a rule match, and the rule then does what it says: plays its sound, speaks its line and, if it escalates, shows its panel, repeats its alert and runs its Shortcut. That is what rules are for.
- **Anything that needs a Mac that is already compromised, or physical access to it.** Someone who can already run code as you, or sit at your unlocked Mac, can read your notifications without SignalLadder.
- **What a Shortcut does with the text it is given.** A rule's last step can hand a notification's app name, title, subtitle and body to a Shortcut you named, and the Shortcut can send them anywhere. That is what the step is for. The text is whatever the sender wrote, so a Shortcut should treat it as untrusted. A report that SignalLadder runs a Shortcut no rule names, or gives one more than those four fields, is in scope. A rules file can name any Shortcut on your Mac, so read a rules file someone else wrote before you use it.
- **The size of the Accessibility permission itself.** That is how macOS designed it, and it is listed below. A report that SignalLadder's code uses it on anything other than Notification Centre is in scope.
- **Problems in macOS or Apple's frameworks.** Report those to Apple.

## Security model at a glance

- **Permissions.** Accessibility, which is required, and Notifications, which is used only for the app's self-test and health alarm. It does not use the microphone, camera, screen recording, full-disk access, location, contacts or automation. Its hotkey for acknowledging an alert needed no permission on macOS 26.7, the only version it has been checked on.
- **Not sandboxed.** The App Sandbox blocks Accessibility, so the app cannot be sandboxed. That is also why it is not on the Mac App Store.
- **No network code and no dependencies.** SignalLadder's own code has no networking, telemetry, analytics, crash reporting or update checks, and uses only Apple frameworks. A Shortcut a rule runs is not SignalLadder's code, and may use the network.
- **Hardened Runtime, no entitlements.** `Scripts/make-app.sh` signs with the Hardened Runtime, passes no entitlements, and refuses an ad-hoc signature. There is no notarised download yet.
- **Notification text stays in memory, with two exceptions.** The last 50, and the notification held by any escalation not yet acknowledged, gone when you quit. It is not written to logs. It reaches disk only as text you put in a rule condition, and in the input file a Shortcut reads: a folder of its own, mode 0700, holding a file, mode 0600, with a notification's app name, title, subtitle and body. That file is deleted the moment the Shortcut's process ends, and anything left is removed when SignalLadder starts and when it quits.
- **Untrusted input.** Notification text is matched, never executed. A Shortcut is run by the name in your rules file, or by the name you press Test Shortcut on in the rule editor, as one argument and never through a shell, and a notification's text reaches it only as data in the input file. There is no regular-expression operator: rules use plain comparisons and a glob whose worst case is bounded. A rules file is read strictly, so an unknown key is an error and a newer format is refused rather than misread. It is written in one step, and a copy of the version it replaces is kept.

Known gaps:

- The Accessibility grant is broad. Once you allow it, macOS lets SignalLadder read any app's interface. Only its code, which you can read, keeps it to Notification Centre.
- There is no signed download yet, and nothing in the repository today would let you check that a future one matches the source. Building it yourself is the way to be sure.
- `rules.json` is written with your account's default file permissions. SignalLadder does not tighten them.
- The Shortcut's input file is deleted, not overwritten. After a crash it stays until SignalLadder next starts. What a Shortcut does with the text once it has it is outside SignalLadder's control.
- That notification text never reaches a log is upheld by code review, not by an automated test. [Privacy and permissions](docs/privacy.md#logs) says what is tested and what is not.
