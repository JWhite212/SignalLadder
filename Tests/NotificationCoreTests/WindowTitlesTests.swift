import XCTest
@testable import NotificationCore

/// The window titles the app's controllers show (M5 plan, Ruling 18). The two
/// that exist were typed into their controllers until they moved here, and the
/// first test holds them to the words they had then, so that moving them
/// changed nothing a user reads, or a script looks for.
final class WindowTitlesTests: XCTestCase {
    func testTheTwoTitlesThatMovedHereAreTheWordsTheyWereBefore() {
        XCTAssertEqual(WindowTitles.inspector, "SignalLadder Inspector")
        XCTAssertEqual(WindowTitles.ruleEditor, "SignalLadder Rules")
    }

    func testNoTwoTitlesAreAlikeAndEachBeginsWithTheAppsName() {
        let titles = [WindowTitles.inspector, WindowTitles.ruleEditor]
        XCTAssertEqual(Set(titles).count, titles.count, "two windows with one title cannot be told apart by a script")
        for title in titles {
            XCTAssertTrue(title.hasPrefix("SignalLadder"), "\(title) does not begin with the app's name")
        }
    }
}
