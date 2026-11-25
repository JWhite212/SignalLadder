import XCTest
@testable import NotificationCore

/// The escalation panel's lines (M4 Task 4). Never what arrived (ruling 17).
final class EscalationPanelTextTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func time(_ date: Date) -> String { date == start ? "10:42" : "later" }
    private func line(_ summary: EscalationSummary) -> String { EscalationPanelText.line(for: summary, time: time) }

    /// A summary carrying notification text wherever it can: a spoken repeat
    /// and a spoken final alert both hold the line they said.
    private func summary(_ status: EscalationSummary.Status, tier: Int = 3, repeats: Int = 3, cap: Int? = 20,
                         final: FinalOutcome? = nil) -> EscalationSummary {
        EscalationSummary(ruleName: "On-call mentions", startedAt: start, status: status, tierReached: tier,
                          repeatCount: repeats, repeatCap: cap,
                          lastRepeat: .spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0, outputSilent: false),
                          final: final ?? .alerted(.spoke(text: "Placeholder body text", voice: "Daniel", gainDB: 0, outputSilent: false)))
    }

    func testALiveLineNamesTheRuleTheStartTheTierAndTheRepeats() {
        XCTAssertEqual(line(summary(.live)), "On-call mentions — since 10:42 — tier 3, repeat 3 of 20")
    }

    func testARepeatWithNoLimitHasNoOf() {
        XCTAssertEqual(line(summary(.live, cap: nil)), "On-call mentions — since 10:42 — tier 3, repeat 3")
    }

    func testBeforeAnyRepeatOnlyTheTierIsShown() {
        XCTAssertEqual(line(summary(.live, tier: 2, repeats: 0)), "On-call mentions — since 10:42 — tier 2")
    }

    func testACappedLineSaysItHasStoppedRepeating() {
        XCTAssertEqual(line(summary(.capped(at: start), repeats: 20)),
                       "On-call mentions — since 10:42 — tier 3, repeat 20 of 20, no longer repeating")
    }

    func testAMissedLineSaysSoAndNothingMore() {
        XCTAssertEqual(line(summary(.missedWhileAsleep(convertedAt: start, acknowledgedAt: nil))),
                       "On-call mentions — since 10:42 — missed while asleep")
    }

    private let notInstalled = FinalOutcome.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")

    func testAShortcutThatFailedIsShownButNotWhy() {
        XCTAssertEqual(line(summary(.live, tier: 4, final: notInstalled)),
                       "On-call mentions — since 10:42 — tier 4, repeat 3 of 20, its Shortcut failed")
    }

    func testACappedLineStillShowsAFailedShortcut() {
        XCTAssertEqual(line(summary(.capped(at: start), tier: 4, repeats: 20, final: notInstalled)),
                       "On-call mentions — since 10:42 — tier 4, repeat 20 of 20, no longer repeating, its Shortcut failed")
    }

    func testAShortcutThatStartedAddsNothing() {
        XCTAssertEqual(line(summary(.live, tier: 4, final: .shortcutLaunched(name: "Page me"))),
                       "On-call mentions — since 10:42 — tier 4, repeat 3 of 20")
    }

    func testAMissedLineLeavesAFailedShortcutToTheMenu() {
        // What is still to do is to see it; the menu and the Inspector carry
        // the failure.
        XCTAssertEqual(line(summary(.missedWhileAsleep(convertedAt: start, acknowledgedAt: nil), final: notInstalled)),
                       "On-call mentions — since 10:42 — missed while asleep")
    }

    func testTheFirstRepeatIsCounted() {
        XCTAssertEqual(line(summary(.live, repeats: 1)), "On-call mentions — since 10:42 — tier 3, repeat 1 of 20")
    }

    func testTheHeadingButtonAndOverflowWords() {
        XCTAssertEqual(EscalationPanelText.title, "SignalLadder: waiting for you to acknowledge")
        XCTAssertEqual(EscalationPanelText.acknowledge, "Acknowledge")
        XCTAssertEqual(EscalationPanelText.overflow(3), "and 3 more: acknowledge all from the menu, or press ⌃⌥⌘A")
    }

    func testTheStartTimeIsTheOneGiven() {
        XCTAssertTrue(EscalationPanelText.line(for: summary(.live), time: { _ in "09:00" }).contains("since 09:00"))
    }

    func testNoLineEverCarriesWhatArrived() {
        let statuses: [EscalationSummary.Status] = [.live, .capped(at: start), .acknowledged(at: start),
                                                    .missedWhileAsleep(convertedAt: start, acknowledgedAt: nil),
                                                    .missedWhileAsleep(convertedAt: start, acknowledgedAt: start)]
        for status in statuses {
            let text = line(summary(status, final: notInstalled)) + line(summary(status))
            for fixture in ["Alex Example", "Placeholder", "mentioned you", "Daniel"] {
                XCTAssertFalse(text.contains(fixture), "\(status): \(text)")
            }
        }
    }

    // MARK: - A row in parts (M7 plan, Stage 3)

    private typealias Part = EscalationPanelText.Row.Part
    private func row(_ summary: EscalationSummary) -> EscalationPanelText.Row {
        EscalationPanelText.row(for: summary, time: time)
    }

    private func quiet(_ status: EscalationSummary.Status, tier: Int = 3, repeats: Int = 3, cap: Int? = 20,
                       matches: Int = 1) -> EscalationSummary {
        EscalationSummary(ruleName: "On-call mentions", startedAt: start, status: status, tierReached: tier,
                          repeatCount: repeats, repeatCap: cap, matchCount: matches)
    }

    func testALiveRowHasItsTiersNumberAndSaysTheStartAndTheRepeats() {
        let said = row(quiet(.live))
        XCTAssertEqual(said.name, "On-call mentions")
        XCTAssertEqual(said.mark, .tier(3))
        XCTAssertEqual(said.detail, [.words("since "), .figure("10:42"), .words(" — repeat "), .figure("03/20")])
        XCTAssertEqual(said.detailText, "since 10:42 — repeat 03/20")
        XCTAssertEqual(said.line, "On-call mentions — since 10:42 — tier 3, repeat 3 of 20", "what VoiceOver is told")
    }

    /// The tier is the numeral, so the words do not say it again.
    func testARowOnATiersColourDoesNotSayTheTierInWords() {
        for tier in 1...4 {
            XCTAssertFalse(row(quiet(.live, tier: tier)).detailText.contains("tier"))
            XCTAssertEqual(row(quiet(.live, tier: tier)).mark, .tier(tier))
        }
    }

    func testBeforeAnyRepeatARowSaysOnlyWhenItBegan() {
        XCTAssertEqual(row(quiet(.live, tier: 2, repeats: 0)).detail, [.words("since "), .figure("10:42")])
    }

    func testARowCountsItsMatchesFromTwo() {
        XCTAssertEqual(row(quiet(.live, matches: 7)).detailText, "since 10:42 — 7 matches — repeat 03/20")
        XCTAssertEqual(row(quiet(.live, matches: 1)).detailText, "since 10:42 — repeat 03/20")
    }

    func testACappedRowSaysItHasStoppedRepeating() {
        XCTAssertEqual(row(quiet(.capped(at: start), repeats: 20)).detailText, "since 10:42 — repeat 20/20, no longer repeating")
        XCTAssertEqual(row(quiet(.capped(at: start), repeats: 0)).detailText, "since 10:42 — no longer repeating")
        XCTAssertEqual(row(quiet(.capped(at: start), repeats: 20)).mark, .tier(3))
    }

    /// A row whose Shortcut failed has no colour, so it has no numeral and says
    /// its tier in words.
    func testARowWhoseShortcutFailedIsAFaultAndSaysItsTierInWords() {
        var summary = quiet(.capped(at: start), tier: 4, repeats: 20)
        summary.final = .shortcutFailed(name: "Page me", reason: "the Shortcut is not installed")
        let said = row(summary)
        XCTAssertEqual(said.mark, .fault)
        XCTAssertEqual(said.detailText, "since 10:42 — tier 4, repeat 20/20, no longer repeating — its Shortcut failed")
        XCTAssertFalse(said.detailText.contains("Page me"), "the Shortcut's name and the reason stay in the Inspector")
        XCTAssertFalse(said.detailText.contains("not installed"))

        var live = quiet(.live, tier: 4, repeats: 0)
        live.final = .shortcutFailed(name: "Page me", reason: "x")
        XCTAssertEqual(row(live).detailText, "since 10:42 — tier 4 — its Shortcut failed")
    }

    func testAMissedRowIsAFaultAndSaysSoAndNothingMore() {
        let said = row(quiet(.missedWhileAsleep(convertedAt: start, acknowledgedAt: nil), matches: 2))
        XCTAssertEqual(said.mark, .fault)
        XCTAssertEqual(said.detailText, "since 10:42 — 2 matches — missed while asleep")
    }

    /// A summary can carry what was spoken, in its last repeat and its final
    /// alert. No part of a row holds any of it.
    func testNoPartOfARowHoldsWhatArrived() {
        let statuses: [EscalationSummary.Status] = [.live, .capped(at: start),
                                                    .missedWhileAsleep(convertedAt: start, acknowledgedAt: nil)]
        for status in statuses {
            let said = row(summary(status))
            for text in [said.name, said.detailText, said.line] {
                XCTAssertFalse(text.contains("Alex Example"), text)
                XCTAssertFalse(text.contains("Placeholder body"), text)
                XCTAssertFalse(text.contains("Daniel"), text)
            }
        }
    }

    /// Both numbers are as wide as the limit and at least two figures, so the
    /// count does not grow wider as it passes 9.
    func testTheRepeatFigureIsAsWideAsItsLimit() {
        XCTAssertEqual(EscalationPanelText.repeatFigure(3, of: 20), "03/20")
        XCTAssertEqual(EscalationPanelText.repeatFigure(20, of: 20), "20/20")
        XCTAssertEqual(EscalationPanelText.repeatFigure(4, of: 5), "04/05")
        XCTAssertEqual(EscalationPanelText.repeatFigure(7, of: 100), "007/100")
        XCTAssertEqual(EscalationPanelText.repeatFigure(100, of: 100), "100/100")
        XCTAssertEqual(EscalationPanelText.repeatFigure(12, of: nil), "12")
        XCTAssertEqual(EscalationPanelText.repeatFigure(3, of: nil), "3")
    }

    /// The row and the line say the same things: every figure of the row is in the line's words.
    func testTheRowAndTheLineAgreeOnWhenAndHowMany() {
        let summary = quiet(.live, matches: 4)
        let said = row(summary)
        XCTAssertTrue(said.line.contains("since 10:42"))
        XCTAssertTrue(said.line.contains("4 matches"))
        XCTAssertTrue(said.line.contains("repeat 3 of 20"))
        XCTAssertTrue(said.detailText.contains("4 matches"))
    }
}
