# M3a: Rules That Match, Silently — Implementation Plan

> **Execution:** validated-code-plus-independent-review (see Ruling 1). Each task is committed from code that was compiled, tested and mutation-checked before this plan was written, then reviewed against the **requirements below** — not against a reference implementation.

**Goal:** Let the user write rules and see, on real captured traffic, exactly which notifications each rule matches — before any rule is allowed to make a sound.

**Architecture:** The rule model, matcher, engine and file format are pure code in `NotificationCore`. The capture decision path moves out of an untested closure in `CaptureController` into a tested `CapturePipeline` in the core, and the engine attaches at its end. The app target only moves bytes (the rules file) and draws menus. A rule's only effect in M3a is an annotation on its Inspector row.

**Tech Stack:** Swift 5.9, Foundation, AppKit/SwiftUI (app target only), XCTest.

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md` — §4 architecture, §5.7 rule model, §5.10 engine, §5.11 matching semantics, §6 persistence, §7.2 Inspector, §7.3 authoring loop, §10 testing, §12 milestones.

## Global Constraints

- **Notification content is never written to disk, logged, or transmitted** (§2.1). Rules are user-authored patterns, not notification content, and may be persisted.
- `NotificationCore` imports no framework that needs a TCC grant, no UI framework, and references no file or network API. Enforced by `PurityTests`.
- Matching is **case- and diacritic-insensitive** throughout (§5.11).
- `matches` is **glob, not regex**: `*` and `?`, linear, cannot blow up (§5.11).
- **Array order is priority; the first enabled match wins**; a notification triggers at most one rule (§5.10).
- Rules file: `Application Support/…/rules.json`, **versioned** (§6).
- macOS 14.0 floor; `LSUIElement`.
- `swift build` / `swift test` need the sandbox override.

## Where M3a sits

M3 in the spec delivers the rule AST, engine, JSON store, visual builder, Tier 1 sound and speech, and the mute walkthrough. That is split three ways, as M2 was:

|         | Delivers                                                                                        | Why this order                                                                                                |
| ------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **M3a** | Rules that match, silently. Hand-written `rules.json`, Inspector annotations, dry run on reload | Every later part depends on it, and it lets rules be proven against real traffic before anything is audible   |
| **M3b** | The first alert you can hear — Tier 1 sound, and the mute walkthrough **with** it               | The spec requires mute to ship with the first sound, or the alert layers over the source app's own ping (§12) |
| **M3c** | The rule editor — visual builder, "Make a rule from this"                                       | Hand-written JSON covers the gap for a single technical user                                                  |

## Rulings made while writing this plan

**1. Code first, then plan, then independent review.** M2c's plan contained five defects in its reference code, each found only when an implementer built it or a reviewer ran it. This time every line was written, compiled and tested in a scratch worktree first; 161 tests pass and fourteen deliberate mutations — one per property worth protecting — were each caught by at least one test. With the code verified, re-dispatching implementers to transcribe it adds cost and transcription risk and buys no quality. Tasks are committed from the verified tree and each passes an independent review against the requirements here. _Cost if wrong:_ author and plan-writer are the same person, so the plan cannot catch the author's blind spots — which is exactly what the independent reviews are for.

**2. The rule AST contains only what can be evaluated today.** `and`, `or`, `not`, `field`. The spec's `timeWindow`, `onCall`, `screenLocked` and `frequencyAtLeast` arrive in M5 with the context that feeds them; `regex` arrives in M5 with its lint, subject cap and time budget. A condition over data the app does not yet collect would always evaluate against a placeholder — the reason `ContextSnapshot` omits `onCall`, applied one layer up.

**3. The rules file is written by hand in M3a, so its JSON is designed to be.** Custom `Codable`, not synthesised: synthesised output is positional (`"_0"`, `"_1"`) and silently broken by reordering associated values. The shape mirrors the M5 text language. `id` may be omitted; `enabled` may be omitted and defaults to **on**, because a rule someone wrote that silently does not run is the failure this app exists to prevent.

**4. One bad rule never silences the rest, and is never hidden.** A malformed rule is rejected and reported by name and position; the others load. Only a file that cannot be understood at all — not JSON, wrong shape, newer format — loads nothing, and says so. A newer format is refused outright rather than decoded with today's rules, which would produce misleading per-rule errors instead of the one true fact.

**5. Rules that decode but cannot mean what was written are rejected.** Empty `and` (would match everything), empty `or` (could never match), empty `contains`/`matches` value, unnamed rule. `equals ""` is allowed: it means "has no subtitle".

**6. The app never overwrites the rules file.** It writes exactly once, ever: creating a starter file when none exists, on explicit request, with `.withoutOverwriting` so the guarantee is the OS's. A damaged file is reported, never replaced — it is the only copy of the user's rules.

**7. A rules problem claims the warning glyph.** An on-call tool whose rules did not load is exactly as silent as one that cannot see banners (§7.1).

**8. A preview never rewrites history.** Reloading rules re-evaluates every retained row — the spec's dry run (§7.3) — but writes to a separate `preview` field, never `annotation`, and never updates the last-match record. From M3b `annotation` means _an alert sounded_; a row claiming "Matched X" for a notification that matched nothing on arrival would be a lie about what happened.

**9. "No rules loaded" is never shown as "matched no rule".** With nothing to evaluate against, a row is _not evaluated_. The spec calls matching nothing the most common confusion (§7.2); manufacturing it would be worse.

**10. Repeats never reach the rule engine.** Dedupe exists so one banner's animation does not produce several events. Evaluating each would, from M3b, sound one alert several times.

**11. Wording lives in the core.** Inspector row text is derived by pure, tested functions. Both of M2c's wording defects lived in untested UI code.

**12. The probe hides notification text unless asked.** It is a developer tool outside §2.1's letter, but its output is a terminal — scrolled back, pasted into reports, redirected to files. It was the one place content routinely left memory by default. `--show-content` restores it.

---

## File structure

| File                                               | Task | Responsibility                                                                     |
| -------------------------------------------------- | ---- | ---------------------------------------------------------------------------------- |
| `Sources/NotificationCore/Rule.swift`              | 1    | `Rule`, `RuleCondition`, `Field`, `Operator`, hand-editable JSON, the starter rule |
| `Sources/NotificationCore/RuleSetCodec.swift`      | 1    | File format, versioning, validation, `RuleStoreStatus`                             |
| `Sources/NotificationCore/Glob.swift`              | 2    | Anchored linear glob                                                               |
| `Sources/NotificationCore/RuleEngine.swift`        | 2    | Field access, `RuleEvaluator`, `RuleEngine`                                        |
| `Sources/NotificationCore/CapturePipeline.swift`   | 3, 4 | Every decision about a captured banner                                             |
| `Sources/NotificationCore/InspectorEntry.swift`    | 4    | `preview` field, `InspectorRowText`                                                |
| `Sources/NotificationCore/CaptureRingBuffer.swift` | 4    | `setPreview(id:_:)`                                                                |
| `Sources/SignalLadder/CaptureController.swift`     | 3    | Reduced to an adapter from the AX observer to the pipeline                         |
| `Sources/SignalLadder/RuleStore.swift`             | 5    | Reads the file; creates the starter file; never overwrites                         |
| `Sources/SignalLadder/AppDelegate.swift`           | 5    | Rules menu section, glyph, reload                                                  |
| `Sources/SignalLadder/InspectorView.swift`         | 5    | Outcome and preview lines                                                          |
| `Sources/signalladder-probe/main.swift`            | 6    | Content hidden by default                                                          |
| `docs/rules-format.md`                             | 7    | How to write rules by hand                                                         |

---

## Task 1: The rule model and its file format

**Files:** `Rule.swift`, `RuleSetCodec.swift`, `Tests/…/RuleSetCodecTests.swift`

**Produces:** `Rule(id:name:condition:isEnabled:)`, `RuleCondition` (`and`/`or`/`not`/`field`), `Field` (`app title subtitle body raw subrole`), `Operator` (`equals notEquals contains matches`), `Rule.editingExample`; `RuleSetCodec.decode(_:) throws -> (rules, problems)`, `.encode(_:)`, `.problems(in:)`, `.describe(_:)`, `.Problem`, `.FileError`; `RuleStoreStatus` with `load(_ data: Data?)`, `isProblem`, `summary`, `detail`.

**Required behaviour**

- File shape `{"version": 1, "rules": [...]}`; rule shape `{"id"?, "name", "enabled"?, "condition"}`; condition exactly one of `{"and": [...]}`, `{"or": [...]}`, `{"not": {...}}`, `{"field", "op", "value"}`. Two shapes in one object is an error naming "exactly one".
- Omitted `id` is minted; omitted `enabled` means on.
- Encoding is the readable shape, pretty-printed with sorted keys; never positional keys. Encode→decode is lossless.
- Version is checked before any rule is decoded. Newer → `unsupportedVersion`; missing or below 1 → `unreadable`.
- A rule that fails to decode or fails validation becomes a `Problem` carrying its index and — when recoverable — its name; the remaining rules still load.
- Problem text says where in the file the fault is (e.g. `condition.and[0]`) and names the missing key; syntax errors say "not valid JSON" with the parser's detail.
- `RuleStoreStatus`: no file is not a problem; counts separate enabled from disabled; partial load, unreadable and unsupported-version are problems; unreadable states "no rules are active" and gives the reason in `detail`.
- The starter rule loads cleanly as `.loaded(enabled: 0, disabled: 1)`.

**Tests that pin it:** `testAHandWrittenFileDecodes`, `testOmittedEnabledMeansOn`, `testOmittedIdIsMinted`, `testEncodingIsTheReadableShapeNotSynthesisedPositionalKeys`, `testEncodeThenDecodeIsLossless`, `testAMalformedRuleIsReportedAndTheOthersStillLoad`, `testAProblemSaysWhereInTheFileItWent`, `testAConditionWithTwoShapesIsRejectedAsAmbiguous`, `testEmptyGroupsAreRejectedBecauseTheyMatchEverythingOrNothing`, `testEmptyContainsOrMatchesIsRejectedButEmptyEqualsIsAllowed`, `testAnUnnamedRuleIsRejected`, `testAProblemBuriedInANestedGroupIsFound`, `testNotJSONIsUnreadableAndSaysWhere`, `testANewerFormatIsRefusedRatherThanMisread`, `testAMissingVersionIsUnreadable`, `testNoFileIsNotAProblem`, `testCountsSeparateEnabledFromDisabled`, `testEveryStateWhereSomethingWrittenIsNotInEffectIsAProblem`, `testAPartialLoadKeepsTheGoodRulesAndNamesTheBadOnesInTheDetail`, `testAnUnreadableFileSaysNoRulesAreActive`, `testTheStarterFileLoadsCleanlyAndActivatesNothing`

**Commit:** `feat: a rule format people can write by hand, and read back when it breaks`

---

## Task 2: Matching

**Files:** `Glob.swift`, `RuleEngine.swift`, `Tests/…/GlobTests.swift`, `Tests/…/RuleEngineTests.swift`

**Consumes:** Task 1's types. **Produces:** `Glob.matches(_:pattern:)`, `CapturedNotification.value(of:)`, `RuleEvaluator.matches(_:_:)`, `RuleEngine.firstMatch(for:in:)`.

**Required behaviour**

- Glob: `*` any run including none, `?` exactly one Character (grapheme, not UTF-16 unit), everything else literal; **anchored** to the whole string; case- and diacritic-insensitive; worst case O(n·m) — a pathological pattern against 5,000 characters finishes well under a second.
- `value(of:)` maps every `Field` case; adding a case without teaching it fails a test.
- `equals` is whole-string and case/diacritic-insensitive; `notEquals` is its exact complement; `contains` is case-insensitive substring (`localizedStandardContains`); `matches` is the glob.
- `and`/`or`/`not` compose. Empty groups keep their mathematical meaning in the evaluator (rejected at load instead).
- `firstMatch`: array order is priority, disabled rules are skipped, no match is `nil`.
- The spec's field-only worked examples (`#prod-* OR #incident-*`; `#alerts AND deploy`) behave as written.

