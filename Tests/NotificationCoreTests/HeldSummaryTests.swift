import XCTest
@testable import NotificationCore

/// What a snooze held, as it is kept and read back (M5 plan, Task 4, Ruling 12,
/// O9). The saved shape is pinned in literals, so that a change to it is a
/// choice and not a drift. Ids are invented (§10.1).
final class HeldSummaryTests: XCTestCase {
    private let a = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let b = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func read(_ stored: Any?) -> HeldSummary { HeldSummary(stored: stored, now: now) }

    /// A record as the preferences would hand it back, with `counts` and the rest.
    private func record(_ counts: Any, since: Any? = 1_789_999_000.0, unannounced: Any? = 2, extra: [String: Any] = [:]) -> [String: Any] {
        var record: [String: Any] = ["counts": counts]
        if let since { record["since"] = since }
        if let unannounced { record["unannounced"] = unannounced }
        return record.merging(extra) { $1 }
    }

    // MARK: - What is saved

    func testTheSavedShapeIsADictionaryOfCountsByIdATimeAndAWholeNumberToAnnounce() throws {
        let summary = HeldSummary(counts: [a: 2, b: 1], firstHeldAt: Date(timeIntervalSince1970: 1_789_999_000), unannounced: 3)
        let saved = try XCTUnwrap(summary.propertyList)
        let literal: [String: Any] = [
            "counts": [a.uuidString: 2, b.uuidString: 1],
            "since": 1_789_999_000.0,
            "unannounced": 3,
        ]
        XCTAssertEqual(NSDictionary(dictionary: saved), NSDictionary(dictionary: literal))
        XCTAssertEqual(Set(saved.keys), ["counts", "since", "unannounced"], "and nothing else")
        XCTAssertTrue(saved["unannounced"] is Int, "a whole number")
        XCTAssertTrue(saved["since"] is Double, "seconds since 1970, in a real number")
        let counts = try XCTUnwrap(saved["counts"] as? [String: Int], "whole numbers keyed by the id's string")
        XCTAssertEqual(counts.count, 2)
    }

    func testARecordWithAnUnreadableEarlierPartSaysSoAsTheWholeNumberOne() throws {
        let saved = try XCTUnwrap(HeldSummary(counts: [a: 1], unannounced: 0, recordUnreadable: true).propertyList)
        let literal: [String: Any] = ["counts": [a.uuidString: 1], "unannounced": 0, "unreadable": 1]
        XCTAssertEqual(NSDictionary(dictionary: saved), NSDictionary(dictionary: literal),
                       "no time is made up for a record that has none")
        XCTAssertTrue(saved["unreadable"] is Int)

        let alone = try XCTUnwrap(HeldSummary(recordUnreadable: true).propertyList)
        let aloneLiteral: [String: Any] = ["counts": [String: Int](), "unannounced": 0, "unreadable": 1]
        XCTAssertEqual(NSDictionary(dictionary: alone), NSDictionary(dictionary: aloneLiteral),
                       "an unreadable record is saved as one, and is not dropped")
    }

    func testAnEmptySummarySavesNothingAtAll() {
        XCTAssertNil(HeldSummary().propertyList)
        XCTAssertTrue(HeldSummary().isEmpty)
    }

    func testWhatIsSavedIsReadBackAsItWas() {
        for summary in [
            HeldSummary(counts: [a: 2, b: 1], firstHeldAt: Date(timeIntervalSince1970: 1_789_999_000), unannounced: 3),
            HeldSummary(counts: [a: 5], firstHeldAt: nil, unannounced: 0),
            HeldSummary(counts: [a: 1], firstHeldAt: Date(timeIntervalSince1970: 1_789_999_000), unannounced: 1, recordUnreadable: true),
            HeldSummary(recordUnreadable: true),
        ] {
            XCTAssertEqual(read(summary.propertyList), summary)
        }
    }

    // MARK: - What is read

    func testAbsentIsNone() {
        XCTAssertEqual(read(nil), HeldSummary())
        XCTAssertTrue(read(nil).isEmpty)
    }

    func testAValueThatIsThereAndCannotBeReadAsARecordIsUnreadableAndHoldsNothing() {
        let values: [(label: String, value: Any)] = [
            ("a string", "garbled"),
            ("a number", 5),
            ("a Boolean", true),
            ("a list", [1, 2]),
            ("a null", NSNull()),
            ("an empty dictionary", [String: Any]()),
            ("a record with no counts", ["unannounced": 2]),
            ("counts that are not a dictionary", ["counts": "two"]),
            ("counts that are a list", ["counts": [2]]),
            ("a dictionary with keys that are not strings", [1: 2]),
        ]
        for entry in values {
            let summary = read(entry.value)
            XCTAssertTrue(summary.recordUnreadable, entry.label)
            XCTAssertFalse(summary.isEmpty, "\(entry.label) is reported, never silence")
            XCTAssertEqual(summary.counts, [:], entry.label)
            XCTAssertEqual(summary.unannounced, 0, entry.label)
        }
    }

