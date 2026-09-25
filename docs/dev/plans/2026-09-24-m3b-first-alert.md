# M3b: The First Alert You Can Hear — Implementation Plan

> **Execution:** each task is implemented with its tests, committed behind a gate (full suite green at the expected count, zero build warnings), and then independently reviewed against the requirements below.

**Goal:** When a notification matches a rule that has an alert, play that rule's sound — level-matched, gain-validated, and recorded honestly in the Inspector — and walk the user through muting the source app so the alert is the app's only voice.

**Architecture:** The rule format gains an optional `alert` and moves to version 2. Loudness maths, alert outcomes, sound-name validation and bundle-ID resolution are pure code in `NotificationCore`. Playback lives in a new `AlertAudio` library target with its own tests, which render the real audio graph offline so no test makes a sound. The app target wires a match to playback and adds the mute walkthrough to the menu.

**Tech Stack:** Swift 5.9, AVFoundation, AudioToolbox, CoreAudio (read-only output state), AppKit, XCTest.

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md` — §1.1 replacement model, §5.8 alert actions, §5.16 audio engine, §6 persistence, §7.2 Inspector, §8.2 mute walkthrough and bundle-ID lookup, §10 testing, §12 milestones, §15 sound set.

**Measured groundwork:** `docs/dev/notes/2026-09-11-m1-findings.md`, sections "M3b groundwork", "Audio (§5.16)" and "Speech (§5.9)"; runnable checks in `docs/dev/spikes/`.

## Global Constraints

- **Notification content is never written to disk, logged, or transmitted** (§2.1). Sounds and rules are user data and may be persisted.
- `NotificationCore` imports no UI or permission-bearing framework and touches no file or network API. Enforced by `PurityTests`.
- Nothing may claim more than was established. A match is not an alert, and an alert played is not an alert heard.
- An alert must never be layered over the source app's own sound without the user being told (§1.1).
- macOS 14.0 floor; event-driven; near-zero idle CPU.

## Rulings

**1. Sound in M3b; speech next.** Speech renders correctly to buffers (measured), but its start-up latency is unmeasured and it needs its own player node at 22.05 kHz mono. A sound is what the on-call need requires. Speech follows as its own milestone once its latency is known.

**2. Alerts are opt-in per rule, and alerts require format version 2.** A rule without `alert` is silent — how every M3a rule already behaves — so upgrading makes nothing noisy by surprise. The silence is always stated where the match is shown, never implied. A version 1 file still loads; a version 1 file _containing_ an alert is rejected, because an M3a build would read it and silently drop every alert in it. Version 2 is what makes an older build refuse the file instead.

**3. `"silent"` is a real alert.** A rule whose alert is silent matches, claims the notification (first match wins), and stays quiet. That is how "Weather should not interrupt me" is expressed, and it must read differently from a rule that simply has no alert yet.

**4. Every sound is level-matched.** Measured peaks run from −15 dBFS (Frog) to −5 dBFS (Hero); speech sits at −1.3. At gain 0 each sound is normalised so its peak lands at −1 dBFS, so "100%" means the same loudness for every sound. The user's gain applies on top, and the peak limiter is the backstop, never the mechanism.

**5. Gain is validated, not trusted.** `AVAudioUnitEQ.globalGain` applied +40 dB when asked, despite its documented +24 dB ceiling. Rules outside −40…+12 dB are rejected with a reason.

**6. A sound that cannot be found is a problem at load, not silence at the incident.** Sound names are checked against the sounds that exist when rules load. A typo such as `"Glas"` is reported by rule name, like any other rule problem. If a file vanishes after load, playback fails loudly and the row says so.

**7. "Played" is not "heard".** The app records what it did: which sound, at what gain. If the default output device was muted, or its volume effectively zero, at that moment, the row and menu say so. Nothing claims the user heard it.

**8. Default output device only.** The spec's per-device engines and device choice arrive with the settings UI.

**9. Custom sounds are files, named without extension.** Anything in `Application Support/com.jamiewhite.signalladder/Sounds/` is available by file name, and overrides a system sound of the same name — the user's file is the user's intent. System sounds (`/System/Library/Sounds`) cover §15's interim.

**10. The mute walkthrough ships with the sound (§12), and says what it cannot know.** Muting cannot be verified: the readable preferences file is a year stale and the live settings are TCC-protected (measured). So the menu lists each app with a sounding rule, deep-links to that app's notification settings when its bundle ID resolves uniquely (§8.2), and keeps a checklist the user confirms. Unconfirmed apps are named, not hidden.

**11. The bundle-ID lookup scans application folders directly.** §8.2 suggests `NSMetadataQuery`; a synchronous scan of `/Applications` and `/System/Applications` is deterministic, needs no Spotlight index, and runs only when the user opens the walkthrough. Running apps are consulted first.

**12. Do Not Disturb is named where it matters.** Banners are not drawn during DND, so nothing can be captured, and M2b's logs showed DND switching on when the screen locked. The walkthrough states this and links to Focus settings. It cannot be verified either.

---

## Task 1: Alerts in the rule format (version 2)

**Files:** `Sources/NotificationCore/Rule.swift`, `Sources/NotificationCore/RuleSetCodec.swift`, `Tests/NotificationCoreTests/RuleSetCodecTests.swift`, `Sources/SignalLadder/RuleStore.swift`

- `AlertAction`: `.sound(name: String, gainDB: Double)` and `.silent`. `Rule.alert: AlertAction?` — nil means no alert set.
- JSON: `"alert": {"sound": "Glass", "gainDB": 6}` (`gainDB` optional, default 0) or `"alert": "silent"`. Anything else is an error that says what was expected.
- `currentVersion` is 2. Version 1 and 2 load. An alert in a version 1 file is a problem naming the rule and the fix.
- Validation: gain within −40…+12 dB; sound name non-empty; a sound name not among the available sounds (compared ignoring case) is a problem naming the rule by its real number, the missing sound, and what is available.
- `RuleStoreStatus.load(_:availableSounds:)` — no default, so the app cannot skip it; it passes `SoundLibrary.availableNames`. _(Corrected: first drafted as an injected `soundExists` predicate.)_
- The starter file becomes version 2 and still activates nothing.
- **Moved here from Task 3 during implementation:** `SoundLibrary` (in the new `AlertAudio` target), because validating sound names at load needs the list of sounds that exist, and a throwaway stand-in would only have been replaced. `RuleStoreStatus.load` takes `availableSounds` with no default, so the app cannot forget to check.
- **Added during implementation:** unknown keys are rejected at every level (rule, alert, condition). With alerts optional, an ignored key is the most dangerous typo there is — `"alrt"` would decode into a quietly silent rule, `"gain"` into a quietly quieter one, `"enabeld": false` into a rule that is quietly on.

## Task 2: Loudness

**Files:** `Sources/NotificationCore/Loudness.swift`, `Tests/NotificationCoreTests/LoudnessTests.swift`

- Pure: from a measured peak and the rule's gain, the EQ gain that puts the sound's peak at −1 dBFS + user gain.
- A file below −60 dBFS, or with a peak that is not a real number, cannot be played: `appliedGainDB` returns nil and the player must report a failure — "Played" for a file nobody could hear would be a false report. _(Refined during implementation: the draft said such a file would play unadjusted.)_
- Normalisation boosts at most +24 dB, so a very quiet recording stays quieter rather than turning its own hiss into the alert.

## Task 3: `AlertAudio` — playback that is tested without making a sound

**Files:** `Package.swift`, `Sources/AlertAudio/…`, `Tests/AlertAudioTests/…`

- `SoundLibrary` — _moved to Task 1; see there._
- **Decided during implementation:** every sound is converted to one internal format (48 kHz stereo) when first loaded, so the graph is wired once and never re-plumbed mid-alert, and its peak is measured on the converted audio — what actually plays. The engine runs only while a sound plays: a running engine holds the output device awake, which would break the near-zero idle cost.
- The graph — player → `AVAudioUnitEQ` → Apple PeakLimiter → main mixer — is built by one function used both live and in tests (offline manual rendering).
- `AlertPlayer.play(name:gainDB:)` loads (and caches) the file and its measured peak, applies the loudness gain, interrupts any sound still playing (§5.15: serialised, never mixed), and reports what it did, including the default output device's mute and volume state read through CoreAudio.
- Tests, all offline: every system sound at gain 0 peaks within 0.5 dB of −1 dBFS; at +12 dB no sample exceeds full scale; −40 dB lands ~40 dB lower; an unknown or unreadable file throws rather than playing nothing.

## Task 4: A match plays its alert, and the row says what happened

**Files:** `CapturePipeline.swift`, `InspectorEntry.swift`, `CaptureRingBuffer.swift`, app wiring, tests

- The pipeline plays the alert itself, through an injected `playSound` with no default, the same way the self-test check is injected. _(Corrected: first drafted as the pipeline returning the match and row for the app to act on, which would have left every alert decision in the untested app target.)_ No alert, silent, play, and the failure bookkeeping are all decided in the core; the app supplies only the speaker.
- `AlertOutcome`: played (sound, the rule's gain, whether the output reported itself silent), silent by rule, no alert set, failed (reason). Recorded on the row; never written by a preview; never set for a repeat or the app's own traffic (both already excluded upstream). _(Refined: one "output silent" flag rather than the raw mute and volume figures. Whether the device reported silence is what the app can know; whether 30% volume was loud enough is not.)_
- Row and menu wording comes from pure, tested functions: _Played Glass (+6 dB)_; _Played Glass — but the Mac's sound output was muted or at zero volume_; _Silent by rule_; _Silent — this rule has no alert_; _Could not play: …_.
- **Added during implementation:** a sound that could not play turns the menu-bar glyph to its alarm state and keeps its own menu line until a later sound plays. A quieter match afterwards does not hide it, and reloading rules does not clear it: a file can exist, pass the load-time check, and still not decode.
- **Added during implementation:** when an enabled rule has a sound and the output is muted or at zero volume right now, the menu says so. A menu line rather than the glyph: muting may be deliberate, a failed sound never is.

## Task 5: The mute walkthrough

**Files:** `Sources/NotificationCore/BundleResolver.swift` (pure), app menu, `UserDefaults` checklist, tests

- Resolve an app name to a bundle ID: unique match → deep link `x-apple.systempreferences:com.apple.preference.notifications?id=<bundleID>`; none or ambiguous → the Notifications pane with the name shown (§8.2). Matching ignores case and accents.
- Apps needing muting: those named by `app equals …` in a rule with a sound, plus any app that has triggered a sounding rule this session.
- Per app: open its notification settings; confirm "I've muted it" (persisted). Unconfirmed apps are listed as such.
- A Do Not Disturb entry explains the capture gap and opens Focus settings.
- **Decided during implementation:** the walkthrough is one menu item, titled with the apps still unconfirmed (_⚠︎ Not confirmed muted: Microsoft Teams_) or, once all are done, _Confirmed muted: …_. Its submenu holds, per app, _Open Notification Settings for …_ and _I've Turned Its Sound Off_, then the Focus entry. It appears only when some app needs muting. On a missing or ambiguous match, an alert naming the app is shown before the Notifications pane opens, so the name is on screen (§8.2).
- **Measured:** on the development Mac, the folder scan found 132 apps in 154 ms cold and 24 ms warm, and runs only on that click. _Microsoft Teams_ resolves uniquely to `com.microsoft.teams2`, _Weather_ to `com.apple.weather`, _Calendar_ to `com.apple.iCal`. macOS 26 still registers `com.apple.preference.notifications` as the Notifications pane's legacy identifier, and Focus is `com.apple.Focus-Settings.extension` (both read from the settings extensions' Info.plists). Whether `?id=` lands on the app itself can only be seen by opening it: a human check.
- Two running apps sharing a name are ambiguous without reading the disk; the user chooses rather than being sent to a guess.

## Task 6: Docs, harness and live verification

- `docs/rules-format.md`: the `alert` key, gain, sound names, custom sounds, version 2.
- `Scripts/verify-live.sh`: the rules line still reads healthy after the upgrade; the mute section is present when a sounding rule exists.
- **Decided during implementation:** the harness fails on a sound that could not play and on a muted output while a rule has a sound. It requires the walkthrough whenever an enabled sounding rule names an app, counted from the rules file (configuration, never a notification). It never prints the walkthrough's app names, because some come from captured banners.
- **Found during implementation, and fixed:**
  - Formatting an out-of-range gain for its problem message converted it to `Int`, so a hand-written `"gainDB": 1e300` trapped the app at load instead of being reported.
  - A sound file of any length was decoded whole into memory — about 1.4 GB for an hour of audio — and one over about 24 hours trapped. Sounds are now refused before decoding when longer than 30 seconds.
- **Found in the independent review, and settled:**
  - _Privacy._ The mute checklist stored app names, and an app name can come from a captured banner (`appNameGuess` is parsed from the banner's own text), so a banner that parsed oddly could put message text on disk. It now stores a SHA-256 of each folded name, which answers "did the user confirm this app?" and nothing else.
  - _A change of output device._ Nothing observed the engine's configuration-change notification. It now resets to the between-alerts state — engine and player stopped, pending completions disowned — and the next alert starts cleanly. The player is also told to play unconditionally rather than trusting an `isPlaying` a change may have left stale.
  - _Decoding on the capture path._ The first alert for each sound decoded its file inside the Accessibility callback. Sounds are now prepared when the rules load, which also turns a file that cannot play — unreadable, silent, over 30 seconds — into a rule problem at load (ruling 6, extended).
  - _A rule with two faults_ reported only the first, so the second surfaced one edit later. All of a rule's reasons, including its sound's, now arrive in one problem.
  - _Isolation._ `CapturePipeline` said it was main-actor only; it is now `@MainActor`, so the compiler enforces it.
  - _Not changed:_ duplicate JSON keys (the last silently wins) cannot be detected through `JSONDecoder`; the guide says so. The volume read was questioned and measured: the call used returns the same value as `AudioHardwareService` on the development Mac.
- **Human checks** (they make sound, open System Settings, or drive the running app — none of which this session does):
  - [x] `Scripts/verify-live.sh` passes against this branch's build (`build/SignalLadder.app`, signed and ready). _12/12 on 2026-09-25, built from `main` at 2e1e77e._
  - [ ] A matching notification plays the rule's sound, at a sensible level, once. _Plays once: one "Played Glass" per notification (2026-09-25). The level still needs a listener._
  - [ ] Two different sounds at gain 0 sound roughly equally loud. _Needs a listener._
  - [x] With output muted, the row says the output was muted, and the menu warns before any match. _The warning appeared before the match; the match read "Played Tink — but the Mac's sound output was muted or at zero volume"._
  - [x] Each deep link opens the right pane: Microsoft Teams' notification settings (does `?id=` select the app, or only open the list?); Focus settings. _`?id=` selects the app: System Settings opened on Microsoft Teams' own page, with its Play sound for notification switch. Focus opened Focus._
  - [x] _I've Turned Its Sound Off_ is still ticked after a relaunch.
  - [x] A rule naming a missing sound is reported at load, by name. _`Rule 4 ("M3 check — missing sound"): sound "Glas" was not found — available: …`_

## Not in this plan

Speech (next milestone). Escalation tiers 2–4, the alert panel, repeat, acknowledge (M4). Output-device choice and sound import UI (settings). The rule editor (M3c).
