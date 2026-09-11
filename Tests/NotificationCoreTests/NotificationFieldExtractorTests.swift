// Tests/NotificationCoreTests/NotificationFieldExtractorTests.swift
import XCTest
@testable import NotificationCore

final class NotificationFieldExtractorTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_757_000_000)

    private func extract(_ text: String,
                         children: [String] = [],
                         subrole: String = "AXNotificationCenterBanner") -> CapturedNotification {
        NotificationFieldExtractor.extract(
            RawCapture(timestamp: when, rawText: text, subrole: subrole),
            textChildren: children
        )
    }

    // MARK: - Primary path: text children

    /// Real capture, macOS 26.7, Script Editor via osascript.
    func testThreeChildrenMapToTitleSubtitleBody() {
        let n = extract("Script Editor, Test Title, Test Sub, Placeholder body",
                        children: ["Test Title", "Test Sub", "Placeholder body"])
        XCTAssertEqual(n.appNameGuess, "Script Editor")
        XCTAssertEqual(n.title, "Test Title")
        XCTAssertEqual(n.subtitle, "Test Sub")
        XCTAssertEqual(n.body, "Placeholder body")
    }

    /// Real capture, macOS 26.7, Microsoft Teams. Note the Alert subrole.
    func testTwoChildrenMapToTitleAndBody() {
        let n = extract("Microsoft Teams, This is a test notification, Message preview.",
                        children: ["This is a test notification", "Message preview."],
                        subrole: "AXNotificationCenterAlert")
        XCTAssertEqual(n.appNameGuess, "Microsoft Teams")
        XCTAssertEqual(n.title, "This is a test notification")
        XCTAssertEqual(n.subtitle, "")
        XCTAssertEqual(n.body, "Message preview.")
        XCTAssertEqual(n.subrole, "AXNotificationCenterAlert")
    }

    func testOneChildMapsToTitleOnly() {
        let n = extract("SomeApp, Just a title", children: ["Just a title"])
        XCTAssertEqual(n.appNameGuess, "SomeApp")
        XCTAssertEqual(n.title, "Just a title")
        XCTAssertEqual(n.subtitle, "")
        XCTAssertEqual(n.body, "")
    }

    /// Children win over the description even when the two disagree — the
    /// children are authoritative because they are already separated.
    func testChildrenTakePrecedenceOverCommaSplitting() {
        let n = extract("App, Smith, John, the body",
                        children: ["Smith, John", "the body"])
        XCTAssertEqual(n.appNameGuess, "App")
        XCTAssertEqual(n.title, "Smith, John",
                       "A comma inside a child value must survive intact")
        XCTAssertEqual(n.body, "the body")
    }

    func testMoreThanThreeChildrenKeepsFirstThreeAndJoinsRemainderIntoBody() {
        let n = extract("App, a, b, c, d", children: ["a", "b", "c", "d"])
        XCTAssertEqual(n.title, "a")
        XCTAssertEqual(n.subtitle, "b")
        XCTAssertEqual(n.body, "c d")
    }

    // MARK: - Fallback path: comma splitting

    func testFallsBackToCommaSplittingWhenNoChildren() {
        let n = extract("Weather, Rain expected at 3pm")
        XCTAssertEqual(n.appNameGuess, "Weather")
        XCTAssertEqual(n.title, "Rain expected at 3pm")
        XCTAssertEqual(n.subtitle, "")
        XCTAssertEqual(n.body, "")
    }

    func testFallbackWithThreeSegmentsFillsTitleAndBody() {
        let n = extract("App, Title, Body")
        XCTAssertEqual(n.appNameGuess, "App")
        XCTAssertEqual(n.title, "Title")
        XCTAssertEqual(n.body, "Body")
    }

    func testFallbackWithFourSegmentsFillsAllThree() {
        let n = extract("App, Title, Sub, Body")
        XCTAssertEqual(n.appNameGuess, "App")
        XCTAssertEqual(n.title, "Title")
        XCTAssertEqual(n.subtitle, "Sub")
        XCTAssertEqual(n.body, "Body")
    }

    /// Five or more segments means at least one field contained a comma. The
    /// surplus is rejoined into the body with its comma restored, so no text
    /// is silently lost — the whole point of the fallback being lossy-but-
    /// complete rather than lossy-and-truncating.
    func testFallbackWithFiveSegmentsRejoinsSurplusIntoBody() {
        let n = extract("App, Title, Sub, Body part one, body part two")
        XCTAssertEqual(n.appNameGuess, "App")
        XCTAssertEqual(n.title, "Title")
        XCTAssertEqual(n.subtitle, "Sub")
        XCTAssertEqual(n.body, "Body part one, body part two",
                       "The comma must be restored when rejoining surplus segments")
    }

    func testFallbackWithManySegmentsLosesNoText() {
        let n = extract("App, T, S, a, b, c, d")
        XCTAssertEqual(n.body, "a, b, c, d")
    }

    func testFallbackWithNoCommaPutsEverythingInTitle() {
        let n = extract("Some unparseable banner text")
        XCTAssertEqual(n.appNameGuess, "")
        XCTAssertEqual(n.title, "Some unparseable banner text")
    }

    func testEmptyStringYieldsEmptyFields() {
        let n = extract("")
        XCTAssertEqual(n.appNameGuess, "")
        XCTAssertEqual(n.title, "")
        XCTAssertEqual(n.subtitle, "")
        XCTAssertEqual(n.body, "")
    }

    /// The documented lossy case: with commas as the only delimiter and no
    /// newline to fall back on, a comma inside a field is indistinguishable
    /// from a field boundary. This is why rawText is preserved.
    func testFallbackMisparsesCommaInsideAFieldButPreservesRaw() {
        let text = "Microsoft Teams, Example, Alex, body text"
        let n = extract(text)
        XCTAssertEqual(n.appNameGuess, "Microsoft Teams")
        XCTAssertEqual(n.title, "Example")
        XCTAssertEqual(n.subtitle, "Alex")
        XCTAssertEqual(n.body, "body text")
        XCTAssertEqual(n.rawText, text, "rawText must survive untouched")
    }

    // MARK: - Invariants

    func testRawTextAndSubroleAlwaysPreserved() {
        let text = "App, Title, Sub, Body"
        let n = extract(text, children: ["Title", "Sub", "Body"])
        XCTAssertEqual(n.rawText, text)
        XCTAssertEqual(n.subrole, "AXNotificationCenterBanner")
        XCTAssertEqual(n.timestamp, when)
    }

    func testTrimsWhitespaceAroundAllFields() {
        let n = extract("  App ,  Title  ", children: ["  Title  ", "  Body  "])
        XCTAssertEqual(n.appNameGuess, "App")
        XCTAssertEqual(n.title, "Title")
        XCTAssertEqual(n.body, "Body")
    }
}
