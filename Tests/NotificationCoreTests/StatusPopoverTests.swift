import XCTest
@testable import NotificationCore

/// What the status item's popover shows, and what a press of the item opens
/// (M7 plan, Stage 5). Every line is one the menu's text types wrote, so each
/// test gives the builder the menu's own words and asks where they stand.
final class StatusPopoverTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func time(_ date: Date) -> String { date == start ? "10:42" : "later" }

    /// A summary carrying notification text wherever it can.
    private func summary(_ status: EscalationSummary.Status = .live, name: String = "On-call mentions", tier: Int = 3,
                         repeats: Int = 4, cap: Int? = 20, final: FinalOutcome? = nil) -> EscalationSummary {
        EscalationSummary(ruleName: name, startedAt: start, status: status, tierReached: tier,
                          repeatCount: repeats, repeatCap: cap,
                          lastRepeat: .spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0, outputSilent: false),
                          final: final ?? .alerted(.spoke(text: "Placeholder body text", voice: "Daniel", gainDB: 0,
                                                          outputSilent: false)))
    }

    private let idleSnooze = SnoozeMenu(items: [.snooze(title: SnoozeText.menuTitle, submenu: [
        .start(.fifteenMinutes, title: "For 15 minutes"), .start(.oneHour, title: "For 1 hour"),
    ])])

    private func facts(listed: [EscalationSummary] = [], shortcutFailure: CapturePipeline.ShortcutFailure? = nil,
                       healthTitle: String = "Working — verified 3 min ago", cause: HealthCause? = nil,
                       setupNudge: String? = nil, onCall: Bool = false, onCallLines: [String] = [],
                       onCallFindings: [String] = [], snooze: SnoozeMenu? = nil,
                       ruleDetail: [String] = [], ruleLines: [String] = [],
                       launchAtLoginLine: String? = nil) -> StatusPopover.Facts {
        StatusPopover.Facts(listed: listed, shortcutFailure: shortcutFailure, healthTitle: healthTitle, cause: cause,
                            setupNudge: setupNudge, onCall: onCall, onCallLines: onCallLines,
                            onCallFindings: onCallFindings, snooze: snooze ?? idleSnooze,
                            capturedLine: StatusMenuText.capturedLine(count: 212),
                            ruleSummary: "3 rules in effect", ruleDetail: ruleDetail, ruleLines: ruleLines,
                            launchAtLoginLine: launchAtLoginLine)
    }

    private func content(_ facts: StatusPopover.Facts) -> StatusPopover.Content {
        StatusPopover.content(facts, time: time)
    }

    private func section(_ heading: String, in content: StatusPopover.Content) -> [StatusPopover.Line]? {
        content.sections.first { $0.heading == heading }?.lines
    }

    // MARK: - Nothing waiting

    func testWithNothingListedThereIsNoBlockAndNoAcknowledge() {
        let shown = content(facts())
        XCTAssertTrue(shown.waiting.isEmpty)
        XCTAssertNil(shown.acknowledgeTitle)
        XCTAssertNil(shown.moreWaiting)
        XCTAssertTrue(shown.escalationLines.isEmpty)
    }

    func testTheQuietPopoverHasCaptureAndRulesAndNoOnCallSection() {
        let shown = content(facts())
        XCTAssertEqual(shown.sections.map(\.heading), [StatusPopoverText.captureHeading, StatusPopoverText.rulesHeading])
        XCTAssertEqual(section(StatusPopoverText.captureHeading, in: shown)?.map(\.text),
                       ["Working — verified 3 min ago", "Captured 212 notifications"])
        XCTAssertEqual(section(StatusPopoverText.rulesHeading, in: shown)?.map(\.text), ["3 rules in effect"])
    }

    // MARK: - What waits

    func testAnEscalationIsABlockInItsTiersColourWithItsRepeatsLarge() throws {
        let shown = content(facts(listed: [summary()]))
        let block = try XCTUnwrap(shown.waiting.first)
        XCTAssertEqual(shown.waiting.count, 1)
        XCTAssertEqual(block.row, EscalationPanelText.row(for: summary(), time: time), "the panel's row, word for word")
        XCTAssertEqual(block.tone, .upper)
        XCTAssertEqual(block.figure, "04/20")
        XCTAssertEqual(shown.acknowledgeTitle, AlertMenuText.acknowledgeTitle(listed: 1))
    }

    func testEachTierHasItsOwnColour() {
        let shown = content(facts(listed: [summary(tier: 1), summary(tier: 2), summary(tier: 4)]))
        XCTAssertEqual(shown.waiting.map(\.tone), [.first, .second, .upper])
    }

    func testBeforeTheFirstRepeatThereIsNoLargeFigure() {
        XCTAssertNil(content(facts(listed: [summary(tier: 1, repeats: 0)])).waiting.first?.figure)
    }

    func testARepeatWithNoLimitIsTheCountAlone() {
        XCTAssertEqual(content(facts(listed: [summary(cap: nil)])).waiting.first?.figure, "4")
    }

    func testAFailedShortcutsBlockHasNoColourAndNoFigure() throws {
        let failed = summary(tier: 4, final: .shortcutFailed(name: "Page me", reason: "not installed"))
        let block = try XCTUnwrap(content(facts(listed: [failed])).waiting.first)
        XCTAssertNil(block.tone, "a fault is never a tier's colour")
        XCTAssertNil(block.figure)
        XCTAssertEqual(block.row.mark, .fault)
    }

    func testOneMissedWhileAsleepIsAFaultBlock() throws {
        let missed = summary(.missedWhileAsleep(convertedAt: start, acknowledgedAt: nil))
        let block = try XCTUnwrap(content(facts(listed: [missed])).waiting.first)
        XCTAssertNil(block.tone)
        XCTAssertEqual(block.row.mark, .fault)
    }

    func testMoreThanTheLimitAreCountedAndAcknowledgeIsForThemAll() {
        let listed = (1...5).map { summary(name: "Rule \($0)") }
        let shown = content(facts(listed: listed))
        XCTAssertEqual(shown.waiting.count, StatusPopover.waitingLimit)
        XCTAssertEqual(shown.waiting.map(\.row.name), ["Rule 1", "Rule 2", "Rule 3"])
        XCTAssertEqual(shown.moreWaiting, "and 2 more")
        XCTAssertEqual(shown.acknowledgeTitle, AlertMenuText.acknowledgeTitle(listed: 5))
    }

    func testExactlyTheLimitSaysNothingOfMore() {
        XCTAssertNil(content(facts(listed: (1...3).map { summary(name: "Rule \($0)") })).moreWaiting)
    }

    func testTheEscalationLinesAreTheMenus() {
        let failure = CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: start,
                                                      reason: "the Shortcut is not installed")
        let listed = [summary(), summary(.missedWhileAsleep(convertedAt: start, acknowledgedAt: nil))]
        let shown = content(facts(listed: listed, shortcutFailure: failure))
        XCTAssertEqual(shown.escalationLines.map(\.text),
                       AlertMenuText.escalationLines(listed: listed, shortcutFailure: failure, time: time))
        XCTAssertEqual(shown.escalationLines.first?.mark, .fault, "the failed Shortcut's line has the menu's warning sign")
        XCTAssertEqual(shown.escalationLines.dropFirst().map(\.mark), [.plain, .plain])
        XCTAssertTrue(shown.escalationLines.allSatisfy { $0.action == nil })
    }

    func testAFailedShortcutWithNothingListedStillHasItsLine() {
        let failure = CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: start,
                                                      reason: "the Shortcut is not installed")
        let shown = content(facts(shortcutFailure: failure))
        XCTAssertEqual(shown.escalationLines.count, 1)
        XCTAssertNil(shown.acknowledgeTitle)
    }

    /// The popover is drawn where anyone can see it, as the panel is.
    func testNothingThatArrivedIsAnywhereInIt() {
        let shown = content(facts(listed: [summary(), summary(tier: 4, final: .shortcutFailed(name: "Page me", reason: "x"))]))
        let words = String(describing: shown)
        XCTAssertFalse(words.contains("Alex Example"))
        XCTAssertFalse(words.contains("Placeholder body text"))
    }

    // MARK: - The lines

    func testACauseIsAFaultThatOpensItsPane() throws {
        let cause = HealthCause.notificationPermissionDenied
        let lines = try XCTUnwrap(section(StatusPopoverText.captureHeading, in: content(facts(healthTitle: "Not working",
                                                                                           cause: cause))))
        XCTAssertEqual(lines.map(\.text), ["Not working", cause.advice, "Captured 212 notifications"])
        XCTAssertEqual(lines[1].mark, .fault)
        XCTAssertEqual(lines[1].action, cause.pane.map(StatusPopover.Action.openPane))
    }

    func testACauseNoPaneFixesIsAFaultThatDoesNothing() throws {
        let cause = HealthCause.observerNotAttached
        XCTAssertNil(cause.pane)
        let lines = try XCTUnwrap(section(StatusPopoverText.captureHeading, in: content(facts(cause: cause))))
        XCTAssertEqual(lines[1].mark, .fault)
        XCTAssertNil(lines[1].action)
    }

    func testTheSetupLineShowsTheGuide() throws {
        let lines = try XCTUnwrap(section(StatusPopoverText.captureHeading,
                                          in: content(facts(setupNudge: "Setup: 2 steps left"))))
        XCTAssertEqual(lines.map(\.text), ["Working — verified 3 min ago", "Setup: 2 steps left", "Captured 212 notifications"])
        XCTAssertEqual(lines[1].action, .showSetupGuide)
    }

    func testWhileOnCallItsLinesAndFindingsAreShownAndAnUrgentOneIsAFault() throws {
        let urgent = OnCallText.urgentMark + "No rule is enabled"
        let shown = content(facts(onCall: true, onCallLines: ["On call since Mon 09:00", "Keeping this Mac awake"],
                                  onCallFindings: [urgent, "Launch at login is off"]))
        let lines = try XCTUnwrap(section(StatusPopoverText.onCallHeading, in: shown))
        XCTAssertEqual(lines.map(\.text), ["On call since Mon 09:00", "Keeping this Mac awake", urgent, "Launch at login is off"])
        XCTAssertEqual(lines.map(\.mark), [.plain, .plain, .fault, .plain])
    }

    func testOffCallItsLinesAreNotShownEvenIfGiven() {
        let shown = content(facts(onCall: false, onCallLines: ["On call since Mon 09:00"], onCallFindings: ["x"]))
        XCTAssertNil(section(StatusPopoverText.onCallHeading, in: shown))
    }

    func testASnoozesLinesAndDismissAreWithOnCallAndItsChoicesAreTheTiles() throws {
        let held = HeldSummary()
        let snooze = SnoozeMenu(items: [
            .snooze(title: SnoozeText.menuTitle, submenu: [.line("On call: only ticked rules are quiet"),
                                                           .start(.thirtyMinutes, title: "For 30 minutes"),
                                                           .end(title: "End Snooze")]),
            .line("Snoozed until 15:30"),
            .line("3 matches were held"),
            .dismiss(title: "Dismiss", shown: held),
        ])
        let shown = content(facts(snooze: snooze))
        let lines = try XCTUnwrap(section(StatusPopoverText.onCallHeading, in: shown))
        XCTAssertEqual(lines.map(\.text), ["Snoozed until 15:30", "3 matches were held", "Dismiss"])
        XCTAssertEqual(lines.map(\.action), [nil, nil, .dismissHeld(held)])
        XCTAssertEqual(shown.snoozeChoices.map(\.text), ["On call: only ticked rules are quiet", "For 30 minutes", "End Snooze"])
        XCTAssertEqual(shown.snoozeChoices.map(\.action), [nil, .startSnooze(.thirtyMinutes), .endSnooze])
    }

    func testTheLaunchAtLoginLineIsShownWhenTheMenuShowsIt() throws {
        let shown = content(facts(launchAtLoginLine: LaunchAtLoginText.menuLine))
        XCTAssertEqual(try XCTUnwrap(section(StatusPopoverText.onCallHeading, in: shown)).map(\.text),
                       [LaunchAtLoginText.menuLine])
    }

    func testTheRulesDetailIsIndentedAndAWarningIsAFault() throws {
        let shown = content(facts(ruleDetail: ["rules.json: line 4"],
                                  ruleLines: [AlertMenuText.outputSilentWarning, "Current rules match 2 of the last 50"]))
        let lines = try XCTUnwrap(section(StatusPopoverText.rulesHeading, in: shown))
        XCTAssertEqual(lines.map(\.text), ["3 rules in effect", "rules.json: line 4", AlertMenuText.outputSilentWarning,
                                           "Current rules match 2 of the last 50"])
        XCTAssertEqual(lines.map(\.mark), [.plain, .indented, .fault, .plain])
    }

    // MARK: - Tiles and commands

    func testTheThreeTiles() {
        let tiles = content(facts()).tiles
        XCTAssertEqual(tiles.map(\.kind), [.inspector, .rules, .snooze])
        XCTAssertEqual(tiles.map(\.title), ["Inspector", "Rules", SnoozeText.menuTitle])
        XCTAssertEqual(tiles.map(\.key), ["⌘I", "⌘E", nil])
        XCTAssertEqual(tiles.map(\.action), [.showInspector, .editRules, nil])
    }

    func testTheCommandsOffCall() {
        let commands = content(facts()).commands
        XCTAssertEqual(commands.map(\.title), [OnCallText.menuTitle, SetupText.rulesFileMenuTitle,
                                               StatusMenuText.reloadRulesTitle, SettingsText.menuTitle, "Quit SignalLadder"])
        XCTAssertEqual(commands.map(\.key), [nil, nil, "⌘R", "⌘,", "⌘Q"])
        XCTAssertEqual(commands.map(\.isOn), [false, nil, nil, nil, nil])
        XCTAssertEqual(commands.map(\.action), [.toggleOnCall, .openRulesFile, .reloadRules, .showSettings, .quit])
    }

    func testOnCallTheItemIsTickedAndTheCheckIsOffered() {
        let commands = content(facts(onCall: true)).commands
        XCTAssertEqual(commands.first?.isOn, true)
        XCTAssertEqual(commands.dropFirst().first?.title, OnCallText.checkItemTitle)
        XCTAssertEqual(commands.dropFirst().first?.action, .showOnCallCheck)
    }

    func testTheKeysTheMenuHasWorkWhileThePopoverIsOpen() {
        let shown = content(facts())
        XCTAssertEqual(shown.action(forCommandKey: "i"), .showInspector)
        XCTAssertEqual(shown.action(forCommandKey: "e"), .editRules)
        XCTAssertEqual(shown.action(forCommandKey: "r"), .reloadRules)
        XCTAssertEqual(shown.action(forCommandKey: ","), .showSettings)
        XCTAssertEqual(shown.action(forCommandKey: "q"), .quit)
        XCTAssertEqual(shown.action(forCommandKey: "I"), .showInspector)
    }

    func testNoOtherKeyDoesAnything() {
        let shown = content(facts(listed: [summary()]))
        for key in ["a", "w", "", "\r", " ", "ie"] {
            XCTAssertNil(shown.action(forCommandKey: key), key)
        }
    }

    // MARK: - What a press opens

    func testAClickOpensThePopover() {
        XCTAssertEqual(StatusItemPress.leftClick(option: false, control: false).opens, .popover)
    }

    func testARightClickAndAClickWithOptionOrControlOpenTheMenu() {
        XCTAssertEqual(StatusItemPress.rightClick.opens, .menu)
        XCTAssertEqual(StatusItemPress.leftClick(option: true, control: false).opens, .menu)
        XCTAssertEqual(StatusItemPress.leftClick(option: false, control: true).opens, .menu)
        XCTAssertEqual(StatusItemPress.leftClick(option: true, control: true).opens, .menu)
    }

    /// VoiceOver's press and the live check's are no mouse click.
    func testAPressThatIsNoClickOpensTheMenu() {
        XCTAssertEqual(StatusItemPress.other.opens, .menu)
    }
}
