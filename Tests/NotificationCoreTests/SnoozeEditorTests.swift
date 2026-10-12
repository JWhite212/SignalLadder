import XCTest
@testable import NotificationCore

/// The rule editor's box "Stay quiet while I have snoozed", and the caption
/// beneath it that says what it does for the rule on show (M5 plan, Task 4,
/// Rulings 3 and 12, O8; O14 is out, so no line about a rule that applies only
/// while on call). The caption is chosen by `EditorText` from the rule, so each
/// sentence, and which rules it is said of, is held here.
///
/// The app target has no tests, so the last tests read `LadderEditorView.swift`
/// and `RuleEditorModel.swift` as `SettingsWiringTests` reads its views, and
/// hold the places that carry the box and its caption out to what the core
/// decided. Fixtures are invented text, never captured content (§10.1).
final class SnoozeEditorTests: XCTestCase {
    private let glass = AlertAction.sound(name: "Glass", gainDB: 0)
    private let speech = SpeechAction(voiceIdentifier: "com.apple.voice.compact.en-GB.Daniel")
    private let page = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    private func rule(alert: AlertAction? = .sound(name: "Glass", gainDB: 0), _ escalation: Escalation? = nil,
                      ticked: Bool, enabled: Bool = true) -> Rule {
        Rule(name: "Pager", condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled,
             alert: alert, escalation: escalation, quietWhenSnoozed: ticked)
    }

    private func caption(_ rule: Rule) -> String { EditorText.snoozeCaption(for: rule) }