    func testAnEntryThatCannotBeReadIsLeftOutAndMarksTheRecordWhileTheRestIsKept() {
        let bad: [(label: String, key: String, value: Any)] = [
            ("a key that is not an id", "not-an-id", 3),
            ("zero", b.uuidString, 0),
            ("a negative number", b.uuidString, -1),
            ("a fraction", b.uuidString, 1.5),
            ("true", b.uuidString, true),
            ("a string", b.uuidString, "2"),
            ("not a number", b.uuidString, Double.nan),
            ("infinite", b.uuidString, Double.infinity),
            ("past what a count can be", b.uuidString, HeldSummary.largestReadableCount + 1),
            ("a list", b.uuidString, [2]),
        ]
        for entry in bad {
            let summary = read(record([a.uuidString: 2, entry.key: entry.value]))
            XCTAssertEqual(summary.counts, [a: 2], entry.label)
            XCTAssertTrue(summary.recordUnreadable, entry.label)
        }
    }

    func testAWholeNumberInAnyBoxIsACountAndTheLargestReadableOneIsRead() {
        XCTAssertEqual(HeldSummary.largestReadableCount, 2_147_483_647)
        let summary = read(record([a.uuidString: 2.0, b.uuidString: 2_147_483_647]))
        XCTAssertEqual(summary.counts, [a: 2, b: 2_147_483_647])
        XCTAssertFalse(summary.recordUnreadable)
        XCTAssertEqual(summary.total, 2 + 2_147_483_647)
        XCTAssertTrue(read(record([b.uuidString: 2_147_483_648])).recordUnreadable, "one more is not a count")
    }

    func testTwoKeysThatReadAsOneIdAreAddedAndNotDropped() {
        let summary = read(record([a.uuidString: 2, a.uuidString.lowercased(): 3]))
        XCTAssertEqual(summary.counts, [a: 5])
        XCTAssertFalse(summary.recordUnreadable)
    }

    func testAnUnknownKeyBesideTheFieldsIsIgnoredAndTheMarkerIsReadWhateverItHolds() {
        XCTAssertFalse(read(record([a.uuidString: 2], extra: ["somethingNew": 1])).recordUnreadable)
        for marker in [1, 0, true, "yes", NSNull()] as [Any] {
            XCTAssertTrue(read(record([a.uuidString: 2], extra: ["unreadable": marker])).recordUnreadable, "\(marker)")
        }
        XCTAssertEqual(read(record([a.uuidString: 2], extra: ["unreadable": 1])).counts, [a: 2], "and the counts are kept")
    }

    func testTheTimeOfTheFirstHoldIsNeverLaterThanNowAndIsNotMadeUp() {
        XCTAssertEqual(read(record([a.uuidString: 1], since: 1_789_999_000.0)).firstHeldAt, Date(timeIntervalSince1970: 1_789_999_000))
        XCTAssertEqual(read(record([a.uuidString: 1], since: 1_790_086_400.0)).firstHeldAt, now, "from the future reads as now")
        for unreadable in [-1.0, Double.nan, Double.infinity, true, "yesterday", Date(), [1.0]] as [Any] {
            let summary = read(record([a.uuidString: 1], since: unreadable))
            XCTAssertNil(summary.firstHeldAt, "\(unreadable)")
            XCTAssertFalse(summary.recordUnreadable, "a time is not a page, so it does not mark the record: \(unreadable)")
            XCTAssertEqual(summary.counts, [a: 1])
        }
        XCTAssertNil(read(record([a.uuidString: 1], since: nil)).firstHeldAt)
    }

    func testWhatIsStillToBeAnnouncedIsReadAndAnUnreadableNumberOwesWhatWasCounted() {
        XCTAssertEqual(read(record([a.uuidString: 3, b.uuidString: 2], unannounced: 4)).unannounced, 4)
        XCTAssertEqual(read(record([a.uuidString: 3, b.uuidString: 2], unannounced: 0)).unannounced, 0)
        for unreadable in [-1, 1.5, "2", true, Double.nan, HeldSummary.largestReadableCount + 1, NSNull()] as [Any] {
            XCTAssertEqual(read(record([a.uuidString: 3, b.uuidString: 2], unannounced: unreadable)).unannounced, 5,
                           "\(unreadable): the user is told once more, and not never")
        }
        XCTAssertEqual(read(record([a.uuidString: 3], unannounced: nil)).unannounced, 3, "absent")
        XCTAssertEqual(read(record([String: Int](), unannounced: 5)).unannounced, 0, "with nothing held there is nothing to announce")
    }

    // MARK: - Holding

