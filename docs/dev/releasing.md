# Releasing SignalLadder

How a commit becomes a download: built, signed, notarised by Apple and stapled, on the maintainer's Mac. This page is for the maintainer. Nobody else needs it to build or contribute.

**Where this stands (2026-10-14).** `Scripts/release.sh` has made a release. On 2026-10-14 it built, signed, notarised and stapled 1.0.0 from `main` at `a6de31b` with Xcode 27.1, and Apple accepted the app and the DMG: see [The 1.0.0 release](#the-100-release). Before that, on 2026-09-30, it ran for real as a rehearsal, first with the Xcode 27 beta and then with a released Xcode, and nothing was tagged, published or installed: see [The first real run](#the-first-real-run). It has also had dry runs (`--skip-notarize`), which stop short of Apple's notary service: the first is described under [What the dry run showed](#what-the-dry-run-showed), and another was made on 2026-10-05 in a clean scratch clone, where it finished with exit 0. A rejected submission has not been tried.

1.0.0 is tagged `v1.0.0` and released with a signed and notarised DMG, whose release notes give its checksum and the Xcode that built it. `v0.1.0`, the tag before it, was source only.

- [The short version](#the-short-version)
- [What the script does](#what-the-script-does)
- [One-time setup](#one-time-setup)
- [Before any public release: the go/no-go bar](#before-any-public-release-the-gono-go-bar)
- [Each release](#each-release)
- [When the script stops](#when-the-script-stops)
- [What the dry run showed](#what-the-dry-run-showed)
- [The first real run](#the-first-real-run)
- [A later dry run](#a-later-dry-run)
- [The 1.0.0 release](#the-100-release)
- [What has not been tried](#what-has-not-been-tried)

## The short version

```sh
SIGNALLADDER_IDENTITY=<40-character SHA-1> Scripts/release.sh
```

That builds, signs, notarises and staples, and leaves `build/release/SignalLadder-<version>.dmg` and its checksum. `--skip-notarize` is the dry run: everything except Apple's notary service and stapling, with `-unnotarized` in the file names so the result cannot be mistaken for a release. `--allow-dirty` builds a tree with uncommitted changes, which a release never does.

The script **never uploads, tags, publishes, installs into `/Applications` or launches the app.** The last steps, trying the DMG and publishing it, are yours.

## What the script does

1. **Checks the signing identity.** It must be the 40-character SHA-1 of a `Developer ID Application` certificate in your keychain, and the certificate's team must be `RVVRP4WY6B`. Any other kind of certificate, such as Apple Development or Apple Distribution, is refused, because an app signed with it cannot be notarised for use outside the App Store.
2. **Records the toolchain**: `xcodebuild -version`, `swift --version`, the developer directory and the macOS version. It warns loudly if Xcode is a beta.
3. **Reads the version and identifier from `Resources/Info.plist`**, and warns if the tag `v<version>` already exists or if you are not on `main`. It refuses a tree with uncommitted changes unless you pass `--allow-dirty`.
4. **Checks the notarytool profile works**, before the build, so a mistyped name costs seconds and not a build. It asks Apple only for the list of past submissions.
5. **Builds with `Scripts/make-app.sh release`**, which signs with the Hardened Runtime and a secure timestamp.
6. **Checks the executable**: exactly `arm64`, and no newer a minimum macOS than `Info.plist` promises.
7. **Checks the signature**: it verifies, has the Hardened Runtime flag and a secure timestamp, and its designated requirement names the identifier from `Info.plist` and team `RVVRP4WY6B`. The requirement is what a user's Accessibility grant is keyed on, so a signature that names anything else would make every user grant access again.
8. **Notarises the app, then staples the ticket to it.** It zips the app with `ditto`, submits it with `notarytool submit --wait`, and stops unless the status is exactly `Accepted`. On any other status it fetches and prints `notarytool log` first. The app is done first so that it carries its own ticket, and a first launch works offline even after the app has been dragged out of the DMG.
9. **Builds the DMG**: the app and an `Applications` link, compressed (UDZO), volume name `SignalLadder <version>`, with no background picture or custom window layout. It signs the DMG and mounts it read-only to check that it holds an arm64 app whose signature verifies.
10. **Notarises and staples the DMG.**
11. **Prints the final verification**: `spctl` on the app and on the DMG, and `stapler validate` on both. A real release stops unless `spctl` reports `source=Notarized Developer ID` for both and both tickets validate.
12. **Writes the outputs**, and only now, so a run that fails leaves nothing that looks like a release.

The calls to Apple's tools that can wait go through a time limit, because they have hung on this Mac. `codesign -d` did once, and macOS has no `timeout` command, so the script uses `perl`'s alarm. A call that overstays is killed and reported as timed out. If `codesign -d` times out, a dry run says so and carries on, and a real release stops, because it could not then say the requirement was read back.

It uses only what ships with macOS and Xcode.

### What it writes

In `build/release/`, which git ignores:

| File | What it is |
| --- | --- |
| `SignalLadder-<version>.dmg` | The download. A dry run writes `SignalLadder-<version>-unnotarized.dmg` instead, which is signed but not notarised and is not for anyone else. |
| `SignalLadder-<version>.dmg.sha256` | Its checksum from `shasum -a 256`, made after stapling because stapling changes the file. Check it with `shasum -a 256 -c` in the same folder. |
| `SignalLadder-<version>.build.txt` | The commit, whether the tree was clean, the toolchain, whether it was a beta, the Apple submission ids, the sizes and the checksum. Keep it with the release notes. |

A real run refuses to start if `SignalLadder-<version>.dmg` is already there. Building a version twice gives different bytes and a different checksum, so delete the old file yourself if you mean to do that.

The build also replaces `build/SignalLadder.app` with the release build, and stapling changes it. Run `Scripts/make-app.sh debug` afterwards to go back to a debug build.

## One-time setup

### Apple Developer Program

Check that your membership is current and that every agreement is accepted, at developer.apple.com under Account, and in App Store Connect under Business, which lists the agreements. Until both are true, Apple can refuse notarisation. The maintainer believed both were in order on 2026-09-30, and Apple accepted the submissions made that day. Check again before a release, because only a submission tests it.

### The signing certificate

You need a `Developer ID Application` certificate and its private key in the login keychain of the Mac that builds releases. This Mac has one, `Developer ID Application: Jamie White (RVVRP4WY6B)`, valid to 2031. List your identities with:

```sh
security find-identity -v -p codesigning
```

The hash at the start of the `Developer ID Application` line is what `SIGNALLADDER_IDENTITY` takes. Put `export SIGNALLADDER_IDENTITY=<hash>` in your shell profile, the same as for `make-app.sh`. Note the spelling: two Ds, as in _Ladder_. The list on this Mac has nine identities and only one of them is a Developer ID one. The script was run with an Apple Development hash and an Apple Distribution hash on 2026-09-30, and refused both.

### Credentials for notarytool

`notarytool` reads credentials from a keychain profile, which you create once. There are two ways to authenticate, and either works. The app-specific password is prompted for, so it never lands in your shell history. The API key route reads the `.p8` file and prompts for nothing, so keep that file private.

**An app-specific password.** At appleid.apple.com, under Sign-In and Security, create an app-specific password. Then:

```sh
xcrun notarytool store-credentials "SignalLadder" --apple-id <Apple ID> --team-id RVVRP4WY6B
```

It prompts for the password. Do not put it on the command line.

**An App Store Connect API key.** In App Store Connect, create a team API key under Users and Access, in Integrations. Apple lets you download the `.p8` file once, so keep it somewhere safe. Note the key's ID and the issuer ID. Then:

```sh
xcrun notarytool store-credentials "SignalLadder" --key <path to the .p8 file> --key-id <key ID> --issuer <issuer ID>
```

`notarytool` says the issuer is required for a team key and must be left out for an individual key.

`SignalLadder` is the profile name the script looks for. To use another, set `NOTARY_PROFILE`. `store-credentials` checks the credentials with Apple before it saves them. To see that the profile works later:

```sh
xcrun notarytool history --keychain-profile SignalLadder
```

An empty list is right for a profile that has not been used yet, and after a submission the list shows it. The script runs this check itself before it builds. If macOS asks whether `notarytool` may use the keychain item, that is expected the first time. A prompt hidden behind another window makes the call time out after two minutes, and the script says so.

### Back up the signing key

The certificate is no use without its private key, and the key lives only in this Mac's keychain. In Keychain Access, under My Certificates, select the `Developer ID Application` certificate, choose File, then Export Items, and save a `.p12` with a strong password. Keep the file and the password in separate places, both away from this Mac.

The designated requirement names the team and not the certificate, so a replacement Developer ID certificate from the same team should satisfy it and leave users' Accessibility grants alone. That has not been tried.

### The bundle identifier

The identifier and the team make up the designated requirement, so both are baked into every user's Accessibility grant. Changing either after users have installed the app makes every one of them grant access again. Settle the identifier before the first release.

The scripts read it from `Resources/Info.plist`, and `make-app.sh` and `release.sh` need nothing else changed. The code and docs also write it out, so a change is not one line. `grep -rl com.jamiewhite .` finds them. The ones that matter most are `Sources/SignalLadder/RuleStore.swift` and `Sources/AlertAudio/SoundLibrary.swift`, which put the rules and sounds in a folder under Application Support named after it, so users who had the old identifier would lose sight of their rules. The log subsystem, the Shortcut input folder, `Scripts/verify-live.sh`, one test and the docs carry it too. The preferences are named after it as well, in `~/Library/Preferences/com.jamiewhite.signalladder.plist`, so a new identifier would also lose every user's saved preferences: the mute checklist, the on-call state, the Launch at login choice, the snooze and its held counts, and the Setup Guide's progress.

### Use a released Xcode

On 2026-09-30 the only Xcode on this Mac was a beta (27.0, build 27A5228h, installed as `Xcode-beta.app`), and the script warned about it at the start and again at the end. A beta compiler and SDK can change from one seed to the next, and a release should be built by a toolchain a release could be built with. Since 2026-10-13 the Xcode on this Mac is `/Applications/Xcode.app`, version 27.1 (build 27A9275), selected by `xcode-select`. The script goes by two signs of a beta, the name of the Xcode's folder and the name of its app icon, and neither is there, so it does not warn about this one. 27.1 is a released Xcode, and 1.0.0 was built with it: its build record says _Beta Xcode: no_. To build with a particular Xcode, point the script at it:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer SIGNALLADDER_IDENTITY=<hash> Scripts/release.sh
```

The script only warns. Whether a beta build is acceptable for a particular release is yours to decide.

## Before any public release: the go/no-go bar

Agreed with the owner on 2026-09-30. A release is published only when every box is ticked, and a box is ticked only for a check someone actually did.

- [ ] **Real use.** At least 10 real on-call shifts over at least two weeks, with the release candidate running beside your current pager: no missed pages, and every false alert explained.
- [ ] **macOS versions.** Verified on macOS 26 and on macOS 15.4 or later. macOS 14 is verified too, or the release notes say it is untested.
- [ ] **Human checks.** Every human check in the plans is ticked, including sleep on a Mac that can sleep and the Shortcut that pages your phone. The M4 plan's Task 7 lists the ones for escalation, and the 1.0 plan's Task 9 lists the ones for 1.0 (on-call mode, snooze, a burst of matches, Launch at login and the Setup Guide among them). On 2026-10-13 none of the 1.0 plan's is ticked.
- [ ] **The download itself.** The notarised DMG passes Gatekeeper on a clean user account (step 5 below), an upgrade over the previous build keeps the Accessibility permission, and following [Removing everything](../privacy.md#removing-everything) leaves nothing behind.

## Each release

1. **Choose the version and bump it.** Set `CFBundleShortVersionString` in `Resources/Info.plist`. The script stops unless it looks like `1.0.0`, with an optional suffix such as `-rc.1`, because it becomes part of the file names. `CFBundleVersion` is `1.0.0` too: the same text as the release number, and not a count. The script reads it and prints it twice, in the note it makes when it reads the version and on the first line of the build record, and does not parse, compare or check it. Whether it stays equal to the release number, or goes back to being a count that is raised for each release, is the maintainer's to say and has not been decided. Move the `[Unreleased]` entries in [CHANGELOG.md](../../CHANGELOG.md) under the new version and its date. The script names the disk image `SignalLadder-<version>.dmg`, gives its volume the name _SignalLadder <version>_ and warns if the tag `v<version>` already exists, which means that version was released and needs a bump. Check that the README and getting-started page still say what is true about downloads.
2. **Commit on `main`.** The script refuses a tree with uncommitted changes, so that every release is a commit.
3. **Run the tests**: `swift test`.
4. **Run the script**, with a released Xcode:

   ```sh
   SIGNALLADDER_IDENTITY=<hash> Scripts/release.sh
   ```

   Nothing prints while Apple processes a submission, and the script gives up waiting after 40 minutes. There are two waits, one for the app and one for the DMG. The real runs of 2026-09-30 took 5 minutes 12 seconds and 4 minutes 46 seconds in all, with the build and both waits.
5. **Try the DMG on a clean account.** Create a new standard user in System Settings, under Users & Groups, and log in as it. Get the DMG there in a way that marks it as downloaded, such as AirDrop or a browser download. A copy from a USB stick or with `cp` is not marked, and then Gatekeeper is never asked. Then:
   - Open the DMG and drag the app to `/Applications`.
   - Open it. macOS may say it was downloaded from the internet and ask you to confirm, and it must not say it cannot check it for malware or that it is damaged.
   - Run `spctl -a -t exec -vv /Applications/SignalLadder.app`. It should report `source=Notarized Developer ID`.
   - Turn the network off and open the app again, to see that its own stapled ticket is enough.
   - Grant Accessibility, and go through the Setup Guide, which opens by itself on a new account.

   Note which macOS versions you tried it on in the release notes. Then remove that copy, from the test account or by deleting the account with its files. A copy the test account put in `/Applications` is owned by it, so your own account cannot replace it without an administrator's password: that happened with 1.0.0, after the test account was deleted.
6. **Check the go/no-go bar above.** Publish only if every box is ticked.
7. **Tag and publish.** This is yours, and the script does none of it. Tag the commit, push the tag, make the release on GitHub, and attach the DMG and its `.sha256` file. Put the checksum in the notes. Say in the notes which Xcode built it, and give the update steps from [Updating](../getting-started.md#updating), since the app never says a new version exists. Mark a release candidate (`-rc.1`) as a pre-release on GitHub, so that `releases/latest`, which the README and the docs link to and the button beneath the version line in Settings opens, skips it.

8. **Bump the Homebrew cask**, once the tap exists (see below). Set `version` and `sha256` in [Packaging/homebrew/Casks/signalladder.rb](../../Packaging/homebrew/Casks/signalladder.rb) to the release's, the checksum being the one in its `.sha256` file, commit that here, and copy the file to the tap's `Casks/signalladder.rb`. Skip a release candidate: `livecheck` follows `releases/latest`, which skips pre-releases too.

## The Homebrew tap

Asked for in #60, for people who update with Homebrew. It is a tap of the project's own, not the official `homebrew/cask`, which takes apps only once they are well known. Nothing in the app changes: Homebrew downloads the same signed, notarised DMG from the GitHub release, so the app still makes no connection of its own.

- **The cask** is [Packaging/homebrew/Casks/signalladder.rb](../../Packaging/homebrew/Casks/signalladder.rb), kept here so that a release changes it in the same repository. It installs `SignalLadder.app` from `SignalLadder-<version>.dmg`, needs macOS 14 (Sonoma) or later as `LSMinimumSystemVersion` says, quits the running app before an uninstall, and on `brew uninstall --zap` removes the support folder (`~/Library/Application Support/com.jamiewhite.signalladder`, which holds rules.json and the Sounds folder) and the preferences.
- **Checked on 2026-10-18**, on macOS 27.2 with Homebrew 7.0.9, from a local tap: `brew style` and `brew audit --cask --strict --online` passed, and `brew install --cask --appdir=<folder>` installed 1.0.0, which `spctl` accepted as `Notarized Developer ID`, and `brew uninstall --cask` removed it. The test copy left out `uninstall quit:`, so that its uninstall would not quit the copy of the app that was running. The quit itself, `--zap`, and an upgrade from one version to the next have not been tried.
- **To publish it**, which is the maintainer's: create the public repository `JWhite212/homebrew-signalladder`, put the cask at `Casks/signalladder.rb`, and push. Users then run `brew install --cask jwhite212/signalladder/signalladder`, and `brew upgrade --cask` once a later version is in the tap. Add those lines to [Updating](../getting-started.md#updating) and the README's download section only once the tap is public.

## When the script stops

| It says | It means |
| --- | --- |
| `SIGNALLADDER_IDENTITY is not set` | Set it to the hash. If it mentions one D, you spelt the name _SIGNALLADER_. |
| `is 'Apple Development: …'` or another kind | The hash is not a `Developer ID Application` certificate. |
| `is not among the valid code-signing identities` | The hash is wrong, or the certificate has expired or been revoked. |
| `the tree has uncommitted changes` | Commit, or pass `--allow-dirty` for a build that is not a release. |
| `already exists` | A notarised DMG for this version is already in `build/release`. Delete it, or bump the version. |
| `notarytool cannot use the profile` | Create the profile, or set `NOTARY_PROFILE`. See [One-time setup](#credentials-for-notarytool). |
| `notarytool did not answer in 120 s` | A keychain prompt may be waiting behind another window, or Apple's service is down. |
| `signing the app failed on Apple's timestamp service`, or `the DMG` | Apple's timestamp service did not answer. The script tries ten times, ten seconds apart, and only for this failure. |
| `Apple's timestamp service did not answer in 10 tries` | It is unreliable at times. Wait a few minutes and run again. If it was the app that could not be signed, nothing had been submitted. If it was the DMG, Apple had already accepted the app, and the next run will submit it again. |
| `codesign -d timed out` | Only a real release stops here. Run it again. If it keeps timing out, `--skip-notarize` shows whether the rest is sound. |
| `the designated requirement does not name …` | The signature and `Info.plist` disagree about the identifier or team. Users' Accessibility grants would not carry over, so do not ship it. |
| `the executable has architectures …` | It is not arm64 only. Was the script run from a Rosetta terminal? |
| `Apple did not accept the app` (or `the dmg`) | Read the log the script printed. It lists each problem by file. Nothing was stapled or written. |
| `Apple was still processing …` | The wait ended before Apple answered. The message has the `notarytool info` command that asks again. |
| `stapler could not attach the ticket` | Apple accepted it, but the ticket may not have reached the server stapler reads from. Run `xcrun stapler staple` on the file in a few minutes. The script keeps its working folder. |
| `final check(s) failed` | Apple accepted both, but `spctl` or `stapler` disagreed. The stapled DMG is in the kept working folder, and nothing needs submitting again. |

## What the dry run showed

Run on 2026-09-30, on macOS 26.7.1 on Apple silicon, with Xcode 27.0 (27A5228h, a beta) and Apple Swift 6.4, as `Scripts/release.sh --skip-notarize --allow-dirty`. The tree had uncommitted changes, the commit was on a branch other than `main`, and the tag `v0.1.0` already existed. The script warned about all three, and about the beta.

- The first run took 98 seconds, with the release build made from scratch in 13 seconds. The last took 94, with the build already done.
- The executable is arm64 only, and its minimum macOS is 14.0, the same as `Info.plist`.
- The signature verifies. The designated requirement read back as `identifier "com.jamiewhite.signalladder" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = RVVRP4WY6B`, with the Hardened Runtime flag (`flags=0x10000(runtime)`) and a secure timestamp. `codesign -d` did not hang this time.
- **The app is 3.98 MB**, counting the size of every file in it, and the DMG is 2.83 MB. The executable is 2.89 MB and the icon 1.08 MB. The README said about 2 MB and now says about 4 MB.
- The DMG mounted, held an arm64 app whose signature verifies, and had an `Applications` link.
- `spctl -a -t exec -vv` on the app and `spctl -a -t open --context context:primary-signature -vv` on the DMG both said `rejected`, `source=Unnotarized Developer ID`, which is right for a build Apple has not seen.
- **Apple's timestamp service failed most of the time.** Across the runs and probes of that day, 23 of 33 signing attempts ended in `A timestamp was expected but was not found`, each after about 15 seconds, in runs of up to five in a row. A later attempt always got through. The first run signed the app first time and needed three tries for the DMG, and the last needed four for the app. That is why the script tries ten times, and why a run can take several minutes longer than 94 seconds, or give up, when the service is having a bad day.

## The first real run

On 2026-09-30, on macOS 26.7.1 with the Xcode 27 beta, the script ran for real from a clean tree, with the `SignalLadder` notary profile. It was a rehearsal of the pipeline, not a release: nothing was tagged, published or installed.

- Apple accepted the app, and then the DMG. Both tickets were stapled and both validate.
- `spctl` said `accepted` and `source=Notarized Developer ID` for the app and for the DMG.
- Signing the DMG hit Apple's timestamp failure twice before the third try got through, which the retry exists for.
- It took 312 seconds in all. The app is 3.98 MB and the DMG 2.85 MB.

The same day, with the released Xcode 26.6 (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), the first attempt got as far as a notarised, stapled app. Then `stapler validate`, on the copy inside the DMG, did not answer within the 60 seconds it was given, and the script stopped, wrongly saying the ticket was missing. Checks that may ask Apple's servers now get 180 seconds, and up to three tries, and a timeout is reported as one. The next run passed every step:

- Apple accepted the app and the DMG, both tickets validate, and `spctl` said `Notarized Developer ID` for both.
- It took 286 seconds, with two timestamp retries while the app was signed. The app is 3.90 MB and the DMG 2.74 MB.

## A later dry run

On 2026-10-05, on macOS 26.7.1 with Xcode 26.6, `Scripts/release.sh --skip-notarize` was run in a clean scratch clone of the tree, to check that `Scripts/make-app.sh` stamps the build with the commit it was made from. It finished with exit 0: the signature verified, and the designated requirement named `com.jamiewhite.signalladder` and team `RVVRP4WY6B`, with the Hardened Runtime and a secure timestamp. Apple's timestamp service failed once while the app was signed, so the script ran `make-app.sh` again, and it stamped again. Nothing was notarised.

## The 1.0.0 release

On 2026-10-14 the maintainer ran `Scripts/release.sh` on `main` at `a6de31b`, the commit tagged `v1.0.0`, from a clean tree, on macOS 27.2 (26B5101f) with Xcode 27.1 (27A9275) and Apple Swift 6.4. The script did not warn about a beta.

- Apple accepted the app, and then the DMG. It took 81 seconds in all.
- The app is 5.98 MB and the DMG 3.36 MB (3,363,049 bytes), with the SHA-256 `e6f37b8efaa6789a18765352ba47035920655db5995a8fb08755f9674b73d56c`.
- The maintainer pushed the annotated tag `v1.0.0` and made the release as a draft, with the DMG and its `.sha256`. The DMG that GitHub held had the same checksum, `spctl` said `Notarized Developer ID` for it, and its stapled ticket validated.
- On a clean user account on macOS 27.2, the DMG opened, the app was dragged to Applications and opened, and Gatekeeper accepted it as notarised.
- The release was published at 03:09 UTC. Releases on this repository are immutable, so its files cannot be replaced: a fix ships as a new version.

## What has not been tried

- **A rejected submission.** Only the accepted path has met Apple. The code that reads `notarytool`'s answer was also run against a stand-in that returned canned answers: invalid, still in progress, no submission id and unreadable. A real rejection may differ in shape, and the script stops rather than guess when it cannot read one.
- **macOS 14 and 15.** The script has run on macOS 26.7.1 and, for 1.0.0, on macOS 27.2. The app has not been seen on macOS 14 or 15.
- **An offline first launch**, which is the point of stapling the app itself. A clean account was tried for 1.0.0, and whether that first launch was offline is not recorded.

How users receive updates was decided on 2026-10-14, in [Updates after 1.0](plans/2026-10-14-updates-options.md#decided). The free app keeps making no network connection, so there is no updater and nothing checks for a new version. [Updating](../getting-started.md#updating) tells a user how to hear of a release and replace their copy, and 1.1 is to add a button in Settings that opens the latest release in the browser.
