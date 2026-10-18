import XCTest
@testable import NotificationCore

/// While a page's alert is sounding, a match on a rule with no ladder plays nothing, so a
/// noisy rule cannot cut off a page's first alert, repeat or spoken line (1.1 plan,
/// Ruling 14, O8). A page's alert still cuts off another page's, and any alert still cuts
/// off a plain one.
@MainActor
final class PagePrecedenceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private var sounds = 0
    private var asked = 0
    private var begun = 0
    private var pageSounding = false

    override func setUp() {
        sounds = 0
        asked = 0
        begun = 0
        pageSounding = false
    }

    private let plain = Rule(name: "Chatter", condition: .field(.app, .equals, "Slack"),
                             alert: .sound(name: "Pop", gainDB: 0))
    private let page = Rule(name: "On call", condition: .field(.app, .equals, "Microsoft Teams"),
                            alert: .sound(name: "Glass", gainDB: 0),
                            escalation: Escalation(tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0))))

    private func pipeline(selfTest: Bool = false, held: Bool = false, join: EscalationJoin? = nil) -> CapturePipeline {
        CapturePipeline.forTest(
            isSelfTest: { _, _ in selfTest },
            playSound: { [unowned self] name, gain in
                sounds += 1
                return .played(sound: name, gainDB: gain, outputSilent: false)
            },
            isPageSounding: { [unowned self] in
                asked += 1
                return pageSounding
            },
            beginEscalation: { [unowned self] _, _, _, _ in begun += 1 },
            holdForSnooze: { _ in held },
            joinEscalation: { _, _ in join })
    }

    @discardableResult
    private func post(_ p: CapturePipeline, _ app: String, _ title: String, children: [String]? = nil,
                      at offset: TimeInterval = 0) -> CapturePipeline.Outcome {
        p.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: "\(app), \(title)",
                             subrole: "AXNotificationCenterBanner"),
                  textChildren: children ?? [title])
    }

    func testARuleWithNoLadderPlaysNothingWhileAPageIsSounding() {
        pageSounding = true
        let p = pipeline()
        p.setRules([plain])
        post(p, "Slack", "lunch?")
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .heldBackForPage)
        XCTAssertEqual(sounds, 0, "the player is not reached")
        XCTAssertEqual(asked, 1)
    }

    func testARuleWithALadderStillPlaysWhileAPageIsSounding() {
        pageSounding = true
        let p = pipeline()
        p.setRules([page])
        post(p, "Microsoft Teams", "Prod is down")
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false),
                       "a page's alert still cuts off another page's: the newest is the news")
        XCTAssertEqual(begun, 1)
        XCTAssertEqual(asked, 0, "a page is never asked about")
    }

    func testARuleWithNoLadderPlaysWhenNoPageIsSounding() {
        let p = pipeline()
        p.setRules([plain])
        post(p, "Slack", "lunch?")
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .played(sound: "Pop", gainDB: 0, outputSilent: false))
        XCTAssertEqual(sounds, 1)
        XCTAssertEqual(asked, 1)
    }

    func testOnlyAMatchThatWouldPlayAsksWhetherAPageIsSounding() {
        pageSounding = true
        // A match a snooze holds.
        var p = pipeline(held: true)
        p.setRules([plain])
        post(p, "Slack", "held")
        // A match that joins: a rule with a ladder, which is never asked anyway.
        p = pipeline(join: EscalationJoin(matchNumber: 2, alert: nil, ranShortcut: false))
        p.setRules([page])
        post(p, "Microsoft Teams", "joined")
        // A silent rule, and a rule with no alert.
        p = pipeline()
        p.setRules([Rule(name: "Quiet", condition: .field(.app, .equals, "Slack"), alert: .silent),
                    Rule(name: "None", condition: .field(.app, .equals, "Mail"))])
        post(p, "Slack", "quiet")
        post(p, "Mail", "none")
        // The self-test.
        p = pipeline(selfTest: true)
        p.setRules([plain])
        post(p, "Slack", "self-test")
        XCTAssertEqual(asked, 0)

        // A repeat that dedupe drops, and a fuller read of a banner that already set
        // its rule off: each is asked about once, for the first read only.
        pageSounding = false
        p = pipeline()
        p.setRules([plain])
        post(p, "Slack", "lunch?", at: 0)
        post(p, "Slack", "lunch?", at: 0.5)
        XCTAssertEqual(asked, 1, "a repeat is not asked")
        post(p, "Slack", "standup", children: ["standup"], at: 5)
        post(p, "Slack", "standup", children: ["standup", "in 5"], at: 5.3)
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .alreadySetOff)
        XCTAssertEqual(asked, 2, "nor is a read of a banner that already set its rule off")
    }

    func testAnAlertHeldBackForAPageIsNotAFailure() {
        let p = pipeline()
        p.setRules([plain])
        pageSounding = true
        post(p, "Slack", "first")
        XCTAssertNil(p.unresolvedAlertFailure, "nothing failed, and nothing is held as failed")
        XCTAssertFalse(AlertOutcome.heldBackForPage.needsAttention)
        XCTAssertFalse(AlertOutcome.heldBackForPage.wasHeard)
        XCTAssertFalse(AlertOutcome.heldBackForPage.tookThePlayer)
        XCTAssertNil(AlertOutcome.heldBackForPage.spokenText)

        // A failure already held stays held: a held-back alert says nothing is fixed.
        let failing = CapturePipeline.forTest(playSound: { _, _ in .failed("sound \"Pop\" was not found") },
                                              isPageSounding: { [unowned self] in pageSounding })
        failing.setRules([plain])
        pageSounding = false
        post(failing, "Slack", "fails", at: 10)
        let held = failing.unresolvedAlertFailure
        XCTAssertNotNil(held)
        pageSounding = true
        post(failing, "Slack", "held back", at: 20)
        XCTAssertEqual(failing.unresolvedAlertFailure, held)
        XCTAssertEqual(failing.history.entries.first?.alertOutcome, .heldBackForPage,
                       "no fallback plays for it either")
    }

    func testAnAlertHeldBackForAPageIsTheLastMatch() throws {
        pageSounding = true
        let p = pipeline()
        p.setRules([plain])
        post(p, "Slack", "lunch?")
        let last = try XCTUnwrap(p.lastMatch)
        XCTAssertEqual(last.ruleName, "Chatter")
        XCTAssertEqual(last.alert, .heldBackForPage)
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .heldBackForPage)
    }

    func testAPageIsSoundingOnlyWhileTheEscalationsAlertIsPlaying() {
        var owner = PlayerOwnership()
        owner.alertSetOff(.played(sound: "Glass", gainDB: 0, outputSilent: false), byEscalation: true)
        XCTAssertTrue(owner.pageIsSounding(playerBusy: true))
        XCTAssertFalse(owner.pageIsSounding(playerBusy: false), "it has ended, though it was the last to start")
        owner.alertSetOff(.failed("sound \"Hero\" was not found"), byEscalation: false)
        XCTAssertTrue(owner.pageIsSounding(playerBusy: true), "an alert that never reached the player changes nothing")
        owner.alertSetOff(.played(sound: "Pop", gainDB: 0, outputSilent: false), byEscalation: false)
        XCTAssertFalse(owner.pageIsSounding(playerBusy: true), "a plain alert took the player")
        XCTAssertFalse(owner.pageIsSounding(playerBusy: false))
        owner.alertSetOff(.failed("sound \"Hero\" was not found"), byEscalation: true)
        XCTAssertFalse(owner.pageIsSounding(playerBusy: true), "an escalation's alert that failed leaves it as it was")
    }

    /// The line is not a failure, so the harness and the menu, which find a failure by
    /// its stem, never take it for one. It is declared on one line, as the harness reads
    /// such lines from the source.
    func testTheHeldBackLineIsNotAFailureStem() throws {
        XCTAssertEqual(InspectorRowText.alert(.heldBackForPage), "Not played: a page was sounding")
        XCTAssertEqual(InspectorRowText.heldBackForPage, "Not played: a page was sounding")
        for stem in [InspectorRowText.couldNotPlay, InspectorRowText.couldNotSpeak] {
            XCTAssertFalse(InspectorRowText.heldBackForPage.contains(stem), stem)
        }
        let root = PackageRoot.url
        let source = try String(contentsOf: root.appendingPathComponent("Sources/NotificationCore/InspectorEntry.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("    public static let heldBackForPage = \"Not played: a page was sounding\"\n"))
    }
}

/// The app asks the player and its owner, and decides nothing itself. This reads the app
/// target's source, and shows the line is there, not that it runs.
final class PagePrecedenceWiringTests: XCTestCase {
    func testThePipelineAsksThePlayerAndItsOwnerWhetherAPageIsSounding() throws {
        let app = SourceCode.code(of: try XCTUnwrap(AppSources.read("AppDelegate.swift")))
        XCTAssertEqual(app.components(separatedBy: "playerOwnership.pageIsSounding(playerBusy: alertPlayer.isPlayingAlert)").count - 1, 1)
        let capture = SourceCode.code(of: try XCTUnwrap(AppSources.read("CaptureController.swift")))
        XCTAssertEqual(capture.components(separatedBy: "isPageSounding: isPageSounding,").count - 1, 1,
                       "handed to the pipeline as it is given")
        XCTAssertEqual(capture.components(separatedBy: "isPageSounding: @escaping () -> Bool,").count - 1, 1, "with no default")
    }
}