    func testAHoldAddsToTheRuleAndToWhatIsToBeAnnouncedAndTheFirstSetsTheTime() {
        var summary = HeldSummary()
        summary.recordHold(of: a, at: now)
        summary.recordHold(of: b, at: now + 60)
        summary.recordHold(of: a, at: now + 120)
        XCTAssertEqual(summary.counts, [a: 2, b: 1])
        XCTAssertEqual(summary.firstHeldAt, now, "the first, and not the last")
        XCTAssertEqual(summary.unannounced, 3)
        XCTAssertEqual(summary.total, 3)
        summary.settled()
        XCTAssertEqual(summary.unannounced, 0)
        XCTAssertEqual(summary.counts, [a: 2, b: 1], "what was held stays")
        summary.recordHold(of: b, at: now + 180)
        XCTAssertEqual(summary.unannounced, 1)
        XCTAssertEqual(summary.firstHeldAt, now)
    }

    func testAHoldDoesNotMakeUpATimeForARecordThatLostItsOwn() {
        var summary = read(record([a.uuidString: 1], since: nil))
        summary.recordHold(of: a, at: now + 60)
        XCTAssertNil(summary.firstHeldAt)
        var unreadable = HeldSummary(recordUnreadable: true)
        unreadable.recordHold(of: a, at: now + 60)
        XCTAssertNil(unreadable.firstHeldAt, "earlier matches were held that cannot be dated")
        XCTAssertTrue(unreadable.recordUnreadable)
    }

    // MARK: - Dismissing

    func testDismissingTakesOutWhatWasShownRuleByRuleAndLeavesWhatWasHeldSince() {
        var summary = HeldSummary(counts: [a: 3, b: 1], firstHeldAt: now, unannounced: 4)
        summary.dismiss(HeldSummary(counts: [a: 2], firstHeldAt: now, unannounced: 2))
        XCTAssertEqual(summary.counts, [a: 1, b: 1], "one of a's and all of b's came after what was shown")
        XCTAssertEqual(summary.unannounced, 2)
    }

    func testDismissingAllThatWasHeldLeavesNothingAtAll() {
        var summary = HeldSummary(counts: [a: 2, b: 1], firstHeldAt: now, unannounced: 3)
        summary.dismiss(summary)
        XCTAssertEqual(summary, HeldSummary())
        XCTAssertNil(summary.propertyList, "so the key goes")
    }

    func testWhatIsToBeAnnouncedFallsByWhatTheShownOneWasToAnnounceAndNeverBelowZero() {
        var announcedSince = HeldSummary(counts: [a: 3], unannounced: 3)
        announcedSince.dismiss(HeldSummary(counts: [a: 1], unannounced: 0))
        XCTAssertEqual(announcedSince.unannounced, 3, "the shown one had nothing left to announce")

        var settledSince = HeldSummary(counts: [a: 2], unannounced: 0)
        settledSince.dismiss(HeldSummary(counts: [a: 1], unannounced: 3))
        XCTAssertEqual(settledSince.unannounced, 0, "it was announced after the line was drawn, and does not go below zero")

        var extra = HeldSummary(counts: [a: 2], unannounced: 7)
        extra.dismiss(HeldSummary(counts: [a: 2], unannounced: 2))
        XCTAssertEqual(extra.unannounced, 0, "with nothing left held there is nothing to announce")
    }

    func testTheTimeOfTheFirstHoldGoesWhenAnythingIsTakenOutAndStaysWhenNothingIs() {
        var summary = HeldSummary(counts: [a: 2], firstHeldAt: now, unannounced: 2)
        summary.dismiss(HeldSummary(counts: [b: 1], unannounced: 1))
        XCTAssertEqual(summary.firstHeldAt, now, "nothing was taken out")
        summary.dismiss(HeldSummary(counts: [a: 1], unannounced: 1))
        XCTAssertNil(summary.firstHeldAt, "the first of what is left was held later, and when is not kept")
        XCTAssertEqual(summary.counts, [a: 1])
    }

    func testDismissingWhatIsNotThereTakesOutNothingAndChangesNothing() {
        let before = HeldSummary(counts: [a: 1], firstHeldAt: now, unannounced: 1)
        var summary = before
        summary.dismiss(HeldSummary(counts: [b: 5], unannounced: 5))
        XCTAssertEqual(summary, before)
        summary.dismiss(HeldSummary())
        XCTAssertEqual(summary, before)
    }

    func testARecordThatCannotBeReadIsClearedOnlyByAShownOneThatSaidSo() {
        var summary = HeldSummary(counts: [a: 1], unannounced: 1, recordUnreadable: true)
        summary.dismiss(HeldSummary(counts: [a: 1], unannounced: 1))
        XCTAssertTrue(summary.recordUnreadable, "the line did not say so")
        XCTAssertTrue(summary.counts.isEmpty)
        summary.dismiss(HeldSummary(recordUnreadable: true))
        XCTAssertFalse(summary.recordUnreadable)
        XCTAssertTrue(summary.isEmpty)
    }

    func testACountThatIsNotPositiveIsNotKept() {
        let summary = HeldSummary(counts: [a: 0, b: -2], unannounced: -3)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.unannounced, 0)
    }
}
