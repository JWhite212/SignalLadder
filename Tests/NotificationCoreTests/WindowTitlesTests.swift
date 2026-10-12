import XCTest
@testable import NotificationCore

/// The window titles the app's controllers show (M5 plan, Ruling 18). The first
/// two were typed into their controllers until they moved here, and the first
/// test holds them to the words they had then, so that moving them changed
/// nothing a user reads, or a script looks for.
final class WindowTitlesTests: XCTestCase {
    func testTheTwoTitlesThatMovedHereAreTheWordsTheyWereBefore() {
        XCTAssertEqual(WindowTitles.inspector, "SignalLadder Inspector")
        XCTAssertEqual(WindowTitles.ruleEditor, "SignalLadder Rules")
    }

    func testTheOnCallChecksTitleIsItsOwn() {
        XCTAssertEqual(WindowTitles.onCallCheck, "SignalLadder On-Call Check")
    }

    func testTheSettingsTitleIsItsOwn() {
        XCTAssertEqual(WindowTitles.settings, "SignalLadder Settings")
    }

    func testTheSetupGuidesTitleIsItsOwnAndNamesTheWindowTheSettingsButtonOpens() {
        XCTAssertEqual(WindowTitles.setupGuide, "SignalLadder Setup Guide")
        // Settings' button opens the window by the name the window has, so a user who presses
        // it sees the words they pressed.
        XCTAssertTrue(WindowTitles.setupGuide.hasSuffix("Setup Guide"))
        XCTAssertTrue(SetupText.openGuideButton.contains("Setup Guide"), SetupText.openGuideButton)
    }

    func testNoTwoTitlesAreAlikeAndEachBeginsWithTheAppsName() {
        let titles = [WindowTitles.inspector, WindowTitles.ruleEditor, WindowTitles.onCallCheck, WindowTitles.settings,
                      WindowTitles.setupGuide]
        XCTAssertEqual(Set(titles).count, titles.count, "two windows with one title cannot be told apart by a script")
        for title in titles {
            XCTAssertTrue(title.hasPrefix("SignalLadder"), "\(title) does not begin with the app's name")
        }
    }
}