**Tests that pin it:** all of `GlobTests` (8) and `RuleEngineTests` (13), including `testAPathologicalPatternFinishesQuickly`, `testEveryFieldReadsTheMatchingProperty`, `testNotEqualsIsTheExactComplementOfEquals`, `testArrayOrderIsPriorityAndTheFirstMatchWins`, `testDisabledRulesAreSkippedNotTreatedAsNonMatching`.

**Commit:** `feat: match rules against notifications, first enabled rule wins`

---

## Task 3: Move the capture decisions into the tested core

**Files:** `CapturePipeline.swift` (new), `CaptureController.swift`, `Tests/…/CapturePipelineTests.swift` (new)

**Produces:** `CapturePipeline(ownAppName:isSelfTest:history:dedupe:)`, `process(_:textChildren:) -> Outcome` (`.selfTest`, `.ownNotification`, `.suppressedRepeat`, `.recorded(matchedRule:)`), `captureCount`, `history`.

**This task is a move, not a change.** Every behaviour in `CaptureController`'s capture closure must survive intact and be pinned by a test before anything is added to it.

**Required behaviour**

- Order is: extract fields → self-test check → own-notification backstop → dedupe → record. Self-test and own notifications are neither recorded nor counted; the self-test is recognised from the text children when the description is empty.
- A self-test never enters the dedupe window: identical text arriving within 1.5s afterwards is recorded, not suppressed.
- A repeat lands on the row it duplicates, is not recorded again and is not counted; the pending-count fallback for an evicted row survives.
- `CaptureController` keeps its public surface (`captureCount`, `history`, `observerAttached`, `observerEventCount`, `onChange`, `onAttach`, `start`, `isRunning`) and becomes an adapter; `onChange` fires for recorded and suppressed outcomes, not for the app's own traffic.
- `isSelfTest` is injected, because `CanaryService` posts through UserNotifications and cannot live in the core.

