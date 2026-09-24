import XCTest
@testable import NotificationCore

final class GlobTests: XCTestCase {
    func testLiteralPatternMustMatchTheWholeString() {
        XCTAssertTrue(Glob.matches("#prod", pattern: "#prod"))
        XCTAssertFalse(Glob.matches("#prod-api", pattern: "#prod"),
                       "anchored: a glob is not a substring search — that is `contains`")
    }

    func testStarMatchesAnyRunIncludingNone() {
        XCTAssertTrue(Glob.matches("#prod-api", pattern: "#prod-*"))
        XCTAssertTrue(Glob.matches("#prod-", pattern: "#prod-*"))
        XCTAssertFalse(Glob.matches("#staging-api", pattern: "#prod-*"))
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        XCTAssertTrue(Glob.matches("P1", pattern: "P?"))
        XCTAssertFalse(Glob.matches("P", pattern: "P?"))
        XCTAssertFalse(Glob.matches("P10", pattern: "P?"))
    }

    func testStarsCanAppearAnywhereAndRepeat() {
        XCTAssertTrue(Glob.matches("incident in #prod-db resolved", pattern: "*#prod-*"))
        XCTAssertTrue(Glob.matches("abc", pattern: "***"))
        XCTAssertTrue(Glob.matches("", pattern: "*"))
    }

    func testEmptyPatternMatchesOnlyTheEmptyString() {
        XCTAssertTrue(Glob.matches("", pattern: ""))
        XCTAssertFalse(Glob.matches("x", pattern: ""))
    }

    func testMatchingIsCaseAndDiacriticInsensitive() {
        // §5.11. A rule written in lower case must still match the banner.
        XCTAssertTrue(Glob.matches("Microsoft Teams", pattern: "microsoft*"))
        XCTAssertTrue(Glob.matches("Équipe Opérations", pattern: "equipe*"))
    }

    func testAQuestionMarkSpansOneWholeCharacterNotOneByte() {
        // Grapheme clusters, not UTF-16 units: an emoji is one character.
        XCTAssertTrue(Glob.matches("🔥 P1", pattern: "? P1"))
    }

    /// The reason `matches` is glob and not regex. A backtracking matcher
    /// takes exponential time on this input; this one must finish instantly,
    /// because a rule runs against every notification on the main thread.
    func testAPathologicalPatternFinishesQuickly() {
        let text = String(repeating: "a", count: 5_000)
        let pattern = String(repeating: "*a", count: 40) + "*b"

        let start = Date()
        XCTAssertFalse(Glob.matches(text, pattern: pattern))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0,
                          "O(n·m) worst case; anything slower means backtracking crept back in")
    }
}
