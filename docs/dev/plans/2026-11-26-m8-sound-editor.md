# M8: the sound editor, phase 1 (1.4)

> **Status:** plan, written on 2026-11-26 from `main` at dd66092 (1.3.0, not yet published). Nothing in it is built, but for one part of Task 1: what Ruling 17 asks was found to be a fault in 1.3 as it stood and was built the same day, for 1.3 (#264, `main` at fe27111).

**Mode:** standalone. The inputs are the owner's description of the feature on 2026-11-26, a read of the audio code that day, and three designs made independently from it and compared.

**Inputs taken as given:** work type is a new feature with a new window. Risk tolerance is conservative: this app pages people, and the editor writes into the one folder its alert sounds are read from. It ships as 1.4, after 1.3 is published.

**Goal:** from a rule's sound, open a window that shows the sound as a waveform and lets you trim it, cut and repeat parts of it, fade it and change the level of a part, hear the result as the rule would play it, be told plainly when it would make a poor alert, and save it as a sound of your own, without ever putting a sound that plays today at risk.

## What it is, and what it is not

An editor for alert sounds of at most 30 seconds. It is not a general audio editor. Phase 1 edits one sound. Making a sound from nothing, speech, adding a second sound, changing speed, matching perceived loudness and sound packs are later phases, listed under [Not in this plan](#not-in-this-plan).

| You can       | How                                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------------- |
| See the sound | A waveform, with a playhead, zoom and a selection made by dragging or from the keyboard                     |
| Hear it       | Space plays and stops. A selection can be looped. It plays at the rule's gain, level-matched as an alert is |
| Shorten it    | **Trim** keeps the selection. **Delete** removes it                                                         |
| Rearrange it  | Cut, copy, paste and duplicate a selection                                                                  |
| Shape it      | **Fade In**, **Fade Out**, and a gain in decibels on a selection, against the rest of the sound             |
| Lengthen it   | **Repeat** plays the selection a number of times with a gap between                                         |
| Go back       | Undo, redo, and **Reset to Original**                                                                       |
| Be warned     | Seven checks, most with one press that fixes them                                                           |
| Keep it       | **Save as New** by default. Saving over a sound that rules use asks first                                   |

## Owner decisions

Assumed from the owner's answer "plan phase 1" on 2026-11-26. Each is the default this plan was written to, and each can be changed before Task 2 starts at no cost.

- **O1. It ships as 1.4, after 1.3 is published.** _Otherwise:_ hold 1.3 for it, which delays three finished features by the whole of this plan.
- **O2. Gain on a selection is in phase 1, and the pulse designer is phase 2.** _Otherwise:_ swap them, which adds a tone generator to this plan and takes Task 4's gain out.
- **O3. No microphone recording, in any phase planned here.** It would add a permission prompt and a Hardened Runtime entitlement to an app that already reads every notification. A recording made elsewhere is added with **Add Sound…**.
- **O4. The checks' thresholds are provisional.** The figures in Ruling 12 come from summaries of standards and papers that were not read in full. Task 4 ships them as named constants in one place, and they are set by ear in the human checks before release.
- **O5. A recipe is kept in a hidden folder inside your sounds folder.** _Otherwise:_ a visible file beside each sound, which you would see in the Finder and could move with it.

## Rulings

**1. An edit is a recipe, and the alert plays a plain file.** The editor saves two things: an ordinary audio file, which is all a rule or `SoundLibrary` ever sees, and a recipe that says how it was made from its source. A recipe that is lost, unreadable or from a newer version changes nothing about what plays. The sound is then a plain sound, and the editor opens it as a new source.

**2. A recipe is a list of pieces of the source, not a log of operations.** `SoundRecipe.segments` is an ordered list. A piece is a stretch of the source, with a gain and its fades, or a stretch of silence. Every edit is a pure function from one recipe to the next, so nothing stored can point at something an earlier edit removed. Undo is a stack of recipes, which are small values and hold no audio. **Reset to Original** is the list of one piece, the whole source.

**3. Positions are whole frames at 48 kHz, on the source's own timeline.** The source is decoded once to the player's format, 48 kHz stereo float (`AlertPlayer.swift:110`, `convert` at `:467`), and every position in a recipe counts frames of that. No time in a recipe is a fraction of a second, so two reads of one recipe cannot differ by rounding.

**4. A cut is moved to a quiet point when it is made, and smoothed when it is rendered.** When an edit is made, the window's model moves each edge of the selection to the nearest zero crossing within 5 ms, reading the samples of the result as last rendered, and only then calls the edit, which stays a pure function of the recipe and the frames it is given. A crossing is one of the channels added together, so both move as one. Where there is none within 5 ms the edge goes to the quietest frame in that window. The recipe stores the frame the edge moved to. When the recipe is rendered, a join between two pieces that were not neighbours in the source gets a fade down and a fade up of 5 ms each, or half the piece if that is shorter. It is a dip and not an overlap, so the length of the result is exactly the sum of its pieces and a position in the window maps to one frame. Neighbouring pieces with the same gain are merged, so an edit that is undone by hand leaves no seam.

**5. The pure work is in `NotificationCore`, and files and decoding are in `AlertAudio`.** Recipes, edits, rendering, the checks and every word are arithmetic on arrays of numbers and values, so they sit in the core, which may touch neither files nor audio hardware (`Package.swift:13`) and is held to that by `PurityTests`. The samples cross between the two as `SampleBuffer`, an array of channels, which is `Sendable`. No `AVAudioPCMBuffer` leaves the function that made it.

**6. Rendering never runs on the main actor.** A render is a loop over at most 30 seconds of samples, started in a detached task over values only. Each request carries a number, and a result that is not the newest is dropped. The main actor swaps in the finished peaks and findings and nothing else. The app builds with warnings as errors, so this is checked by the compiler and not by care.

**7. A preview can never cut off an alert, and is never taken for one.** The editor plays through a new `AlertPlayer.testBuffer`, which is refused while an alert is playing exactly as `testSound` is (`AlertPlayer.swift:319`), and which a starting alert stops as it stops any test. It is played at the gain the whole result would be given as an alert, worked out once from the whole result's peak and handed to it, so a quiet part played on its own is heard as quiet as it will be and is not raised to full level; a part with nothing in it plays as silence. It records nothing, in the Inspector or anywhere, and never calls `alertSetOff`, so `PlayerOwnership` (`Sources/NotificationCore/PlayerOwnership.swift:33`) does not know of it.

**8. Nothing gets a sound's name until it has passed the checks an added sound passes.** The rendered file is written under a hidden name, decoded and measured by `SoundImport.check` (`SoundImport.swift:193`), and only then renamed. A sound it replaces is set aside first and put back if any step after that fails. This is `SoundImport`'s own sequence (`:135-165`), taken out into one `SoundInstall` that adding and saving both call, so there is one implementation of the step that can lose a sound.

**9. Save as New is the default, and the rule then names the new sound.** The suggested name is the source's with a number. Saving over a sound is offered only for a sound of your own, and asks first when any rule uses it, saying how many. A macOS sound cannot be saved over: its edit is always a copy under a new name, as `SoundImport` already refuses a macOS name (`:122`). After **Save as New**, the alert the editor was opened from names the new sound, as a change to the draft, as adding a sound does (`AlertEditorView.swift:224`).

**10. A recipe is trusted only for the file it made.** It records the length and a digest of what it rendered. Opened later, a file that does not match was replaced outside the editor, and is treated as a plain sound. The recipe's own copy of its source is what it renders from, so a source that is later changed or deleted cannot break it.

**11. The result may run over 30 seconds while you edit, and cannot be saved until it does not.** An edit that would take the result past 120 seconds is refused when it is made, which bounds memory. Between 30 and 120 seconds, **Save** is off and the length check says why, with one press that keeps the first 30 seconds. Nothing is ever shortened without being asked.

**12. The checks advise, and two of them block.** Each is one sentence and, where there is a fix, one press that makes it, and the fix is an edit like any other and can be undone.

| Check                | When, provisionally (O4)                                                                                                       | The press                                  |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------ |
| Starts too abruptly  | It reaches half its peak in under 10 ms                                                                                        | Fade in the first 30 ms                    |
| Too short            | Under 0.5 seconds                                                                                                              | Repeat it three times, 0.3 seconds apart   |
| Silence at the start | More than 0.1 seconds below the silence floor                                                                                  | Trim it                                    |
| Silence at the end   | More than 0.25 seconds below the silence floor                                                                                 | Trim it                                    |
| Clipping             | A run of samples at full scale. Advice only: the damage is in the source                                                       | None. It says to start from a cleaner copy |
| Too long             | Over 30 seconds. This one blocks saving                                                                                        | Keep the first 30 seconds                  |
| Nothing to hear      | The whole result is below the silence floor. This one blocks saving too, as a sound that is silent is refused when it is added | Undo                                       |

The silence floor is the player's own, `Loudness.silenceFloorDBFS`. Only the last two are drawn as a fault is, with `.faultOutlined()`, because only they stop something. The others are advice, and are not drawn as faults: `FaultOutline` is for what stops an alert reaching you.

**13. The waveform works without a mouse and without colour.** It is one focusable element. Space plays and stops, the arrows move the playhead, Shift extends the selection, and Home and End go to the ends. To VoiceOver it is one adjustable element that says the position and the selection in seconds, with actions to select all, play and clear. The selection is drawn with handles and bracket lines as well as a tint, and line widths come from `DisplaySettings`, as `FaultOutline`'s do.

**14. The saved file is 48 kHz stereo float WAV.** It is what the player would convert to anyway, so saving loses nothing beyond the first decode, and a level above full scale is kept as it is and not clipped. At 30 seconds it is about 11.5 MB.

**15. The privacy page lists every new file before the code that writes it merges.** `docs/privacy.md` says what the app writes and where, and says it writes nothing else. Task 5 changes that page in the same pull request that adds the writer.

**16. How loud a sound plays is the player's decision, and the editor does not pretend otherwise.** Every sound is brought to the same peak when it plays (`Loudness.appliedGainDB`), and a rule's own gain is added to that. So a gain on a selection changes that part against the rest of the sound, and a gain on the whole sound changes nothing anyone hears. The window says so beside the gain, **Gain** is offered only for a selection that is not the whole, and no check offers to lower the level of everything.

**17. A set-aside sound is never deleted while its name is free.** _As built, for 1.3 (#264):_ a sound being replaced is set aside under a hidden name that holds the attempt, the type of the sound that is to replace it and its own file name, `.replacing-<attempt>-<type>-<file name>`, and the staged copy is `.adding-<attempt>.<type>` of the same attempt. `SoundImport.recoverSetAsideSounds`, which `RuleStore.reload` calls before it lists the sounds and each add calls first, finishes a replace that was stopped. With the staged copy still there the rename never happened, and the old sounds go back. With it gone and a file of the name and the new type there, the new sound arrived, and the old ones are deleted. Otherwise an old sound goes back if its own file name is free, and is left hidden if it is not. Nothing is deleted on a guess, and nothing is judged by its age, as this ruling first proposed: moving a file keeps its date, so age said nothing. A name too long for the hidden name is refused before anything is moved. Saving from the editor sets a sound and its recipe aside by the same rule.

**18. An edit that would leave nothing is refused.** Deleting the whole result, or trimming to an empty selection, does nothing and says why. A source that is already over 120 seconds cannot be opened: no sound of that length can have been added, and one put in the folder by hand is refused with its length.

## Types

**`NotificationCore`** (pure):

| Type               | What it is                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `SampleBuffer`     | Channels of samples, `[[Float]]`, at 48 kHz. `Sendable`                                                                         |
| `SoundRecipe`      | `version`, `source` (the stored copy's name, its length in frames, a digest), `segments`, the rendered file's length and digest |
| `SoundSegment`     | `.clip(start, end, gainDB, fades)` or `.silence(frames)`                                                                        |
| `SoundFade`        | In or out, its length, and how far into it this piece begins, so a fade across a later cut stays one fade                       |
| `SoundEdit`        | Each edit as a pure function: trim, delete, cut, paste, duplicate, fade in, fade out, gain, repeat                              |
| `SoundEditHistory` | Past, present and future recipes: `commit`, `undo`, `redo`, `reset`                                                             |
| `SoundRecipeCodec` | Reads and writes a recipe as JSON, versioned, refusing unknown keys, as `RuleSetCodec` does for rules                           |
| `ZeroCrossing`     | The nearest quiet point to a frame, within a window                                                                             |
| `SoundRender`      | `render(source:recipe:) -> SampleBuffer`                                                                                        |
| `WaveformPeaks`    | Minimum and maximum for each column of the drawing                                                                              |
| `SoundChecks`      | `findings(in:) -> [SoundFinding]`, each with its `SoundFix`                                                                     |
| `SoundSaveNaming`  | The suggested new name, and whether saving over is allowed                                                                      |
| `SoundUse`         | Which rules name a sound                                                                                                        |
| `SoundEditorText`  | Every word the window shows or says                                                                                             |

**`AlertAudio`** (files and decoding):

| Type                                                       | What it is                                                                                        |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `SoundInstall`                                             | Stage, check, set aside, rename, put back. Taken out of `SoundImport`, which then calls it        |
| `SoundDecoding`                                            | Decode a file to a `SampleBuffer`, the conversion the player already does                         |
| `SoundEditStore`                                           | `open(name)`: the source, and its recipe if it has a trusted one. `save(recipe, as:, replacing:)` |
| `AlertPlayer.testBuffer(_:ruleGainDB:loop:)`, `stopTest()` | The preview                                                                                       |

**`SignalLadder`** (thin): `SoundEditorWindowController`, `SoundEditorModel`, `SoundEditorView`, `WaveformView`.

## On disk

All inside `~/Library/Application Support/com.jamiewhite.signalladder/Sounds/`:

| Path                                 | What                                                    |
| ------------------------------------ | ------------------------------------------------------- |
| `Name.wav`                           | The rendered sound. The only thing a rule can name      |
| `.edits/Name.edit/recipe.json`       | Its recipe                                              |
| `.edits/Name.edit/source.ext`        | A copy of what it was made from, a macOS sound included |
| `.rendering-….wav`, `.recipe-….json` | Staged while saving, removed at once whatever happens   |

`SoundLibrary` skips hidden files and does not look inside folders (`SoundLibrary.swift:72`), so none of this but `Name.wav` is ever listed. Staged files a crash left are removed the next time a sound is added or saved, as `.adding-` files are now (`SoundImport.swift:171`), and a sound that was set aside and never put back is put back, by Ruling 17, as 1.3 already does. A sidecar in `.edits/` whose sound no longer has a file of its name, because it was deleted or renamed in the Finder, is removed at the same time once it is old.

## The plan

Each task is one pull request against `main`, green on both toolchains, with every new test seen to fail once. Nothing new can be reached until Task 9. Tasks 1 and 5 are the exception to "nothing changes": they move code every user already runs, adding a sound and decoding one to play it, so their acceptance includes every existing test of that code unchanged and the default live check on a build of the branch.

### Task 1: one place that installs a sound

**Files:** `Sources/AlertAudio/SoundInstall.swift` (new), `SoundImport.swift`, `Tests/AlertAudioTests/`.

- Take the stage, check, set aside, rename and put back sequence out of `SoundImport.copyIn` into `SoundInstall`, taking the staged file, the name and whether it may replace.
- `SoundImport` keeps its `move` seam, `staleAfter` and `removeStaleStagedCopies`, which its tests use, and passes them through.
- The set-aside name and `recoverSetAsideSounds` are 1.3's, built in #264 (Ruling 17), and move into `SoundInstall` unchanged, with their tests.
- The stale-file sweep is widened to the staged names saving adds, and to no set-aside name: those are for the recovery alone.
- _Acceptance:_ every existing `SoundImportTests` case passes unchanged, the fifteen of #264 among them, and the default `Scripts/verify-live.sh` passes on a build of the branch. No new behaviour, so no new test but one that `SoundImport` installs through `SoundInstall`.

### Task 2: recipes and edits

**Files:** `Sources/NotificationCore/SoundRecipe.swift`, `SoundEdit.swift`, `SoundEditHistory.swift`, `SoundRecipeCodec.swift` (all new), tests.

- The types of Rulings 2 and 3, with the invariants held by construction: no piece is empty, every piece lies inside the source, neighbours with the same gain are one piece.
- Every edit of the table at the top, as a pure function, and refused past 120 seconds (Ruling 11).
- The codec: versioned, unknown keys refused, a newer version reported as needing a newer SignalLadder.
- _Acceptance:_ tests show that trim then undo gives back the recipe, that delete across a join keeps the arithmetic of lengths, that a fade across two pieces equals one fade, that gain and fade give the same result in either order, that repeat's length is the count times the selection plus the gaps, and that every edit round-trips through the codec.

### Task 3: rendering and the drawing's numbers

**Files:** `Sources/NotificationCore/SoundRender.swift`, `ZeroCrossing.swift`, `WaveformPeaks.swift` (new), tests.

- Render per Ruling 4. One pass, one allocation of the result.
- _Acceptance:_ on a sine wave with a delete, the step between samples at the join is below a set bound; the result's length equals the recipe's; a fade begins or ends at zero; a snap lands on a change of sign and never further than its window; peaks of a known signal are what they should be.

### Task 4: the checks and the words

**Files:** `Sources/NotificationCore/SoundChecks.swift`, `SoundSaveNaming.swift`, `SoundUse.swift`, `SoundEditorText.swift` (new), `WindowTitles.swift`, tests.

- The seven checks of Ruling 12, their thresholds as named constants in one place, and the fix for each as a `SoundEdit`.
- Names: the next free "Name 2", never a macOS sound's name, never one in use unless saving over was asked for.
- _Acceptance:_ one test for each check on a made signal, firing just past its threshold and not just short of it; each fix clears its own finding; a suggested name is never a macOS sound's.

### Task 5: opening and saving

**Files:** `Sources/AlertAudio/SoundDecoding.swift`, `SoundEditStore.swift` (new), `AlertPlayer.swift`, `docs/privacy.md`, tests.

- `SoundDecoding` is the decode and convert the player does, moved so both use it. The player's behaviour does not change.
- `open`: the source and, when its recipe matches its file (Ruling 10), the recipe.
- `save`: copy the source into the sidecar on a first save, render, write the WAV and the recipe under hidden names, install the WAV through `SoundInstall`, then rename the recipe into the sidecar, with any recipe it replaces set aside and put back with its sound. If the recipe's rename fails after the sound's has succeeded, the sound is kept and is a plain sound, which Rulings 1 and 10 make safe, and the window says its edits cannot be reopened.
- The sweep of orphaned sidecars described under [On disk](#on-disk).
- `SoundDecoding` gives back the same failures the player gives now, in the same words, and the player calls it on the main actor as before; only the editor calls it elsewhere.
- The privacy page gains the rows of [On disk](#on-disk) (Ruling 15).
- _Acceptance:_ every existing `AlertPlayerTests` case passes unchanged, and the default `Scripts/verify-live.sh` passes on a build of the branch. With real folders: a failed rename puts the old sound and its recipe back; a sidecar whose sound is gone is removed once old and not before, and one whose sound is there is never removed; a render that is silent or over 30 seconds never gets a name; a file replaced outside the editor opens as a plain sound; a macOS sound saves as a copy; the library lists only the WAV; nothing hidden is left after a save or a failure.

### Task 6: the preview

**Files:** `Sources/AlertAudio/AlertPlayer.swift`, tests.

- `testBuffer(_:gainDB:from:loop:)` and `stopTest()`, on the path `testSound` takes. It is given its gain (Ruling 7), a frame to start from, and optionally a range to go round, and it says where it has got to, for the playhead.
- `stopTest()` stops a preview and nothing else: called while an alert plays, it does nothing.
- _Acceptance:_ rendered offline, as the player's tests are: a preview is refused while an alert plays; an alert starting stops a preview and its loop; `stopTest()` during an alert leaves the alert whole; a quiet selection of a loud sound comes out as quiet as it is in the whole; a selection with nothing in it plays silence and is not an error; the engine is stopped when a preview ends; it changes nothing an alert reads.

### Task 7: the window, read-only

**Files:** `Sources/SignalLadder/SoundEditorWindowController.swift`, `SoundEditorModel.swift`, `SoundEditorView.swift`, `WaveformView.swift` (new), `ViewLiteralsTests.swift`, `WindowTitlesTests.swift`, a wiring test.

- The window, built and kept as the app's others are (`RuleEditorWindowController.swift:46-67`), on the navy ground.
- The waveform, selection, playhead, zoom, play, stop and loop, and the checks listed without their presses. No edit yet.
- Space plays the result as last rendered. While a newer render is under way it plays the last finished one, and the window says it is catching up.
- Reached by nothing a user can find: the button is added in Task 9.
- _Acceptance:_ wiring tests show the view holds no words of its own, the preview calls `testBuffer` and never `play`, Space is handled by the waveform, and every control has a label from `SoundEditorText`.

### Task 8: editing

**Files:** the Task 7 files, a wiring test.

- Each edit wired to the history, with its shortcut: ⌘X, ⌘C, ⌘V, ⌘D, ⌘Z, ⇧⌘Z, ⌘A.
- Each check's press.
- Renders per Ruling 6.
- VoiceOver per Ruling 13.
- _Acceptance:_ wiring tests show every edit goes through `SoundEditHistory.commit`, that a render is started off the main actor and its result checked against the newest request, and that only the blocking check is outlined as a fault.

### Task 9: saving, and the way in

**Files:** `AlertEditorView.swift`, `RuleEditorModel.swift`, `EditorText.swift`, the Task 7 files, `docs/rules-format.md`, `docs/getting-started.md`, `docs/architecture.md`, `CHANGELOG.md`, wiring tests.

- **Edit Sound…** beside **Add Sound…** (`AlertEditorView.swift:182`), off when the rule's sound is not found.
- **Save as New**, **Save** and the questions of Ruling 9. Closing with unsaved edits asks, as the rule editor does (`RuleEditorWindowController.swift:166`).
- After a save: the player forgets what it had decoded, the editor lists the sounds again, and the rule names the new sound.
- The pages, and the changelog entry.
- _Acceptance:_ wiring tests for each of those. Then the human checks below, by the owner, before 1.4 is tagged.

## Human checks

For the owner, on the build that would be released, since no test hears a sound:

- [ ] Trim, delete, duplicate and repeat on three different sounds: no click at any join, at normal volume and in headphones.
- [ ] Each check fires on a sound that should set it off, and its press fixes it. The thresholds of Ruling 12 are right by ear, or are changed.
- [ ] A preview while an alert is escalating is refused, and says so.
- [ ] An alert that arrives during a looped preview is heard, whole.
- [ ] Save as New, then the rule plays the new sound. Save over a sound two rules use: asked, and both play the new one.
- [ ] The whole window with the keyboard alone, and with VoiceOver.
- [ ] With Increase contrast and Reduce transparency on: the selection and the playhead are still plain.
- [ ] Quit during a save: the old sound is still there and still plays.

## Not in this plan

- **Phase 2:** a pulse designer that makes a sound from pitch, pulse length, gap and count; a tone with a spoken word; inserting or layering a second sound; versions of one sound for the later tiers of a ladder.
- **Phase 3:** change of speed; matching sounds by perceived loudness; hearing a sound as a laptop speaker or an older ear would; a check that two rules' sounds can be told apart; sound packs.
- **Never, as planned here:** microphone recording (O3), more than one layer, plug-ins, any network use.
- Removing or renaming a sound in the app. That stays in the Finder, as 1.3 decided, and a sidecar whose sound has gone is removed by Task 5's sweep.

## Risks

| Risk                                               | What holds it                                                                         |
| -------------------------------------------------- | ------------------------------------------------------------------------------------- |
| A failed save loses a sound that pages someone     | Ruling 8: one install step, set aside and put back, tested with a rename made to fail |
| A preview cuts off a page                          | Ruling 7, a wiring test that forbids `play`, and two of the human checks              |
| A join clicks                                      | Ruling 4, the bound in Task 3's test, and the first human check                       |
| A long render stalls the app while an alert is due | Ruling 6, and the 120 second bound of Ruling 11                                       |
| The recipe and its file come apart                 | Ruling 10: a mismatch is a plain sound, never an error                                |
| The thresholds are wrong                           | O4: constants in one place, set by ear before release, and advice only                |
| The waveform cannot be used without a mouse        | Ruling 13, a wiring test, and a human check                                           |
| Source copies fill the disk                        | Each is at most 64 MB, the limit an added sound has, and is removed with its sound    |

## Rollback

Tasks 2 to 4 and 6 to 8 add nothing a user can reach, and each can be reverted alone. Tasks 1 and 5 change how a sound is added and decoded without changing what either does, and each is reverted alone too, back to the code 1.3 shipped. Task 9 is reverted by removing the button: sounds already saved are ordinary files and go on playing, and their recipes are ignored by a build that does not know them.
