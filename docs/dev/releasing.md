# Releasing SignalLadder

How a commit becomes a download: built, signed, notarised by Apple and stapled, on the maintainer's Mac. This page is for the maintainer. Nobody else needs it to build or contribute.

**Where this stands (2026-09-30).** `Scripts/release.sh` is written and has had a dry run (`--skip-notarize`), described under [What the dry run showed](#what-the-dry-run-showed). **Nothing has ever been submitted to Apple's notary service**, so the notarising and stapling steps have not run against the real service. The first real release is their first real test, and it is worth watching. No release has been made: 0.1.0 is source only.

- [The short version](#the-short-version)
- [What the script does](#what-the-script-does)
- [One-time setup](#one-time-setup)
- [Each release](#each-release)
- [When the script stops](#when-the-script-stops)
- [What the dry run showed](#what-the-dry-run-showed)
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

Check that your membership is current and that every agreement is accepted, at developer.apple.com under Account, and in App Store Connect under Business, which lists the agreements. Until both are true, Apple can refuse notarisation. The maintainer believed both were in order on 2026-09-30, but a submission is the only real test of it.

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

An empty list is right before the first submission. The script runs this check itself before it builds. If macOS asks whether `notarytool` may use the keychain item, that is expected the first time. A prompt hidden behind another window makes the call time out after two minutes, and the script says so.

### Back up the signing key

The certificate is no use without its private key, and the key lives only in this Mac's keychain. In Keychain Access, under My Certificates, select the `Developer ID Application` certificate, choose File, then Export Items, and save a `.p12` with a strong password. Keep the file and the password in separate places, both away from this Mac.

The designated requirement names the team and not the certificate, so a replacement Developer ID certificate from the same team should satisfy it and leave users' Accessibility grants alone. That has not been tried.

### The bundle identifier

The identifier and the team make up the designated requirement, so both are baked into every user's Accessibility grant. Changing either after users have installed the app makes every one of them grant access again. Settle the identifier before the first release.

The scripts read it from `Resources/Info.plist`, and `make-app.sh` and `release.sh` need nothing else changed. The code and docs also write it out, so a change is not one line. `grep -rl com.jamiewhite .` finds them. The ones that matter most are `Sources/SignalLadder/RuleStore.swift` and `Sources/AlertAudio/SoundLibrary.swift`, which put the rules and sounds in a folder under Application Support named after it, so users who had the old identifier would lose sight of their rules. The log subsystem, the Shortcut input folder, `Scripts/verify-live.sh`, one test and the docs carry it too.

### Use a released Xcode

The maintainer's Xcode is a beta (27.0, build 27A5228h, installed as `Xcode-beta.app`), and the script warns about it at the start and again at the end. A beta compiler and SDK can change from one seed to the next, and a release should be built by a toolchain a release could be built with. Install the released Xcode, and point the script at it:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer SIGNALLADDER_IDENTITY=<hash> Scripts/release.sh
```

The script only warns. Whether a beta build is acceptable for a particular release is yours to decide.

## Before any public release: the go/no-go bar

Agreed with the owner on 2026-09-30. A release is published only when every box is ticked, and a box is ticked only for a check someone actually did.

- [ ] **Real use.** At least 10 real on-call shifts over at least two weeks, with the release candidate running beside your current pager: no missed pages, and every false alert explained.
- [ ] **macOS versions.** Verified on macOS 26 and on macOS 15.4 or later. macOS 14 is verified too, or the release notes say it is untested.
- [ ] **Human checks.** Every human check in the plans is ticked, including sleep on a Mac that can sleep and the Shortcut that pages your phone. The M4 plan's Task 7 lists them.
- [ ] **The download itself.** The notarised DMG passes Gatekeeper on a clean user account (step 5 below), an upgrade over the previous build keeps the Accessibility permission, and following [Removing everything](../privacy.md#removing-everything) leaves nothing behind.

## Each release

1. **Choose the version and bump it.** Set `CFBundleShortVersionString` in `Resources/Info.plist`, and raise `CFBundleVersion`. Move the `[Unreleased]` entries in [CHANGELOG.md](../../CHANGELOG.md) under the new version and its date. Check that the README and getting-started page still say what is true about downloads.
2. **Commit on `main`.** The script refuses a tree with uncommitted changes, so that every release is a commit.
3. **Run the tests**: `swift test`.
4. **Run the script**, with a released Xcode:

   ```sh
   SIGNALLADDER_IDENTITY=<hash> Scripts/release.sh
   ```

   Nothing prints while Apple processes a submission, and the script gives up waiting after 40 minutes. There are two waits, one for the app and one for the DMG. How long each takes has not been measured, because none has been made.
5. **Try the DMG on a clean account.** Create a new standard user in System Settings, under Users & Groups, and log in as it. Get the DMG there in a way that marks it as downloaded, such as AirDrop or a browser download. A copy from a USB stick or with `cp` is not marked, and then Gatekeeper is never asked. Then:
   - Open the DMG and drag the app to `/Applications`.
   - Open it. macOS may say it was downloaded from the internet and ask you to confirm, and it must not say it cannot check it for malware or that it is damaged.
   - Run `spctl -a -t exec -vv /Applications/SignalLadder.app`. It should report `source=Notarized Developer ID`.
   - Turn the network off and open the app again, to see that its own stapled ticket is enough.
   - Grant Accessibility, and go through a first run.

   Note which macOS versions you tried it on in the release notes.
6. **Check the go/no-go bar above.** Publish only if every box is ticked.
7. **Tag and publish.** This is yours, and the script does none of it. Tag the commit, push the tag, make the release on GitHub, and attach the DMG and its `.sha256` file. Put the checksum in the notes. Say in the notes which Xcode built it.

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

## What has not been tried

- **The notary service.** `notarytool submit`, `info` and `log`, `stapler staple`, and the two `spctl` results that say `Notarized Developer ID`, have never run against Apple. The code that reads `notarytool`'s answer was run against a stand-in that returned canned answers: accepted, invalid, still in progress, no submission id and unreadable. The whole flow without `--skip-notarize` was run with the stand-in in place of Apple's tools, to check the order of the steps and what is written where. A real answer may differ in shape, and the script stops rather than guess when it cannot read one.
- **A released Xcode.** The only Xcode on this Mac is a beta.
- **macOS 14 and 15.** Every check so far was on macOS 26.7.
- **A clean account, and an offline first launch**, which is the point of stapling the app itself.

Not settled, and not decided here: how users will receive updates (there is no updater, and nothing checks for a new version), and what has to be true before a build is good enough to publish.
