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

    /// A read with no text at all holds nothing, and is taken for no banner.
    func testAReadWithNoTextIsTakenForNoOtherBanner() throws {
        let d = CaptureDeduplicator(window: 1.5)
        let first = d.admit("Teams, Alice", textChildren: ["Alice"], at: t0)
        d.noteSetOff(rule, banner: try XCTUnwrap(first.banner))
        XCTAssertEqual(d.admit("", textChildren: [], at: t0.addingTimeInterval(0.3)).setOff, [])
    }
}
