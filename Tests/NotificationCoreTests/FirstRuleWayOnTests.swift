import XCTest
@testable import NotificationCore

/// The Setup Guide's first-rule step after a rule made from a notification was saved switched
/// off, or with no sound (workflow audit, 2026-10-16, finding 15). The step was right that no
/// rule switched on makes a sound, and it offered only "Make a Rule from This…", which put a
/// second "New rule for <app>" into the draft beside the first. Now a press selects an
/// untouched rule already made from that app's banner instead of adding another, and while
/// there are rules the step offers "Edit Rules…" and says why, so the rule already made can
/// be switched on and given a sound. Banners with no app name are left as the documented
/// decision has them: the step says where the rule is made instead.
final class FirstRuleWayOnTests: XCTestCase {
    private let teams = CapturedNotification(timestamp: Date(timeIntervalSince1970: 0), appNameGuess: "Microsoft Teams",
                                             title: "#prod-alerts", subtitle: "", body: "down",
                                             rawText: "Microsoft Teams, #prod-alerts, down", subrole: "AXNotificationCenterBanner")

    private func facts(ruleStatus: RuleStoreStatus, apps: [String] = ["Microsoft Teams"]) -> SetupFacts {
        SetupFacts(accessibilityTrusted: true, notifications: .init(permission: .allowed, wouldDisplay: true), health: .verified,
                   lastVerifiedAt: nil, ruleStatus: ruleStatus, ruleReach: RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0),
                   rulesFileReadOnly: nil, anythingCaptured: true, capturedAppNames: apps, appsToMute: [],
                   muteChecklist: MuteChecklist(), loginItem: .off(wanted: false), progress: SetupProgress())
    }

    private func words(_ facts: SetupFacts) -> SetupText.StepWords {
        SetupText.words(for: .firstRule, facts: facts, time: { _ in "12:00" })
    }

    // MARK: - Making the rule again

    func testAPressSelectsAnUntouchedRuleAlreadyMadeFromThatAppsBanner() {
        let made = RuleSeed.rule(from: teams)
        let other = Rule(name: "Pager", condition: .field(.app, .equals, "PagerDuty"), isEnabled: true)
        XCTAssertEqual(RuleSeed.untouchedSeed(for: teams, in: [other, made]), made.id)
    }

    func testARuleChangedSinceItWasMadeIsNotTakenForAnotherPress() {
        var switchedOn = RuleSeed.rule(from: teams)
        switchedOn.isEnabled = true
        var withSound = RuleSeed.rule(from: teams)
        withSound.alert = .sound(name: "Glass", gainDB: 0)
        var renamed = RuleSeed.rule(from: teams)
        renamed.name = "Teams pages"
        for changed in [switchedOn, withSound, renamed] {
            XCTAssertNil(RuleSeed.untouchedSeed(for: teams, in: [changed]), "\(changed)")
        }
        XCTAssertNil(RuleSeed.untouchedSeed(for: teams, in: []))
    }

    // MARK: - The step's way on

    func testWithRulesAndNoneThatPagesTheStepOffersEditRulesAndSaysWhy() {
        for status in [RuleStoreStatus.loaded(enabled: 0, disabled: 1), .loaded(enabled: 1, disabled: 0),
                       .loadedWithProblems(enabled: 0, disabled: 1, rejected: [RuleSetCodec.Problem(index: 1, name: nil, reason: "x")])] {
            let shown = words(facts(ruleStatus: status))
            XCTAssertEqual(shown.buttons.map(\.action), [.makeRule, .editRules], "\(status)")
            XCTAssertEqual(shown.detail, [SetupText.appsReadLine(count: 1), SetupText.firstRuleHasRules], "\(status)")
        }
        XCTAssertEqual(SetupText.firstRuleHasRules,
                       "You have rules, and none is switched on and makes a sound or speaks. Choose Edit Rules… to switch one on "
                       + "and give it a sound, or make another.")
        XCTAssertEqual(SetupText.label(for: .editRules), StatusMenuText.editRulesTitle)
    }

    func testWithNoRulesTheStepIsAsItWas() {
        let shown = words(facts(ruleStatus: .noRulesFile))
        XCTAssertEqual(shown.buttons.map(\.action), [.makeRule])
        XCTAssertEqual(shown.detail, [SetupText.appsReadLine(count: 1)])
        XCTAssertEqual(words(facts(ruleStatus: .loaded(enabled: 0, disabled: 0))).buttons.map(\.action), [.makeRule], "an empty file")
    }

    /// The documented decision for banners with no app name stands: the step says where the
    /// rule is made instead. With rules, Edit Rules… is offered there too.
    func testBannersWithNoAppNameKeepTheirSentenceAndGainEditRulesOnlyWithRules() {
        let none = words(facts(ruleStatus: .noRulesFile, apps: []))
        XCTAssertEqual(none.buttons.map(\.action), [.checkAgain])
        XCTAssertEqual(none.detail, [SetupText.bannersWithoutNames])
        let some = words(facts(ruleStatus: .loaded(enabled: 0, disabled: 1), apps: []))
        XCTAssertEqual(some.buttons.map(\.action), [.checkAgain, .editRules])
        XCTAssertEqual(some.detail, [SetupText.bannersWithoutNames, SetupText.firstRuleHasRules])
    }
}

/// How the guide and the editor carry that out. The app target has no tests, so this reads
/// its sources.
final class FirstRuleWayOnWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file), "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testMakingARuleSelectsAnUntouchedOneBeforeAddingAnother() throws {
        let make = try XCTUnwrap(OnCallWiringTests.body(of: "func makeRule(from entry: InspectorEntry) {", in: try code("RuleEditorModel.swift")))
        XCTAssertEqual(make.trimmingCharacters(in: .whitespacesAndNewlines), [
            "source = entry.captured",
            "guard isEditable else { return }",
            "if let made = RuleSeed.untouchedSeed(for: entry.captured, in: rules) { return selection = made }",
            "let rule = RuleSeed.rule(from: entry.captured)",
            "rules.insert(rule, at: RuleSeed.insertionIndex(for: entry.captured, in: rules, sounds: sounds))",
            "selection = rule.id",
        ].joined(separator: "\n"))
    }

    func testEditRulesShowsTheRuleEditor() throws {
        let coordinator = try code("SetupCoordinator.swift")
        XCTAssertEqual(count("case .editRules:\nruleEditor.show()\nreturn nil", in: coordinator), 1)
    }
}
