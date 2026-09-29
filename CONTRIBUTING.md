# Contributing to SignalLadder

Thank you for wanting to help. SignalLadder is a small macOS menu-bar app with one maintainer, [@JWhite212](https://github.com/JWhite212), so a careful contribution is worth more than a fast one. This page says what every change is judged by, how to build and check one, and the conventions the code already follows.

- [The one question](#the-one-question)
- [Before you start](#before-you-start)
- [Setting up](#setting-up)
- [How the code is organised](#how-the-code-is-organised)
- [Conventions](#conventions)
- [Tests](#tests)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [Documentation](#documentation)
- [Licensing of your contribution](#licensing-of-your-contribution)
- [Security and conduct](#security-and-conduct)

## The one question

Every change is judged by one question: **does this help someone not miss the critical alert?**

SignalLadder exists because its author is on call and misses critical alerts when chatty apps ping constantly. The noise teaches you to ignore it, and the one alert that matters is lost among the rest. It is an alert-fatigue tool, not a sound-personalisation toy.

That decides a lot in practice:

- A change that makes a missed alert less likely is welcome. So is one that makes a failure louder, clearer or earlier.
- A change that adds noise is unlikely to be accepted, however useful it is otherwise.
- A change that lets the app say something reassuring it has not established is unlikely to be accepted either. _Played_ is not _heard_, and _verified_ carries its age. See [Say no more than was established](#conventions).

## Before you start

Open an issue for anything beyond a small fix. A small fix is a typo, a wording error, a documentation correction, or a bug whose fix is obvious and comes with a test. Everything else, such as a new feature, field, operator or alert, a change to the rules format, a change to how capture, health or audio work, or a new dependency, deserves an issue first.

The issue forms ask for what helps most. Notifications carry other people's names and messages, so replace every name, channel and message with a placeholder before you paste anything. See [Fixtures/captures/README.md](Fixtures/captures/README.md) for the rules.

Why ask first:

- **Much of the code encodes something measured.** How macOS draws, replaces and replays banners was found by experiment, and the results are recorded in [docs/dev/notes](docs/dev/notes). A change that looks like a simplification can undo a fix. A short conversation before you write it costs less than a rewrite after.
- **Some things are planned and some are only ideas.** Alerts that keep going until acknowledged have a plan in [docs/dev/plans](docs/dev/plans) and no code. Snooze, an on-call mode, a `regex` operator, a text rule language and a Settings window appear in the original design and are not built. If you want to work on one, say so, so the design is not done twice.
- **There is one maintainer.** A change that was discussed is reviewed faster.

If you have found a security problem, do not open an issue. See [Security and conduct](#security-and-conduct).

## Setting up

You need a Mac and a Swift toolchain.

- The app declares macOS 14 Sonoma as its minimum. All development and every recorded live check so far has been on macOS 26.7 on an Apple silicon Mac.
- Use a recent Xcode, or the Xcode command-line tools. The package manifest declares `swift-tools-version:5.9`, but only a recent toolchain has been tried: the maintainer builds with Apple Swift 6.4 (Xcode 27 beta), in Swift 5 language mode. If the build fails on an older one, say which in an issue.

```
swift build                        # build everything
swift test                         # run every test
swift test --filter PurityTests    # one suite or case, by name
```

`swift test` needs no certificate and no permission prompt, and it makes no sound: audio is rendered into memory. It takes about 20 seconds of test time, most of it speech. To read the result, look for the `Executed N tests` lines. The `Test run with 0 tests` lines at the end come from a newer test library the project does not use, and are expected. At the time of writing there are 507 tests: 421 in `NotificationCoreTests`, 67 in `AlertAudioTests` and 19 in `RuleStorageTests`.

Some tests depend on your Mac. The speech tests skip themselves if the en-GB voice they use is not installed. One test expects the Mac to report an output device. Another expects the macOS system sounds to exist.

### Building and running the app

[docs/getting-started.md](docs/getting-started.md) walks through building the app, signing it and granting permissions. Two things matter most if you are contributing:

- **Set your own signing identity.** `Scripts/make-app.sh` takes the 40-character SHA-1 of a code-signing identity in `SIGNALLADDER_IDENTITY`. Its default is the maintainer's own, which is not on your Mac, so without your own it builds everything and then fails at the signing step. List yours with `security find-identity -v -p codesigning`.
- **Ad-hoc signing is refused on purpose.** It ties the app's identity to a hash of each build, and macOS then forgets the Accessibility grant every time you rebuild.

The supported way to run the app is the signed bundle the script builds, `build/SignalLadder.app`. `swift run SignalLadder` is not supported: the app takes its name from its bundle and sends its self-test through it.

To see what a banner looks like from the outside, run `swift run signalladder-probe`. It prints each captured banner with its text hidden as a character count. `--show-content` prints the text, so redact it before you share the output.

### Checking a running build

`Scripts/verify-live.sh` checks a running, signed `build/SignalLadder.app`. It reads the menu, posts test banners, and confirms the app captured them, that health agrees with what happened, and that the Inspector and rule editor open.

```
open build/SignalLadder.app
./Scripts/verify-live.sh
```

- **The terminal you run it from needs Accessibility**, in System Settings › Privacy & Security, because the script reads the menu through System Events. Without it the script exits with 2, meaning it could not run.
- It posts three real banners on your screen, titled _SignalLadder Test_. It prints no captured text.
- It exits 0 if every check passed and 1 if one failed.
- It cannot grant or revoke Accessibility, switch the app's banners off, or toggle Do Not Disturb. Those stay manual, and it lists them at the end.

## How the code is organised

The package has four libraries, an app and a command-line probe. Every decision lives in `NotificationCore`, as pure code that is tested without any permission: what a banner says, whether it is a repeat, which rule matches, what health is, and what the menu says about it. `NotificationCapture`, `AlertAudio` and `RuleStorage` are the parts that touch the system: Accessibility and notifications, audio, and the rules file. The app target, `SignalLadder`, only connects them, and has no tests of its own. So when you add behaviour, put the decision in `NotificationCore` with tests and keep only the system call in the outer target.

[docs/architecture.md](docs/architecture.md) is the map: the principles behind the design, a module table, the path from a banner to a sound, how the app knows it still works, how rules are stored, and how audio is tested. Read its principles before a first change, because they are the reasons behind the conventions below. The original design and the running log of live findings are under [docs/dev](docs/dev). The design predates the code and describes features that are not built, so where the two disagree, the code is right.

## Conventions

These are visible throughout the code. Following them is most of what review asks for.

- **Comments explain why, and cite the evidence.** A comment rarely says what a line does. It says why the line is there, and when a decision rests on something measured or something that went wrong, it says what and when: _measured on macOS 26.7, 2026-09-29_. Cite the design by section (`§5.16`) or the note that records the finding. If you learn how macOS behaves by experiment, add a dated entry to [docs/dev/notes](docs/dev/notes) with the macOS version, what you saw, and what you did not test.
- **Wording that says what the app knows lives in `NotificationCore`, where it is tested.** Health lines, alert outcomes, the rules status, the rule editor's text and the mute walkthrough are pure functions there. Wording is where the app has misled before, and the app target cannot be tested. Menu item titles are in the app target, and `Scripts/verify-live.sh` matches some English wording, so change the script when you change the wording.
- **Say no more than was established.** _Played_ means the app played it, not that you heard it. _Verified_ carries its age. Muting is _confirmed_, because it is the user's word. New messages and interface text follow the same rule.
- **Notification text never goes into logs, files, fixtures or screenshots.** Logging passes a process id, a subrole or a count, never text. The only text on disk is the text a user chooses to put in a rule. Fixtures follow [Fixtures/captures/README.md](Fixtures/captures/README.md): replace people with `Alex Example`, messages with `Placeholder body text` and channels with `General`, and keep app names as they are. The same goes for screenshots, issue text and test data. A change that makes any notification text leave memory needs discussion first, and an update to [docs/privacy.md](docs/privacy.md).
- **Failures are reported, never swallowed.** A failure that could leave someone without an alert must reach them: an outcome on the Inspector row, a line in the menu, a problem listed against the rule. Do not add a fallback that quietly does something else. Where you catch an error and carry on, a comment should say why that is safe. Prefer finding a problem when rules load to finding it at the incident.
- **No third-party dependencies without discussion.** The package has none, and every framework it imports is Apple's. The app holds an Accessibility grant and reads other people's notifications, so anything it links runs with that access. Open an issue first, and expect a high bar.
- **Zero compiler warnings.** A clean build emits none, and changes are held to that. Check with `swift package clean && swift build 2>&1 | grep warning`.
- **British English in user-facing text.** Menu items, messages, documentation and comments use it: _behaviour_, _colour_, _organise_, _licence_ (noun) and _license_ (verb), _Notification Centre_, _on call_. Identifiers we name follow it too, such as `NotificationCentreHistory`. Apple's API names stay as Apple spells them.

## Tests

- **New behaviour comes with tests.** A bug fix comes with a test that fails without the fix. `swift test` must pass.
- **Put tests where the code is.** Decisions go in `NotificationCoreTests`, which has `FakeNode`, an in-memory Accessibility tree, for banner location and reading. Audio goes in `AlertAudioTests`, which renders the real graph offline and measures it. The rules file goes in `RuleStorageTests`, which uses real temporary folders. `PurityTests` fails if `NotificationCore` imports a permission-bearing framework or touches a file or URL. Move the code rather than work around it.
- **Watch a new test fail.** Break the behaviour it covers, check that the test notices, then restore it. A test you have never seen fail proves little.
- **Changes that touch capture, health or audio also need a live check on a real Mac.** `NotificationCapture`, the app target and the probe have no automated tests, so they are covered by `Scripts/verify-live.sh` and by checking by hand what it cannot. Say which macOS you used in the pull request. Every recorded live check so far was on macOS 26.7, so results from macOS 14 and 15 are especially welcome. If you cannot check on a real Mac, say so and the maintainer will.

## Commit messages

The history follows one convention. A type, a colon, and a plain sentence about the behaviour:

```
fix: a banner that replaces another while it is on screen is captured
fix: opening Notification Centre no longer replays history a minute old
feat: a match speaks
test: the live harness checks a banner that replaces another is captured once
docs: M3d's four listening checks pass
```

- The type is one of `feat`, `fix`, `docs`, `test` or `refactor`. There is no scope in brackets.
- The sentence starts in lower case, has no full stop, and says what is now true or what was wrong, not what you did to the files.
- A body is optional. When a change needs one, it says why the change was needed and what was observed, wrapped at about 72 characters.
- One concern per commit.

## Pull requests

- **Keep them small, with one concern.** A refactor and a behaviour change belong in separate pull requests.
- **Name the branch for the change,** such as `fix/fresh-history-replay`, and branch from `main`.
- **Fill in the [template](.github/pull_request_template.md).** It asks what the change does, why, and how you checked it, and then for four things: `swift test` passes; a live check on a running build, with the macOS version, if you touched capture, health or audio; `docs/rules-format.md` updated, and older files still loading, if you changed the rules file; and no notification text reaching a log, a file, a fixture or a screenshot.
- **Link the issue** with `Fixes #…`.

## Documentation

- **A change to the rules file updates [docs/rules-format.md](docs/rules-format.md)** in the same pull request: a key, field, operator, alert, version or error message. Older files must still load. A file is written at the lowest version that holds its rules, and a version newer than the app understands is refused, not misread.
- **A change a user can see adds a line under Unreleased in [CHANGELOG.md](CHANGELOG.md)**, in the style of the entries already there.
- **A change to what the app stores, logs or sends, or to the permissions it needs, updates [docs/privacy.md](docs/privacy.md),** and needs discussion before you write it.
- **Say what is true, and what is not.** Do not describe planned work as built. Label it as planned, or leave it out. The voice is plain and calm, in the second person and in short sentences, with no hype. Screenshots use placeholder content only.

## Licensing of your contribution

SignalLadder is licensed under the [GNU General Public License, version 3](LICENSE). Contributions are accepted under the same licence: what you contribute is licensed to everyone on the same terms as the rest of the project. There is no separate agreement to sign.

Only contribute work that is yours to license this way. If you include code from somewhere else, it must be under a licence that is compatible with GPL-3.0, and the pull request should say where it came from.

## Security and conduct

- **Security problems** go to [SECURITY.md](SECURITY.md), not to a public issue. Reports are made privately through [GitHub's private vulnerability reporting](https://github.com/JWhite212/SignalLadder/security/advisories/new).
- **Conduct** is covered by the [Code of Conduct](CODE_OF_CONDUCT.md). It applies in issues, pull requests and every other space around the project.
