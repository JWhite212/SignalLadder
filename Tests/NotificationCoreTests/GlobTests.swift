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

    func testWildcardsNeverSplitACharacter() {
        // ß folds to "ss" and ﬁ to "fi". A literal may cover such a character
        // through its folded form, but a wildcard may not start or stop inside
        // one: `?` is one whole character and `*` absorbs whole characters.
        // Before this, "s?" matched "ß" — `?` matching half a character.
        XCTAssertFalse(Glob.matches("ß", pattern: "s?"))
        XCTAssertFalse(Glob.matches("ß", pattern: "s*"))
        XCTAssertFalse(Glob.matches("ẞ", pattern: "*s"))
        XCTAssertFalse(Glob.matches("ﬁ", pattern: "f?"))
        XCTAssertFalse(Glob.matches("ﬂ", pattern: "f*"))
        XCTAssertFalse(Glob.matches("Straße", pattern: "Stras?e"))
        XCTAssertTrue(Glob.matches("ﬁre", pattern: "fi*"), "a literal covering the whole ligature still matches")
    }

    func testWildcardsAreOnlyTheCharactersTheUserTyped() {
        // An asterisk carrying an accent folds to a plain "*". It must stay the
        // literal it was written as, not become a wildcard.
        XCTAssertFalse(Glob.matches("x", pattern: "*\u{301}"))
        XCTAssertTrue(Glob.matches("*\u{301}", pattern: "*"))
    }

    /// Checked against an INDEPENDENT reference: it works on whole original
    /// characters and whole literal runs, with its own tokeniser, and shares
    /// no helper with the matcher. An earlier version of this test used the
    /// matcher's own `foldedWithBoundaries` in its reference — so it agreed
    /// with the matcher on 200,000 inputs while both were wrong about "s?"
    /// against "ß". A reference that shares a model with the code cannot
    /// check that model. Seeded, so a failure reproduces.
    func testAgreesWithAnIndependentMatcherOnRandomInput() {
        func reference(_ text: String, _ pattern: String) -> Bool {
            func fold(_ s: String) -> [Character] {
                Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
            }
            let characters = text.map { fold(String($0)) }
            enum Part { case anyRun, anyOne, literal([Character]) }
            var parts: [Part] = []
            var run: [Character] = []
            for c in pattern {
                if c == "*" || c == "?" {
                    if !run.isEmpty { parts.append(.literal(run)); run = [] }
                    parts.append(c == "*" ? .anyRun : .anyOne)
                } else {
                    run += fold(String(c))
                }
            }
            if !run.isEmpty { parts.append(.literal(run)) }

            func go(_ i: Int, _ j: Int) -> Bool {
                if j == parts.count { return i == characters.count }
                switch parts[j] {
                case .anyRun:
                    return (i...characters.count).contains { go($0, j + 1) }
                case .anyOne:
                    return i < characters.count && go(i + 1, j + 1)
                case .literal(let wanted):
                    // A literal run must cover whole characters.
                    var covered: [Character] = []
                    var k = i
                    while k < characters.count, covered.count < wanted.count {
                        covered += characters[k]
                        k += 1
                    }
                    return covered == wanted && go(k, j + 1)
                }
            }
            return go(0, 0)
        }

        var seed: UInt64 = 0xB0D1
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let textAlphabet = ["a", "s", "f", "i", "l", "e", "ß", "ẞ", "ﬁ", "ﬂ", "é", "e\u{301}", "E", "🔥", "👍🏽", "*", "?"]
        let patternAlphabet = ["a", "s", "f", "i", "l", "e", "ß", "ﬁ", "é", "E", "?", "*"]

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

    func testAnIdenticalLiteralAlwaysMatchesItself() {
        // Folding a whole string and folding it one character at a time can
        // differ (invisible format characters beside Cyrillic combining marks).
        // Text and pattern must be folded by the same procedure, so that any
        // string, however exotic, matches itself.
        for sample in ["\u{2064}\u{0486}", "\u{0301},ξ", "\u{206A}\u{0486}Ǯ", "ṡī\u{2064}\u{0483}ᾫ", "Straße", "🇬🇧 #prod"] {
            XCTAssertTrue(Glob.matches(sample, pattern: sample), sample.debugDescription)
        }
    }
}
