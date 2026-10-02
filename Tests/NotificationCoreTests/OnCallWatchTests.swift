import XCTest
@testable import NotificationCore

/// When the on-call watch opens the check window and sounds one beep (M5 plan,
/// Rulings 9 and 10, O5 part 2). It is a pure function of whether the app is on
/// call, the findings just produced and what stood at the last look, so each of
/// these asks it as the app does, carrying what it remembers from one look to the
/// next. Nothing here sounds a beep or shows a window.
final class OnCallWatchTests: XCTestCase {
    typealias Kind = OnCallCheck.Finding.Kind

    // MARK: - Findings as the check produces them

    private func rulesRefused(_ count: Int) -> OnCallCheck.Finding {
        OnCallCheck.Finding(kind: .rulesNotInEffect, text: OnCallText.rulesNotInEffect(count: count), count: count)
    }

    private let noRule = OnCallCheck.Finding(kind: .noRuleEnabled, text: OnCallText.noRuleEnabled)
    private let loginOff = OnCallCheck.Finding(kind: .loginItemOff, text: OnCallText.loginItemOff)
    private let loginByHand = OnCallCheck.Finding(kind: .loginItemByHand, text: OnCallText.loginItemByHand)
    private let muted = OnCallCheck.Finding(kind: .outputMuted, text: AlertMenuText.outputSilentSentence)
    private let beepsOff = OnCallCheck.Finding(kind: .beepsInaudible, text: OnCallText.beepsInaudible)
    private let notVerified = OnCallCheck.Finding(kind: .notVerifiedYet, text: OnCallText.notVerifiedYet)
    private let health = OnCallCheck.Finding(kind: .health, text: HealthCause.accessibilityNotTrusted.advice)
    private let unconfirmed = OnCallCheck.Finding(kind: .unconfirmedMuting, text: OnCallText.unconfirmedMuting(count: 2), count: 2)
    private let focus = OnCallCheck.Finding(kind: .focus, text: OnCallCheck.focusAdvisory)
    private let sleep = OnCallCheck.Finding(kind: .sleep, text: OnCallText.sleepAdvisory)
    private let noSound = OnCallCheck.Finding(kind: .noSoundOrShortcut, text: OnCallText.noSoundOrShortcut)

    private func shortcutsMissing(_ count: Int) -> OnCallCheck.Finding {
        OnCallCheck.Finding(kind: .shortcutNotFound, text: RuleWarnings.summarySentence(count: count) ?? "", count: count)
    }

    /// Looks as the app does, on call or off, keeping what the watch remembers.
    private final class Looker {
        var state = OnCallWatch.State()
        var onCall = true
        private(set) var looks: [OnCallWatch.Decision] = []

        @discardableResult
        func look(_ findings: [OnCallCheck.Finding]) -> OnCallWatch.Decision {
            let decision = OnCallWatch.decide(onCall: onCall, findings: findings, previous: state)
            state = decision.state
            looks.append(decision)
            return decision
        }
    }

    /// Findings that never open the window or sound, for a look that should be quiet.
    private var advisories: [OnCallCheck.Finding] { [focus, sleep] }

    // MARK: - A finding that stands at the first look

    /// After a launch that restored on-call mode there is nothing remembered, and
    /// a finding already standing is as new as one that has just appeared.
    func testAFindingStandingAtTheFirstLookOpensTheWindowAndSoundsOnce() {
        let looker = Looker()
        let first = looker.look([rulesRefused(1)] + advisories)
        XCTAssertTrue(first.openWindow)
        XCTAssertTrue(first.beep)
        XCTAssertEqual(first.state.standing, [.rulesNotInEffect: 1])
    }

    func testTheSameFindingsAgainDoNothing() {
        let looker = Looker()
        looker.look([rulesRefused(2), noRule, loginOff] + advisories)
        for _ in 0..<5 {
            let again = looker.look([rulesRefused(2), noRule, loginOff] + advisories)
            XCTAssertFalse(again.openWindow)
            XCTAssertFalse(again.beep)
        }
    }

    func testNothingStandingOpensNothingAndSoundsNothing() {
        let looker = Looker()
        let quiet = looker.look(advisories)
        XCTAssertFalse(quiet.openWindow)
        XCTAssertFalse(quiet.beep)
        XCTAssertEqual(quiet.state, OnCallWatch.State())
    }

    // MARK: - A finding that appears after a reload or a save

    func testARuleRefusedAfterAReloadIsANewFindingThatSoundsOnceAndOpensTheWindow() {
        let looker = Looker()
        looker.look(advisories)
        let afterReload = looker.look([rulesRefused(1)] + advisories)
        XCTAssertTrue(afterReload.openWindow)
        XCTAssertTrue(afterReload.beep)
        XCTAssertFalse(looker.look([rulesRefused(1)] + advisories).beep, "and only once")
    }

