# M7: the Night watch redesign (1.2)

> **Status:** plan, written on 2026-11-25 from `main` at 104486b. Stage 1 is built and draws nothing. Stage 2 is built: a fault is no longer orange. Nothing else in it is built. The design is agreed in mock-ups only; the owner chose it on 2026-11-25.

**Mode:** standalone. The inputs are the owner's chosen mock-ups and a read of the code on 2026-11-25.

**Inputs taken as given:** work type is a redesign of the look, with three changes of behaviour inside it (a popover, a rename, and what orange means). Risk tolerance is conservative, because this is an on-call tool and every surface here is one somebody reads under stress. It ships after 1.1, as 1.2.

## The design

The owner compared five directions and chose the one called "Night watch on glass".

| Surface          | What changes                                                                                                                                                                                                                                                                                                                                                   |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status item      | While an alert escalates, a capsule in the tier's colour holding the tier and the repeat count in SF Mono (`2 04/20`). Other states keep a symbol. A problem is the slashed bell in an outlined box, with no colour.                                                                                                                                           |
| Popover          | Opens on a click. A block in the tier's colour says who is waiting, since when, and the repeat count in large SF Mono, with Acknowledge. Then capture, on-call and rules lines; three tiles (Inspector, Rules, Snooze); then the remaining commands. Navy ground.                                                                                              |
| Status menu      | Kept as it is, on right-click and Option-click.                                                                                                                                                                                                                                                                                                                |
| Escalation panel | Navy ground. One rounded block per escalation in its tier's colour, with a large tier numeral, the rule's name, and since, matches and repeat in SF Mono. A failed Shortcut is an outlined block with the slashed bell and its sentence, and no colour.                                                                                                        |
| Rule editor      | Follows the system's light or dark. The rule list is an inset panel with each rule numbered and a four-segment strip showing how far its ladder reaches. The ladder is four tier capsules in a row; the selected tier's settings open underneath. The conditions come next, and under them "Matching notifications". Navy only for the selected rule and Save. |
| Type             | SF Mono for every time, count and key equivalent.                                                                                                                                                                                                                                                                                                              |
| Material         | Liquid Glass on macOS 26 and later for the popover and the panel; solid navy on macOS 14 and 15 and under Reduce Transparency.                                                                                                                                                                                                                                 |
| Colour           | Tier 1 amber `#ffc857`, tier 2 orange `#ff8a2b`, tiers 3 and 4 red `#ff4d3d`, on navy `#0c1224`. Orange stops meaning a fault.                                                                                                                                                                                                                                 |

Not designed, and left as they are apart from the fault change: the Inspector, Settings, the Setup Guide and the On-Call Check.

## Where things stand

| Fact                                                       | Evidence                                                                                                                                                                                        |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.1 is not tagged                                          | Latest tag `v1.0.0`; `main` at 104486b. The owner has run the fixed build daily since 2026-11-07.                                                                                               |
| There is no shared style                                   | No theme file, no `ViewModifier`, no colour assets. Colours are `.secondary`, `.orange`, `.green`, `.blue` inline.                                                                              |
| No availability checks exist                               | No `#available` or `@available` in `Sources/`. The floor is macOS 14 (`Package.swift:6`).                                                                                                       |
| No accessibility display setting is read                   | Nothing reads Increase Contrast, Reduce Transparency, Reduce Motion or Differentiate Without Colour.                                                                                            |
| Orange carries a meaning in about 16 places                | Warnings, a rule with problems, an alert that did not sound, a failed test, and "taken by a rule above" in the dry run (`DryRunView.swift:65`).                                                 |
| The status item is an `NSMenu` set on the item             | `AppDelegate.swift:885-891`. Opening it also starts capture, re-evaluates health and reads the login item (`:893-954`).                                                                         |
| The escalation panel takes finished strings                | `AlertPanelController` is given `(UUID, String)` rows. Tier and repeat exist as numbers only in `EscalationSummary`.                                                                            |
| The panel shows tiers 2 to 4 only                          | The panel appears at tier 2. Tier 1 is the first alert.                                                                                                                                         |
| The ladder is not four tiers in a row today                | Tier 1 is `Rule.alert`. `LadderEditorView` has a preset picker (Off, Gentle, On call, Wake me, Custom), a sentence, and a "Customise…" disclosure holding tiers 2 to 4. Tier 2 is a delay only. |
| The section is not called "Dry run" in the app             | It is "Tried on recent notifications" (`EditorText.swift:944`), used once (`RuleDetailView.swift:95`).                                                                                          |
| CI builds on Xcode 26.6 and Xcode 16.4, warnings as errors | A macOS 26 symbol guarded only by `#available` does not compile on the Xcode 16.4 job.                                                                                                          |
| CI fails if fewer tests run than the docs state            | `docs/architecture.md` says 2673.                                                                                                                                                               |
| There is no screenshot tooling                             | The images in `docs/assets/` are made by hand from scratch programs.                                                                                                                            |

