import XCTest
@testable import NotificationCore

/// The words of a snooze's summary (M5 plan, Task 4, Ruling 18, O9). Rule names
/// here are invented (§10.1).
final class SnoozeTextTests: XCTestCase {
    private let a = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let b = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    private let c = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
    private let d = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
    private let e = UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!

    private func line(_ counts: [UUID: Int], names: [UUID: String], unreadable: Bool = false) -> String? {
        SnoozeText.summaryLine(HeldSummary(counts: counts, recordUnreadable: unreadable), names: names)
    }

    // MARK: - The words

    func testTheWordsArePinned() {
        XCTAssertEqual(SnoozeText.heldStem, "held while snoozed")
        XCTAssertEqual(SnoozeText.heldOneMatchStem, "1 match held while snoozed")
        XCTAssertEqual(SnoozeText.unreadableSentence, "Some matches were held while snoozed and their record could not be read")
        XCTAssertEqual(SnoozeText.unreadableEnding, " — and some other matches were held and their record could not be read")
        XCTAssertEqual(SnoozeText.ruleNotFound, "a rule that cannot be found by its id")
        XCTAssertEqual(SnoozeText.namesShown, 3)
    }

    func testTheSingularStemIsTheCountAndTheStemTheHarnessReadsTogether() {
        XCTAssertTrue(SnoozeText.heldOneMatchStem.hasSuffix(SnoozeText.heldStem))
        XCTAssertTrue(SnoozeText.heldOneMatchStem.hasPrefix("1 match "), "match, and not matches")
    }

    private var constants: [String] {
        [SnoozeText.heldStem, SnoozeText.heldOneMatchStem, SnoozeText.unreadableSentence,
         SnoozeText.unreadableEnding, SnoozeText.ruleNotFound]
    }

    func testACountIsMatchesAndNeverMessagesOrNotifications() {
        for word in constants {
            XCTAssertFalse(word.lowercased().contains("message"), word)
            XCTAssertFalse(word.lowercased().contains("notification"), word)
        }
    }

    /// The words of `text`, as lower case runs of letters, so that a count, a
    /// sign and a stop are none of them words.
    private func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    func testALineIsMadeOfItsFixedWordsItsCountsAndTheRulesOwnNamesAndNamesNoApp() {
        // Rules that match on apps and are named in the user's own words: what a
        // rule matches on is not what the line says (Ruling 18).
        let apps = ["Microsoft Teams", "Slack", "PagerDuty", "Outlook"]
        let ids = [a, b, c, d]
        let ruleNames = ["On-call mentions", "Night shift", "Pager", "Release"]
        let rules = zip(ids, zip(ruleNames, apps)).map { id, entry in
            Rule(id: id, name: entry.0, condition: .field(.app, .equals, entry.1))
        }
        let names = SnoozeText.names(of: rules)
        let lines = [
            line([a: 2, b: 4], names: names),
            line([a: 1], names: names),
            line([a: 1, b: 1, c: 1, d: 1], names: names),
            line([e: 3], names: names),
            line([a: 1, e: 1], names: names, unreadable: true),
            line([:], names: names, unreadable: true),
        ].compactMap { $0 }
        XCTAssertEqual(lines.count, 6)

        let ownWords = Set((constants + ruleNames).flatMap(words) + ["and", "more", "matches"])
        for text in lines {
            for word in words(text) {
                XCTAssertTrue(ownWords.contains(word), "\"\(word)\" in: \(text)")
            }
        }
        for app in apps {
            for text in lines + constants {
                XCTAssertFalse(text.lowercased().contains(app.lowercased()), "\(app) in: \(text)")
            }
        }
    }

    // MARK: - The line

    func testTheLineForTheExampleInThePlan() {
        XCTAssertEqual(line([a: 2, b: 4], names: [a: "On-call mentions", b: "Team chatter"]),
                       "6 matches held while snoozed: On-call mentions ×2, Team chatter ×4")
    }

    func testOneMatchOfOneRuleIsTheSingularStemThenAColonTheNameAndTimesOne() {
        let one = line([a: 1], names: [a: "On-call mentions"])
        XCTAssertEqual(one, "1 match held while snoozed: On-call mentions ×1")
        XCTAssertEqual(one, SnoozeText.heldOneMatchStem + ": " + "On-call mentions" + " ×1", "which is what the harness's guard relies on")
    }

    func testManyMatchesOfOneRuleArePluralWhileTheOneRuleStandsAlone() {
        XCTAssertEqual(line([a: 5], names: [a: "On-call mentions"]), "5 matches held while snoozed: On-call mentions ×5")
        XCTAssertEqual(line([a: 1, b: 1], names: [a: "A", b: "B"]), "2 matches held while snoozed: A ×1, B ×1",
                       "two rules with one match each are two matches")
    }

    func testThreeNamesAreAllShownAndNothingIsSaidOfMore() {
        XCTAssertEqual(line([a: 1, b: 2, c: 3], names: [a: "Alpha", b: "Bravo", c: "Charlie"]),
                       "6 matches held while snoozed: Alpha ×1, Bravo ×2, Charlie ×3")
    }