**Tests that pin it:** `testADistinctCaptureIsRecordedAndCounted`, `testTheSelfTestIsNeitherRecordedNorCounted`, `testTheSelfTestIsFoundInTheChildrenWhenTheDescriptionIsEmpty`, `testTheAppsOwnAlarmIsNeitherRecordedNorCounted`, `testTheSelfTestNeverEntersTheDedupeWindow`, `testARepeatLandsOnTheRowItDuplicatesAndIsNotRecordedAgain`

**Commit:** `refactor: move every capture decision into the tested core`

---

## Task 4: Evaluate rules at capture, and preview them on reload

**Files:** `CapturePipeline.swift`, `InspectorEntry.swift`, `CaptureRingBuffer.swift`, both test files

**Consumes:** Tasks 2 and 3. **Produces:** `CapturePipeline.setRules(_:) -> Int`, `rules`, `lastMatch` (`LastMatch(ruleName:at:)`), `currentRuleMatchCount`; `InspectorEntry.preview`; `CaptureRingBuffer.setPreview(id:_:)`; `InspectorRowText.outcome(_:)` and `.preview(_:)`.

**Required behaviour**

- At capture: with no rules loaded the row is left **unannotated** (not evaluated); with rules loaded it is annotated with the first match's name, or with "matched nothing". A live match updates `lastMatch`.
- Repeats are never evaluated and never update `lastMatch` (Ruling 10).
- `setRules` replaces the rules and writes a **preview** onto every retained row; it never touches `annotation` and never updates `lastMatch` (Ruling 8). Clearing the rules clears the previews. Returns how many retained rows the new rules match.
- `currentRuleMatchCount` is the current rules' verdict on everything retained — preview where present, else the live annotation — and is zero with no rules, so annotations from rules that no longer exist are never counted.
- `InspectorRowText.outcome` distinguishes: not evaluated (no rules ever); arrived before any rules were loaded; matched _X_; matched no rule. `preview` is shown only when it differs from what happened, and a preview of nothing is stated, not omitted.