## Code read for this plan

| File                                                                                                                                                                     | Relevance | Notes                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/SignalLadder/AppDelegate.swift:885-1068`, `:1098-1251`                                                                                                          | High      | Status item, menu build, the gate, the glyph and its 0.8 s pulse timer.                                                         |
| `Sources/NotificationCore/MenuRebuildGate.swift`                                                                                                                         | High      | Rows never move while the menu is open; actions act on what was shown.                                                          |
| `Sources/NotificationCore/StatusGlyph.swift`                                                                                                                             | High      | Pure precedence: problem, escalating, snoozed, held, on call, normal. `Facts` has `escalationLive: Bool` and no tier or repeat. |
| `Sources/AlertPanel/AlertPanelController.swift`                                                                                                                          | High      | Borderless non-activating `NSPanel`; reuses row views so a press is never lost; `maxRows = 6`.                                  |
| `Sources/NotificationCore/EscalationPanelText.swift`, `EscalationCoordinator.swift:10-72`                                                                                | High      | The line format, and the numbers behind it.                                                                                     |
| `Sources/SignalLadder/RuleEditorView.swift`, `RuleDetailView.swift`, `LadderEditorView.swift`, `AlertEditorView.swift`, `ConditionBuilderView.swift`, `DryRunView.swift` | High      | The editor. Three `AlertEditorView` mounts: tier 1, tier 3's repeat, tier 4's final step.                                       |
| `Tests/NotificationCoreTests/ViewLiteralsTests.swift:582-623`                                                                                                            | High      | New view and controller files must be registered and may hold no word.                                                          |
| `Tests/AlertPanelTests` (`:49-65`, `:117-128`, `:225-250`, `:262-271`)                                                                                                   | High      | Panel flags, row identity, the import whitelist, and accessors that assume a row's first and last subviews.                     |
| `Tests/NotificationCoreTests/MenuRebuildWiringTests.swift`, `SetupWiringTests.swift:1252-1278`, about ten wiring suites                                                  | High      | Read `AppDelegate` and view source as text.                                                                                     |
| `Scripts/verify-live.sh`, `Scripts/harness-guards.sh` and their fixtures                                                                                                 | High      | Find the status item by `AXMenuExtra` and read `menu items of menu 1`.                                                          |
| `.github/workflows/ci.yml`                                                                                                                                               | Med       | Two toolchains.                                                                                                                 |
| `docs/getting-started.md:304`, `docs/troubleshooting.md`, `docs/privacy.md`, `docs/architecture.md:66`, `:140`, `:147`                                                   | Med       | Name the menu, the heading and the panel's contract.                                                                            |

| Pattern to follow                                             | Example                            | Apply to                                                       |
| ------------------------------------------------------------- | ---------------------------------- | -------------------------------------------------------------- |
| Words live in `NotificationCore` and are tested there         | `EditorText`, `StatusMenuText`     | every new label, tooltip and VoiceOver string                  |
| A pure decision in the core, drawn by the app                 | `StatusGlyph`                      | tier tone, the capsule's text, the popover's rows              |
| An input with no default, so no caller can forget it          | `CapturePipeline.init`             | the new `StatusGlyph.Facts` fields, the accessibility settings |
| A refactor and a change of look go in separate pull requests  | `CONTRIBUTING.md`                  | Stage 1 against Stages 2 to 6                                  |
| A fix carries its CHANGELOG line and the pages it makes false | `CONTRIBUTING.md`, "Documentation" | every stage                                                    |

## Sizing

| Stage                        | Size | Why                                                                                                   |
| ---------------------------- | ---- | ----------------------------------------------------------------------------------------------------- |
| 1. Style foundation          | S    | New files only; nothing drawn differently.                                                            |
| 2. What a fault looks like   | M    | 16 call sites and the wiring tests that pin their lines.                                              |
| 3. Escalation panel          | M    | A new row model across a sealed boundary; row reuse must survive.                                     |
| 4. Status item capsule       | M    | New facts in a pure type with many constructions in tests; the tooltip defect lives here.             |
| 5. Popover                   | L    | A new window with its own focus, dismissal and VoiceOver; the live harness must still reach the menu. |
| 6. Rule editor               | L    | Three pull requests; the most pinned source in the app.                                               |
| 7. Glass                     | S    | Two materials behind compile and availability guards.                                                 |
| 8. Pages, images and release | M    | Every image is stale and made by hand.                                                                |

## Impact

- Users on macOS 14 and 15 get the redesign in solid navy. Users on 26 and later get glass.
- The status menu keeps working exactly as today on right-click, so the live check, its guards and its fixtures keep their subject.
- Three things people know change: a click opens a popover and no longer the menu; a heading is renamed; orange no longer means "this will stop an alert".
- The design system, the README images and four doc pages describe the old look until Stage 8.

## The plan

Each stage is one or more pull requests against `main`, each shippable by itself and each carrying its tests, its CHANGELOG line and the pages it makes false. Stages 2 to 5 depend on Stage 1. Stage 2 lands before any tier colour is drawn, so orange never means two things at once.

**Before Stage 1.** Tag 1.1. Merging any of this to `main` first would put it inside 1.1.

### Stage 1: style foundation (refactor, no change of look)

1. `NotificationCore`: a `TierTone` (first, second, upper) from a tier number, with tests. No colour; the core may not import AppKit or SwiftUI.
2. App target: a palette (navy, the three tier colours, the outline) and a mono font helper, in files that are not named `*View`, `*Controller` or `*Coordinator`.
3. `AlertPanel`: its own AppKit copy of the palette. The target may import only AppKit and Foundation, so it cannot share the app's.
4. A small value for the four display settings (Increase Contrast, Reduce Transparency, Reduce Motion, Differentiate Without Colour), read from `NSWorkspace` in the app and passed in, so tests can set each.
5. The compile guard for new-SDK symbols, proved on both CI toolchains with one harmless use.

### Stage 2: what a fault looks like

1. A fault label drawn as its symbol, an outline and its sentence, in label colour. Replace orange at each warning site. _As built:_ each place keeps the symbol it had, since the symbol says which kind of fault it is (a filled triangle for a rule that does not run, a struck-through speaker for a muted output), and the slashed bell is kept for the status item and the panel. The outline goes round what stops an alert or a rule; a line of the Inspector, the save bar and the On-Call Check's findings are in the label colour and heavier with no outline, and advice that leaves a rule in effect has none. _Not in effect_ has the outline only for a rule with problems.
2. "Taken by a rule above" in the dry run is neither a fault nor a tier: secondary label colour.
3. Under Increase Contrast and Differentiate Without Colour the outline thickens; nothing depends on hue.
4. Update the wiring tests that pin the orange lines, each in the pull request that changes its line.

### Stage 3: escalation panel

1. A row model owned by `AlertPanel`: id, rule name, since (a string), tier, repeat count and cap, match count, and a status enum (escalating, no longer repeating, Shortcut failed, missed while asleep). Numbers and enums only; no notification text can cross.
2. `EscalationPanelText` gains a function that builds that model's words and the full spoken line. The existing one-line function stays, as the VoiceOver label and for the menu.
3. Draw the blocks. Restyle a row in place when its tier changes; keep row and button identity.
4. A row that was missed while asleep has no tier to show: draw it as an outlined block with its sentence.
5. Measure the new row height on the smallest supported screen and set `maxRows` from it.
6. Update `docs/architecture.md` where it states the panel's contract.

### Stage 4: status item capsule

1. `StatusGlyph.Facts` gains the highest live tier and its repeat count and cap, with no defaults. The decision returns the capsule's text and its spoken description.
2. Draw the capsule as a non-template image; keep template symbols for every other state. Precedence is unchanged.
3. Reduce Motion: the pulse stops alternating and the capsule holds steady.
4. Width: fixed-width digits so the item does not jitter; check it on a notched display with a full menu bar.
5. The tooltip is still reassigned on every rebuild. Watch for the stuck tooltip (#217) during this stage's live use, and stop if it gets worse.

### Stage 5: popover

1. A pure builder in `NotificationCore` returns the popover's rows from the same facts and the same text types the menu uses, so the two cannot disagree.
2. The status item stops setting `item.menu`. A click opens the popover; a right-click or Option-click pops up the existing menu, built and gated as today.
3. Opening the popover runs what `menuNeedsUpdate` runs: start capture if trusted, refresh audibility, re-evaluate health, read the login item.
4. Rows do not move while the popover is open, and Acknowledge acts on what was shown, as the menu's does.
5. Focus: the popover takes key so Esc, Tab and Return work, and closes on Esc, on a click outside, and when another app takes focus. On macOS 27 and later use `NSStatusItem.expandedInterfaceDelegate` for this; below it, a local and a global event monitor.
6. Key equivalents (⌘I, ⌘E, ⌘R, ⌘Q) work while the popover is open. Quit stays out of the main menu.
7. VoiceOver: every row is a real control with its words; the waiting block reads rule, since, matches, tier and repeat.
8. The live check opens the menu by right-click (or the `AXShowMenu` action) and reads it as before. Its fixtures do not change. Add checks that the popover opens and closes.
9. The tooltips and pages that say "open the menu" are reworded.

### Stage 6: rule editor (three pull requests)

**6a. The list.** An inset panel; each rule's position as a number; the four-segment ladder strip. Drag, the Delete key, the context menu and "Top rule wins" unchanged. The number is the row's position and nothing is stored.

**6b. The ladder.** Four capsules. The preset picker stays above them, because presets are how most rules are set and they are derived, never stored. Selecting a capsule shows that tier's settings underneath:

- Tier 1: the first alert (None, Silent, Sound, Speech, and the sound, gain, voice, Says, rate, pitch and speech gain).
- Tier 2: its switch and its delay. No alert controls; tier 2 has none.
- Tier 3: its switch, every, at most, stop after, and its alert (Sound or Speech).
- Tier 4: its switch, its delay, and an alert or a Shortcut with Test Shortcut.

A tier that is off shows an outlined capsule and a switch to turn it on. All four tier panels stay mounted and only one is shown, so a half-typed number and a test's message survive moving between capsules. If a preset removes the selected tier, the selection moves to tier 1.

**6c. Conditions and matches.** The heading "Tried on recent notifications" becomes "Matching notifications" and the section moves to sit under the conditions. The sentence inside it is unchanged.

### Stage 7: glass

`NSGlassEffectView` behind the popover and the panel on macOS 26 and later, navy-tinted; solid navy below 26, under Reduce Transparency, and under Increase Contrast. The tier blocks stay solid on every version: they carry text that must be read.

### Stage 8: pages, images and release

1. Reword `docs/getting-started.md`, `docs/troubleshooting.md`, `docs/privacy.md` and `docs/architecture.md`.
2. Remake the README hero, the social preview and the six screenshots, with placeholder content only.
3. Update the design system: orange no longer means a fault; add the tier colours, the navy surfaces and the mono styles.
4. Raise the test count in `docs/architecture.md`.
5. Run the live check in all four modes on a signed build; swap the owner's running copy on their go-ahead; soak; tag 1.2.

### Owner decisions

Decided on 2026-11-25:

- It ships after 1.1, as 1.2.
- A click opens the popover; right-click and Option-click keep the menu.
- Glass on macOS 26 and later, solid navy below. The floor stays at macOS 14.
- The rule editor follows the system's light or dark.

Open, with the default this plan takes unless told otherwise:

| Question                                                                                                                                                                | Default                                                                                                         |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| The panel never shows tier 1, so amber never appears on it. Keep one mapping everywhere (tier 1 amber, 2 orange, 3 and 4 red), or shift it so the panel uses all three? | Keep one mapping. A colour that means tier 2 in one window and tier 3 in another is worse than an unused amber. |
| Does the preset picker stay above the four capsules?                                                                                                                    | Yes.                                                                                                            |
| How long does 1.2 soak before its tag?                                                                                                                                  | The same bar as 1.1: one week and five shifts on the build.                                                     |
| Do the Inspector, Settings, the Setup Guide and the On-Call Check get a design of their own?                                                                            | Not in 1.2. They take the fault change and SF Mono for times only.                                              |

## Risks

| Risk                                                                        | Likelihood        | What limits it                                                                                                                     |
| --------------------------------------------------------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| A failed Shortcut reads as an ordinary red block                            | Med               | Stage 2 lands first; the fault block has no colour, a different shape and its sentence.                                            |
| The popover loses what `NSMenu` gives for free (VoiceOver, arrow keys, Esc) | High              | The menu stays on right-click. The popover's rows are real controls. A VoiceOver pass is part of Stage 5's done.                   |
| A click on the status item steals focus from the app in front, mid-incident | Med               | The escalation panel stays non-activating and keeps its own Acknowledge and ⌃⌥⌘A. Only the popover takes key, and only on a click. |
| The live check can no longer open the menu                                  | Med               | Stage 5 item 8, before the menu's click path changes.                                                                              |
| Wiring tests that read source fail broadly                                  | Certain           | Each changes in the pull request that changes its line. Deleting one without a replacement drops the count below what CI requires. |
| A macOS 26 symbol breaks the Xcode 16.4 job                                 | High if unguarded | Stage 1 item 5 proves the guard before anything needs it.                                                                          |
| The capsule makes the stuck tooltip worse                                   | Low to Med        | Stage 4 item 5.                                                                                                                    |
| Glass is unreadable over a busy desktop                                     | Med               | Tier blocks are solid; the ground falls back to solid navy under either accessibility setting.                                     |
| macOS 14 and 15 are never seen by a person                                  | High              | CI compiles and tests the solid path. A look on a macOS 15 machine or VM before the tag is the owner's call.                       |
| Taller panel rows push Acknowledge off the screen                           | Low               | Stage 3 item 5.                                                                                                                    |

## Tests

- Core: `TierTone`; the panel row model's words and its no-leak fixtures; the new `StatusGlyph` facts through every state; the popover's row builder against the menu's fixtures.
- Panel: the flags, row and button identity across a tier change, the import whitelist, and new accessors for the block's parts.
- App: `ViewLiteralsTests` with each new file registered; wiring tests rewritten beside the lines they pin.
- Both materials and each display setting are reachable from tests through the injected value.
- Live, on a signed build: the default check and `--on-call`, `--escalation` and `--snooze`; a VoiceOver pass over the popover, the panel and the editor; Increase Contrast and Reduce Transparency each switched on once.

## Rollback

Every stage is its own pull request and reverts by itself. Stage 5 is the one to revert first if the popover misbehaves: setting `item.menu` again restores today's behaviour, and the menu was never removed. The owner's earlier builds stay in `build/previous/`.