    /// A ladder at each step of its shape that is not a Shortcut, so that nothing
    /// is said of a Shortcut for want of one and not for want of a ladder.
    private var laddersWithoutAShortcut: [Escalation?] {
        [nil, Escalation(), Escalation(tier2: PanelAlert()), Escalation(tier3: RepeatAlert(action: glass)),
         Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass), tier4: FinalAlert(action: .alert(glass)))]
    }

    // MARK: - A rule whose last step is a Shortcut

    func testTheCaptionSaysTheBoxDoesNothingAndThePageStillGoesWhileTheLadderHasAShortcutAndNamesIt() {
        let ladders = [Escalation(tier4: page),
                       Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass), tier4: page)]
        for ticked in [true, false] {
            for ladder in ladders {
                let said = caption(rule(ladder, ticked: ticked))
                let context = "ticked \(ticked), \(String(describing: ladder))"
                XCTAssertTrue(said.contains("A snooze never holds a rule that runs a Shortcut, so “Page me” still runs."),
                              "\(context): \(said)")
                XCTAssertTrue(said.contains("This box does nothing while tier 4 is a Shortcut."), "\(context): \(said)")
                // The rule is not held, so nothing is said of what is held.
                XCTAssertFalse(said.contains(EditorText.snoozeHoldsWholeRule), context)
                XCTAssertFalse(said.contains(EditorText.snoozeWouldHoldWholeRule), context)
                XCTAssertFalse(said.contains(EditorText.snoozeNeverTouchesRunning), context)
            }
        }
        let other = caption(rule(Escalation(tier4: FinalAlert(action: .shortcut(name: "Wake the on-call phone"))),
                                 ticked: true))
        XCTAssertTrue(other.contains("“Wake the on-call phone” still runs"), "it names the Shortcut the rule has: \(other)")
        XCTAssertFalse(other.contains("Page me"))
    }

    func testTheTickIsSaidToBeKeptOnlyWhileTheBoxIsTickedAndAShortcutIsThere() {
        let kept = "Your tick is kept if you take the Shortcut away."
        XCTAssertTrue(caption(rule(Escalation(tier4: page), ticked: true)).contains(kept))
        XCTAssertFalse(caption(rule(Escalation(tier4: page), ticked: false)).contains("kept"),
                       "there is no tick to keep")
        for ladder in laddersWithoutAShortcut {
            XCTAssertFalse(caption(rule(ladder, ticked: true)).contains("kept"), "no Shortcut, nothing to take away")
        }
    }

    func testTheCaptionSaysNothingOfAShortcutWhenThereIsNone() {
        for ticked in [true, false] {
            for alert in [nil, .silent, glass, .speak(speech)] as [AlertAction?] {
                for ladder in laddersWithoutAShortcut {
                    let said = caption(rule(alert: alert, ladder, ticked: ticked))
                    XCTAssertFalse(said.contains("Shortcut"),
                                   "ticked \(ticked), \(String(describing: alert)), \(String(describing: ladder)): \(said)")
                    XCTAssertFalse(said.contains("tier 4"), said)
                }
            }
        }
    }

    func testAShortcutWithNoNameIsStillAShortcutAndIsNotQuotedAsEmpty() {
        // A Shortcut with no name is one to a snooze, the safe direction, so the
        // box still does nothing; no empty quotation marks stand in for a name.
        for name in ["", "   ", "\n"] {
            for ticked in [true, false] {
                let said = caption(rule(Escalation(tier4: FinalAlert(action: .shortcut(name: name))), ticked: ticked))
                XCTAssertTrue(said.contains("A snooze never holds a rule that runs a Shortcut, even one that has no name yet."),
                              "\(String(reflecting: name)): \(said)")
                XCTAssertTrue(said.contains("This box does nothing while tier 4 is a Shortcut."), said)
                XCTAssertFalse(said.contains("“"), "no name to quote: \(said)")
                XCTAssertFalse(said.contains("still runs"), "a Shortcut with no name is not said to run: \(said)")
            }
        }
    }

    // MARK: - A rule that makes no sound

    func testARuleThatMakesNoSoundIsSaidToBeNeverHeldWhateverItsBoxSays() {
        let silent = "This rule makes no sound, so a snooze never holds it: this box does nothing to it, "
            + "and whatever else it does still happens."
        XCTAssertEqual(EditorText.snoozeNeverHoldsSilentRule, silent)
        let shapes: [(alert: AlertAction?, ladder: Escalation?)] = [
            (nil, nil), (.silent, nil), (.silent, Escalation(tier2: PanelAlert())),
            (nil, Escalation(tier2: PanelAlert())), (.silent, Escalation(tier3: RepeatAlert(action: .silent))),
        ]
        for ticked in [true, false] {
            for shape in shapes {
                let said = caption(rule(alert: shape.alert, shape.ladder, ticked: ticked))
                XCTAssertEqual(said, silent, "ticked \(ticked), \(String(describing: shape))")
            }
        }
    }

    func testARuleThatSoundsOnALaterTierAloneIsOneThatMakesASound() {
        for ladder in [Escalation(tier3: RepeatAlert(action: glass)),
                       Escalation(tier4: FinalAlert(action: .alert(.speak(speech))))] {
            let said = caption(rule(alert: .silent, ladder, ticked: true))
            XCTAssertFalse(said.contains("makes no sound"), said)
            XCTAssertTrue(said.contains(EditorText.snoozeHoldsWholeRule), said)
        }
    }

    func testARuleSwitchedOffIsSaidToDoWhatItWouldDoSwitchedOnAndNotToMakeNoSound() {
        // A rule that is off makes no noise, but has not stopped being one that
        // would: the editor's own line says it is off, and this says what the box
        // would do.
        let off = caption(rule(ticked: true, enabled: false))
        XCTAssertEqual(off, caption(rule(ticked: true, enabled: true)))
        XCTAssertFalse(off.contains("makes no sound"))
        XCTAssertEqual(caption(rule(alert: .silent, ticked: false, enabled: false)), EditorText.snoozeNeverHoldsSilentRule,
                       "a rule that is off and silent is silent")
        XCTAssertTrue(caption(rule(Escalation(tier4: page), ticked: false, enabled: false)).contains("“Page me” still runs"))
    }

    func testARuleThatMakesNoSoundAndRunsAShortcutIsToldBothAndEachIsTrueOnItsOwn() {
        for ticked in [true, false] {
            let said = caption(rule(alert: .silent, Escalation(tier4: page), ticked: ticked))
            XCTAssertEqual(said, EditorText.snoozeNeverHoldsSilentRule + " "
                           + EditorText.snoozeNeverHoldsShortcutRule(shortcutName: "Page me", ticked: ticked),
                           "ticked \(ticked)")
            XCTAssertTrue(said.contains("makes no sound"))
            XCTAssertTrue(said.contains("“Page me” still runs"))
        }
    }

    // MARK: - A rule a snooze may hold

    func testTheWholeRuleSentenceIsSaidForATickedRuleASnoozeMayHoldAndSaysTheLadderIsHeldToo() {
        XCTAssertEqual(EditorText.snoozeHoldsWholeRule,
                       "While snoozed, nothing this rule does will start: no sound, no panel and no escalation.")
        for alert in [glass, .speak(speech)] {
            for ladder in laddersWithoutAShortcut {
                let made = rule(alert: alert, ladder, ticked: true)
                XCTAssertTrue(made.snoozeMayHold, "a rule a snooze may hold")
                XCTAssertEqual(caption(made), EditorText.snoozeHoldsWholeRule + " " + EditorText.snoozeNeverTouchesRunning,
                               "\(alert), \(String(describing: ladder))")
            }
        }
        let said = caption(rule(ticked: true))
        for part in ["no sound", "no panel", "no escalation"] { XCTAssertTrue(said.contains(part), part) }
    }

    func testAnUntickedRuleASnoozeCouldHoldIsToldWhatTickingWouldDoAndNotThatItIsHeld() {
        XCTAssertEqual(EditorText.snoozeWouldHoldWholeRule,
                       "If you tick this, then while snoozed nothing this rule does will start: "
                       + "no sound, no panel and no escalation.")
        for ladder in laddersWithoutAShortcut {
            let made = rule(ladder, ticked: false)
            XCTAssertFalse(made.snoozeMayHold, "it is not ticked")
            let said = caption(made)
            XCTAssertEqual(said, EditorText.snoozeWouldHoldWholeRule + " " + EditorText.snoozeNeverTouchesRunning,
                           String(describing: ladder))
            XCTAssertFalse(said.contains(EditorText.snoozeHoldsWholeRule),
                           "nothing is held until the box is ticked, and the caption does not say it is")
        }
    }

    func testASnoozeNeverTouchingAnAlertAlreadyEscalatingIsSaidWhereTheBoxCanHoldARuleAndNowhereElse() {
        XCTAssertEqual(EditorText.snoozeNeverTouchesRunning, "A snooze never touches an alert that is already escalating.")
        for ticked in [true, false] {
            for ladder in laddersWithoutAShortcut {
                XCTAssertTrue(caption(rule(ladder, ticked: ticked)).hasSuffix(EditorText.snoozeNeverTouchesRunning))
            }
            // Where the box does nothing there is nothing for it to leave alone.
            for ladder in [nil, Escalation(), Escalation(tier2: PanelAlert())] as [Escalation?] {
                XCTAssertFalse(caption(rule(alert: .silent, ladder, ticked: ticked)).contains("escalating"),
                               "a rule that makes no sound")
            }
            XCTAssertFalse(caption(rule(Escalation(tier4: page), ticked: ticked)).contains("escalating"),
                           "a rule that runs a Shortcut")
        }
    }

    // MARK: - Every shape of rule

    /// The caption does not say a rule is held that the pipeline would not hold.
    /// The rule's own `snoozeMayHold` is the oracle, so that a change to what a
    /// snooze may hold that leaves the editor behind fails here, and the grid is
    /// every combination of the facts the rule's decision reads.
    func testTheCaptionSaysAWholeRuleIsHeldExactlyWhenTheRuleItselfSaysASnoozeMayHoldIt() {
        let alerts: [AlertAction?] = [nil, .silent, glass, .speak(speech), .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: speech)]
        let ladders: [Escalation?] = [nil, Escalation(), Escalation(tier2: PanelAlert()),
                                      Escalation(tier3: RepeatAlert(action: .silent)),
                                      Escalation(tier3: RepeatAlert(action: glass)),
                                      Escalation(tier4: FinalAlert(action: .alert(.silent))),
                                      Escalation(tier4: FinalAlert(action: .alert(glass))),
                                      Escalation(tier4: page), Escalation(tier4: FinalAlert(action: .shortcut(name: ""))),
                                      Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass), tier4: page)]
        var held = 0, notHeld = 0
        for alert in alerts {
            for ladder in ladders {
                let context = "\(String(describing: alert)), \(String(describing: ladder))"

                let ticked = rule(alert: alert, ladder, ticked: true)
                let saidTicked = caption(ticked)
                XCTAssertFalse(saidTicked.isEmpty, context)
                XCTAssertEqual(saidTicked.contains(EditorText.snoozeHoldsWholeRule), ticked.snoozeMayHold, "ticked, \(context)")
                XCTAssertFalse(saidTicked.contains(EditorText.snoozeWouldHoldWholeRule), "ticked, \(context)")

                // Ticking it is what would make it so, and an unticked rule is told so.
                let unticked = rule(alert: alert, ladder, ticked: false)
                let saidUnticked = caption(unticked)
                XCTAssertFalse(saidUnticked.isEmpty, context)
                XCTAssertEqual(saidUnticked.contains(EditorText.snoozeWouldHoldWholeRule), ticked.snoozeMayHold,
                               "unticked, \(context)")
                XCTAssertFalse(saidUnticked.contains(EditorText.snoozeHoldsWholeRule), "unticked, \(context)")

                // And whether it makes a sound and whether it runs a Shortcut are each said as they are.
                let silent = !alertsAloudSwitchedOn(ticked)
                XCTAssertEqual(saidTicked.contains("makes no sound"), silent, "ticked, \(context)")
                XCTAssertEqual(saidTicked.contains("A snooze never holds a rule that runs a Shortcut"),
                               ladder?.tier4?.action.shortcutName != nil, "ticked, \(context)")
                if ticked.snoozeMayHold { held += 1 } else { notHeld += 1 }
            }
        }
        XCTAssertGreaterThan(held, 0, "the grid holds rules that are held")
        XCTAssertGreaterThan(notHeld, 0, "and rules that are not")
    }

    private func alertsAloudSwitchedOn(_ rule: Rule) -> Bool {
        var on = rule
        on.isEnabled = true
        return on.alertsAloud
    }

    func testTheCaptionIsTheSameWhetherOrNotARuleIsSwitchedOnForEveryShapeOfRule() {
        for ticked in [true, false] {
            for ladder in laddersWithoutAShortcut + [Escalation(tier4: page)] {
                for alert in [nil, .silent, glass] as [AlertAction?] {
                    XCTAssertEqual(caption(rule(alert: alert, ladder, ticked: ticked, enabled: true)),
                                   caption(rule(alert: alert, ladder, ticked: ticked, enabled: false)))
                }
            }
        }
    }

    // MARK: - What the caption holds

    func testTheCaptionQuotesNothingOfTheRuleButAShortcutsNameAndNothingANotificationSaid() {
        let canary = "ZQXCANARYFRAGMENT"
        let made = Rule(name: "Pager \(canary)", condition: .field(.body, .contains, canary),
                        alert: .soundAndSpeak(soundName: "Glass", soundGainDB: 0,
                                              speech: SpeechAction(voiceIdentifier: canary, template: "{body} \(canary)")),
                        escalation: Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass)),
                        quietWhenSnoozed: true)
        var unticked = made
        unticked.quietWhenSnoozed = false
        var noAlert = made
        noAlert.alert = nil
        for variant in [made, unticked, noAlert] {
            XCTAssertFalse(caption(variant).contains(canary))
            XCTAssertFalse(caption(variant).contains("Glass"), "no sound is named")
            XCTAssertFalse(caption(variant).contains("Pager"), "no rule is named")
        }
        // The one name it quotes is the Shortcut's, which the user typed.
        var withShortcut = made
        withShortcut.escalation = Escalation(tier4: FinalAlert(action: .shortcut(name: "Page me")))
        XCTAssertTrue(caption(withShortcut).contains("“Page me”"))
        XCTAssertFalse(caption(withShortcut).contains(canary))
    }

    func testTheSnoozeBoxIsAnnouncedInTheWordsOfItsVisibleLabelAndNotAsATier() {
        XCTAssertEqual(EditorText.label(.snoozeSwitch), SnoozeText.ruleSwitchLabel)
        XCTAssertFalse(EditorText.label(.snoozeSwitch).hasPrefix("Tier"))
        let others = EditorText.Control.allCases.filter { $0 != .snoozeSwitch }.map(EditorText.label)
        XCTAssertFalse(others.contains(EditorText.label(.snoozeSwitch)), "no other control is announced alike")
    }

    // MARK: - The view and the model, read as source

    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func position(of needle: String, in text: String) throws -> String.Index {
        try XCTUnwrap(text.range(of: needle), "\(needle) is not there").lowerBound
    }

    /// The box is bound to the rule's own flag, labelled with the core's words, and
    /// followed by the core's caption of the same rule, after the ladder's own
    /// controls. It is never disabled, in its own body or by anything after it in the
    /// editor's: a box that does nothing for a rule is still kept, which the caption
    /// says.
    func testTheLadderEditorShowsTheBoxBoundToTheRulesFlagAndTheCaptionOfThatRuleAfterTheLadder() throws {
        let view = try code("LadderEditorView.swift")
        XCTAssertEqual(count("Toggle(isOn: $rule.quietWhenSnoozed) {", in: view), 1)
        XCTAssertEqual(count("Text(SnoozeText.ruleSwitchLabel)", in: view), 1)
        XCTAssertEqual(count(".accessibilityLabel(EditorText.label(.snoozeSwitch))", in: view), 1)
        XCTAssertEqual(count("Text(EditorText.snoozeCaption(for: rule))", in: view), 1)

        let box = try XCTUnwrap(OnCallWiringTests.body(of: "private var snoozeSwitch: some View {", in: view))
        let inBox = try ["Toggle(isOn: $rule.quietWhenSnoozed)", "Text(SnoozeText.ruleSwitchLabel)",
                         ".accessibilityLabel(EditorText.label(.snoozeSwitch))", "Text(EditorText.snoozeCaption(for: rule))"]
            .map { try position(of: $0, in: box) }
        XCTAssertEqual(inBox, inBox.sorted(), "the box, its label, then its caption")
        XCTAssertFalse(box.contains(".disabled("), "the box can be ticked while it does nothing, and the caption says so")

        // Shown once, as a line of its own after the ladder's last control, Customise,
        // and made once.
        let editor = try XCTUnwrap(OnCallWiringTests.body(of: "struct LadderEditorView: View {", in: view))
        XCTAssertEqual(editor.components(separatedBy: "\n").filter { $0 == "snoozeSwitch" }.count, 1,
                       "shown once, a line of its own")
        XCTAssertEqual(count("private var snoozeSwitch: some View {", in: editor), 1)
        XCTAssertLessThan(try position(of: "DisclosureGroup(isExpanded: $customiseOpen)", in: editor),
                          try position(of: "\nsnoozeSwitch\n", in: editor), "it follows the ladder, Customise included")
        XCTAssertLessThan(try position(of: "\nsnoozeSwitch\n", in: editor),
                          try position(of: "private var snoozeSwitch: some View {", in: editor),
                          "and is shown in the body, where it is used")

        // Nor is it disabled from outside its own body. From the line that shows the
        // box to the end of `body` lie whatever is chained to it, whatever wraps it
        // and whatever is chained to the stack that holds it, and none of it may
        // disable. The controls above it are disabled by `usable`, and the box does
        // not follow them: a tick that cannot be taken off holds the rule in a snooze.
        let shown = try XCTUnwrap(OnCallWiringTests.body(of: "var body: some View {", in: editor),
                                  "body is in the editor exactly once, and is closed")
        let fromBox = try XCTUnwrap(shown.range(of: "\nsnoozeSwitch\n"), "the box is shown in body")
        XCTAssertFalse(shown[fromBox.lowerBound...].contains(".disabled("),
                       "nothing after the box in body disables it, chained to it, round it or on its stack")
    }

    /// No preset and no control of the ladder writes the flag (Ruling 3): in the
    /// app target one place names it, the box. What the controls produce carries
    /// the ladder alone, which `EscalationEditingTests` holds.
    func testTheFlagIsNamedInTheAppTargetByTheBoxAlone() throws {
        var found: [String: Int] = [:]
        for file in try AppSources.fileNames() {
            let n = count("quietWhenSnoozed", in: try code(file))
            if n > 0 { found[file] = n }
        }
        XCTAssertEqual(found, ["LadderEditorView.swift": 1])
    }

    /// A duplicate is the rule copied whole, so the flag goes with the rest of it:
    /// it changes the id, the name and the switch, and nothing else.
    func testADuplicateOfARuleKeepsItsBoxBecauseItIsACopyOfTheWholeRule() throws {
        let model = try code("RuleEditorModel.swift")
        let duplicate = try XCTUnwrap(OnCallWiringTests.body(of: "func duplicate(_ id: Rule.ID) {", in: model))
        XCTAssertEqual(duplicate.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, [
            "guard let index = rules.firstIndex(where: { $0.id == id }) else { return }",
            "var copy = rules[index]",
            "copy.id = UUID()",
            "copy.name += \" (copy)\"",
            "copy.isEnabled = false",
            "rules.insert(copy, at: index + 1)",
            "selection = copy.id",
        ])
    }
}