    func testPastThreeNamesTheRestAreCountedAsMoreAndTheCountAtTheFrontIsStillEveryMatch() {
        let names = [a: "Alpha", b: "Bravo", c: "Charlie", d: "Delta", e: "Echo"]
        XCTAssertEqual(line([a: 1, b: 2, c: 3, d: 4], names: names),
                       "10 matches held while snoozed: Alpha ×1, Bravo ×2, Charlie ×3 and 1 more")
        XCTAssertEqual(line([a: 1, b: 2, c: 3, d: 4, e: 5], names: names),
                       "15 matches held while snoozed: Alpha ×1, Bravo ×2, Charlie ×3 and 2 more")
    }

    func testNamesAreInAlphabeticalOrderWithoutRegardToCaseAndTiesGoToTheLargerCount() {
        XCTAssertEqual(line([a: 1, b: 2, c: 3], names: [a: "banana", b: "Cherry", c: "apple"]),
                       "6 matches held while snoozed: apple ×3, banana ×1, Cherry ×2")
        XCTAssertEqual(line([a: 1, b: 3], names: [a: "Pager", b: "Pager"]),
                       "4 matches held while snoozed: Pager ×3, Pager ×1", "two rules with one name are two entries")
    }

    func testTheNameAsWrittenSettlesWhatCaseLeavesWhateverOrderTheRulesWereCountedIn() {
        // Three names that differ only in case, and ids that are new each time,
        // so that the order a dictionary hands them back in is different each time.
        for _ in 0..<12 {
            let ids = [UUID(), UUID(), UUID()]
            let names = [ids[0]: "pager", ids[1]: "PAGER", ids[2]: "Pager"]
            XCTAssertEqual(line(Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) }), names: names),
                           "3 matches held while snoozed: PAGER ×1, Pager ×1, pager ×1")
        }
    }

    func testTwoRulesThatReadAlikeReadAlikeWhateverOrderTheyWereCountedIn() {
        let names = [a: "Pager", b: "Pager", c: "Pager"]
        XCTAssertEqual(line([a: 1, b: 1, c: 1], names: names), "3 matches held while snoozed: Pager ×1, Pager ×1, Pager ×1")
        XCTAssertEqual(line([c: 1, b: 1], names: [:]),
                       "2 matches held while snoozed: a rule that cannot be found by its id ×1, a rule that cannot be found by its id ×1")
    }

    func testAnIdThatCannotBeFoundReadsThePhraseKeepsItsCountAndComesAfterTheNamedRules() {
        XCTAssertEqual(line([a: 2], names: [:]), "2 matches held while snoozed: a rule that cannot be found by its id ×2")
        XCTAssertEqual(line([a: 1, b: 3, c: 2], names: [a: "Zulu"]),
                       "6 matches held while snoozed: Zulu ×1, a rule that cannot be found by its id ×3, "
                           + "a rule that cannot be found by its id ×2",
                       "named rules first, and those that cannot be found by their counts")
        XCTAssertEqual(line([a: 1], names: [b: "Another rule"]), "1 match held while snoozed: a rule that cannot be found by its id ×1")
    }

    // MARK: - A record that could not be read

    func testARecordThatCannotBeReadIsTheSentenceAloneWhenNothingCouldBeCounted() {
        XCTAssertEqual(line([:], names: [a: "Pager"], unreadable: true),
                       "Some matches were held while snoozed and their record could not be read")
    }

    func testARecordThatCannotBeReadIsSaidAfterTheLineOfWhatCouldBeCounted() {
        XCTAssertEqual(line([a: 1], names: [a: "Pager"], unreadable: true),
                       "1 match held while snoozed: Pager ×1 — and some other matches were held and their record could not be read")
        XCTAssertEqual(line([a: 1, b: 1, c: 1, d: 1], names: [a: "A", b: "B", c: "C", d: "D"], unreadable: true),
                       "4 matches held while snoozed: A ×1, B ×1, C ×1 and 1 more"
                           + " — and some other matches were held and their record could not be read")
    }

    func testThereIsNoLineForNothing() {
        XCTAssertNil(line([:], names: [a: "Pager"]))
        XCTAssertNil(SnoozeText.summaryLine(HeldSummary(), names: [:]))
    }

    // MARK: - The names

    func testNamesAreTakenFromTheRulesByIdAndTwoRulesWithOneIdGiveTheFirst() {
        let condition = RuleCondition.field(.app, .equals, "Microsoft Teams")
        let rules = [
            Rule(id: a, name: "First", condition: condition),
            Rule(id: b, name: "Second", condition: condition),
            Rule(id: a, name: "Duplicate of the first", condition: condition),
        ]
        XCTAssertEqual(SnoozeText.names(of: rules), [a: "First", b: "Second"])
        XCTAssertEqual(SnoozeText.names(of: []), [:])
    }
}
