import XCTest
@testable import NotificationCore

/// Where the rule editor shows the notifications a rule matches, and what it
/// calls them (M7 plan, Stage 6c). The section was the last in the pane, under
/// the alert and the ladder, headed "Tried on recent notifications". It is now
/// beneath the conditions it tries, headed "Matching notifications". The app
/// target has no tests, so this reads its sources and opens no window.
final class MatchesSectionWiringTests: XCTestCase {
    func testTheHeadingsWords() {
        XCTAssertEqual(EditorText.matchingNotifications, "Matching notifications")
    }

    func testTheSectionIsBeneathTheConditionsAndAboveWhatTheRuleThenDoes() throws {
        let detail = try code("RuleDetailView.swift")
        let conditions = try position(of: "section(EditorText.whenANotificationMatches) {", in: detail)
        let matches = try position(of: "section(EditorText.matchingNotifications) {", in: detail)
        let then = try position(of: "section(EditorText.then) {", in: detail)
        XCTAssertLessThan(conditions, matches)
        XCTAssertLessThan(matches, then)
        XCTAssertLessThan(try position(of: "ConditionBuilderView(rule: rule)", in: detail), matches,
                          "the conditions, and the buttons that add one, come first")
        XCTAssertLessThan(try position(of: "Button(EditorText.addCondition)", in: detail), matches)
    }

    func testThereIsOneSuchSectionAndItHoldsTheDryRunAsBefore() throws {
        let detail = try code("RuleDetailView.swift")
        XCTAssertEqual(count("section(EditorText.matchingNotifications) {", in: detail), 1)
        XCTAssertEqual(count("DryRunView(model: model, id: id)", in: detail), 1)
        let matches = try position(of: "section(EditorText.matchingNotifications) {", in: detail)
        let dryRun = try position(of: "DryRunView(model: model, id: id)", in: detail)
        XCTAssertLessThan(matches, dryRun)
        XCTAssertLessThan(dryRun, try position(of: "section(EditorText.then) {", in: detail), "it is in that section")
    }

    /// The old heading is gone from the app and the core, so nothing can show it.
    func testTheOldHeadingIsUsedNowhere() throws {
        for file in try AppSources.fileNames() {
            XCTAssertFalse(try code(file).contains("triedOnRecentNotifications"), file)
        }
        XCTAssertNil(try code("DryRunView.swift").range(of: "EditorText.matchingNotifications"),
                     "the heading is the pane's; the sentence inside the section is unchanged")
    }
}
