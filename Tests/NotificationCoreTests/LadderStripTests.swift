import XCTest
@testable import NotificationCore

/// The strip of four segments on a rule's row in the editor's list, and the
/// row's number (M7 plan, Stage 6a).
final class LadderStripTests: XCTestCase {
    private func rule(_ name: String = "On-call mentions", alert: AlertAction? = .silent, escalation: Escalation? = nil,
                      enabled: Bool = true) -> Rule {
        var rule = Rule(name: name, condition: .field(.app, .contains, "Teams"), alert: alert, escalation: escalation)
        rule.isEnabled = enabled
        return rule
    }

    private let repeating = RepeatAlert(action: .silent)
    private let final = FinalAlert(action: .alert(.silent))

    private func on(_ rule: Rule) -> [Bool] { LadderStrip(for: rule).segments.map(\.isOn) }

    func testThereAreAlwaysFourSegmentsInTierOrderEachInItsTiersColour() {
        for strip in [LadderStrip(for: rule(alert: nil)),
                      LadderStrip(for: rule(escalation: Escalation(tier2: PanelAlert(), tier3: repeating, tier4: final)))] {
            XCTAssertEqual(strip.segments.map(\.tier), [1, 2, 3, 4])
            XCTAssertEqual(strip.segments.map(\.tone), [.first, .second, .upper, .upper])
        }
    }

    func testARuleWithAnAlertAndNoLadderReachesTierOne() {
        XCTAssertEqual(on(rule()), [true, false, false, false])
        XCTAssertEqual(on(rule(escalation: Escalation())), [true, false, false, false], "an empty ladder is no ladder")
    }

    func testARuleWithNoAlertHasNoTierOne() {
        XCTAssertEqual(on(rule(alert: nil)), [false, false, false, false])
        XCTAssertEqual(on(rule(alert: nil, escalation: Escalation(tier2: PanelAlert()))), [false, true, false, false])
    }

    func testEachTierOfTheLadderIsItsOwnSegment() {
        XCTAssertEqual(on(rule(escalation: Escalation(tier2: PanelAlert()))), [true, true, false, false])
        XCTAssertEqual(on(rule(escalation: Escalation(tier2: PanelAlert(), tier3: repeating))), [true, true, true, false])
        XCTAssertEqual(on(rule(escalation: Escalation(tier2: PanelAlert(), tier3: repeating, tier4: final))),
                       [true, true, true, true])
    }

    func testATierLeftOutIsAGapAndNotTheEnd() {
        XCTAssertEqual(on(rule(escalation: Escalation(tier3: repeating))), [true, false, true, false])
        XCTAssertEqual(on(rule(escalation: Escalation(tier2: PanelAlert(), tier4: final))), [true, true, false, true])
    }

    func testEverySilentSoundAndSpokenAlertIsTierOne() {
        let speech = SpeechAction(voiceIdentifier: "com.apple.voice.compact.en-GB.Daniel")
        for alert in [AlertAction.silent, .sound(name: "Glass", gainDB: 0), .speak(speech),
                      .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: speech)] {
            XCTAssertEqual(on(rule(alert: alert)).first, true, "\(alert)")
        }
    }

    func testARuleSwitchedOffKeepsItsStrip() {
        let ladder = Escalation(tier2: PanelAlert(), tier3: repeating)
        XCTAssertEqual(LadderStrip(for: rule(escalation: ladder, enabled: false)), LadderStrip(for: rule(escalation: ladder)))
    }

    func testTheStripIsReadFromTheRuleAndNothingElse() {
        XCTAssertEqual(LadderStrip(for: rule("A")), LadderStrip(for: rule("B")), "the name is no part of it")
    }

    // MARK: - In words

    func testWhatAScreenReaderIsTold() {
        XCTAssertEqual(LadderStrip(for: rule(alert: nil)).description, "No tier is on")
        XCTAssertEqual(LadderStrip(for: rule()).description, "Tier 1 is on")
        XCTAssertEqual(LadderStrip(for: rule(escalation: Escalation(tier2: PanelAlert()))).description, "Tiers 1 and 2 are on")
        XCTAssertEqual(LadderStrip(for: rule(escalation: Escalation(tier2: PanelAlert(), tier3: repeating))).description,
                       "Tiers 1, 2 and 3 are on")
        XCTAssertEqual(LadderStrip(for: rule(escalation: Escalation(tier2: PanelAlert(), tier3: repeating, tier4: final))).description,
                       "Tiers 1, 2, 3 and 4 are on")
        XCTAssertEqual(LadderStrip(for: rule(escalation: Escalation(tier3: repeating))).description, "Tiers 1 and 3 are on")
        XCTAssertEqual(LadderStrip(for: rule(alert: nil, escalation: Escalation(tier4: final))).description, "Tier 4 is on")
    }

    func testTheTiersOnAreLowestFirst() {
        XCTAssertEqual(LadderStrip(for: rule(escalation: Escalation(tier2: PanelAlert(), tier4: final))).tiersOn, [1, 2, 4])
        XCTAssertEqual(LadderStrip(for: rule(alert: nil)).tiersOn, [])
    }

    // MARK: - The row's number

    func testARulesNumberIsItsPlaceFromOne() {
        let rules = [rule("A"), rule("B"), rule("C")]
        XCTAssertEqual(rules.map { RuleOrder.position(of: $0.id, in: rules) }, [1, 2, 3])
    }

    func testTheNumberFollowsAMove() {
        let rules = [rule("A"), rule("B"), rule("C")]
        let moved = RuleOrder.moving(rules, fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(RuleOrder.position(of: rules[2].id, in: moved), 1)
        XCTAssertEqual(RuleOrder.position(of: rules[0].id, in: moved), 2)
    }

    func testARuleTheListDoesNotHoldHasNoNumber() {
        XCTAssertNil(RuleOrder.position(of: UUID(), in: [rule("A")]))
        XCTAssertNil(RuleOrder.position(of: UUID(), in: []))
    }

    func testTheNumbersWords() {
        XCTAssertEqual(EditorText.position(1), "1")
        XCTAssertEqual(EditorText.position(12), "12")
        XCTAssertEqual(EditorText.priority(1), "Priority 1")
        XCTAssertEqual(EditorText.priority(12), "Priority 12")
    }
}
