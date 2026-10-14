# Updates After 1.0 — Options for the Owner

> **Status:** decided on 2026-10-14, the day 1.0.0 was published; see [Decided](#decided). Option 1's docs are written. Option 2 is built: **Latest Release on GitHub…** beneath the version line in Settings, with `NoNetworkTests`, which makes the no-network promise test-enforced. Its words are this page's suggestion, which the owner has not settled. It is held by the tests, and was seen in the app on 2026-10-14, on macOS 27.2: pressed through the Accessibility API, not with a mouse, it opened the latest release in Chrome, and no connection by SignalLadder was seen. [Launch at login and Settings](../../architecture.md#launch-at-login-and-settings) says what was seen and what was not.

**The question:** how does someone running 1.0.0 learn that a newer SignalLadder exists, and get it? [Releasing](../releasing.md#what-has-not-been-tried) leaves it open: there is no updater, and nothing checks for a new version. Today the answer is that they find out only if they look.

## Decided

The owner answered on 2026-10-14, each time with the recommendation:

- **The no-network promise is a fixed part of the free app.** It is not traded for updates, so options 3 and 4 are not planned for it.
- **Option 1 now.** [Updating](../../getting-started.md#updating) has a part for the download: how to hear of a release, from GitHub's **Watch › Custom › Releases** or the releases feed, and the steps to replace the copy in Applications. The README links to it and has the FAQ entry _How do I hear about a new version?_, the privacy page's "Updates are manual" links to it, and [Each release](../releasing.md#each-release) says to give the steps in each release's notes and to mark a release candidate as a pre-release.
- **Option 2 is the first piece of 1.1**, in Settings beneath the version line, and not in the menu. With it comes the test that makes the no-network promise test-enforced.
- **Releases come a few times a year.** At that pace a user checking now and then is enough.

The questions below that these answers do not settle are still open: whether `CFBundleVersion` stays equal to the release number, the button's words, and release candidates beyond marking them as pre-releases.

The rest of this page is the options as they were written before the decision.

## Where things stand

- **1.0.0 is on GitHub Releases** at `JWhite212/SignalLadder`, a public repository, as a signed and notarised DMG with its checksum. `v0.1.0` was source only.
- **Releases are made on the owner's Mac, by hand.** `Scripts/release.sh` builds, signs, notarises and staples. It never uploads, tags or publishes: step 7 of [Each release](../releasing.md#each-release) does that by hand. CI builds and tests. It signs nothing and holds no key.
- **The app makes no network connection, and the pages promise it.** [What it never does](../../privacy.md#what-it-never-does) says so, says "Updates are manual", and gives a search of `Sources` that must print nothing. Its pattern already names `Sparkle`. The same promise is in the README (under Features, under Privacy and in the FAQ's _Does it send my notifications anywhere?_), in `SECURITY.md`, which counts any connection made by SignalLadder's own code as in scope, and in `docs/architecture.md`, whose table says the absence of networking is not test-enforced. `CONTRIBUTING.md` allows no third-party dependency without discussion.
- **The only written update path is for a build from source.** [Updating](../../getting-started.md#updating) says to pull, run `make-app.sh`, quit the running copy and replace the one in `/Applications`. Nothing yet tells a DMG user how to update.
- **The version line exists.** The foot of Settings names the version, the commit and the date. `CFBundleVersion` is `1.0.0`, the same text as the release number. Whether it stays so or becomes a count is not decided ([Each release](../releasing.md#each-release), step 1).
- **Launch at login survives a replacement in place, seen twice.** It uses `SMAppService.mainApp`. Replacing the bundle at the same path kept it registered twice on 2026-10-05, on macOS 26.7.1, and the steps used were not recorded. It has not been seen on macOS 14, 15 or 27.2. A copy outside Applications is not offered it at all.
- **The Accessibility grant follows the signature.** It is keyed on the bundle identifier and the team, so any update signed with the same Developer ID should keep it. The go/no-go bar asks for that to be seen on an upgrade over the previous build, and it has not been ticked.
- **Apple silicon only.** The executable is arm64. There is no Intel or universal build, and the floor is macOS 14.

## What matters in choosing

1. **A missed fix is a missed page.** An on-call tool running a stale build with a known fault is the failure SignalLadder exists to prevent. How many users an option reaches matters.
2. **The no-network promise is a feature.** It is unusual, and anyone can check it. On-call tools run on work Macs that security teams review. Weakening it changes four pages, `SECURITY.md` among them.
3. **An update must never land during a shift.** Installing means quitting, and while SignalLadder is quit nothing is captured. Its quit prompt already asks when you are on call or an escalation is listed. Any updater that quits the app meets that prompt.
4. **SignalLadder's own banners mean trouble.** Health alarms use them. A banner saying a version is available would teach people to ignore them. Any notice belongs in the menu or Settings.
5. **Release work stays on the owner's Mac.** Every option below keeps signing and keys off CI.

## Option 1: nothing in the app

**What the user sees.** Nothing new in the app. The docs tell them how to hear of a release: on GitHub, **Watch › Custom › Releases**, which needs a GitHub account, or the releases feed, `https://github.com/JWhite212/SignalLadder/releases.atom`, in any feed reader, which does not.

**Where the docs say it.**
- [Updating](../../getting-started.md#updating) gains a part for the DMG: how to hear of a release, then quit SignalLadder, open the new DMG, drag the app over the copy in Applications, choose **Replace**, open it and read the version line in Settings. The from-source steps stay.
- The README's download paragraph, and a new FAQ entry, _How do I hear about a new version?_
- The privacy page's "Updates are manual" links to Updating.
- Each release's notes repeat the update steps.

**What it costs.** Docs only, so hours. One live check is worth making with it: the DMG steps over a running copy with Launch at login on. That same check ticks the go/no-go bar's upgrade box.

**The no-network promise.** Untouched. The search still prints nothing.

**Releases.** Unchanged. Publishing the release is the announcement, so a draft announces nothing.

**Launch at login.** Dragging over the copy in Applications is the replacement in place seen twice on macOS 26.7.1. The risk is a user who runs the new copy from the disk image or from Downloads. Then two copies exist, and which one macOS starts at login has not been seen. Settings does say when Launch at login is not offered from where a copy is running.

**Apple silicon.** Anyone can download the DMG from a browser, so the release notes must keep saying Apple silicon only. The README's badge already does.

**Weakness.** Reach. Few people watch a repository, and a user on a faulty 1.0.0 stays on it.

## Option 2: an item that only opens the releases page

**What the user sees.** A button in Settings beneath the version line, or a menu item, or both, that opens `https://github.com/JWhite212/SignalLadder/releases/latest` in the browser. The user compares what it shows with the version line. It should not be called _Check for Updates…_, since the app checks nothing. Something like _Latest Release on GitHub…_ says what it does.

**What it costs.** Small, about a day with the docs. One button, one fixed address, its words kept out of the view as `ViewLiteralsTests` requires, and a test that the address is the fixed one with no query string, so it carries nothing about the Mac or the build. Plus option 1's docs.

**The no-network promise.** Kept. The app opens an address and the browser makes the connection, at the user's click. That is the same line the privacy page already draws for a Shortcut. Its list of what the app opens only when you choose, System Settings and the text editor, gains the browser. The search still prints nothing, since `NSWorkspace` is not in it.

A test that reads `Sources` for the search's pattern, as `PurityTests` reads the core, would make the promise test-enforced. It fits with this option or the first.

**Releases.** `releases/latest` is the newest release that is neither a draft nor a pre-release. So a release candidate must be marked as a pre-release on GitHub, or the button offers it to everyone.

**Launch at login and Apple silicon.** As option 1.

**Weakness.** The user still has to look. The place to look is now in the app, beside the version, which is better than a page they may never read.

## Option 3: an opt-in check of the GitHub releases API

**What the user sees.** A switch in Settings, off by default, such as _Check GitHub for a newer version once a day_. When it is on and a newer version exists, the menu gains one line, such as _SignalLadder 1.0.1 is available_, with option 2's item to open the page. No banner, no sound and no change to the bell, whose states mean health. Nothing downloads or installs. A failed check is silent, and never a health problem.

**How it would work.** One `GET` of `https://api.github.com/repos/JWhite212/SignalLadder/releases/latest`, reading `tag_name` and `html_url`, compared with `CFBundleShortVersionString`. At most once a day, and once when switched on. An ephemeral session, so no cookies and no cache. A fixed client name in the request's headers, since GitHub refuses a request without one, and the one macOS adds by default names the build number and the Darwin version. GitHub allows 60 unauthenticated requests an hour from one address, so a limit hit behind a shared office address is possible and must fail silently. GitHub learns the Mac's address, the time, and that it runs SignalLadder. The privacy page must say so.

**What it costs.** Medium, a few days with the docs and live checks.
- A new library target for the request, since `PurityTests` keep `NotificationCore` off the network.
- The version comparison as pure code in `NotificationCore`, with tests for tags such as `v1.0.1` and suffixes such as `-rc.1`.
- The request tested against a stand-in `URLProtocol`, never the real network.
- The switch, the menu line, and one more key in the defaults domain, which the privacy page lists.
- Every page that makes the promise, listed under _Where things stand_.
- Live checks: a real check, one with the network off, and one that finds a newer version.

**The no-network promise.** It becomes conditional: no connection unless you switch on the check, and then one request a day to GitHub. The search no longer prints nothing. It prints one file, and the page says which and why, as it already says that only one file of the app names the Setup Guide's key. The FAQ's _contains no networking at all_ goes. A user with a firewall such as Little Snitch is asked about SignalLadder once.

**Releases.** Nothing new is signed and nothing new runs on the owner's Mac. The habits become load-bearing instead. The tag must stay `v` followed by exactly the `CFBundleShortVersionString`. Release candidates must be pre-releases. A release must be published only once its DMG is attached, or users are told of a version with nothing to download. The repository's address is built into every copy, so it cannot move without breaking their checks.

**A variant.** Read a small file on signalladder.com instead. There is no rate limit and no tie to GitHub. But the owner then runs the server that sees every Mac's address, and the privacy page must say what its logs keep.

**Launch at login and Apple silicon.** As option 1, since the install is still by hand. No Intel copy exists to be told anything.

**Weakness.** Off by default means few turn it on. The absolute promise is traded for a minority.

## Option 4: Sparkle

**What the user sees.** The usual Mac updater: _Check for Updates…_ in the menu, and an alert with the release notes, **Install Update**, **Skip This Version** and **Remind Me Later**. It downloads, verifies, replaces the app in Applications and relaunches it. By default Sparkle asks on the second launch whether to check automatically, unless the app decides. For a menu-bar app, Sparkle 2.2 and later keeps scheduled alerts from taking focus, and asks the app to show its own gentle reminder, which here would be a menu line.

**Where the feed lives.**
- **On GitHub.** Each item points at the DMG already attached to its release. The feed itself is either committed and served from GitHub Pages, or attached to each release and read from `releases/latest/download/appcast.xml`. There is no server to run, and GitHub sees the addresses.
- **On signalladder.com.** The feed's address is the owner's, so the host can change without breaking copies in the field. The owner must keep the domain for as long as any copy checks it. A lapsed domain lets someone else serve the feed. Without the signing key they cannot install anything, but they see every copy's address.

**What it costs.** Large for this project, weeks rather than days with the live checks.
- **The first third-party dependency.** `Package.swift` gains `.package(url: "https://github.com/sparkle-project/Sparkle", …)`. Both of the privacy page's searches then print something. The app no longer imports Apple frameworks alone. Sparkle's licence is MIT, which the GPL allows. This document is the discussion `CONTRIBUTING.md` asks for.
- **Bundling by hand.** `Scripts/make-app.sh` assembles the bundle without an Xcode project, so there is no Archive step to sign Sparkle's helpers. The script would copy `Sparkle.framework` into `Contents/Frameworks`, set the run path, and sign the framework's helpers inside out with the Developer ID and the Hardened Runtime before the app. Its XPC services can be removed, as a non-sandboxed app may. `release.sh`'s checks would cover the nested code. How much the 3.98 MB app grows has to be measured.
- **A second key.** `generate_keys` puts an EdDSA private key in the owner's login keychain, and the public key goes into `Info.plist` as `SUPublicEDKey`, beside `SUFeedURL`. It must be backed up as [the signing key](../releasing.md#back-up-the-signing-key) is. Sparkle lets one of the two be changed in an update signed with the other, but not both. Losing both the Developer ID and the EdDSA key strands every copy on manual updates.
- **The quit.** Installing quits SignalLadder and relaunches it. That quit goes through `applicationShouldTerminate`, and `QuitPolicy` asks about any quit it cannot classify, so on call or with an escalation listed the prompt appears. The app would have to hold the install back in those states through Sparkle's delegate. The relaunch must be seen live: on-call state restored, capture attached and health good. Installing silently at the next quit, which Sparkle offers, would install at a log out, and that needs seeing too.
- **The version.** Sparkle compares `CFBundleVersion`, which must rise with every release and be machine-readable. `1.0.0` works, a suffix such as `-rc.1` is a risk, and the open question in step 1 of Each release must be settled first.

**The no-network promise.** Gone as an absolute. With scheduled checks off it becomes: no connection until you ask it to check, or allow it to. Sparkle's system profile is off unless `SUEnableSystemProfiling` is set, and it stays off. A check then fetches the feed, and an update downloads the DMG. The notes should be in the feed and not linked, so a check is one request. Every page under _Where things stand_ changes, and `SECURITY.md`'s scope line with them.

**Releases.** It fits the owner's Mac, because the EdDSA key must never leave it and CI must never hold it. `release.sh` could run `sign_update` on the stapled DMG and write the feed item into `build/release` beside the `.sha256`, still uploading nothing. Publishing gains a step, in order: the release and its DMG first, then the feed, so no copy is offered a file that is not there. A wrong feed reaches every copy that checks. `sparkle:phasedRolloutInterval` can spread a release over days.

**Launch at login.** Sparkle replaces the bundle at the same path, with the same identifier and signature. That is the case seen to keep the registration twice on macOS 26.7.1, but by hand. Sparkle's own replacement and relaunch have not been seen with it, on any macOS. That is a live check before shipping, and so is the Accessibility grant.

**Apple silicon.** Every copy that can read the feed already runs on Apple silicon, so `sparkle:hardwareRequirements` (`arm64`, Sparkle 2.9 and later) has nothing to stop today. It matters only if an Intel or universal build ever appears. `sparkle:minimumSystemVersion` lets a later release raise the macOS floor without being offered to a Mac it would not run on.

**The Pro edition.** A paid edition sold directly usually ships an updater, and may connect for a licence anyway. If Pro will use Sparkle, building it into the free app first spreads the work. It also puts a dependency and a network path into the GPL app for the paid one's sake.

## Side by side

| | 1. Docs only | 2. Opens the page | 3. Opt-in check | 4. Sparkle |
|---|---|---|---|---|
| In the app | Nothing | One button or item | A switch and a menu line | An updater |
| Connections by SignalLadder's own code | None | None (the browser's) | One a day to GitHub, if switched on | The feed, and the download, when allowed |
| Third-party code | None | None | None | Sparkle |
| Cost to build | Hours | About a day | A few days | Weeks |
| Added to each release | Nothing | Mark candidates as pre-releases | Tag and pre-release discipline | `sign_update`, the feed, a second key to keep |
| Reaches users who do not look | No | Partly | Those who opt in | Yes, if they allow checks |
| Can install during a shift | No | No | No | Only if the app fails to hold it back |

## Recommendation

> **This is a recommendation, not a decision.** The owner decides.

Do option 1 now, and option 2 as the next small piece of work. Keep the no-network promise whole through 1.x. Look again at option 3 or 4 when either a fix ships that users must have and the release notes show options 1 and 2 are not reaching them, or the Pro edition's plan settles whether it needs an updater anyway.

- 1.0.0 is a day old and the release pace is unknown. At a slow pace, an updater's cost in a dependency, a key, a quit path and every page that makes the promise buys little.
- The promise is checkable, and that is a reason to choose SignalLadder on a work Mac.
- Option 2 gets much of option 3's reach for a fraction of the cost, with the version line and the latest release one click apart.
- Option 1's docs are needed whatever comes later, since nothing tells a DMG user how to update. Its live check is the go/no-go bar's upgrade box.
- If an in-app notice is wanted later, option 3 comes before option 4. It adds no dependency and no key, and no install path that quits the app mid-shift.
- Add the test that makes the promise test-enforced alongside option 2, so it cannot break by accident.

## The owner's questions

1. Is the no-network promise a fixed part of the free app, or one you would trade for updates?
2. How often do you expect to release: fixes most months, or a few releases a year?
3. If there is ever an in-app check, should it be off by default, on by default, or asked once in the Setup Guide?
4. Is signalladder.com yours, and do you want to run anything there that sees users' addresses? Or is GitHub the only host?
5. Will the Pro edition need an updater, or a connection for a licence? Should both editions update the same way?
6. Should `CFBundleVersion` stay equal to the release number, or become a count? Options 3 and 4 both need the answer.
7. Should an update ever install while you are on call, while an escalation is listed or while a snooze is holding matches?
8. For option 2: Settings beneath the version line, the menu, or both, and in what words?
9. Release candidates: GitHub pre-releases, so `latest` skips them, or not published at all?