    func testNoRuleEnabledAppearingAfterASaveDoesTheSameAndItsReturnSoundsAgain() {
        let looker = Looker()
        looker.look(advisories)
        let saved = looker.look([noRule] + advisories)
        XCTAssertTrue(saved.openWindow)
        XCTAssertTrue(saved.beep)

        // Fixed, then broken again: the return sounds again.
        let fixed = looker.look(advisories)
        XCTAssertFalse(fixed.openWindow)
        XCTAssertFalse(fixed.beep)
        XCTAssertEqual(fixed.state, OnCallWatch.State(), "what stands is updated when a finding goes")
        let broken = looker.look([noRule] + advisories)
        XCTAssertTrue(broken.openWindow)
        XCTAssertTrue(broken.beep)
    }

    func testAShortcutNameNotFoundIsWatchedAndCounted() {
        let looker = Looker()
        XCTAssertTrue(looker.look([shortcutsMissing(1)]).beep)
        XCTAssertFalse(looker.look([shortcutsMissing(1)]).beep)
        XCTAssertTrue(looker.look([shortcutsMissing(2)]).beep, "a second name not found")
    }

    // MARK: - A count that rises or falls

    func testACountThatRisesSoundsAndOpensTheWindowAndOneThatFallsDoesNot() {
        let looker = Looker()
        looker.look([rulesRefused(1)])
        let rose = looker.look([rulesRefused(3)])
        XCTAssertTrue(rose.openWindow)
        XCTAssertTrue(rose.beep)
        XCTAssertEqual(rose.state.standing, [.rulesNotInEffect: 3])

        let fell = looker.look([rulesRefused(2)])
        XCTAssertFalse(fell.openWindow)
        XCTAssertFalse(fell.beep)
        XCTAssertEqual(fell.state.standing, [.rulesNotInEffect: 2], "a fall updates what stands")
    }

    /// Because the fall was recorded, a rise back to what stood before is a rise.
    func testAFallIsRememberedSoTheCountsReturnToItsOldValueSoundsAgain() {
        let looker = Looker()
        looker.look([rulesRefused(3)])
        looker.look([rulesRefused(1)])
        XCTAssertTrue(looker.look([rulesRefused(3)]).beep)
    }

    func testAFindingThatGoesAndComesBackSoundsEachTimeItComes() {
        let looker = Looker()
        var beeps = 0
        for _ in 0..<4 {
            if looker.look([loginOff]).beep { beeps += 1 }
            if looker.look([]).beep { beeps += 1 }
        }
        XCTAssertEqual(beeps, 4)
    }

    func testTheWholeFileNotInEffectIsItsOwnFindingSoMovingToItFromRefusedRulesSounds() {
        let fileGone = OnCallCheck.Finding(kind: .rulesFileNotInEffect, text: OnCallText.noRulesFileUnreadable)
        let looker = Looker()
        looker.look([rulesRefused(3)])
        let decision = looker.look([fileGone])
        XCTAssertTrue(decision.beep, "three refused to no rules at all is worse, though the count is lower")
        XCTAssertTrue(decision.openWindow)
    }

    // MARK: - The login item

    func testTheLoginItemOffAppearsAndSoundsOnce() {
        let looker = Looker()
        looker.look(advisories)
        let off = looker.look([loginOff] + advisories)
        XCTAssertTrue(off.openWindow)
        XCTAssertTrue(off.beep)
        XCTAssertFalse(looker.look([loginOff] + advisories).beep)
    }

    /// The user's word that they added it by hand makes it a quiet line (Ruling 15):
    /// it neither sounds nor opens the window, at any look.
    func testTheByHandAdvisoryNeverSoundsOrOpensTheWindow() {
        let looker = Looker()
        for _ in 0..<3 {
            let decision = looker.look([loginByHand] + advisories)
            XCTAssertFalse(decision.openWindow)
            XCTAssertFalse(decision.beep)
            XCTAssertEqual(decision.state, OnCallWatch.State())
        }
    }

    // MARK: - A muted output and a silent Alert volume

    /// A beep could not be heard through either, so each opens the window and
    /// sounds nothing; it is not reported again while it stands; and it opens the
    /// window again when it returns after being audible.
    func testAMutedOutputOpensTheWindowWithoutABeepOnceAndAgainWhenItReturns() {
        let looker = Looker()
        looker.look(advisories)
        let appeared = looker.look([muted] + advisories)
        XCTAssertTrue(appeared.openWindow)
        XCTAssertFalse(appeared.beep)
        XCTAssertEqual(appeared.state.standing, [.outputMuted: 1])

        for _ in 0..<3 {
            let standing = looker.look([muted] + advisories)
            XCTAssertFalse(standing.openWindow, "not reported again while it stands")
            XCTAssertFalse(standing.beep)
        }
        looker.look(advisories)   // audible again
        let returned = looker.look([muted] + advisories)
        XCTAssertTrue(returned.openWindow)
        XCTAssertFalse(returned.beep)
    }

