import XCTest
@testable import NotificationCore

final class CaptureDeduplicatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    func testFirstSightingIsNotARepeat() {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("a", at: t0)
        XCTAssertFalse(first.isRepeat)
        XCTAssertEqual(first.repeatCount, 0)
        XCTAssertNotNil(first.banner)
    }

    func testSecondSightingInsideWindowIsARepeat() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        let second = d.admit("a", at: t0.addingTimeInterval(0.5))
        XCTAssertTrue(second.isRepeat)
        XCTAssertEqual(second.repeatCount, 1)
        XCTAssertNil(second.banner, "a repeat reaches no rule, so it is of no banner")
    }

    func testRepeatCountIncrementsAcrossSuccessiveHits() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        _ = d.admit("a", at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(d.admit("a", at: t0.addingTimeInterval(0.4)).repeatCount, 2)
    }

    func testDistinctKeysDoNotCollide() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        XCTAssertFalse(d.admit("b", at: t0.addingTimeInterval(0.1)).isRepeat)
    }

    func testSightingAfterWindowIsTreatedAsNew() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        XCTAssertFalse(d.admit("a", at: t0.addingTimeInterval(2.0)).isRepeat)
    }

    /// The window is anchored to first sighting, not refreshed on each hit, so
    /// a source repeating faster than the window cannot suppress forever.
    func testWindowIsNotSlidingSoFastRepeatsCannotSuppressIndefinitely() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        _ = d.admit("a", at: t0.addingTimeInterval(1.0))
        XCTAssertFalse(d.admit("a", at: t0.addingTimeInterval(1.6)).isRepeat,
                       "Repeats must not keep extending the window")
    }

    // MARK: - The text compared is the description and the text children

    /// A read that kept the description and lost a child, then one that found
    /// it: the same raw text, and not the same text.
    func testTheSameDescriptionWithDifferentChildrenIsNotARepeat() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("Teams, Alice, Prod is down", textChildren: ["Alice"], at: t0)
        XCTAssertFalse(d.admit("Teams, Alice, Prod is down", textChildren: ["Alice", "Prod is down"],
                               at: t0.addingTimeInterval(0.3)).isRepeat)
    }

    func testTheSameDescriptionAndChildrenIsARepeat() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("Teams, Alice, hi", textChildren: ["Alice", "hi"], at: t0)
        XCTAssertTrue(d.admit("Teams, Alice, hi", textChildren: ["Alice", "hi"], at: t0.addingTimeInterval(0.3)).isRepeat)
    }

    /// Two banners whose descriptions were both lost are told apart by their
    /// children.
    func testTwoReadsWithNoDescriptionAndDifferentChildrenAreNotRepeats() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("", textChildren: ["Bob", "Lunch?"], at: t0)
        XCTAssertFalse(d.admit("", textChildren: ["Alice", "Prod is down"], at: t0.addingTimeInterval(0.2)).isRepeat)
    }

    // MARK: - Reads of one banner

    private let rule = UUID()

    /// A read whose text holds all of an earlier read's is a fuller read of the
    /// same banner, and carries what that banner has already set off.
    func testAReadHoldingAllOfAnEarlierReadsTextIsOfTheSameBanner() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice, Prod is down", textChildren: ["Alice"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        let fuller = d.admit("Teams, Alice, Prod is down", textChildren: ["Alice", "Prod is down"],
                             at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(fuller.banner, first.banner)
        XCTAssertEqual(fuller.setOff, [rule])
    }

    /// And a read all of whose text an earlier read held is a poorer read of it:
    /// here a description lost to a timeout.
    func testAReadAllOfWhoseTextAnEarlierReadHeldIsOfTheSameBanner() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice, Prod is down", textChildren: ["Alice", "Prod is down"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        let poorer = d.admit("", textChildren: ["Alice", "Prod is down"], at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(poorer.banner, first.banner)
        XCTAssertEqual(poorer.setOff, [rule])
    }

    /// A follow-up from the same sender keeps the title and replaces the body.
    /// Neither read holds the other's text, so it is a banner of its own.
    func testAReadThatReplacesSomeOfTheTextIsANewBanner() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice, hi", textChildren: ["Alice", "hi"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        let followUp = d.admit("Teams, Alice, Prod is down", textChildren: ["Alice", "Prod is down"],
                               at: t0.addingTimeInterval(0.3))
        XCTAssertNotEqual(followUp.banner, first.banner)
        XCTAssertEqual(followUp.setOff, [])
    }

    /// Another app's banner with text in common is not the same banner: its
    /// description names another app.
    func testAnotherAppsBannerIsNotTheSameBanner() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice", textChildren: ["Alice"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        XCTAssertEqual(d.admit("Slack, Alice, Prod is down", textChildren: ["Alice", "Prod is down"],
                               at: t0.addingTimeInterval(0.3)).setOff, [])
    }

    /// The banner is forgotten one window after its FIRST read, however many
    /// reads of it came since, as a repeat's window is: a banner read again and
    /// again cannot hold a rule back for ever.
    func testABannerIsForgottenOneWindowAfterItsFirstReadNotItsLatest() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice", textChildren: ["Alice"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        XCTAssertEqual(d.admit("Teams, Alice, hi", textChildren: ["Alice", "hi"], at: t0.addingTimeInterval(1.0)).setOff,
                       [rule])
        let late = d.admit("Teams, Alice, hi, there", textChildren: ["Alice", "hi", "there"],
                           at: t0.addingTimeInterval(1.6))
        XCTAssertNotEqual(late.banner, first.banner)
        XCTAssertEqual(late.setOff, [])
    }

    /// A clock set back leaves earlier sightings dated in the future. They are
    /// forgotten, so the same text is not a repeat and a banner does not hold a
    /// rule back for as long as the clock was moved (found on 2026-10-16).
    func testAClockSetBackForgetsWhatWasSeenAheadOfIt() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("PagerDuty, Triggered, db down", at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        let afterTheStep = t0.addingTimeInterval(-50)
        let again = d.admit("PagerDuty, Triggered, db down", at: afterTheStep)
        XCTAssertFalse(again.isRepeat)
        XCTAssertEqual(again.setOff, [])
        XCTAssertTrue(d.admit("PagerDuty, Triggered, db down", at: afterTheStep.addingTimeInterval(0.5)).isRepeat,
                      "the window counts again from the new clock")
    }

    /// A partial read, here only the title, is held by every banner that shares
    /// it. Matched against each read on its own, it joined the next banner with
    /// that title to the one before, and the next one's match was taken as
    /// already set off: five marker banners, read together from an alert stack,
    /// counted as one match (#165). A read is matched against all the text a
    /// banner's reads have shown, so it cannot bridge two.
    func testAPartialReadDoesNotJoinTwoBannersThatShareItsText() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Script Editor, SignalLadder Test, Escalation check, banner 1 of 5",
                            textChildren: ["SignalLadder Test", "Escalation check, banner 1 of 5"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        let partial = d.admit("", textChildren: ["SignalLadder Test"], at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(partial.banner, first.banner, "a read the first banner holds is a poorer read of it")
        let second = d.admit("Script Editor, SignalLadder Test, Escalation check, banner 2 of 5",
                             textChildren: ["SignalLadder Test", "Escalation check, banner 2 of 5"],
                             at: t0.addingTimeInterval(0.2))
        XCTAssertNotEqual(second.banner, first.banner)
        XCTAssertEqual(second.setOff, [], "the second banner has set nothing off")
    }

    /// The same, with the partial read first: the first full read joins it, and
    /// the second full read does not.
    func testAPartialReadFirstStillJoinsOnlyTheBannerWhoseTextHoldsIt() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let partial = d.admit("", textChildren: ["SignalLadder Test"], at: t0)
        let first = d.admit("Script Editor, SignalLadder Test, Escalation check, banner 1 of 5",
                            textChildren: ["SignalLadder Test", "Escalation check, banner 1 of 5"],
                            at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(first.banner, partial.banner)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        let second = d.admit("Script Editor, SignalLadder Test, Escalation check, banner 2 of 5",
                             textChildren: ["SignalLadder Test", "Escalation check, banner 2 of 5"],
                             at: t0.addingTimeInterval(0.2))
        XCTAssertNotEqual(second.banner, first.banner)
        XCTAssertEqual(second.setOff, [])
    }

    /// Five distinct banners with one title, each read in full and with partial
    /// reads among them, all inside one window, are five banners.
    func testABurstOfDistinctBannersWithPartialReadsAmongThemIsEachItsOwn() throws {
        let d = CaptureDeduplicator(window: 1.5)
        var banners: [Int] = []
        for n in 1...5 {
            let at = t0.addingTimeInterval(Double(n) * 0.05)
            let full = d.admit("Script Editor, SignalLadder Test, Escalation check, banner \(n) of 5",
                               textChildren: ["SignalLadder Test", "Escalation check, banner \(n) of 5"], at: at)
            XCTAssertEqual(full.setOff, [], "banner \(n)")
            let id = try XCTUnwrap(full.banner)
            d.noteSetOff(rule, banner: id)
            banners.append(id)
            _ = d.admit("", textChildren: ["SignalLadder Test"], at: at.addingTimeInterval(0.01))
        }
        XCTAssertEqual(Set(banners).count, 5)
    }

    /// A read with no text at all holds nothing, and is taken for no banner.
    func testAReadWithNoTextIsTakenForNoOtherBanner() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice", textChildren: ["Alice"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        XCTAssertEqual(d.admit("", textChildren: [], at: t0.addingTimeInterval(0.3)).setOff, [])
    }
}
