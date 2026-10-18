import XCTest
@testable import NotificationCore

/// Sentences the app target typed until #97, now made in the core where they are tested.
final class MovedSentencesTests: XCTestCase {
    func testTheRuleMatchLineCountsWhatTheRulesInEffectMatchAndIsAbsentWithNothingToCount() {
        XCTAssertEqual(StatusMenuText.ruleMatchLine(matched: 2, of: 50, rulesInEffect: 3), "Current rules match 2 of the last 50")
        XCTAssertEqual(StatusMenuText.ruleMatchLine(matched: 0, of: 1, rulesInEffect: 1), "Current rules match 0 of the last 1")
        XCTAssertNil(StatusMenuText.ruleMatchLine(matched: 0, of: 50, rulesInEffect: 0), "no rule in effect")
        XCTAssertNil(StatusMenuText.ruleMatchLine(matched: 0, of: 0, rulesInEffect: 3), "nothing captured")
    }

    /// The Inspector said "(no app name)" and the dry run "(unknown app)" for the same empty
    /// name. Both now say the one.
    func testARowWithNoAppNameSaysSoInOneWayInBothViews() {
        XCTAssertEqual(InspectorRowText.appName(""), "(no app name)")
        XCTAssertEqual(InspectorRowText.appName("Microsoft Teams"), "Microsoft Teams")
    }

    /// The guide's button and the rule editor's say the same, and the menu's item adds only
    /// its ellipsis.
    func testTheRulesFileButtonIsWordedOnceAndTheMenuItemAddsTheEllipsis() {
        XCTAssertEqual(SetupText.label(for: .openRulesFile), SetupText.openRulesFileTitle)
        XCTAssertEqual(SetupText.rulesFileMenuTitle, SetupText.openRulesFileTitle + "\u{2026}")
    }
}
