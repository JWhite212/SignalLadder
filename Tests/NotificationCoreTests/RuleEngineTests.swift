import XCTest
@testable import NotificationCore

final class RuleEngineTests: XCTestCase {
    private func note(app: String = "Microsoft Teams",
                      title: String = "#general",
                      subtitle: String = "",
                      body: String = "hello",
                      subrole: String = "AXNotificationCenterBanner") -> CapturedNotification {
        CapturedNotification(timestamp: Date(timeIntervalSince1970: 1_757_000_000),
                             appNameGuess: app, title: title, subtitle: subtitle, body: body,
                             rawText: "\(app), \(title), \(body)", subrole: subrole)
    }

    private func rule(_ name: String, _ condition: RuleCondition, enabled: Bool = true) -> Rule {
        Rule(name: name, condition: condition, isEnabled: enabled)
    }

    // MARK: - Fields

    func testEveryFieldReadsTheMatchingProperty() {
        let n = CapturedNotification(timestamp: .distantPast, appNameGuess: "A", title: "T", subtitle: "S",
                                     body: "B", rawText: "R", subrole: "X")
        XCTAssertEqual(Field.allCases.map { n.value(of: $0) }, ["A", "T", "S", "B", "R", "X"],
                       "if a case is added to Field, value(of:) must be taught it in the same change")
    }

    // MARK: - Operators

    func testEqualsIsWholeStringCaseAndDiacriticInsensitive() {
        XCTAssertTrue(RuleEvaluator.matches(.field(.app, .equals, "microsoft teams"), note()))
        XCTAssertFalse(RuleEvaluator.matches(.field(.app, .equals, "Microsoft"), note()),
                       "equals is not a prefix match")
        XCTAssertTrue(RuleEvaluator.matches(.field(.title, .equals, "Équipe"), note(title: "equipe")))
    }

    func testNotEqualsIsTheExactComplementOfEquals() {
        for value in ["microsoft teams", "Microsoft", ""] {
            let condition = RuleCondition.field(.app, .equals, value)
            let complement = RuleCondition.field(.app, .notEquals, value)
            XCTAssertNotEqual(RuleEvaluator.matches(condition, note()),
                              RuleEvaluator.matches(complement, note()), value)
        }
    }

    func testEqualsEmptyMeansTheFieldIsEmpty() {
        // The one legitimate use of an empty value: "has no subtitle".
        XCTAssertTrue(RuleEvaluator.matches(.field(.subtitle, .equals, ""), note(subtitle: "")))
        XCTAssertFalse(RuleEvaluator.matches(.field(.subtitle, .equals, ""), note(subtitle: "Alex")))
    }

    func testContainsIsCaseInsensitiveSubstring() {
        XCTAssertTrue(RuleEvaluator.matches(.field(.body, .contains, "DEPLOY"), note(body: "starting deploy now")))
        XCTAssertFalse(RuleEvaluator.matches(.field(.body, .contains, "rollback"), note(body: "starting deploy now")))
    }

    func testMatchesIsAnchoredGlob() {
        XCTAssertTrue(RuleEvaluator.matches(.field(.title, .matches, "#prod-*"), note(title: "#prod-api")))
        XCTAssertFalse(RuleEvaluator.matches(.field(.title, .matches, "#prod-*"), note(title: "re: #prod-api")))
    }

    // MARK: - Composition

    func testAndOrNotCompose() {
        let prod = RuleCondition.field(.title, .matches, "#prod-*")
        let incident = RuleCondition.field(.title, .matches, "#incident-*")
        let resolved = RuleCondition.field(.body, .contains, "resolved")
        let condition = RuleCondition.and([.or([prod, incident]), .not(resolved)])

        XCTAssertTrue(RuleEvaluator.matches(condition, note(title: "#incident-42", body: "paging")))
        XCTAssertFalse(RuleEvaluator.matches(condition, note(title: "#incident-42", body: "resolved")))
        XCTAssertFalse(RuleEvaluator.matches(condition, note(title: "#general", body: "paging")))
    }

    func testEmptyGroupsKeepTheirMathematicalMeaning() {
        // Rejected at load time; the evaluator itself stays unsurprising.
        XCTAssertTrue(RuleEvaluator.matches(.and([]), note()))
        XCTAssertFalse(RuleEvaluator.matches(.or([]), note()))
    }

    // MARK: - The spec's worked examples (§5.11), field-only forms

    func testSpecExampleProdOrIncident() {
        let condition = RuleCondition.or([.field(.title, .matches, "#prod-*"),
                                          .field(.title, .matches, "#incident-*")])
        XCTAssertTrue(RuleEvaluator.matches(condition, note(title: "#prod-payments")))
        XCTAssertTrue(RuleEvaluator.matches(condition, note(title: "#incident-7")))
        XCTAssertFalse(RuleEvaluator.matches(condition, note(title: "#random")))
    }

    func testSpecExampleAlertsAndDeploy() {
        let condition = RuleCondition.and([.field(.title, .contains, "#alerts"),
                                           .field(.body, .contains, "deploy")])
        XCTAssertTrue(RuleEvaluator.matches(condition, note(title: "#alerts", body: "deploy failed")))
        XCTAssertFalse(RuleEvaluator.matches(condition, note(title: "#alerts", body: "all green")))
    }

    // MARK: - Engine

    func testArrayOrderIsPriorityAndTheFirstMatchWins() {
        let broad = rule("Anything from Teams", .field(.app, .equals, "Microsoft Teams"))
        let narrow = rule("Prod", .field(.title, .matches, "#prod-*"))
        XCTAssertEqual(RuleEngine.firstMatch(for: note(title: "#prod-db"), in: [narrow, broad])?.name, "Prod")
        XCTAssertEqual(RuleEngine.firstMatch(for: note(title: "#prod-db"), in: [broad, narrow])?.name,
                       "Anything from Teams", "reordering the list changes the winner — the list IS the precedence")
    }

    func testDisabledRulesAreSkippedNotTreatedAsNonMatching() {
        let off = rule("Off", .field(.app, .equals, "Microsoft Teams"), enabled: false)
        let on = rule("On", .field(.app, .equals, "Microsoft Teams"))
        XCTAssertEqual(RuleEngine.firstMatch(for: note(), in: [off, on])?.name, "On")
    }

    func testNoMatchIsNil() {
        XCTAssertNil(RuleEngine.firstMatch(for: note(), in: [rule("Weather", .field(.app, .equals, "Weather"))]))
        XCTAssertNil(RuleEngine.firstMatch(for: note(), in: []))
    }
}