    func testAnAlertVolumeAtZeroDoesTheSame() {
        let looker = Looker()
        let appeared = looker.look([beepsOff] + advisories)
        XCTAssertTrue(appeared.openWindow)
        XCTAssertFalse(appeared.beep)
        XCTAssertFalse(looker.look([beepsOff] + advisories).openWindow)
        looker.look(advisories)
        XCTAssertTrue(looker.look([beepsOff] + advisories).openWindow)
    }

    /// A finding that sounds and one that does not, appearing together, sound once.
    func testASoundedFindingAppearingBesideAMutedOutputStillSounds() {
        let looker = Looker()
        let both = looker.look([muted, rulesRefused(1)] + advisories)
        XCTAssertTrue(both.openWindow)
        XCTAssertTrue(both.beep)
    }

    // MARK: - What is not watched

    /// Unconfirmed muting and the advisories are the user's to fix and are shown
    /// and not sounded; health is the health alarm's.
    func testUnconfirmedMutingHealthAndTheAdvisoriesNeverSoundOrOpenTheWindowHere() {
        let looker = Looker()
        for findings in [[unconfirmed], [health], [notVerified], [noSound], advisories,
                         [health, notVerified, unconfirmed, noSound, focus, sleep]] {
            let decision = looker.look(findings)
            XCTAssertFalse(decision.openWindow, "\(findings.map(\.kind))")
            XCTAssertFalse(decision.beep, "\(findings.map(\.kind))")
            XCTAssertEqual(decision.state, OnCallWatch.State(), "none of them is remembered")
        }
    }

    func testWhichKindsAreWatchedAndWhichAreSounded() {
        let watched: Set<Kind> = [.rulesNotInEffect, .rulesFileNotInEffect, .noRuleEnabled, .shortcutNotFound,
                                  .loginItemOff, .outputMuted, .beepsInaudible]
        let silent: Set<Kind> = [.outputMuted, .beepsInaudible]
        for kind in Kind.allCases {
            XCTAssertEqual(OnCallWatch.isWatched(kind), watched.contains(kind), "\(kind)")
            XCTAssertEqual(OnCallWatch.isSounded(kind), watched.contains(kind) && !silent.contains(kind), "\(kind)")
        }
    }

    // MARK: - Off call

    /// Off call nothing opens or sounds and what stands is emptied, so switching on
    /// afterwards sounds for a finding that is still standing.
    func testOffCallNothingOpensOrSoundsAndWhatStandsIsEmptied() {
        let looker = Looker()
        looker.look([rulesRefused(2), loginOff, muted] + advisories)
        XCTAssertFalse(looker.state.standing.isEmpty)

        looker.onCall = false
        let off = looker.look([rulesRefused(2), loginOff, muted, noRule] + advisories)
        XCTAssertFalse(off.openWindow)
        XCTAssertFalse(off.beep)
        XCTAssertEqual(off.state, OnCallWatch.State())

        looker.onCall = true
        let on = looker.look([rulesRefused(2), loginOff, muted] + advisories)
        XCTAssertTrue(on.openWindow)
        XCTAssertTrue(on.beep, "a finding still standing sounds for someone who has just switched on")
    }

    // MARK: - What it remembers

    /// What stands is kinds and counts and no name: findings built from inputs that
    /// carry a rule's name and an app's name leave no trace of either.
    func testWhatStandsHoldsKindsAndCountsAndNoName() {
        let canary = "CANARY-91cc"
        let inputs = OnCallCheck.Inputs(
            health: .verified, unconfirmedMutedApps: [canary], outputSilent: true, alertVolume: 0,
            reach: RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0),
            ruleStatus: .loadedWithProblems(enabled: 1, disabled: 0,
                                            rejected: [RuleSetCodec.Problem(index: 0, name: canary, reason: canary)]),
            shortcutWarnings: [RuleWarning(ruleName: canary, shortcutName: canary, sentence: canary)],
            startsAtLogin: false, loginItemByHand: nil)
        let decision = OnCallWatch.decide(onCall: true, findings: OnCallCheck.findings(inputs), previous: .init())
        XCTAssertEqual(decision.state.standing, [.rulesNotInEffect: 1, .shortcutNotFound: 1, .loginItemOff: 1,
                                                 .outputMuted: 1, .beepsInaudible: 1])
        XCTAssertFalse("\(decision)".contains(canary))
    }
}
