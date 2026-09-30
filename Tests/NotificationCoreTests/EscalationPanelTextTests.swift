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
}
