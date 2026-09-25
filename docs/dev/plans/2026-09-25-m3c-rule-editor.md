# M3c: The Rule Editor — Implementation Plan

> **Execution:** each task is implemented with its tests, committed behind a gate (full suite green at the expected count, zero build warnings, new logic mutation-checked), and independently reviewed against the requirements below.

**Goal:** Make, edit, reorder, enable and delete rules in a window, starting from a real captured notification, with a live dry-run against recent traffic — so a rule is proven before it is trusted — and save them without ever losing or silently changing what the user wrote.

**Architecture:** File safety moves into a new tested `RuleStorage` target. The editor's document model, condition-tree edits, dry-run, seeding and every piece of wording are pure code in `NotificationCore`. `AlertAudio` gains a way to try a sound that can never cut off a real alert. The app target adds the editor window, a thin model and SwiftUI views.

**Tech Stack:** Swift 5.9, SwiftUI hosted in AppKit windows, CryptoKit, Foundation, XCTest.

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md` — §2.1 privacy, §5.10 order is priority, §5.14 RuleBuilderView, §6 persistence ("versioned, atomic write"), §7.2 Inspector, §7.3 the authoring loop, §7.4 rule editor, §7.5 preview at the rule's gain, §8.1 step 5, §12.

**Groundwork:** scoped by five parallel readers (rules model, UI plumbing, audio, SwiftUI feasibility on macOS 14, project history), then stress-tested by four critics (data safety, SwiftUI realism, spec and scope, the authoring loop for the real Teams case) and an independent designer, with every serious finding checked against the code by an adjudicator. The rulings below are what survived.

## Global Constraints

- **Nothing the user wrote is ever lost or silently changed.** Every write is atomic, keeps the previous version, and refuses to overwrite a file that changed since it was read.
- **An unsaved draft never governs a real alert.** The live rules change only when Save succeeds — and then at once.
- **Nothing may claim more than was established.** The dry-run describes the draft, never protection that is not yet in force.
- **Notification content is never written to disk, logged, or transmitted** (§2.1) except as rule text the user explicitly chooses, and the editor says when text will be saved.
- `NotificationCore` imports no UI or permission-bearing framework and touches no file or network API (`PurityTests`).
- macOS 14.0 floor; event-driven; near-zero idle CPU.

## Rulings

**1. The app writes the rules file only when the user presses Save in the editor.** Never on load, never implicitly. The M3a promise that the app never writes over the file is retired everywhere at once — the `RuleStore` comment, `docs/rules-format.md`, and a note on M3a's ruling — and replaced by what is now true: hand-editing still works, the editor saves canonically formatted JSON, and the version on disk before each save is kept.

**2. A save can never leave the file missing or half-written.** The bytes on disk are first copied (never moved) to `rules.previous.json`, then the new file is written atomically (temporary file, then rename), so `rules.json` exists and is complete at every instant. A symlinked `rules.json` is written through to its target, not replaced by a plain file. A missing folder is recreated.

**3. A save refuses to overwrite a file that changed since the editor read it.** The editor keeps a SHA-256 of the bytes it loaded (or that there was no file). Save re-reads first; on any difference — including a file appearing or vanishing — it stops and says what changed (rules added or removed, by name), offering _Reload from Disk_, _Save Anyway_ or _Cancel_. _Save Anyway_ keeps the version it replaces under its own timestamped name, never in the rotating `rules.previous.json` slot. The window between the re-read and the rename is a few milliseconds and is documented rather than coordinated: text editors do not take part in file coordination.

**4. A file the editor cannot fully represent is shown read-only.** A file that is not JSON, has the wrong shape, comes from a newer version, or contains an entry that does not decode as a rule (an unknown key, a bad operator) opens read-only with the reason and _Open Rules File in Text Editor_. Saving it would have to drop what could not be read. _(Considered: carrying undecodable entries through a save as raw text. Rejected for M3c as the one path where a bug destroys user data; those entries come from hand-editing, and a text editor is where they are fixed.)_ A rule that decodes but is invalid — a missing or unplayable sound, a gain out of range, an empty group, an alert in a version 1 file — is an ordinary editable rule with its problems shown live, so the editor can fix it.

**5. The file is written at the lowest version that can express it.** Version 1 when no rule has an alert, 2 otherwise — counting every rule, including one flagged with a problem — so an older build is never locked out needlessly.

**6. The editor edits a draft; Save applies it immediately.** The draft is the whole rule list. Save writes, then reloads through the same path as _Reload Rules_ (sounds prepared, rules applied, Inspector previews refreshed, menu rebuilt) before it reports success. _Revert_ restores what was loaded.

**7. The condition builder binds straight to `RuleCondition` and addresses nodes by index path.** No parallel tree of view models (§5.14). The tree functions are total: a stale path returns nothing rather than trapping, because SwiftUI can evaluate a departing row's binding once after a delete. Structural edits are not animated. Index paths are chosen for simplicity: they need no minted identity and nothing to persist. Rule rows use `Rule.id`, which the first save writes into the file, so ids are stable from then on.

**8. The dry-run respects order and always says it is the draft.** For the selected rule, each retained notification is _matched by this rule_, _claimed by an earlier rule (named)_, or _not matched_ — first match wins, exactly as at runtime. The headline names its status ("In this draft: matches 3 of the last 50 — not in effect until you save"; for a disabled rule, "…when enabled"). A notification claimed above offers _Move above "X"_. It is recomputed on every edit and on every capture, pushed from the app as the Inspector is.

**9. "Make a Rule from This" seeds only the app, and never names a rule from message text.** A button on each Inspector row. It opens the editor with a new rule: `app equals <app>`, disabled, no alert, named "New rule for <app>" — built from the app name, not the title. It is inserted above the first rule that would claim that notification, so it is never born shadowed. The real Teams banner captured so far put message text in its title, so an `equals` on it would match nothing else. _(Corrected: the first draft seeded `title equals`.)_ While the editor was opened from a row, _Add Condition from This Notification_ offers each of its fields. Free text defaults to `contains`, app and subrole to `equals`, and an empty field to `equals ""`. The editor says the chosen text will be saved in the rules file.

**10. Trying a sound can never cut off a real alert.** _Test Sound_ plays the rule's sound at the rule's gain through the same graph (§7.5). While a real alert is playing, it is refused; a real alert cuts off a test sound. It is recorded nowhere. It is not called "preview", which already means the Inspector's view of what the loaded rules would do.

**11. One window, two panes.** `HSplitView` rather than `NavigationSplitView`: this is a small utility window in an app that manages its own windows, and it needs no navigation or toolbar semantics. The window controller is the app's first to guard closing: with unsaved changes it asks _Save_, _Don't Save_ or _Cancel_, closing only after the answer. A save during close that ends in _Reload from Disk_ or _Cancel_ leaves the window open. The menu gains _Edit Rules…_ (⌘E); the old item becomes _Open Rules File in Text Editor…_.

**12. First rule (§8.1 step 5) through the empty state.** With no rules, the editor says how to make the first one from a real notification in the Inspector. There is still no onboarding wizard to host it; the menu-driven onboarding is where it lives until there is.

---

## Task 1: `RuleStorage` — the file, safely

**Files:** `Package.swift`, `Sources/RuleStorage/RulesFile.swift`, `Tests/RuleStorageTests/…`, `Sources/SignalLadder/RuleStore.swift`

- A new library target with its own tests, because the write path must not live in the untested app target.
- `read()` → bytes (or none) and their SHA-256. `save(_:expecting:)` → `.saved`, or `.changedOnDisk(current bytes)`. `saveReplacing(_:)` for _Save Anyway_. The file writer is injectable, so tests can make the final write fail.
- Tests, against real temporary folders:
  - `rules.json` is never absent, including when the final write fails after the backup;
  - the backup holds exactly the previous bytes;
  - a changed file, one that appeared, and one that vanished are each refused;
  - a symlink's target is updated and the link survives;
  - a missing folder is recreated;
  - _Save Anyway_ keeps a timestamped copy.
- `RuleStore` reads through it; behaviour is otherwise unchanged in this task.

## Task 2: The document the editor edits

**Files:** `Sources/NotificationCore/RulesDocument.swift`, `RuleSetCodec.swift`, tests

- `RulesDocument.load(_ data: Data?)` → `.editable(rules, loadedVersion)` or `.readOnly(reason)`, per ruling 4. Decodable-but-invalid rules are kept; problems are derived live, never stored.
- `problems(for:)` in the draft uses the same checks as loading, including sound availability and playability, so the editor and the menu never disagree.
- `encode()` at the minimal version (ruling 5).
- `changesSince(loaded:current:)` → rules added and removed, by name, for the conflict message.

## Task 3: Editing the condition tree

**Files:** `Sources/NotificationCore/ConditionEditing.swift`, tests

- Total, index-path functions:
  - `condition(at:)`, `replacing(at:with:)`, `removing(at:)`, `inserting(_:into:at:)`;
  - `wrapping(at:in:)` (and / or / not), `unwrapping(at:)`, `negating(at:)`.
- Tests cover every stale path returning nil rather than trapping, removing the last child of a group, unwrapping to a single child, and invariants (removal never leaves an empty group silently: the result is reported as a problem).

## Task 4: Dry-run, seeding and wording

**Files:** `Sources/NotificationCore/DryRun.swift`, `RuleSeed.swift`, `EditorText.swift`, tests

- `DryRun.report(for:in:over:)`: order-aware verdicts per retained notification, per ruling 8.
- `RuleSeed.from(_ entry:)` and the insertion index above the first claiming rule; the field offers for _Add Condition from This Notification_.
- `EditorText`: every headline, status, conflict and read-only message, tested as M3b's wording was.

## Task 5: `AlertAudio` — a test sound that yields

**Files:** `Sources/AlertAudio/AlertPlayer.swift`, tests

- The player knows when a real alert is in flight: set by a live play, cleared when it finishes or the output changes.
- `testSound(_:ruleGainDB:)` throws `.alertPlaying` while one is; a live play interrupts a test sound.
- Offline tests cover both directions.

## Task 6: The editor window, the list, and saving

**Files:** `Sources/SignalLadder/RuleEditorWindowController.swift`, `RuleEditorModel.swift`, `RuleListView.swift`, `AppDelegate.swift`, `RuleStore.swift`, `docs/rules-format.md`

- The window: activation as for the Inspector; the close guard (ruling 11).
- The list:
  - drag to reorder by a handle, so the per-row toggle stays instant;
  - enable toggle; add, duplicate, delete;
  - `.buttonStyle(.plain)` on in-row controls.
- The model:
  - holds the draft and the loaded hash;
  - on Save, runs the conflict flow (ruling 3) and applies the rules immediately (ruling 6);
  - Revert.
- The read-only state (ruling 4) and the empty state (ruling 12).
- Menu items per ruling 11. The "never writes" promise is retired in the same commit (ruling 1).
- **Decided during implementation:**
  - The save bar always states, in words, whether what is on screen is in effect: _Saved — these rules are in effect_ or _Unsaved changes — not in effect until you save_.
  - An open editor holding no draft follows _Reload Rules_, so it never shows rules that are no longer the ones in effect.
  - A duplicated rule starts switched off: it is new, and unproven.
  - Sound checks are remembered for the editing session, so typing does not re-read the sound folders on every keystroke; they are refreshed on each reload.

## Task 7: Building a rule

**Files:** `ConditionRowView.swift`, `AlertEditorView.swift`, `DryRunView.swift`, `InspectorView.swift`, `RuleEditorModel.swift`, `AppDelegate.swift`

- The recursive condition builder over Task 3, type-erased at the point of recursion.
- The alert editor (None / Silent / Sound, gain −40…+12 dB with its value shown, _Test Sound_).
- The dry-run panel, with _Move above_, refreshed on each capture.
- _Make a Rule from This_ on each Inspector row; _Add Condition from This Notification_.
- **Added during implementation:**
  - `RuleCondition.adding(_:)`: _Add Condition_ on a rule whose whole condition is one field, such as a fresh seed, puts both in an "all of" group, so it narrows as the user expects.
  - Builder wording (field and operator names, a condition in words, what each alert kind does) lives in `EditorText` with the rest.
  - Gain moves in whole decibels.
  - A sound the rule names but that cannot be found stays in the picker, marked _(not found)_, so the choice shows what the rule says.

## Task 8: Docs, harness and live verification

- `docs/rules-format.md`: editing in the app, what Save does to the file, `rules.previous.json`, conflicts, read-only files.
- `Scripts/verify-live.sh`:
  - _Edit Rules…_ opens a window titled "SignalLadder Rules";
  - opening and closing it without saving leaves `rules.json` byte-identical.
- **Human checks** (they drive SwiftUI. The Accessibility API turned out to read and press nearly all of it — the 2026-09-25 run below was driven that way — but it cannot drag, and it cannot hear):
  - [x] From an Inspector row, a Teams rule can be made, narrowed with the dry-run, given a sound, tested and saved in under a minute. _The path works end to end (from a Script Editor row: there was no Teams traffic). The dry-run narrowed from 5 to 2 of the last 6. Done by hand in under a minute._
  - [x] Typing into a nested condition keeps focus and the cursor. _With the caret mid-value: `zzX-a`, `zzXY-a`, `zzXYZ-a`, focus held throughout._
  - [x] Deleting and wrapping conditions never crashes. _No crash in four structural edits. Each nested ⋯ menu opens its own menu, with a real click and through the raw Accessibility API. An earlier report that Accessibility reached only the top-level group's menu was a fault in the test (see findings, 2026-09-25)._
  - [x] Dragging reorders rules; the toggle responds at once. _The toggle flips at once, and switching it back returns the status to "Saved and in effect". Dragging checked by hand._
  - [x] Closing with unsaved changes asks; each answer does what it says. _Cancel keeps the window and the draft; Don't Save closes and discards; Save closes and writes._
  - [x] Editing `rules.json` by hand while the editor is open, then saving in the editor, is refused with the change named. _Reload from Disk, Save Anyway (dated copy byte-identical to the hand edit) and Cancel each did what they say._
  - [x] After Save, a matching notification is handled by the new rule without _Reload Rules_.
  - [x] _Test Sound_ plays at the rule's gain, and is refused while a real alert plays. _Refused during a real alert ("an alert is playing — try again when it has finished"), and plays once it ends. The gain was confirmed by ear._
  - [x] The first save leaves `rules.previous.json` holding the hand-written file. _Byte-identical._

## Found in review, and settled

Two independent reviews ran after the build: one over Tasks 1–5, one over Tasks 6–8, with every finding checked by a separate skeptic before anything changed.

- _A rules link whose target cannot be found_ (an unmounted drive, a sync client that has not fetched the file) read as "no file". A save then renamed onto the link, replacing it with a plain file holding only the new rules and orphaning the real ones. It is now reported as a file that cannot be opened, naming its target, and every read and write refuses it.
- _Quitting lost an unsaved draft without asking_: quitting never consults a window's close guard. The app now asks the same Save / Don't Save / Cancel question before it quits.
- _"Saved — these rules are in effect" could be false_: it compared the draft with the file, not with what the app was running, so a hand edit that was never reloaded read as in effect. The save bar now distinguishes three states: unsaved; the file is not what is running, with _Put into Effect_; and saved and in effect, counting any saved rules that will not run because of problems.
- _The dry-run's "not in effect until you save" ignored order_: it compared only the rule itself, so moving it — even with the dry-run's own _Move Above_ — left verdicts shown as current that were not. A rule's dry-run is now unsaved if anything at or above it differs from the saved file. This decision and the save state moved into the tested core.
- _A minimised editor counted as closed_, so _Edit Rules…_ re-read the file over its draft. Minimised now counts as open.
- Smaller: the dry-run's empty state now also says it is the draft; a test sound's error no longer carries over to another rule; the sound picker selects a sound written in different case; the notification the editor was opened from is forgotten when the window closes; the drag handle has a larger target.
- _Refuted_: a re-entrant save while a sheet is showing (a sheet makes the window modal).

**Human checks added:** quitting with a draft asks first; after a hand edit that was not reloaded, the save bar says so and _Put into Effect_ applies it.

## Not in this plan

- Undecodable entries carried through a save (ruling 4).
- The Text toggle and the expression language (M5).
- The escalation ladder (M4).
- Speech (its own milestone).
- Regex, time, on-call, screen-lock and frequency conditions (M5).
- A sound library UI and settings (§7.5).
- An onboarding wizard.
