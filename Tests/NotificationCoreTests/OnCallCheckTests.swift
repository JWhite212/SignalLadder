import AppKit
import XCTest
@testable import NotificationCore

/// What the on-call check says, finding by finding (M5 plan, Ruling 9). The
/// inputs are plain values, so each finding is reached from the one fact that
/// makes it, with every other fact at rest. Fixtures are invented text, never
/// captured content (§10.1), and nothing here reads the Mac.
final class OnCallCheckTests: XCTestCase {
    typealias Kind = OnCallCheck.Finding.Kind

    /// Every fact at rest: capture verified, nothing muted, Alert volume up, one
    /// rule in effect that makes a sound, nothing refused or warned about, and
    /// nothing said of the login item. What is left to say is the two standing
    /// advisories.
    private func inputs(health: CaptureHealth = .verified,
                        apps: [String] = [],
                        outputSilent: Bool = false,
                        alertVolume: Double? = 1,
                        reach: RuleReach = RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0),
                        status: RuleStoreStatus = .loaded(enabled: 1, disabled: 0),
                        warnings: [RuleWarning] = [],
                        startsAtLogin: Bool? = nil,
                        byHand: Bool? = nil) -> OnCallCheck.Inputs {
        OnCallCheck.Inputs(health: health, unconfirmedMutedApps: apps, outputSilent: outputSilent,
                           alertVolume: alertVolume, reach: reach, ruleStatus: status, shortcutWarnings: warnings,
                           startsAtLogin: startsAtLogin, loginItemByHand: byHand)
    }

    private func kinds(_ inputs: OnCallCheck.Inputs) -> [Kind] {
        OnCallCheck.findings(inputs).map(\.kind)
    }

    private func finding(_ kind: Kind, in inputs: OnCallCheck.Inputs) -> OnCallCheck.Finding? {
        OnCallCheck.findings(inputs).first { $0.kind == kind }
    }

    private func problem(_ index: Int, _ name: String?) -> RuleSetCodec.Problem {
        RuleSetCodec.Problem(index: index, name: name, reason: "its sound file is gone")
    }

    // MARK: - At rest

    func testWithEveryFactAtRestOnlyTheTwoStandingAdvisoriesAreLeftAndNeitherIsUrgent() {
        let found = OnCallCheck.findings(inputs())
        XCTAssertEqual(found.map(\.kind), [.focus, .sleep])
        XCTAssertFalse(found.contains(where: \.isUrgent))
        XCTAssertFalse(OnCallCheck.shouldOpenWindow(found))
    }

    // MARK: - Health

    func testVerifiedHealthIsNotAFinding() {
        XCTAssertNil(finding(.health, in: inputs(health: .verified)))
        XCTAssertNil(finding(.notVerifiedYet, in: inputs(health: .verified)))
    }

    /// Unknown is a finding and urgent: the check is asking whether the app is
    /// ready, and one that has verified nothing is not. When switching on starts
    /// a self-test and one is already in flight, it would otherwise say nothing at
    /// the one moment the user says they are on call (Ruling 9).
    func testCaptureThatHasNotBeenVerifiedYetIsAnUrgentFinding() throws {
        let unknown = try XCTUnwrap(finding(.notVerifiedYet, in: inputs(health: .unknown)))
        XCTAssertTrue(unknown.isUrgent)
        XCTAssertEqual(unknown.text, OnCallText.notVerifiedYet)
        XCTAssertEqual(OnCallText.notVerifiedYet, "Capture has not been verified yet")
        XCTAssertNil(finding(.health, in: inputs(health: .unknown)), "unknown is not a cause with advice")
    }

    func testADegradedOrBlindHealthIsUrgentAndSaysItsFirstCausesAdvice() throws {
        let degraded = try XCTUnwrap(finding(.health, in: inputs(health: .degraded([.ownAlertsNotShown, .selfTestInconclusive]))))
        XCTAssertTrue(degraded.isUrgent)
        XCTAssertEqual(degraded.text, HealthCause.ownAlertsNotShown.advice)

        let blind = try XCTUnwrap(finding(.health, in: inputs(health: .blind([.accessibilityNotTrusted, .observerNotAttached]))))
        XCTAssertTrue(blind.isUrgent)
        XCTAssertEqual(blind.text, HealthCause.accessibilityNotTrusted.advice)
    }

    func testAHealthWithNoCauseStillSaysSomething() throws {
        let none = try XCTUnwrap(finding(.health, in: inputs(health: .blind([]))))
        XCTAssertEqual(none.text, SelfNotification.fallbackBody)
        XCTAssertFalse(none.text.isEmpty)
    }

    func testHealthComesFirst() {
        let all = inputs(health: .blind([.accessibilityNotTrusted]), apps: ["Teams"], outputSilent: true, alertVolume: 0,
                         status: .unreadable("x"), startsAtLogin: false)
        XCTAssertEqual(kinds(all).first, .health)
    }

    // MARK: - The output and the beeps

    func testAMutedOutputIsAFindingOnlyWhenARuleSounds() throws {
        let sounding = RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0)
        let silentRules = RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 0)

        let muted = try XCTUnwrap(finding(.outputMuted, in: inputs(outputSilent: true, reach: sounding)))
        XCTAssertTrue(muted.isUrgent)
        XCTAssertEqual(muted.text, AlertMenuText.outputSilentSentence)
        XCTAssertNil(finding(.outputMuted, in: inputs(outputSilent: true, reach: silentRules)),
                     "silence is what a user with no sounding rule has chosen")
        XCTAssertNil(finding(.outputMuted, in: inputs(outputSilent: false, reach: sounding)), "an audible output")
    }

    /// The window's sentence and the menu's own warning are one sentence, written
    /// once, the menu's carrying its mark.
    func testTheMutedOutputSentenceIsTheMenusOwnWithoutItsMark() {
        XCTAssertEqual(AlertMenuText.outputSilentWarning, "⚠︎ " + AlertMenuText.outputSilentSentence)
        XCTAssertEqual(AlertMenuText.outputSilentSentence,
                       "Sound output is muted or at zero volume — alerts will not be heard")
    }

    /// The beeps are the app's own channel and not a rule's, so the finding does
    /// not wait for a rule that sounds.
    func testAnAlertVolumeAtZeroIsAnUrgentFindingWhetherOrNotARuleSounds() throws {
        for reach in [RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0),
                      RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 0),
                      RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0)] {
            for volume in [0, 0.01, -1] as [Double] {
                let beeps = try XCTUnwrap(finding(.beepsInaudible, in: inputs(alertVolume: volume, reach: reach)),
                                          "\(volume) with \(reach)")
                XCTAssertTrue(beeps.isUrgent)
                XCTAssertEqual(beeps.text, OnCallText.beepsInaudible)
            }
            for volume in [0.02, 0.5, 1, nil] as [Double?] {
                XCTAssertNil(finding(.beepsInaudible, in: inputs(alertVolume: volume, reach: reach)),
                             "\(String(describing: volume)) with \(reach)")
            }
        }
    }

    func testTheBeepsFindingSaysTheyFollowAlertVolumeNotTheOutputVolume() {
        XCTAssertTrue(OnCallText.beepsInaudible.contains("Alert volume"))
        XCTAssertTrue(OnCallText.beepsInaudible.contains("System Settings › Sound"))
        XCTAssertTrue(OnCallText.beepsInaudible.contains("not the output volume"))
    }

    // MARK: - The rules

    func testRulesThatAreNotInEffectAreOneUrgentFindingWithACountAndNoName() throws {
        let one = inputs(status: .loadedWithProblems(enabled: 1, disabled: 0, rejected: [problem(0, "Pager")]))
        let found = try XCTUnwrap(finding(.rulesNotInEffect, in: one))
        XCTAssertTrue(found.isUrgent)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.text, "1 rule is not in effect, so it will not alert you")

        let three = inputs(status: .loadedWithProblems(enabled: 1, disabled: 0,
                                                       rejected: [problem(0, "A"), problem(1, nil), problem(4, "C")]))
        let many = try XCTUnwrap(finding(.rulesNotInEffect, in: three))
        XCTAssertEqual(many.count, 3)
        XCTAssertEqual(many.text, "3 rules are not in effect, so they will not alert you")
    }

    func testAnUnreadableFileAndOneWrittenByANewerBuildEachSayThatNoRulesAreInEffect() throws {
        let unreadable = try XCTUnwrap(finding(.rulesFileNotInEffect, in: inputs(status: .unreadable("denied"))))
        let newer = try XCTUnwrap(finding(.rulesFileNotInEffect, in: inputs(status: .unsupportedVersion(9))))
        for found in [unreadable, newer] {
            XCTAssertTrue(found.isUrgent)
            XCTAssertTrue(found.text.hasPrefix("No rules are in effect"), found.text)
            XCTAssertNil(found.count)
        }
        XCTAssertNotEqual(unreadable.text, newer.text, "each says why")
        // The reason a file could not be read can hold a path, and the version is a
        // number nobody needs: neither is in the finding.
        XCTAssertFalse(unreadable.text.contains("denied"))
        XCTAssertFalse(newer.text.contains("9"))
        XCTAssertNil(finding(.rulesNotInEffect, in: inputs(status: .unreadable("denied"))))
    }

    func testRulesInEffectWithNothingRefusedAreNoFinding() {
        for status in [RuleStoreStatus.loaded(enabled: 2, disabled: 1), .loaded(enabled: 1, disabled: 0)] {
            XCTAssertNil(finding(.rulesNotInEffect, in: inputs(status: status)))
            XCTAssertNil(finding(.rulesFileNotInEffect, in: inputs(status: status)))
        }
    }

    /// With no file, an empty one or every rule off, switching on would otherwise
    /// say nothing, which is the plainest way to be on call and miss every page.
    func testNoRuleEnabledIsUrgentForNoFileAnEmptyFileAndEveryRuleOff() throws {
        let none = RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0)
        for status in [RuleStoreStatus.noRulesFile, .loaded(enabled: 0, disabled: 0), .loaded(enabled: 0, disabled: 3)] {
            let found = try XCTUnwrap(finding(.noRuleEnabled, in: inputs(reach: none, status: status)), "\(status)")
            XCTAssertTrue(found.isUrgent)
            XCTAssertEqual(found.text, "No rule is enabled, so nothing will alert you")
        }
    }

    /// A refused rule is the finding before it, so this never repeats it; and a
    /// file that is not in effect has its own.
    func testNoRuleEnabledIsAbsentWhenAnEnabledRuleIsInEffectOrARuleWasRefusedOrTheFileIsNotInEffect() {
        let some = RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0)
        let none = RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0)
        XCTAssertNil(finding(.noRuleEnabled, in: inputs(reach: some, status: .loaded(enabled: 1, disabled: 0))))
        XCTAssertNil(finding(.noRuleEnabled, in: inputs(reach: some,
                                                        status: .loadedWithProblems(enabled: 1, disabled: 0, rejected: [problem(0, nil)]))))
        XCTAssertNil(finding(.noRuleEnabled, in: inputs(reach: none,
                                                        status: .loadedWithProblems(enabled: 0, disabled: 0, rejected: [problem(0, nil)]))),
                     "every rule was refused: that is the finding about refused rules")
        XCTAssertNil(finding(.noRuleEnabled, in: inputs(reach: none, status: .unreadable("x"))))
        XCTAssertNil(finding(.noRuleEnabled, in: inputs(reach: none, status: .unsupportedVersion(9))))
    }

    func testTheAdvisoryThatNoRuleMakesASoundOrRunsAShortcutIsForASilentPanelRuleAlone() throws {
        let silentPanel = RuleReach(enabled: 2, alertingAloud: 0, withShortcut: 0)
        let found = try XCTUnwrap(finding(.noSoundOrShortcut, in: inputs(reach: silentPanel)))
        XCTAssertFalse(found.isUrgent)
        XCTAssertEqual(found.text, "No enabled rule makes a sound or runs a Shortcut, so a match will only show the panel")

        XCTAssertNil(finding(.noSoundOrShortcut, in: inputs(reach: RuleReach(enabled: 2, alertingAloud: 1, withShortcut: 0))),
                     "a rule that sounds")
        XCTAssertNil(finding(.noSoundOrShortcut, in: inputs(reach: RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 1))),
                     "a rule whose last step is a Shortcut")
        XCTAssertNil(finding(.noSoundOrShortcut, in: inputs(reach: RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0))),
                     "no rule is enabled, which is its own finding")
    }

    func testRuleReachCountsEnabledRulesThatSoundAndThatEndInAShortcut() {
        func rule(enabled: Bool, alert: AlertAction?, tier4: FinalAction? = nil) -> Rule {
            Rule(name: "A", condition: .field(.app, .equals, "Teams"), isEnabled: enabled, alert: alert,
                 escalation: tier4.map { Escalation(tier4: FinalAlert(action: $0)) })
        }
        let rules = [
            rule(enabled: true, alert: .sound(name: "Glass", gainDB: 0)),
            rule(enabled: true, alert: .silent),
            rule(enabled: true, alert: .silent, tier4: .shortcut(name: "Page me")),
            rule(enabled: false, alert: .sound(name: "Glass", gainDB: 0), tier4: .shortcut(name: "Page me")),
        ]
        XCTAssertEqual(RuleReach(rules: rules), RuleReach(enabled: 3, alertingAloud: 1, withShortcut: 1))
        XCTAssertEqual(RuleReach(rules: []), RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0))
    }

    // MARK: - Shortcuts, the login item and muting

    func testShortcutNamesNotFoundAreUrgentCountedAndNeverNamed() throws {
        func warning(_ rule: String, _ shortcut: String) -> RuleWarning {
            RuleWarning(ruleName: rule, shortcutName: shortcut, sentence: "x")
        }
        let one = try XCTUnwrap(finding(.shortcutNotFound, in: inputs(warnings: [warning("Pager", "Page me")])))
        XCTAssertTrue(one.isUrgent)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.text, RuleWarnings.summarySentence(count: 1))

        let two = try XCTUnwrap(finding(.shortcutNotFound,
                                        in: inputs(warnings: [warning("Pager", "Page me"), warning("Other", "Ring")])))
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.text, RuleWarnings.summarySentence(count: 2))
        XCTAssertNil(finding(.shortcutNotFound, in: inputs(warnings: [])))
    }

    func testTheLoginFindingIsPresentWhenSignalLadderDoesNotStartAtLoginAndAbsentWhenItDoesOrNothingIsKnown() throws {
        let off = try XCTUnwrap(finding(.loginItemOff, in: inputs(startsAtLogin: false)))
        XCTAssertTrue(off.isUrgent)
        XCTAssertEqual(off.text, OnCallText.loginItemOff)
        XCTAssertNil(finding(.loginItemOff, in: inputs(startsAtLogin: true)))
        XCTAssertNil(finding(.loginItemOff, in: inputs(startsAtLogin: nil)), "until a login item exists the app says nothing")
        XCTAssertNil(finding(.loginItemByHand, in: inputs(startsAtLogin: nil, byHand: true)))
        XCTAssertNil(finding(.loginItemByHand, in: inputs(startsAtLogin: true, byHand: true)))
    }

    /// An entry added by hand cannot be read, so the finding that could never be
    /// cleared becomes a quiet line that says so (Ruling 15).
    func testTheUsersWordThatTheyAddedItByHandMakesTheLoginFindingAnAdvisoryThatIsNotUrgent() throws {
        let byHand = try XCTUnwrap(finding(.loginItemByHand, in: inputs(startsAtLogin: false, byHand: true)))
        XCTAssertFalse(byHand.isUrgent)
        XCTAssertEqual(byHand.text, OnCallText.loginItemByHand)
        XCTAssertNil(finding(.loginItemOff, in: inputs(startsAtLogin: false, byHand: true)))
        for word in [nil, false] as [Bool?] {
            XCTAssertNil(finding(.loginItemByHand, in: inputs(startsAtLogin: false, byHand: word)))
            XCTAssertNotNil(finding(.loginItemOff, in: inputs(startsAtLogin: false, byHand: word)), "\(String(describing: word))")
        }
    }

    func testTheLoginFindingSaysItCannotCheckWhatItDoesNotKnow() {
        XCTAssertTrue(OnCallText.loginItemOff.contains("will not start again after a restart or log out"))
        XCTAssertTrue(OnCallText.loginItemOff.contains("unless you added it to Login Items yourself"))
        XCTAssertTrue(OnCallText.loginItemOff.contains("cannot check"))
        XCTAssertTrue(OnCallText.loginItemByHand.contains("cannot check"))
    }

    func testUnconfirmedMutingIsACountAndNeverAName() throws {
        let one = try XCTUnwrap(finding(.unconfirmedMuting, in: inputs(apps: ["Microsoft Teams"])))
        XCTAssertTrue(one.isUrgent)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.text, "1 app not confirmed muted")
        let two = try XCTUnwrap(finding(.unconfirmedMuting, in: inputs(apps: ["Microsoft Teams", "Slack"])))
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.text, "2 apps not confirmed muted")
        XCTAssertNil(finding(.unconfirmedMuting, in: inputs(apps: [])))
    }

    /// Muting is the user's word and cannot be checked, so it is never called
    /// muted as a fact: the finding says "not confirmed".
    func testMutingIsNeverCalledMutedAsAFact() throws {
        let pattern = try NSRegularExpression(pattern: #"(?<!not confirmed )(?<!confirmed )\bmuted\b"#, options: .caseInsensitive)
        for apps in [["Teams"], ["Teams", "Slack"], ["A", "B", "C", "D"]] {
            let found = try XCTUnwrap(finding(.unconfirmedMuting, in: inputs(apps: apps)))
            XCTAssertTrue(found.text.contains("not confirmed muted"), found.text)
            XCTAssertNil(pattern.firstMatch(in: found.text, range: NSRange(found.text.startIndex..., in: found.text)),
                         found.text)
        }
    }

    // MARK: - The standing advisories

    func testTheTwoAdvisoriesComeLastInThatOrderAndAreNeverUrgent() {
        let everything = inputs(health: .blind([.accessibilityNotTrusted]), apps: ["A"], outputSilent: true, alertVolume: 0,
                                status: .loadedWithProblems(enabled: 1, disabled: 0, rejected: [problem(0, nil)]),
                                warnings: [RuleWarning(ruleName: "R", shortcutName: "S", sentence: "x")], startsAtLogin: false)
        let found = OnCallCheck.findings(everything)
        XCTAssertEqual(found.suffix(2).map(\.kind), [.focus, .sleep])
        XCTAssertFalse(found.suffix(2).contains(where: \.isUrgent))
    }

    func testTheFocusAdvisoryReusesTheMuteWalkthroughsSentenceAndSaysItCannotBeReadAndTheWorkaround() throws {
        let focus = try XCTUnwrap(finding(.focus, in: inputs()))
        let reused = MuteWalkthroughText.focus.prefix(2).joined(separator: " ")
        XCTAssertTrue(focus.text.hasPrefix(reused), "the walkthrough's sentence is written once")
        XCTAssertTrue(focus.text.contains(OnCallText.focusCannotRead))
        XCTAssertTrue(focus.text.contains(OnCallText.focusWorkaround))
        XCTAssertTrue(OnCallText.focusCannotRead.contains("cannot read"))
        XCTAssertTrue(OnCallText.focusWorkaround.contains("break through"))
    }

    func testTheSleepAdvisoryIsTheOwnersSentence() throws {
        let sleep = try XCTUnwrap(finding(.sleep, in: inputs()))
        XCTAssertEqual(sleep.text, "A Mac that sleeps, with its lid closed or put to sleep by hand, captures nothing, and SignalLadder cannot wake it")
    }

    // MARK: - Order, and what the menu and the window keep

    private let everything: [OnCallCheck.Inputs] = [
        OnCallCheck.Inputs(health: .unknown, unconfirmedMutedApps: ["A"], outputSilent: true, alertVolume: 0,
                           reach: RuleReach(enabled: 0, alertingAloud: 1, withShortcut: 0),
                           ruleStatus: .loadedWithProblems(enabled: 0, disabled: 0,
                                                           rejected: [RuleSetCodec.Problem(index: 0, name: "R", reason: "x")]),
                           shortcutWarnings: [RuleWarning(ruleName: "R", shortcutName: "S", sentence: "x")],
                           startsAtLogin: false, loginItemByHand: nil),
        OnCallCheck.Inputs(health: .blind([.lazyAccessibilityTree]), unconfirmedMutedApps: [], outputSilent: false,
                           alertVolume: 1, reach: RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 0),
                           ruleStatus: .unreadable("x"), shortcutWarnings: [], startsAtLogin: false, loginItemByHand: true),
        OnCallCheck.Inputs(health: .verified, unconfirmedMutedApps: [], outputSilent: false, alertVolume: 1,
                           reach: RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0),
                           ruleStatus: .noRulesFile, shortcutWarnings: [], startsAtLogin: nil, loginItemByHand: nil),
        // Two advisories ahead of two urgent findings in the order they are found, which
        // is the only way a window that lists them urgent-first can be told from one that
        // lists them as found.
        OnCallCheck.Inputs(health: .verified, unconfirmedMutedApps: ["A"], outputSilent: false, alertVolume: 1,
                           reach: RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 0),
                           ruleStatus: .loaded(enabled: 1, disabled: 0),
                           shortcutWarnings: [RuleWarning(ruleName: "R", shortcutName: "S", sentence: "x")],
                           startsAtLogin: false, loginItemByHand: true),
    ]

    func testEveryKindOfFindingCanBeReached() {
        var reached = Set<Kind>()
        for input in everything { reached.formUnion(kinds(input)) }
        XCTAssertEqual(reached, Set(Kind.allCases))
    }

    func testTheFindingsComeInTheOrderTheyAreListed() {
        let order: [Kind] = [.health, .notVerifiedYet, .outputMuted, .beepsInaudible, .rulesFileNotInEffect,
                             .rulesNotInEffect, .noRuleEnabled, .noSoundOrShortcut, .shortcutNotFound, .loginItemOff,
                             .loginItemByHand, .unconfirmedMuting, .focus, .sleep]
        XCTAssertEqual(Set(order), Set(Kind.allCases), "the order names every kind")
        for input in everything {
            let found = kinds(input)
            let positions = found.map { order.firstIndex(of: $0)! }
            XCTAssertEqual(positions, positions.sorted(), "\(found)")
        }
        // The first set reaches the most of them at once, in this order.
        XCTAssertEqual(kinds(everything[0]),
                       [.notVerifiedYet, .outputMuted, .beepsInaudible, .rulesNotInEffect, .shortcutNotFound,
                        .loginItemOff, .unconfirmedMuting, .focus, .sleep])
    }

    func testEachKindIsUrgentOrNotAsTheCheckSaysAndTheAdvisoriesNever() {
        let urgent: Set<Kind> = [.health, .notVerifiedYet, .outputMuted, .beepsInaudible, .rulesNotInEffect,
                                 .rulesFileNotInEffect, .noRuleEnabled, .shortcutNotFound, .loginItemOff, .unconfirmedMuting]
        for kind in Kind.allCases {
            XCTAssertEqual(kind.isUrgent, urgent.contains(kind), "\(kind)")
        }
        XCTAssertEqual(Set(Kind.allCases).subtracting(urgent), [.noSoundOrShortcut, .loginItemByHand, .focus, .sleep])
    }

    /// The menu's standard lines already carry the health line and its cause (which
    /// reads Checking… or Unverified when nothing is verified), the muted output,
    /// the rules status and its warnings, and the mute count, so the menu keeps
    /// only what they do not, and nothing is said twice (Ruling 9).
    func testTheMenuOmitsWhatItsStandardLinesCarryAndKeepsTheRest() {
        for input in everything {
            let all = OnCallCheck.findings(input)
            let menu = OnCallCheck.menuLines(all)
            XCTAssertEqual(Set(menu.map(\.kind)).intersection([.health, .notVerifiedYet, .outputMuted, .rulesNotInEffect,
                                                              .rulesFileNotInEffect, .shortcutNotFound, .unconfirmedMuting]), [])
            XCTAssertEqual(menu.map(\.kind),
                           all.map(\.kind).filter { [.beepsInaudible, .noRuleEnabled, .noSoundOrShortcut, .loginItemOff,
                                                     .loginItemByHand, .focus, .sleep].contains($0) })
        }
        let kept = Set(everything.flatMap { OnCallCheck.menuLines(OnCallCheck.findings($0)).map(\.kind) })
        XCTAssertEqual(kept, [.beepsInaudible, .noRuleEnabled, .noSoundOrShortcut, .loginItemOff, .loginItemByHand,
                              .focus, .sleep])
    }

    func testTheWindowKeepsEveryFindingWithTheUrgentOnesFirstEachGroupInItsOrder() {
        // One of the inputs finds an advisory before an urgent finding, so the order the
        // window lists them in is not the order they were found in.
        XCTAssertNotEqual(kinds(everything[3]), OnCallCheck.windowLines(OnCallCheck.findings(everything[3])).map(\.kind))
        for input in everything {
            let all = OnCallCheck.findings(input)
            let window = OnCallCheck.windowLines(all)
            XCTAssertEqual(Set(window.map(\.kind)), Set(all.map(\.kind)))
            XCTAssertEqual(window.count, all.count)
            XCTAssertEqual(window.map(\.kind), all.filter(\.isUrgent).map(\.kind) + all.filter { !$0.isUrgent }.map(\.kind))
        }
        // Not verified yet is in the window, though the menu's health line says it.
        XCTAssertTrue(OnCallCheck.windowLines(OnCallCheck.findings(everything[0])).contains { $0.kind == .notVerifiedYet })
    }

    func testAnUrgentLineIsMarkedInTheMenuAndAnAdvisoryIsNot() throws {
        let found = OnCallCheck.findings(inputs(alertVolume: 0))
        let urgent = try XCTUnwrap(found.first { $0.kind == .beepsInaudible })
        XCTAssertEqual(urgent.menuTitle, "⚠︎ " + urgent.menuText)
        XCTAssertEqual(urgent.spokenText, "Urgent: " + urgent.text)
        let advisory = try XCTUnwrap(found.first { $0.kind == .sleep })
        XCTAssertEqual(advisory.menuTitle, advisory.menuText)
        XCTAssertEqual(advisory.spokenText, advisory.text)
    }

    func testTheHeadingCountsTheUrgentFindings() {
        XCTAssertEqual(OnCallCheck.summary(OnCallCheck.findings(inputs())), "Nothing urgent")
        XCTAssertEqual(OnCallCheck.summary(OnCallCheck.findings(inputs(alertVolume: 0))), "1 thing needs your attention")
        XCTAssertEqual(OnCallCheck.summary(OnCallCheck.findings(inputs(alertVolume: 0, startsAtLogin: false))),
                       "2 things need your attention")
        XCTAssertEqual(OnCallCheck.summary(OnCallCheck.findings(everything[0])), "7 things need your attention")
    }

    // MARK: - The menu's short forms

    /// How wide a line is in the menu's own font, in points: the same measure the
    /// menu is judged by, and the one that found the Focus advisory about 1,420 points
    /// wide beside menu lines of about 450 at most.
    private func menuWidth(_ line: String) -> CGFloat {
        (line as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }

    /// A short form fits beside the menu's other lines when it is no wider than the
    /// widest the menu already shows there, the output-muted warning (446 points on
    /// the Mac this was written on; the forms are 420 or fewer, which is the aim).
    /// Measured in the same run in the same font, so another system's font moves the
    /// limit with the lines and nothing is compared to a number from this Mac.
    private var widestMenuLine: CGFloat { menuWidth(AlertMenuText.outputSilentWarning) }
    /// Characters, a proxy for the width where a font is not to be had: the longest
    /// form is 67, and the muted warning, which sets the width above, is 68.
    private let longestMenuLine = 70

    private func assertIsOneShortLine(_ line: String, file: StaticString = #filePath, line number: UInt = #line) {
        XCTAssertFalse(line.contains("\n"), "\(line) is more than one line", file: file, line: number)
        XCTAssertLessThanOrEqual(line.count, longestMenuLine, line, file: file, line: number)
        XCTAssertLessThanOrEqual(menuWidth(line), widestMenuLine, "\(line) is \(menuWidth(line)) points wide",
                                 file: file, line: number)
    }

    /// The Focus advisory is about 1,420 points wide, the sleep line 721 and the beeps
    /// line 912, in a menu whose other lines are about 450 at most, so each finding the
    /// menu keeps is shown in a form of one short line (Ruling 17), and the line about
    /// the hold is one too. Every kind the menu keeps is among those measured.
    func testEveryLineTheMenuShowsFromTheCheckIsOneShortLine() {
        var measured = Set<Kind>()
        for input in everything {
            for found in OnCallCheck.menuLines(OnCallCheck.findings(input)) {
                measured.insert(found.kind)
                assertIsOneShortLine(found.menuTitle)
            }
        }
        XCTAssertEqual(measured, Set(Kind.allCases.filter { !$0.isAlreadyInTheMenu }),
                       "every kind the menu keeps was measured")
        assertIsOneShortLine(OnCallText.awakeLine)
        assertIsOneShortLine(AlertMenuText.awakeLine(held: true) ?? "")
    }

    /// The limit can fail: the sentences the forms replace are over it, so a form that
    /// became its sentence again would fail the test above, and a measure that read
    /// nothing would fail here.
    func testTheSentencesTheFormsReplaceAreFarOverTheLimit() {
        let sentences = [OnCallCheck.focusAdvisory, OnCallText.sleepAdvisory, OnCallText.beepsInaudible,
                         OnCallText.loginItemOff, OnCallText.loginItemByHand, OnCallText.noSoundOrShortcut]
        for sentence in sentences {
            XCTAssertGreaterThan(menuWidth(sentence), widestMenuLine, sentence)
            XCTAssertGreaterThan(sentence.count, longestMenuLine, sentence)
        }
        XCTAssertGreaterThan(menuWidth(OnCallCheck.focusAdvisory), 2 * widestMenuLine)
    }

    /// The window keeps the full sentence and the menu a shorter one, for each finding
    /// that has a short form, and the sentence itself for the rest.
    func testTheMenuShowsAShorterFormOfTheLongFindingsAndTheSentenceForTheRest() {
        let shortened: Set<Kind> = [.beepsInaudible, .noSoundOrShortcut, .loginItemOff, .loginItemByHand, .focus, .sleep]
        var seen = Set<Kind>()
        for input in everything {
            for found in OnCallCheck.findings(input) {
                seen.insert(found.kind)
                if shortened.contains(found.kind) {
                    XCTAssertNotEqual(found.menuText, found.text, "\(found.kind)")
                    XCTAssertLessThan(found.menuText.count, found.text.count, "\(found.kind)")
                } else {
                    XCTAssertEqual(found.menuText, found.text, "\(found.kind)")
                }
            }
        }
        XCTAssertEqual(seen, Set(Kind.allCases))
        // The window lists the sentences, whole.
        let window = OnCallCheck.windowLines(OnCallCheck.findings(everything[0]))
        XCTAssertTrue(window.contains { $0.text == OnCallText.beepsInaudible })
        XCTAssertTrue(window.contains { $0.text == OnCallCheck.focusAdvisory })
        XCTAssertTrue(window.contains { $0.text == OnCallText.sleepAdvisory })
    }

    /// Where the window says what the form does not, the form points to it, in the
    /// words that name the window the menu opens and the title it has.
    func testTheFormsWhereTheWindowSaysMorePointToTheCheck() throws {
        for kind in [Kind.focus, .beepsInaudible, .loginItemOff] {
            let found = try XCTUnwrap(everything.lazy.compactMap { self.finding(kind, in: $0) }.first, "\(kind)")
            XCTAssertTrue(found.menuText.hasSuffix(OnCallText.pointToCheck), found.menuText)
        }
        XCTAssertTrue(OnCallText.pointToCheck.hasSuffix("On-Call Check"))
        XCTAssertTrue(OnCallText.checkItemTitle.contains("On-Call Check"))
        XCTAssertTrue(WindowTitles.onCallCheck.hasSuffix("On-Call Check"))
    }

    /// The menu says the Focus risk and the facts about sleep and the hold, and none of
    /// them is urgent (Ruling 17): no mark, no word of it, and what each says is what
    /// was established and no more. A Focus hides banners and cannot be read; a Mac that
    /// sleeps captures nothing and SignalLadder cannot wake it; the hold costs battery
    /// and a closed lid still sleeps the Mac.
    func testTheFocusSleepAndHoldLinesInTheMenuAreNeverUrgentAndSayWhatWasEstablished() throws {
        let focus = try XCTUnwrap(finding(.focus, in: inputs()))
        let sleep = try XCTUnwrap(finding(.sleep, in: inputs()))
        for found in [focus, sleep] {
            XCTAssertFalse(found.isUrgent)
            XCTAssertEqual(found.menuTitle, found.menuText, "no urgent mark")
        }
        for line in [focus.menuTitle, sleep.menuTitle, OnCallText.awakeLine] {
            XCTAssertFalse(line.contains(OnCallText.urgentMark), line)
            XCTAssertNil(line.range(of: "urgent", options: .caseInsensitive), line)
        }
        XCTAssertTrue(focus.menuText.contains("hides banners"))
        XCTAssertTrue(focus.menuText.contains("cannot be read"))
        XCTAssertTrue(sleep.menuText.contains("captures nothing"))
        XCTAssertTrue(sleep.menuText.contains("SignalLadder cannot wake it"))
        XCTAssertTrue(OnCallText.awakeLine.hasPrefix("Keeping this Mac awake"))
        XCTAssertTrue(OnCallText.awakeLine.contains("costs battery"))
        XCTAssertTrue(OnCallText.awakeLine.contains("a closed lid still sleeps it"))
    }

    // MARK: - What the check window's heading and rows look like

    /// The app target decides nothing about urgency (Ruling 10): whether the
    /// heading says urgent, which symbol it has and what colour, and the same of
    /// every row, are asked here and only carried out there.
    func testAnyUrgentFindingMakesTheListUrgentAndNoAdvisoryDoes() {
        XCTAssertFalse(OnCallCheck.hasUrgent([]))
        for kind in Kind.allCases {
            let alone = [OnCallCheck.Finding(kind: kind, text: "x")]
            XCTAssertEqual(OnCallCheck.hasUrgent(alone), kind.isUrgent, "\(kind) alone")
            // An advisory in front of it, as the check finds them, does not hide it.
            XCTAssertEqual(OnCallCheck.hasUrgent([OnCallCheck.Finding(kind: .focus, text: "x")] + alone), kind.isUrgent,
                           "\(kind) after an advisory")
            XCTAssertEqual(OnCallCheck.hasUrgent(alone + [OnCallCheck.Finding(kind: .sleep, text: "x")]), kind.isUrgent,
                           "\(kind) before an advisory")
        }
    }

    /// The window opens at switch-on for the answer the heading is drawn from, and
    /// the heading's words say the same as its symbol, so a window cannot open
    /// saying "Nothing urgent" with an urgent mark, or the other way about.
    func testTheWindowOpensForTheAnswerTheHeadingIsDrawnFromAndItsWordsAgree() {
        for input in everything + [inputs(), inputs(alertVolume: 0)] {
            let found = OnCallCheck.findings(input)
            XCTAssertEqual(OnCallCheck.shouldOpenWindow(found), OnCallCheck.hasUrgent(found))
            XCTAssertEqual(OnCallCheck.summary(found) == OnCallText.nothingUrgent, !OnCallCheck.hasUrgent(found),
                           OnCallCheck.summary(found))
        }
        XCTAssertFalse(OnCallCheck.hasUrgent(OnCallCheck.findings(inputs())))
        XCTAssertTrue(OnCallCheck.hasUrgent(OnCallCheck.findings(inputs(alertVolume: 0))))
    }

    /// Nothing urgent is not "all is well" for an app that checks only what it can
    /// read, so the heading is a bell and never a tick.
    func testTheHeadingIsABellWithNoTickWhileNothingIsUrgentAndTheWarningWhileAnythingIs() {
        XCTAssertEqual(OnCallCheck.headingSymbol(hasUrgent: false), "bell.badge")
        XCTAssertEqual(OnCallCheck.headingSymbol(hasUrgent: true), "exclamationmark.triangle.fill")
        for urgent in [false, true] {
            let symbol = OnCallCheck.headingSymbol(hasUrgent: urgent)
            XCTAssertFalse(symbol.contains("checkmark"), "\(symbol): nothing urgent is not all is well")
        }
        XCTAssertEqual(OnCallText.nothingUrgentSymbol, OnCallCheck.headingSymbol(hasUrgent: false))
    }

    func testAnUrgentRowHasTheWarningAndAnAdvisoryTheInfoMarkAndTheHeadingMarksUrgencyAsTheRowsDo() {
        for kind in Kind.allCases {
            let row = OnCallCheck.Finding(kind: kind, text: "x")
            XCTAssertEqual(row.symbol, kind.isUrgent ? "exclamationmark.triangle.fill" : "info.circle", "\(kind)")
        }
        XCTAssertNotEqual(OnCallText.urgentSymbol, OnCallText.advisorySymbol)
        XCTAssertEqual(OnCallCheck.headingSymbol(hasUrgent: true), OnCallText.urgentSymbol)
        XCTAssertNotEqual(OnCallCheck.headingSymbol(hasUrgent: false), OnCallText.advisorySymbol,
                          "a heading with nothing urgent is not the mark of a line that is merely advice")
    }

    /// An unknown symbol name draws nothing, so each is asked of the system.
    func testEverySymbolTheWindowNamesIsOneTheSystemKnows() {
        for name in [OnCallText.urgentSymbol, OnCallText.advisorySymbol, OnCallText.nothingUrgentSymbol] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    /// Urgency is shown in the window by an icon that VoiceOver does not read, so the
    /// spoken text carries it, on every urgent line and on no other.
    func testVoiceOverIsToldUrgentOnEveryUrgentLineAndNothingOnTheRest() {
        for kind in Kind.allCases {
            let row = OnCallCheck.Finding(kind: kind, text: "a sentence")
            XCTAssertEqual(row.spokenText, kind.isUrgent ? "Urgent: a sentence" : "a sentence", "\(kind)")
        }
        XCTAssertEqual(OnCallText.urgentSpoken, "Urgent: ")
    }

    // MARK: - What the words may claim

    /// No line may say that a Focus is on or off: it cannot be read. The pattern
    /// is named here, and tested to match what it forbids, so this can fail.
    private let focusClaim = try! NSRegularExpression(
        pattern: #"(focus|do not disturb)( mode)? (is|was|has been) (currently |now )?(on|active|enabled|switched on|turned on)"#,
        options: .caseInsensitive)

    private func claimsAFocusState(_ line: String) -> Bool {
        focusClaim.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    func testThePatternForAFocusClaimMatchesWhatItForbids() {
        XCTAssertTrue(claimsAFocusState("Your Focus is currently active"))
        XCTAssertTrue(claimsAFocusState("Do Not Disturb is on"))
        XCTAssertTrue(claimsAFocusState("Focus mode has been switched on"))
        XCTAssertTrue(claimsAFocusState("do not disturb mode is now enabled"))
        // The mute walkthrough's own sentence is conditional and says no Focus is
        // on, so it passes.
        XCTAssertFalse(claimsAFocusState("so nothing can be captured while one is on."))
        XCTAssertFalse(claimsAFocusState(MuteWalkthroughText.focus.joined(separator: " ")))
    }

    func testNoFindingClaimsAFocusIsOnOrOff() {
        var lines: [String] = [OnCallText.awakeLine]
        for input in everything {
            for found in OnCallCheck.findings(input) {
                lines += [found.text, found.menuText, found.menuTitle, found.spokenText]
            }
        }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.contains(OnCallText.focusMenu), "the menu's short form is one of the lines")
        for line in lines { XCTAssertFalse(claimsAFocusState(line), line) }
    }

    /// The sleep advisory says what sleep does and claims that none happened: a
    /// retrospective line is an owner's option and would be written only from a
    /// measured sleep.
    func testNoFindingSaysTheMacWasAsleep() throws {
        let retrospective = try NSRegularExpression(pattern: #"(was|were|has been) asleep"#, options: .caseInsensitive)
        func says(_ line: String) -> Bool {
            retrospective.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        XCTAssertTrue(says("The Mac was asleep from 02:10"))
        XCTAssertTrue(says("it has been asleep"))
        for input in everything {
            for found in OnCallCheck.findings(input) {
                XCTAssertFalse(says(found.text), found.text)
                XCTAssertFalse(says(found.menuTitle), found.menuTitle)
            }
        }
        XCTAssertFalse(says(OnCallText.awakeLine), OnCallText.awakeLine)
        XCTAssertFalse(says(OnCallText.sleepMenu), OnCallText.sleepMenu)
    }

    /// No finding holds notification text, a rule's name or an app's name, which
    /// a shared screen shows. The inputs that carry names are given a canary one.
    func testNoLineOfAnyKindHoldsAName() {
        let canary = "CANARY-7f3a"
        let named = OnCallCheck.Inputs(
            health: .unknown,
            unconfirmedMutedApps: [canary, "\(canary) two"],
            outputSilent: true, alertVolume: 0,
            reach: RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0),
            ruleStatus: .loadedWithProblems(enabled: 1, disabled: 0,
                                            rejected: [RuleSetCodec.Problem(index: 0, name: canary, reason: "bad \(canary)")]),
            shortcutWarnings: [RuleWarning(ruleName: canary, shortcutName: canary, sentence: "Shortcut \(canary)")],
            startsAtLogin: false, loginItemByHand: nil)
        let unreadable = OnCallCheck.Inputs(
            health: .verified, unconfirmedMutedApps: [], outputSilent: false, alertVolume: 1,
            reach: RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0), ruleStatus: .unreadable(canary),
            shortcutWarnings: [], startsAtLogin: nil, loginItemByHand: nil)

        for input in [named, unreadable] {
            let all = OnCallCheck.findings(input)
            XCTAssertFalse(all.isEmpty)
            let shown = all + OnCallCheck.menuLines(all) + OnCallCheck.windowLines(all)
            for found in shown {
                XCTAssertFalse(found.text.contains(canary), found.text)
                XCTAssertFalse(found.menuTitle.contains(canary), found.menuTitle)
                XCTAssertFalse(found.spokenText.contains(canary), found.spokenText)
            }
            XCTAssertFalse(OnCallCheck.summary(all).contains(canary))
        }
        // It is the counts that carry through, not the names.
        let counts = OnCallCheck.findings(named).compactMap(\.count)
        XCTAssertEqual(counts.sorted(), [1, 1, 2])
    }
}
