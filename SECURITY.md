# Security policy

SignalLadder reads the notification banners on your Mac, so it should be held to a higher standard than most apps. This page says which versions get fixes, how to report a problem privately, what counts as a security problem, and where the app's own limits are. For what it reads, keeps and never does, see [Privacy and permissions](docs/privacy.md).

## Supported versions

SignalLadder is pre-release, at version 0.1.0. There is no tagged release yet.

| Version | Supported |
| ------- | --------- |
| `main` | Yes. Fixes land here |
| Tagged releases | None exist yet. Once they do, only the latest release is supported |

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
- Anything that writes notification text to disk or to logs. The exception is text you choose to put in a rule condition, which is saved in your rules file and is [documented](docs/privacy.md#on-disk).
- Any network connection made by SignalLadder's own code. There should be none.
- Crafted notification text that makes SignalLadder do more than match and alert: run something, open something, read or write files, or crash.
- A crafted rules file that does more than define rules.
- Anything that weakens code signing or the Hardened Runtime, such as an entitlement the app does not need, or a build that ships unsigned or ad-hoc signed.
- Anything that damages a user's rules file: losing, corrupting or silently overwriting it, despite the backups and the check for changes described in [rules format](docs/rules-format.md#where-the-file-is).

These are not, or are handled another way:

- **Missed alerts and capture bugs.** A missed alert is the most serious kind of bug SignalLadder can have, because avoiding one is why it exists. But it is a reliability problem, not a security one. Use the [bug report form](https://github.com/JWhite212/SignalLadder/issues/new/choose), with names and messages replaced by placeholders.
- **A notification that matches a rule.** Anyone who can send you a notification can make a rule match, and the rule then plays its sound or speaks its line. That is what rules are for.
- **Anything that needs a Mac that is already compromised, or physical access to it.** Someone who can already run code as you, or sit at your unlocked Mac, can read your notifications without SignalLadder.
- **The size of the Accessibility permission itself.** That is how macOS designed it, and it is listed below. A report that SignalLadder's code uses it on anything other than Notification Centre is in scope.
- **Problems in macOS or Apple's frameworks.** Report those to Apple.

## Security model at a glance

- **Permissions.** Accessibility, which is required, and Notifications, which is used only for the app's self-test and health alarm. It does not use the microphone, camera, screen recording, full-disk access, location, contacts or automation.
- **Not sandboxed.** The App Sandbox blocks Accessibility, so the app cannot be sandboxed. That is also why it is not on the Mac App Store.
- **No network code and no dependencies.** SignalLadder's own code has no networking, telemetry, analytics, crash reporting or update checks, and uses only Apple frameworks.
- **Hardened Runtime, no entitlements.** `Scripts/make-app.sh` signs with the Hardened Runtime, passes no entitlements, and refuses an ad-hoc signature. There is no notarised download yet.
- **Notification text stays in memory.** The last 50, gone when you quit. It is not written to disk or logs, except text you put in a rule condition.
- **Untrusted input.** Notification text is matched, never executed. There is no regular-expression operator: rules use plain comparisons and a glob whose worst case is bounded. A rules file is read strictly, so an unknown key is an error and a newer format is refused rather than misread. It is written in one step, and a copy of the version it replaces is kept.

Known gaps:

- The Accessibility grant is broad. Once you allow it, macOS lets SignalLadder read any app's interface. Only its code, which you can read, keeps it to Notification Centre.
- There is no release yet, and nothing in the repository today would let you check that a future download matches the source. Building it yourself is the way to be sure.
- `rules.json` is written with your account's default file permissions. SignalLadder does not tighten them.
- That notification text never reaches a log is upheld by code review, not by an automated test. [Privacy and permissions](docs/privacy.md#logs) says what is tested and what is not.