**Tests that pin it:** `testWithNoRulesARowIsNotEvaluatedRatherThanMatchingNothing`, `testAMatchingRuleAnnotatesTheRowAndBecomesTheLastMatch`, `testANonMatchingRowUnderLoadedRulesSaysItMatchedNothing`, `testRepeatsNeverReachTheRuleEngine`, `testNewRulesArePreviewedAgainstEveryRetainedRow`, `testAPreviewNeverRewritesWhatHappenedAtCapture`, `testAPreviewIsNeverReportedAsTheLastMatch`, `testClearingTheRulesClearsThePreviews`, `testCurrentRuleMatchCountCombinesPreviewsWithLiveMatches`, `testWithNoRulesLoadedOldMatchesAreNotCountedAsTheCurrentVerdict`, and the four `InspectorRowText` tests in `CaptureRingBufferTests`.

**Commit:** `feat: annotate captures with the matching rule, and dry-run new rules on reload`

---

## Task 5: The rules file, the menu and the Inspector row

**Files:** `RuleStore.swift` (new), `AppDelegate.swift`, `InspectorView.swift`

**Consumes:** Tasks 1 and 4.

**Required behaviour**

- `RuleStore` reads `~/Library/Application Support/com.jamiewhite.signalladder/rules.json` and hands the bytes to `RuleStoreStatus.load`. An existing but unopenable file is reported as unreadable — never as "no rules file".
- `createExampleIfMissing()` writes the starter file only when none exists, using `.withoutOverwriting` (Ruling 6).
- Rules load at launch. Menu gains, after "Show Inspector…": the status summary; each `detail` line indented; "Last match: _name_ at HH:mm" when there is one; "Current rules match _n_ of the last _m_" when rules and captures both exist; **Edit Rules File…** (⌘E — creates the starter if missing, opens it, falls back to revealing it, reloads; a creation failure is shown in an alert); **Reload Rules** (⌘R).
- The status glyph alarms on `health.isAlarming || ruleStore.status.isProblem` (Ruling 7).
- The Inspector row's outcome line comes from `InspectorRowText.outcome`; a separate line shows `InspectorRowText.preview` when present — never merged into the outcome.

