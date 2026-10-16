import XCTest
@testable import NotificationCore

/// A banner read a second time with different text. `BannerTracker` captures a
/// read that finds text the last one did not, since the fuller text may match a
/// rule the first read could not, so the pipeline must let it reach the rules:
/// only text that is the same, description and text children alike, is a repeat
/// that never does (M3a plan, Ruling 10). And one banner never sets one rule off
/// twice: a read whose text holds all of an earlier read's, or all of whose text
/// an earlier read held, inside dedupe's window, is a read of the same banner,
/// and does not set off again a rule that banner has already set off.
///
/// Most tests hand each banner the tracker captures to the pipeline, as the
/// watcher does, so that what reaches the rules is what a live read would hand
/// on. Nothing plays and nothing waits on a real clock. Fixtures are invented
/// text (§10.1).
@MainActor
final class FullerReadTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    /// In the order they happened: "gate", "join", each sound as "play:Glass",
    /// and "begin:<rule>".
    private var events: [String] = []
    private var held = false

    override func setUp() {
        events = []
        held = false
    }

    private func pipeline() -> CapturePipeline {
        CapturePipeline(ownAppName: "SignalLadder", isSelfTest: { _, _ in false },
                        playSound: { [unowned self] name, gain in
                            events.append("play:\(name)")
                            return .played(sound: name, gainDB: gain, outputSilent: false)
                        },
                        speak: { text, speech in
                            .spoke(text: text, voice: "Daniel", gainDB: speech.gainDB, outputSilent: false)
                        },
                        playAndSpeak: { name, gain, text, speech in
                            .playedAndSpoke(sound: name, soundGainDB: gain, text: text, voice: "Daniel",
                                            speechGainDB: speech.gainDB, outputSilent: false)
                        },
                        beginEscalation: { [unowned self] rule, _, _, _ in events.append("begin:\(rule.name)") },
                        holdForSnooze: { [unowned self] _ in
                            events.append("gate")
                            return held
                        },
                        joinEscalation: { [unowned self] _, _ in
                            events.append("join")
                            return nil
                        })
    }

    private var played: [String] { events.filter { $0.hasPrefix("play:") } }

    private let ladder = Escalation(tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0)))

    /// A rule that only the body can set off.
    private lazy var prodDown = Rule(name: "Prod down", condition: .field(.body, .contains, "prod is down"),
                                     alert: .sound(name: "Sosumi", gainDB: 0), escalation: ladder)

    /// A rule that any read with the sender's name sets off.
    private let fromAlice = Rule(name: "From Alice", condition: .field(.title, .equals, "Alice"),
                                 alert: .sound(name: "Glass", gainDB: 0))

    /// The window a banner is shown in, reduced to the wrappers seen live.
    private func window(_ banner: FakeNode) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(children: [banner])])])
        ])
    }

    /// One read of a banner element, with the description and the children that
    /// read found. A description of nil is one lost to a timeout.
    private func read(_ children: [String], description: String? = "Teams, Alice, Prod is down",
                      element: String = "a") -> FakeNode {
        FakeNode(subrole: "AXNotificationCenterBanner", description: description, id: element,
                 children: children.map { FakeNode(value: $0) })
    }

    /// Hands on each banner the tracker captures, as the watcher does.
    @discardableResult
    private func scan(_ tracker: BannerTracker, _ p: CapturePipeline, _ banner: FakeNode,
                      at offset: TimeInterval) -> [(BannerTracker.Sighting, CapturePipeline.Outcome)] {
        let at = t0.addingTimeInterval(offset)
        return tracker.scan(window(banner), at: at).new.map { sighting in
            (sighting, p.process(RawCapture(timestamp: at, rawText: sighting.rawText, subrole: sighting.subrole),
                                 textChildren: sighting.textChildren))
        }
    }

    @discardableResult
    private func capture(_ p: CapturePipeline, _ description: String, _ children: [String],
                         at offset: TimeInterval) -> CapturePipeline.Outcome {
        p.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: description,
                             subrole: "AXNotificationCenterBanner"), textChildren: children)
    }

    // MARK: - A fuller read reaches the rules

    /// The first read lost the body's child to a timeout, which any read of
    /// another process can, and kept the description whole. Its fields come from
    /// its one child, so its body is empty and the rule on the body does not
    /// match. The next read finds the body, and the tracker captures it again,
    /// with the same description: that read must reach the rule. It is asked at
    /// the times Task 5's bounded re-reads would come (M6 plan, B1: 0.3 s and
    /// 1.0 s) and at the end of dedupe's window, each inside it.
    func testAFullerReadWithTheSameDescriptionReachesTheRules() {
        for offset in [0.3, 1.0, 1.45] {
            setUp()
            let tracker = BannerTracker()
            let p = pipeline()
            p.setRules([prodDown])

            let first = scan(tracker, p, read(["Alice"]), at: 0)
            XCTAssertEqual(first.map(\.1), [.recorded(matchedRule: nil)], "at \(offset)")

            let second = scan(tracker, p, read(["Alice", "Prod is down"]), at: offset)
            XCTAssertEqual(second.count, 1, "the tracker captures the fuller read, at \(offset)")
            XCTAssertEqual(second.first?.0.rawText, first.first?.0.rawText,
                           "both reads hand on the same description as the raw text, at \(offset)")
            XCTAssertEqual(second.first?.1, .recorded(matchedRule: "Prod down"), "at \(offset)")
            XCTAssertEqual(events, ["gate", "join", "play:Sosumi", "begin:Prod down"], "at \(offset)")
            XCTAssertEqual(p.history.entries.first?.alertOutcome,
                           .played(sound: "Sosumi", gainDB: 0, outputSilent: false), "at \(offset)")
            XCTAssertEqual(p.lastMatch?.ruleName, "Prod down", "at \(offset)")
            XCTAssertEqual(p.captureCount, 2, "each read has a row, at \(offset)")
        }
    }

    /// A description lost to a timeout is handed on empty, and two different
    /// banners each read without one carried the same raw text. The second was
    /// taken for a repeat of the first and never reached a rule.
    func testTwoBannersEachReadWithoutADescriptionAreBothRecorded() {
        let p = pipeline()
        p.setRules([prodDown])
        XCTAssertEqual(capture(p, "", ["Bob", "Lunch?"], at: 0), .recorded(matchedRule: nil))
        XCTAssertEqual(capture(p, "", ["Alice", "Prod is down"], at: 0.2), .recorded(matchedRule: "Prod down"))
        XCTAssertEqual(played, ["play:Sosumi"])
    }

    // MARK: - A true repeat is still a repeat

    /// The same description and the same children inside the window: one
    /// banner's animation, or two notifications that cannot be told apart. It is
    /// counted on its row and never reaches the rules, so it never sounds.
    func testTheSameTextAgainIsStillARepeatThatNeverReachesTheRules() {
        let p = pipeline()
        p.setRules([fromAlice])
        XCTAssertEqual(capture(p, "Teams, Alice, hi", ["Alice", "hi"], at: 0), .recorded(matchedRule: "From Alice"))
        XCTAssertEqual(capture(p, "Teams, Alice, hi", ["Alice", "hi"], at: 0.4), .suppressedRepeat)
        XCTAssertEqual(events, ["gate", "play:Glass"])
        XCTAssertEqual(p.captureCount, 1)
        XCTAssertEqual(p.history.entries.first?.suppressedRepeatCount, 1)
    }

    /// A repeat of the partial read lands on the partial read's row, not on the
    /// fuller read's, although both carry the same description: the row it
    /// counts on is the one with the text dedupe compared.
    func testARepeatOfThePartialReadIsCountedOnItsOwnRow() {
        let p = pipeline()
        capture(p, "Teams, Alice, Prod is down", ["Alice"], at: 0)
        capture(p, "Teams, Alice, Prod is down", ["Alice", "Prod is down"], at: 0.3)
        XCTAssertEqual(capture(p, "Teams, Alice, Prod is down", ["Alice"], at: 0.5), .suppressedRepeat)
        XCTAssertEqual(p.history.entries.map(\.suppressedRepeatCount), [0, 1], "newest first")
    }

    // MARK: - One banner sets one rule off once

    /// The partial read already set the rule off. The fuller read matches the
    /// same rule: it has a row of its own, which says so, and plays nothing,
    /// asks no snooze and leaves the last match as it was.
    func testAFullerReadMatchingTheRuleTheBannerAlreadySetOffDoesNotSoundItAgain() {
        let tracker = BannerTracker()
        let p = pipeline()
        p.setRules([fromAlice])

        scan(tracker, p, read(["Alice"]), at: 0)
        let last = p.lastMatch
        let second = scan(tracker, p, read(["Alice", "Prod is down"]), at: 0.3)

        XCTAssertEqual(second.map(\.1), [.recorded(matchedRule: "From Alice")])
        XCTAssertEqual(events, ["gate", "play:Glass"], "one sound for one banner, and one question to the snooze")
        XCTAssertEqual(p.history.entries.first?.annotation, MatchAnnotation(ruleName: "From Alice"))
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .alreadySetOff)
        XCTAssertEqual(p.history.entries.last?.alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false),
                       "the first read's row keeps what it did")
        XCTAssertEqual(p.lastMatch, last)
    }

    /// For a rule with a ladder, the fuller read neither joins the escalation
    /// its first read began, which would count one banner as two matches and
    /// could play its first alert again, nor begins another.
    func testAFullerReadOfALadderRuleAlreadySetOffNeitherJoinsNorBeginsAgain() {
        let tracker = BannerTracker()
        let p = pipeline()
        let alice = Rule(name: "From Alice", condition: .field(.title, .equals, "Alice"),
                         alert: .sound(name: "Glass", gainDB: 0), escalation: ladder)
        p.setRules([alice])

        scan(tracker, p, read(["Alice"]), at: 0)
        scan(tracker, p, read(["Alice", "Prod is down"]), at: 0.3)

        XCTAssertEqual(events, ["gate", "join", "play:Glass", "begin:From Alice"])
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .alreadySetOff)
    }

    /// A match the snooze held set the rule off as much as one that played: the
    /// fuller read is not held a second time, so the snooze counts one banner
    /// once.
    func testAFullerReadOfAMatchTheSnoozeHeldIsNotHeldAgain() {
        let tracker = BannerTracker()
        let p = pipeline()
        p.setRules([fromAlice])
        held = true

        scan(tracker, p, read(["Alice"]), at: 0)
        scan(tracker, p, read(["Alice", "Prod is down"]), at: 0.3)

        XCTAssertEqual(events, ["gate"])
        XCTAssertEqual(p.history.entries.map(\.alertOutcome), [.alreadySetOff, .snoozed])
    }

    /// The fuller text matches a different rule, higher in the list, which the
    /// partial text could not. That rule has not been set off for this banner,
    /// and it may be the one that pages, so it sounds and begins its ladder, as a
    /// match of its own. The first read's alert has already played and its row
    /// keeps it. One alert too many is the price, and never one too few.
    func testAFullerReadMatchingAHigherRuleSetsThatRuleOff() {
        let tracker = BannerTracker()
        let p = pipeline()
        p.setRules([prodDown, fromAlice])

        let first = scan(tracker, p, read(["Alice"]), at: 0)
        let second = scan(tracker, p, read(["Alice", "Prod is down"]), at: 0.3)

        XCTAssertEqual(first.map(\.1), [.recorded(matchedRule: "From Alice")])
        XCTAssertEqual(second.map(\.1), [.recorded(matchedRule: "Prod down")])
        XCTAssertEqual(events, ["gate", "play:Glass", "gate", "join", "play:Sosumi", "begin:Prod down"])
        XCTAssertEqual(p.lastMatch?.ruleName, "Prod down")
    }

    /// The other way round: the full read came first, and a later read of the
    /// same banner has less text, as when macOS lays a banner out again as a new
    /// element and that read loses its description. It used to reach the rules
    /// with a different raw text and sound the same rule a second time.
    func testALaterReadWithLessTextDoesNotSoundTheRuleAgain() {
        let tracker = BannerTracker()
        let p = pipeline()
        p.setRules([fromAlice])

        scan(tracker, p, read(["Alice", "Prod is down"]), at: 0)
        let second = scan(tracker, p, read(["Alice", "Prod is down"], description: nil, element: "b"), at: 0.4)

        XCTAssertEqual(second.map(\.1), [.recorded(matchedRule: "From Alice")])
        XCTAssertEqual(played, ["play:Glass"])
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .alreadySetOff)
    }

    /// A follow-up from the same sender can arrive in the same element: the
    /// same title over a new body (M6 plan, Ruling 13). Neither read holds all
    /// of the other's text, so the second is a banner of its own, and sets the
    /// rule off again, as it did before.
    func testAFollowUpInTheSameElementSetsTheRuleOffAgain() {
        let tracker = BannerTracker()
        let p = pipeline()
        p.setRules([fromAlice])

        scan(tracker, p, read(["Alice", "hi"], description: "Teams, Alice, hi"), at: 0)
        let second = scan(tracker, p, read(["Alice", "Prod is down"]), at: 0.5)

        XCTAssertEqual(second.map(\.1), [.recorded(matchedRule: "From Alice")])
        XCTAssertEqual(played, ["play:Glass", "play:Glass"])
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false))
    }

    /// The window is dedupe's, anchored to the banner's first read and never
    /// lengthened by a later one. A fuller read after it is taken for a new
    /// banner and sets the rule off again: one alert too many, never one too few.
    func testAFullerReadAfterTheWindowSetsTheRuleOffAgain() {
        let tracker = BannerTracker()
        let p = pipeline()
        p.setRules([fromAlice])

        scan(tracker, p, read(["Alice"]), at: 0)
        scan(tracker, p, read(["Alice", "Prod is down"]), at: 1.0)
        let third = scan(tracker, p, read(["Alice", "Prod is down", "Sev 1"],
                                          description: "Teams, Alice, Prod is down, Sev 1"), at: 1.6)

        XCTAssertEqual(third.map(\.1), [.recorded(matchedRule: "From Alice")])
        XCTAssertEqual(played, ["play:Glass", "play:Glass"])
        XCTAssertEqual(p.history.entries.map(\.alertOutcome),
                       [.played(sound: "Glass", gainDB: 0, outputSilent: false), .alreadySetOff,
                        .played(sound: "Glass", gainDB: 0, outputSilent: false)])
    }
}
