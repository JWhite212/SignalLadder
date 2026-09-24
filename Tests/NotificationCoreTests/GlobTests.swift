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

    // MARK: - Characters that fold to more than one character

    func testAQuestionMarkMatchesOneCharacterEvenWhenFoldingLengthensIt() {
        // Case-folding turns ß into "ss" and the ligature ﬁ into "fi". `?` must
        // still consume one character of the ORIGINAL text. It did not — and the
        // code comment of the time claimed the length change was harmless.
        XCTAssertTrue(Glob.matches("Straße", pattern: "Stra?e"))
        XCTAssertTrue(Glob.matches("ﬁle", pattern: "?le"))
        XCTAssertFalse(Glob.matches("Straße", pattern: "Stra??e"))
    }

    func testFoldingEquivalenceStillHoldsForLiterals() {
        // The fix above must not cost what whole-string folding gave: literals
        // stay equivalent under folding, consistent with equals and contains.
        XCTAssertTrue(Glob.matches("STRASSE", pattern: "straße"))
        XCTAssertTrue(Glob.matches("Straße", pattern: "strasse"))
    }

    func testAStarIsAWildcardEvenWhereTheTextHoldsAnAsterisk() {
        // A pattern `*` meeting a literal `*` in the text was consumed as a
        // literal, so "*" failed to match "**" — and a rule like "*urgent*"
        // silently never fired on a message that itself used *emphasis*.
        XCTAssertTrue(Glob.matches("**", pattern: "*"))
        XCTAssertTrue(Glob.matches("a*b", pattern: "a*"))
        XCTAssertTrue(Glob.matches("*urgent* deploy", pattern: "*urgent*"))
    }

    /// Checked against an exhaustive matcher over the same model: fold, then
    /// let `?` consume one original character. Exponential and obviously
    /// correct, so the linear matcher must agree with it everywhere. Both bugs
    /// above lived exactly where hand-written cases had not looked; random
    /// input over the troublesome characters looks everywhere. Seeded, so a
    /// failure reproduces.
    func testAgreesWithAnExhaustiveMatcherOnRandomInput() {
        func reference(_ text: String, _ pattern: String) -> Bool {
            let (t, ends) = Glob.foldedWithBoundaries(text)
            let p = Array(Glob.fold(pattern))
            func go(_ i: Int, _ j: Int) -> Bool {
                if j == p.count { return i == t.count }
                switch p[j] {
                case "*": return (i...t.count).contains { go($0, j + 1) }
                case "?": return i < t.count && go(ends[i], j + 1)
                default:  return i < t.count && t[i] == p[j] && go(i + 1, j + 1)
                }
            }
            return go(0, 0)
        }

        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let textAlphabet = ["a", "b", "s", "ß", "ﬁ", "é", "E", "🔥", "*", "?"]
        let patternAlphabet = ["a", "b", "s", "ß", "f", "i", "e", "?", "*"]

        for _ in 0..<20_000 {
            let text = (0..<next(7)).map { _ in textAlphabet[next(textAlphabet.count)] }.joined()
            let pattern = (0..<next(6)).map { _ in patternAlphabet[next(patternAlphabet.count)] }.joined()
            let fast = Glob.matches(text, pattern: pattern)
            let slow = reference(text, pattern)
            if fast != slow {
                return XCTFail("\(text.debugDescription) vs \(pattern.debugDescription): matcher \(fast), reference \(slow)")
            }
        }
    }
}