**Tests:** none new — every decision this task displays is made in the core and tested there. The app layer is verified live in Task 7.

**Commit:** `feat: load rules from disk, surface their state, and show matches in the Inspector`

---

## Task 6: The probe hides notification text by default

**Files:** `Sources/signalladder-probe/main.swift`

**Required behaviour:** title, subtitle, body, raw text and the dedupe log line print as `<N characters>` or `(empty)` unless `--show-content` is passed; app name and subrole always print; startup says which mode is active and how to change it.

**Commit:** `fix: the probe no longer prints notification text unless asked`

---

## Task 7: Live verification and the rules-format document

**Files:** `docs/rules-format.md` (new), `Scripts/verify-live.sh`, `docs/dev/notes/2026-09-11-m1-findings.md`

- `docs/rules-format.md`: file location, the complete shape with one example per operator, the defaults, what each validation error means, and the dry-run workflow (edit → Reload Rules → read the Inspector).
- `verify-live.sh`: assert the menu shows a line beginning `Rules:` or `⚠︎ Rules`, and that **Reload Rules** is present.
- **Human checks** (they relaunch the app, so they need a person):
  - [ ] **Edit Rules File…** with no file creates the starter; menu shows `Rules: none active, 1 off`; glyph unchanged.
  - [ ] Enable a rule matching a notification already in the Inspector, **Reload Rules**: that row shows _Current rules would match …_; its outcome line is unchanged; the menu shows _Current rules match 1 of the last N_.
  - [ ] Post a matching notification: row shows _Matched …_; menu shows _Last match_.
  - [ ] Break the JSON, **Reload Rules**: warning glyph; menu names the fault; file untouched on disk.
  - [ ] Capture a real Teams @mention and record its **shape** (which field holds the channel, which holds the mention) in the findings note — structure only, never the message (§10.1). This decides how the user's first real rule is written.

**Commit:** `docs: how to write rules by hand` / `test: cover the rules menu in the live harness`

---

## Done when

- `swift test` passes at 161 tests; build has zero warnings.
- A rule written in `rules.json` annotates matching Inspector rows, and reloading previews it against every retained row without rewriting what happened.
- A damaged rules file is reported by name and position, claims the warning glyph, and is never overwritten.
- The probe prints no notification text by default.

## Not in this plan

Sound, speech and the mute walkthrough (M3b). The rule editor, "Make a rule from this" and the builder's dry-run UI (M3c). Context conditions and `regex` (M5). The two long-standing capture defects — `AXElementNode` conflating absent with failed, and dedupe keyed on content rather than element identity — remain open; the Inspector's suppressed-repeat count is still collecting the evidence the second one needs.

## Validation record

Built and tested in a scratch worktree before this plan was committed. 161 tests pass; zero build warnings. One compile error was caught that would otherwise have shipped: a default argument reading a main-actor static (`RuleStore.defaultFileURL`), now `nonisolated`.

Fourteen deliberate mutations, each breaking one property, were each caught by at least one test: glob loses its backtrack; glob stops anchoring; `equals` becomes case-sensitive; engine ignores `enabled`; last match wins instead of first; empty `and` accepted; newer format misread; malformed rule dropped silently; omitted `enabled` means off; self-test checked after dedupe; preview rewrites history; no rules shown as matched-nothing; preview reported as last match; repeats reach the engine.
