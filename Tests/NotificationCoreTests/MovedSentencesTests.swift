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

    /// The editor's lines that are built from a name, moved from its views (#97 part two).
    func testTheEditorsBuiltLinesSayWhatTheViewsSaid() {
        XCTAssertEqual(EditorText.soundNotFound("Klaxon"), "Klaxon (not found)")
        XCTAssertEqual(EditorText.voiceNotInstalled("com.apple.voice.compact.en-GB.Daniel"),
                       "com.apple.voice.compact.en-GB.Daniel (not installed)")
        XCTAssertEqual(EditorText.voiceChoice(name: "Daniel", language: "en-GB"), "Daniel — en-GB")
        XCTAssertEqual(EditorText.takenBy("Mute Weather"), "— taken by “Mute Weather”")
        XCTAssertEqual(EditorText.saveFailedDetail("The disk is full."),
                       "The disk is full.\n\nNothing was changed: rules.json is as it was, and your draft is still here.")
        XCTAssertEqual("Pager" + EditorText.copySuffix, "Pager (copy)")
    }

    /// The Inspector's lines built from a row, moved from its view.
    func testTheInspectorsBuiltLinesSayWhatTheViewSaid() {
        XCTAssertEqual(InspectorRowText.suppressed(3), "3 suppressed")
        XCTAssertEqual(InspectorRowText.said("Prod is down"), "Said: “Prod is down”")
        XCTAssertEqual(SetupText.label(for: .makeRule), InspectorRowText.makeRuleFromThis, "one wording for one act")
    }

    /// The main menu's Edit items keep the names macOS gives them, which is what lets a user
    /// find them, and the Window menu's Close.
    func testTheMainMenuKeepsTheStandardNames() {
        XCTAssertEqual([MainMenuText.edit, MainMenuText.undo, MainMenuText.redo, MainMenuText.cut, MainMenuText.copy,
                        MainMenuText.paste, MainMenuText.delete, MainMenuText.selectAll],
                       ["Edit", "Undo", "Redo", "Cut", "Copy", "Paste", "Delete", "Select All"])
        XCTAssertEqual([MainMenuText.window, MainMenuText.close], ["Window", "Close"])
    }
}
