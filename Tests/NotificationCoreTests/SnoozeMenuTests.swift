import XCTest
@testable import NotificationCore

/// What the status menu shows of a snooze, as the one value the app renders (M5
/// plan, Task 4, Rulings 12, 17 and 18, O8 to O10): the items, their order, which
/// are top-level, and the words. Rule names are invented (§10.1). Nothing here
/// builds a menu, plays a sound or waits on a clock.
final class SnoozeMenuTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// 15:30 on 2026-09-21 in UTC, which is the day `now` falls on, at 14:13.
    private let endsAt = Date(timeIntervalSince1970: 1_790_004_600)

    /// The clock time as the menu shows one: 24-hour, en_GB, UTC, so that it is the
    /// same on every Mac whatever its settings.
    private let clock: (Date) -> String = { date in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private let a = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let b = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!

    // MARK: - Fixtures

    private func rule(_ name: String, alert: AlertAction? = .sound(name: "Glass", gainDB: 0), ticked: Bool = true,
                      enabled: Bool = true, escalation: Escalation? = nil) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled, alert: alert,
             escalation: escalation, quietWhenSnoozed: ticked)
    }

    /// A ladder whose last step is the phone page.
    private let paging = Escalation(tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me")))

    /// Five rules that alert aloud, three of which a snooze may hold, and three
    /// that are in neither list: one ticked and silent, one ticked and off, one
    /// ticked with no alert at all.
    private var fiveAndThree: [Rule] {
        [rule("On-call mentions"),
         rule("Team chatter"),
         rule("Release notes"),
         rule("Page me rule", escalation: paging),          // ticked, but ends in a Shortcut
         rule("Weather", ticked: false),                      // not ticked
         rule("Quiet ticked", alert: .silent),                // ticked, makes no sound
         rule("Off ticked", enabled: false),                  // ticked, switched off
         rule("No alert ticked", alert: nil)]                 // ticked, no alert
    }

    /// On-call mode switched on the day before `now`, which is before any moment a test
    /// gives for a snooze that ended, so that a test that does not care when the mode
    /// came on does not have the line hidden by it.
    private var onSinceYesterday: Date { now.addingTimeInterval(-86_400) }

    /// - Parameter state: the on-call state itself, for the tests that care since when;
    ///   without it `onCall` says whether the mode is on, since yesterday.
    private func menu(rules: [Rule]? = nil, onCall: Bool = false, state: OnCallState? = nil, ends: Date? = nil,
                      summary: HeldSummary = HeldSummary(), endedAt: Date? = nil, at moment: Date? = nil) -> SnoozeMenu {
        SnoozeText.menu(rules: rules ?? fiveAndThree, onCall: state ?? (onCall ? .on(since: onSinceYesterday) : .off),
                        snoozeEndsAt: ends, summary: summary, endedByOnCallAt: endedAt, now: moment ?? now, time: clock)
    }

    /// Every line and title at the top level, in order, and what kind each is.
    private func topLevel(_ menu: SnoozeMenu) -> [String] {
        menu.items.map {
            switch $0 {
            case .snooze(let title, _): return "snooze:\(title)"
            case .line(let text): return "line:\(text)"
            case .dismiss(let title, _): return "dismiss:\(title)"
            }
        }
    }

    private func submenu(_ menu: SnoozeMenu) throws -> [SnoozeMenu.SubmenuItem] {
        guard case .snooze(_, let submenu)? = menu.items.first else {
            XCTFail("the first item is not the Snooze item")
            return []
        }
        return submenu
    }

    /// Every word the menu holds, top-level and in the submenu.
    private func everyText(_ menu: SnoozeMenu) -> [String] {
        menu.items.flatMap { item -> [String] in
            switch item {
            case .snooze(let title, let submenu):
                return [title] + submenu.map {
                    switch $0 {
                    case .line(let text): return text
                    case .start(_, let title): return title
                    case .end(let title): return title
                    }
                }
            case .line(let text): return [text]
            case .dismiss(let title, _): return [title]
            }
        }
    }

    private func held(_ counts: [UUID: Int], unreadable: Bool = false) -> HeldSummary {
        HeldSummary(counts: counts, firstHeldAt: now.addingTimeInterval(-600), unannounced: counts.values.reduce(0, +),
                    recordUnreadable: unreadable)
    }

    // MARK: - The words

    /// The on-call line never says a snooze quiets what it does not: a ticked rule
    /// that is silent, or that ends in a Shortcut, still alerts, so the line names
    /// both conditions in the words the "quiets no rules" line uses (O8, O10).
    func testTheOnCallLineNamesTheTwoConditionsAndNeverSaysEveryTickedRule() {
        XCTAssertTrue(SnoozeText.onCallNote.contains("make a sound"), SnoozeText.onCallNote)
        XCTAssertTrue(SnoozeText.onCallNote.contains("do not run a Shortcut"), SnoozeText.onCallNote)
        XCTAssertFalse(SnoozeText.onCallNote.contains("every rule"), SnoozeText.onCallNote)
        XCTAssertTrue(SnoozeText.quietsNoRules.contains("makes a sound and does not run a Shortcut"))
    }

    func testTheTitlesAndTheLinesAreTheWordsThePlanGives() {
        XCTAssertEqual(SnoozeText.menuTitle, "Snooze")
        XCTAssertEqual(SnoozeText.endTitle, "End Snooze")
        XCTAssertEqual(SnoozeText.dismissTitle, "Dismiss")
        XCTAssertEqual(SnoozeText.activeStem, "Snoozed until")
        XCTAssertEqual(SnoozeText.stillAlertingStem, "Still alerting")
        XCTAssertEqual(SnoozeText.ruleSwitchLabel, "Stay quiet while I have snoozed")
        XCTAssertEqual(SnoozeText.onCallNote,
                       "You are on call. A snooze quiets only the rules you ticked that make a sound and do not run a Shortcut.")
        XCTAssertEqual(SnoozeText.endedByOnCall, "Snooze ended — you are on call")
        XCTAssertEqual(SnoozeText.quietsNoRules,
                       "Snooze quiets no rules yet — tick “Stay quiet while I have snoozed” on a rule that makes a sound and does not run a Shortcut")
    }

    func testTheDurationsAreFifteenMinutesThirtyMinutesAnHourAndTwoHoursInThatOrder() {
        XCTAssertEqual(SnoozeDuration.allCases, [.fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours])
        XCTAssertEqual(SnoozeDuration.allCases.map(SnoozeText.durationTitle),
                       ["For 15 minutes", "For 30 minutes", "For 1 hour", "For 2 hours"])
    }

    func testTheWordsNameNoAppAndCountMatchesAndNeverMessages() {
        for text in everyText(menu(onCall: true, ends: endsAt, summary: held([a: 2], unreadable: true), endedAt: nil)) {
            XCTAssertFalse(text.lowercased().contains("message"), text)
            XCTAssertFalse(text.lowercased().contains("notification"), text)
            XCTAssertFalse(text.contains("Microsoft Teams"), "what a rule matches on is not what the menu says")
        }
        XCTAssertEqual(SnoozeText.endedNoticeLifetime, SnoozeDuration.longest, "as long as a snooze can run")
        XCTAssertEqual(SnoozeText.endedNoticeLifetime, 7200)
    }

    // MARK: - The Snooze item and its submenu

    func testTheSnoozeItemIsFirstAndOpensTheFourDurationsAndNothingElseWhenOffCallAndNotSnoozed() throws {
        let value = menu()
        guard case .snooze(let title, let submenu)? = value.items.first else { return XCTFail("no Snooze item first") }
        XCTAssertEqual(title, "Snooze")
        XCTAssertEqual(submenu, [
            .start(.fifteenMinutes, title: "For 15 minutes"),
            .start(.thirtyMinutes, title: "For 30 minutes"),
            .start(.oneHour, title: "For 1 hour"),
            .start(.twoHours, title: "For 2 hours"),
        ])
    }

    /// Starting a snooze while already on call is allowed, and the submenu says what
    /// it does, first, in one line (O10).
    func testWhileOnCallTheSubmenuBeginsWithTheOnCallLineAndOffCallItHasNone() throws {
        let on = try submenu(menu(onCall: true))
        XCTAssertEqual(on.first, .line("You are on call. A snooze quiets only the rules you ticked that make a sound and do not run a Shortcut."))
        XCTAssertEqual(on.count, 5, "the line and the four durations")
        XCTAssertEqual(Array(on.dropFirst()), try submenu(menu(onCall: false)))
        let off = try submenu(menu(onCall: false))
        XCTAssertFalse(off.contains(.line(SnoozeText.onCallNote)))
        XCTAssertEqual(off.count, 4)
    }

    func testEndSnoozeIsTheLastItemOfTheSubmenuOnlyWhileASnoozeRuns() throws {
        XCTAssertEqual(try submenu(menu(ends: endsAt)).last, .end(title: "End Snooze"))
        XCTAssertEqual(try submenu(menu(onCall: true, ends: endsAt)).last, .end(title: "End Snooze"))
        for onCall in [true, false] {
            XCTAssertFalse(try submenu(menu(onCall: onCall, ends: nil)).contains(.end(title: SnoozeText.endTitle)),
                           "no snooze runs, on call \(onCall)")
        }
        XCTAssertEqual(try submenu(menu(ends: endsAt)).count, 5, "the durations and End Snooze")
    }

    /// The harness reads the menu's top-level items, and a line that must be opened to
    /// be read is where a missed page hides (Ruling 17): the submenu holds the on-call
    /// line, the durations and End Snooze, and every other line is top-level.
    func testTheSubmenuHoldsOnlyTheOnCallLineTheDurationsAndEndSnoozeAndEveryOtherLineIsTopLevel() throws {
        let value = menu(onCall: true, ends: endsAt, summary: held([a: 2, b: 1]), endedAt: nil)
        let inside = try submenu(value)
        XCTAssertEqual(inside.count, 6)
        for item in inside {
            switch item {
            case .line(let text): XCTAssertEqual(text, SnoozeText.onCallNote)
            case .start(let duration, _): XCTAssertTrue(SnoozeDuration.allCases.contains(duration))
            case .end(let title): XCTAssertEqual(title, SnoozeText.endTitle)
            }
        }
        let outside = topLevel(value)
        XCTAssertEqual(outside.first, "snooze:Snooze")
        XCTAssertTrue(outside.contains { $0.hasPrefix("line:\(SnoozeText.activeStem) ") }, "the active line")
        XCTAssertTrue(outside.contains { $0.hasPrefix("line:\(SnoozeText.stillAlertingStem): ") }, "the line of what still alerts")
        XCTAssertTrue(outside.contains { $0.contains("matches \(SnoozeText.heldStem)") }, "the summary line")
        XCTAssertTrue(outside.contains("dismiss:Dismiss"), "Dismiss")
        // Nothing top-level is anything the submenu holds.
        XCTAssertFalse(outside.contains("line:\(SnoozeText.onCallNote)"))
        XCTAssertFalse(outside.contains { $0.contains("For 15 minutes") || $0.contains(SnoozeText.endTitle) })
    }

    // MARK: - While a snooze runs

    func testWhileASnoozeRunsTheActiveLineAndTheLineOfWhatStillAlertsFollowTheSnoozeItAsTopLevelLines() {
        XCTAssertEqual(topLevel(menu(ends: endsAt)), [
            "snooze:Snooze",
            "line:Snoozed until 15:30 — quiets 3 of 5 rules",
            "line:Still alerting: Page me rule, Weather",
        ])
    }

    /// The counts are over the enabled rules that alert aloud, the quieted ones being
    /// those a snooze may hold. A ticked rule whose last step is a Shortcut is among
    /// those still alerting, and a rule that was never going to sound is in neither
    /// list: not the silent one, not the one that is off and not the one with no alert.
    func testQuietsNOfMAndStillAlertingCountOnlyEnabledRulesThatAlertAloudAndATickedRuleWithAShortcutStillAlerts() {
        let lines = topLevel(menu(ends: endsAt))
        XCTAssertTrue(lines.contains("line:Snoozed until 15:30 — quiets 3 of 5 rules"))
        XCTAssertTrue(lines.contains("line:Still alerting: Page me rule, Weather"), "the flagged rule with a Shortcut is among them")
        for notListed in ["Quiet ticked", "Off ticked", "No alert ticked"] {
            XCTAssertFalse(lines.contains { $0.contains(notListed) }, "\(notListed) is in neither list")
        }
        for quieted in ["On-call mentions", "Team chatter", "Release notes"] {
            XCTAssertFalse(lines.contains { $0.hasPrefix("line:Still alerting") && $0.contains(quieted) }, "\(quieted) is quieted")
        }
    }

    /// A rule that sounds only on a later tier alerts aloud, so it counts; one whose
    /// later tier alone is a Shortcut does not, and is left out of both.
    func testARuleThatSoundsOnALaterTierAloneCountsAndOneWhoseOnlyStepIsAShortcutDoesNot() {
        let laterTier = Escalation(tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0), intervalSeconds: 30))
        let rules = [rule("Later sound", alert: .silent, escalation: laterTier),
                     rule("Shortcut only", alert: .silent, escalation: paging)]
        XCTAssertTrue(rules[0].alertsAloud)
        XCTAssertFalse(rules[1].alertsAloud)
        XCTAssertEqual(topLevel(menu(rules: rules, ends: endsAt)), [
            "snooze:Snooze",
            "line:Snoozed until 15:30 — quiets 1 of 1 rule",
        ], "the one that sounds is quieted, the other is in neither list, and a rule may be held so the advice is not there")
    }

    func testTheRuleIsSingularForOneAndPluralForNoneAndForMore() {
        XCTAssertEqual(SnoozeText.activeLine(endsAt: endsAt, quieting: 1, of: 1, time: clock), "Snoozed until 15:30 — quiets 1 of 1 rule")
        XCTAssertEqual(SnoozeText.activeLine(endsAt: endsAt, quieting: 0, of: 1, time: clock), "Snoozed until 15:30 — quiets 0 of 1 rule")
        XCTAssertEqual(SnoozeText.activeLine(endsAt: endsAt, quieting: 0, of: 0, time: clock), "Snoozed until 15:30 — quiets 0 of 0 rules")
        XCTAssertEqual(SnoozeText.activeLine(endsAt: endsAt, quieting: 2, of: 2, time: clock), "Snoozed until 15:30 — quiets 2 of 2 rules")
    }

    /// "Snoozed until" is the stem the harness extracts, and the line begins with it,
    /// whatever follows and however the clock shows the time.
    func testTheActiveLineBeginsWithTheStemTheHarnessReadsWhateverFollows() {
        let variants: [[Rule]] = [fiveAndThree, [], [rule("Only", ticked: false)], [rule("Only")]]
        for rules in variants {
            for onCall in [true, false] {
                let lines = menu(rules: rules, onCall: onCall, ends: endsAt, summary: held([a: 1])).items.compactMap { item -> String? in
                    if case .line(let text) = item, text.hasPrefix(SnoozeText.activeStem) { return text }
                    return nil
                }
                XCTAssertEqual(lines.count, 1, "one active line, \(rules.count) rules, on call \(onCall)")
            }
        }
        XCTAssertTrue(SnoozeText.activeLine(endsAt: endsAt, quieting: 0, of: 0, time: { _ in "any time" }).hasPrefix(SnoozeText.activeStem))
    }

    func testTheClockTimeIsFormattedByTheFormatterTheMenuIsGiven() {
        var asked: [Date] = []
        let value = SnoozeText.menu(rules: fiveAndThree, onCall: .off, snoozeEndsAt: endsAt, summary: HeldSummary(),
                                    endedByOnCallAt: nil, now: now, time: { asked.append($0); return "T" })
        XCTAssertEqual(asked, [endsAt], "asked for the end, once, and for nothing else")
        XCTAssertTrue(topLevel(value).contains("line:Snoozed until T — quiets 3 of 5 rules"))
        // 15:30 as en_GB shows it, and not 3:30 PM.
        XCTAssertEqual(clock(endsAt), "15:30")
    }

    func testTheLineOfWhatStillAlertsNamesThreeAndCountsTheRestInTheOrderTheRulesWereWritten() {
        let rules = ["Zulu", "Alpha", "Mike", "Echo", "Bravo"].map { rule($0, ticked: false) }
        XCTAssertTrue(topLevel(menu(rules: rules, ends: endsAt)).contains("line:Still alerting: Zulu, Alpha, Mike and 2 more"))
        XCTAssertEqual(SnoozeText.stillAlertingLine(["A", "B", "C"]), "Still alerting: A, B, C")
        XCTAssertEqual(SnoozeText.stillAlertingLine(["A", "B", "C", "D"]), "Still alerting: A, B, C and 1 more")
        XCTAssertEqual(SnoozeText.stillAlertingLine(["A"]), "Still alerting: A")
        XCTAssertNil(SnoozeText.stillAlertingLine([]))
    }

    func testThereIsNoLineOfWhatStillAlertsWhenASnoozeQuietsEveryRuleThatAlertsAloud() {
        let rules = [rule("One"), rule("Two")]
        XCTAssertEqual(topLevel(menu(rules: rules, ends: endsAt)), ["snooze:Snooze", "line:Snoozed until 15:30 — quiets 2 of 2 rules"])
    }

    /// No snooze is running, so the active line and the line of what still alerts are
    /// not there, on call or not.
    func testWithNoSnoozeRunningThereIsNeitherTheActiveLineNorTheLineOfWhatStillAlerts() {
        for onCall in [true, false] {
            let lines = topLevel(menu(onCall: onCall))
            XCTAssertFalse(lines.contains { $0.hasPrefix("line:\(SnoozeText.activeStem)") })
            XCTAssertFalse(lines.contains { $0.hasPrefix("line:\(SnoozeText.stillAlertingStem)") })
        }
    }

    // MARK: - A snooze that would do nothing says so

    func testWithNoRuleASnoozeMayHoldTheMenuSaysSnoozeQuietsNoRulesYet() {
        let none: [[Rule]] = [
            [],
            [rule("Not ticked", ticked: false)],
            [rule("Ticked and silent", alert: .silent)],
            [rule("Ticked and off", enabled: false)],
            [rule("Ticked with no alert", alert: nil)],
            [rule("Ticked, and the page is a Shortcut", escalation: paging)],
        ]
        for rules in none {
            XCTAssertEqual(topLevel(menu(rules: rules)), ["snooze:Snooze", "line:\(SnoozeText.quietsNoRules)"], "\(rules.map(\.name))")
        }
        XCTAssertTrue(SnoozeText.quietsNoRules.hasPrefix("Snooze quiets no rules yet"))
    }

    func testThatLineIsNotThereWhenARuleMayBeHeldAndStandsDuringASnoozeThatQuietsNothing() {
        XCTAssertFalse(topLevel(menu()).contains("line:\(SnoozeText.quietsNoRules)"))
        XCTAssertFalse(topLevel(menu(ends: endsAt)).contains("line:\(SnoozeText.quietsNoRules)"))
        let rules = [rule("Not ticked", ticked: false)]
        XCTAssertEqual(topLevel(menu(rules: rules, ends: endsAt)), [
            "snooze:Snooze",
            "line:Snoozed until 15:30 — quiets 0 of 1 rule",
            "line:Still alerting: Not ticked",
            "line:\(SnoozeText.quietsNoRules)",
        ])
    }

    // MARK: - The summary, before, during and after a snooze

    private func summaryLines(_ menu: SnoozeMenu) -> [String] {
        menu.items.compactMap { item -> String? in
            if case .line(let text) = item, text.contains(SnoozeText.heldStem) { return text }
            return nil
        }
    }

    /// The summary stands until the user dismisses it, so it is there before a snooze
    /// has run, during one and after it has ended, and each time its line and Dismiss
    /// are top-level, the Dismiss directly beside the line.
    func testTheSummaryLineAndDismissAreTopLevelBeforeDuringAndAfterASnooze() {
        let summary = held([a: 2, b: 4])
        let rules = [Rule(id: a, name: "On-call mentions", condition: .field(.app, .equals, "X")),
                     Rule(id: b, name: "Team chatter", condition: .field(.app, .equals, "Y"))]
        let line = "6 matches held while snoozed: On-call mentions ×2, Team chatter ×4"
        for (phase, ends) in [("before", nil), ("during", endsAt), ("after", nil)] as [(String, Date?)] {
            let value = menu(rules: rules, ends: ends, summary: summary)
            XCTAssertEqual(topLevel(value).suffix(2), ["line:\(line)", "dismiss:Dismiss"], phase)
            XCTAssertEqual(value.items.last, .dismiss(title: "Dismiss", shown: summary), phase)
            XCTAssertEqual(summaryLines(value), [line], phase)
        }
        XCTAssertEqual(SnoozeText.summaryLine(summary, names: SnoozeText.names(of: rules)), line, "the line is the summary's own")
    }

    /// The summary line is the one `summaryLine` makes, so the words are written once.
    func testTheSummaryLineIsTheOneTheSummaryTextMakesFromTheCurrentRules() {
        let rules = [Rule(id: a, name: "On-call mentions", condition: .field(.app, .equals, "X"))]
        let single = menu(rules: rules, summary: held([a: 1]))
        XCTAssertEqual(summaryLines(single), ["\(SnoozeText.heldOneMatchStem): On-call mentions ×1"])
        let unknown = menu(rules: rules, summary: held([b: 3]))
        XCTAssertEqual(summaryLines(unknown), ["3 matches held while snoozed: a rule that cannot be found by its id ×3"])
    }

    /// Dismiss carries the summary its line was made from, which the app hands back, so
    /// that a match held while the menu was open is not taken out unseen (Ruling 22).
    func testDismissCarriesTheSummaryItsLineWasMadeFrom() {
        let summary = held([a: 2])
        guard case .dismiss(let title, let shown)? = menu(summary: summary).items.last else { return XCTFail("no Dismiss") }
        XCTAssertEqual(title, SnoozeText.dismissTitle)
        XCTAssertEqual(shown, summary)
        XCTAssertEqual(shown.counts, [a: 2])
    }

    func testWithNoSummaryThereIsNoSummaryLineAndNoDismiss() {
        for ends in [nil, endsAt] as [Date?] {
            let value = menu(ends: ends, summary: HeldSummary())
            XCTAssertTrue(summaryLines(value).isEmpty)
            XCTAssertFalse(topLevel(value).contains { $0.hasPrefix("dismiss:") })
        }
    }

    /// A record that could not be read is a summary: its sentence is shown, with
    /// Dismiss, and it is never left out (Ruling 12).
    func testARecordThatCouldNotBeReadShowsItsSentenceAndDismissToo() {
        let summary = HeldSummary(counts: [:], unannounced: 0, recordUnreadable: true)
        let value = menu(summary: summary)
        XCTAssertEqual(topLevel(value).suffix(2), ["line:\(SnoozeText.unreadableSentence)", "dismiss:Dismiss"])
        XCTAssertEqual(value.items.last, .dismiss(title: "Dismiss", shown: summary))
    }

    /// The menu makes no sound: what it asks of a controller is a read, and a snooze
    /// that ran out owes the one announcement it owes, and building the menu, once or
    /// many times, before, during and after, adds none (O9).
    @MainActor
    func testBuildingTheMenuMakesNoSoundAndAddsNoAnnouncement() {
        let clockScheduler = ManualScheduler(start: now)
        var announced = 0
        let controller = SnoozeController(scheduler: clockScheduler, storedUntil: nil, storedHeld: nil,
                                          save: { _, _ in }, changed: {}, announce: { announced += 1 })
        let ticked = Rule(id: a, name: "On-call mentions", condition: .field(.app, .equals, "X"),
                          alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true)
        func build() -> SnoozeMenu {
            SnoozeText.menu(rules: [ticked], onCall: .off, snoozeEndsAt: controller.endsAt, summary: controller.summary,
                            endedByOnCallAt: nil, now: clockScheduler.now(), time: clock)
        }
        _ = build()
        controller.start(.fifteenMinutes)
        XCTAssertTrue(controller.holds(ticked))
        for _ in 0..<3 { _ = build() }
        XCTAssertEqual(announced, 0, "during")
        clockScheduler.advance(by: 15 * 60)
        XCTAssertEqual(announced, 1, "the controller's own announcement, once, when the snooze ran out")
        for _ in 0..<3 { _ = build() }
        XCTAssertEqual(announced, 1, "after: reading and building add none")
        XCTAssertEqual(summaryLines(build()).count, 1, "and the summary is still there")
    }

    // MARK: - On-call mode ended a snooze

    private var endedLine: String { "line:\(SnoozeText.endedByOnCall)" }

    func testAfterSwitchingOnCallOnEndedASnoozeTheMenuSaysSoRightAfterTheSnoozeItem() {
        let ended = now.addingTimeInterval(-60)
        XCTAssertEqual(topLevel(menu(onCall: true, endedAt: ended)).prefix(2), ["snooze:Snooze", endedLine])
        XCTAssertEqual(SnoozeText.endedByOnCall, "Snooze ended — you are on call")
    }

    /// The line says "you are on call", so it stands only while that is true, and it
    /// stands for as long as a snooze can run, from the moment it ended: after that the
    /// snooze it reports would have run out whatever its length (Ruling 12, O10).
    func testTheEndedLineStandsForAsLongAsASnoozeCanRunAndNoLonger() {
        let ended = now
        func shown(after seconds: TimeInterval) -> Bool {
            topLevel(menu(onCall: true, endedAt: ended, at: ended.addingTimeInterval(seconds))).contains(endedLine)
        }
        XCTAssertTrue(shown(after: 0))
        XCTAssertTrue(shown(after: 15 * 60))
        XCTAssertTrue(shown(after: 2 * 60 * 60 - 1), "a second short of the longest snooze")
        XCTAssertFalse(shown(after: 2 * 60 * 60), "as long as a snooze can run, and no longer")
        XCTAssertFalse(shown(after: 5 * 60 * 60))
    }

    func testTheEndedLineIsNotThereOffCallOrWhileASnoozeRunsOrWhenNothingEndedOrForAMomentThatHasNotCome() {
        let ended = now.addingTimeInterval(-60)
        XCTAssertFalse(topLevel(menu(onCall: false, endedAt: ended)).contains(endedLine), "off call it would not be true")
        XCTAssertFalse(topLevel(menu(onCall: true, ends: endsAt, endedAt: ended)).contains(endedLine),
                       "a snooze started since is the news")
        XCTAssertFalse(topLevel(menu(onCall: false, ends: endsAt, endedAt: ended)).contains(endedLine))
        XCTAssertFalse(topLevel(menu(onCall: true, endedAt: nil)).contains(endedLine), "nothing ended")
        XCTAssertFalse(topLevel(menu(onCall: true, endedAt: now.addingTimeInterval(3600))).contains(endedLine),
                       "an end that is later than now is a clock that was set back, and is not shown")
    }

    /// What the app does: it saves the new state, and the step that ends the snooze comes
    /// straight after, so the moment is the same instant as `since`, or a moment later.
    func testTheEndedLineStandsForTheSnoozeThatTheSwitchEndedWhetherTheMomentIsTheSinceOrAfterIt() {
        let ended = now.addingTimeInterval(-60)
        XCTAssertTrue(topLevel(menu(state: .on(since: ended), endedAt: ended)).contains(endedLine),
                      "the moment is the instant the mode went on")
        XCTAssertTrue(topLevel(menu(state: .on(since: ended.addingTimeInterval(-0.001)), endedAt: ended)).contains(endedLine),
                      "or just after it")
        XCTAssertFalse(topLevel(menu(state: .on(since: ended.addingTimeInterval(0.001)), endedAt: ended)).contains(endedLine),
                       "a moment before the mode went on is from before this run of it")
    }

    /// A snooze that ended when on-call mode went on, and then the mode was switched off and on
    /// again with no snooze to end, is not a snooze that ended now: the notice is for the run of
    /// the mode that ended it (Ruling 18, O10).
    func testSwitchingOnCallOffAndOnAgainDoesNotBringBackTheLineForASnoozeThatEndedBefore() {
        let ended = now.addingTimeInterval(-600)
        XCTAssertTrue(topLevel(menu(state: .on(since: ended), endedAt: ended)).contains(endedLine), "while it is the same run")
        XCTAssertFalse(topLevel(menu(state: .off, endedAt: ended)).contains(endedLine), "off call")
        let switchedBackOn = now.addingTimeInterval(-120)
        XCTAssertFalse(topLevel(menu(state: .on(since: switchedBackOn), endedAt: ended)).contains(endedLine),
                       "on again, within the lifetime, and nothing was ended by it")
        // And one that the second switch-on did end is told, with the moment the app notes for it.
        XCTAssertTrue(topLevel(menu(state: .on(since: switchedBackOn), endedAt: switchedBackOn)).contains(endedLine))
    }

    /// A time that could not be read says nothing of which run a moment belongs to, and the
    /// line says no more than the app has read. The mode is still on, which the submenu says.
    func testTheEndedLineIsNotShownWhenTheTimeTheModeWentOnIsNotKnownAndTheSubmenuStillSaysItIsOn() throws {
        XCTAssertFalse(topLevel(menu(state: .on(since: nil), endedAt: now.addingTimeInterval(-60))).contains(endedLine))
        XCTAssertFalse(topLevel(menu(state: .on(since: nil), endedAt: now)).contains(endedLine))
        XCTAssertEqual(try submenu(menu(state: .on(since: nil))).first, .line(SnoozeText.onCallNote))
    }

    func testTheEndedLineIsNotInTheSubmenuAndTheSummaryStaysBesideIt() throws {
        let value = menu(onCall: true, summary: held([a: 2]), endedAt: now.addingTimeInterval(-60))
        XCTAssertFalse(try submenu(value).contains(.line(SnoozeText.endedByOnCall)))
        let lines = topLevel(value)
        XCTAssertEqual(lines.first, "snooze:Snooze")
        XCTAssertEqual(lines[1], endedLine)
        XCTAssertEqual(lines.last, "dismiss:Dismiss")
    }

    // MARK: - The order

    /// Everything at once, in the order the plan gives: the Snooze item; the active
    /// line and the line of what still alerts; the line that says it ended, which is
    /// never beside an active one, so it is left out here; the line that says no rule
    /// is ticked; the summary and Dismiss.
    func testEveryLineIsInTheOrderTheMenuShowsThem() {
        let rules = [rule("Not ticked", ticked: false)]
        let value = menu(rules: rules, onCall: true, ends: endsAt, summary: held([a: 1]), endedAt: now.addingTimeInterval(-60))
        XCTAssertEqual(topLevel(value), [
            "snooze:Snooze",
            "line:Snoozed until 15:30 — quiets 0 of 1 rule",
            "line:Still alerting: Not ticked",
            "line:\(SnoozeText.quietsNoRules)",
            "line:\(SnoozeText.heldOneMatchStem): a rule that cannot be found by its id ×1",
            "dismiss:Dismiss",
        ])
        let ended = menu(rules: rules, onCall: true, summary: held([a: 1]), endedAt: now.addingTimeInterval(-60))
        XCTAssertEqual(topLevel(ended), [
            "snooze:Snooze",
            endedLine,
            "line:\(SnoozeText.quietsNoRules)",
            "line:\(SnoozeText.heldOneMatchStem): a rule that cannot be found by its id ×1",
            "dismiss:Dismiss",
        ])
    }

    func testTheValueFollowsItsInputsAndIsTheSameForTheSameInputs() {
        XCTAssertEqual(menu(ends: endsAt, summary: held([a: 1])), menu(ends: endsAt, summary: held([a: 1])))
        XCTAssertNotEqual(menu(ends: endsAt), menu(ends: nil))
        XCTAssertNotEqual(menu(summary: held([a: 1])), menu(summary: held([a: 2])))
        XCTAssertNotEqual(menu(onCall: true), menu(onCall: false))
    }
}

/// What a notification said never reaches the menu's snooze lines (M5 plan, Task 4,
/// Rulings 12 and 18): a notification whose words are a canary is fed through the
/// pipeline with a snooze on, and what the menu then shows has no part of it. Real
/// notification text does flow in, to the row and to what is said, which is shown
/// first, so that this is a test that can fail.
@MainActor
final class SnoozeMenuContentTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let clock: (Date) -> String = { date in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func testANotificationsTextReachesNoLineOfTheMenuWhileASnoozeRunsAndAfterItEnds() throws {
        let title = "Zyxwv-4417 quartzite sundial"
        let body = "ledger-9f2c obsidian marmalade"
        let fragments = ["Zyxwv-4417", "Zyxwv", "quartzite", "sundial", "ledger-9f2c", "ledger", "obsidian", "marmalade"]
        // A rule that speaks what it read, written from some of the same words, as a
        // real one is, and that a snooze may hold.
        let rule = Rule(name: "On-call mentions", condition: .field(.body, .contains, "ledger-9f2c"),
                        alert: .soundAndSpeak(soundName: "Glass", soundGainDB: 0,
                                              speech: SpeechAction(voiceIdentifier: daniel, template: "{title}. {body}")),
                        quietWhenSnoozed: true)
        let scheduler = ManualScheduler(start: t0)
        let snooze = SnoozeController(scheduler: scheduler, storedUntil: nil, storedHeld: nil,
                                      save: { _, _ in }, changed: {}, announce: {})
        var spoken: [String] = []
        let pipeline = CapturePipeline(
            ownAppName: "SignalLadder", isSelfTest: { _, _ in false },
            playSound: { name, gain in .played(sound: name, gainDB: gain, outputSilent: false) },
            speak: { text, speech in
                spoken.append(text)
                return .spoke(text: text, voice: "Daniel", gainDB: speech.gainDB, outputSilent: false)
            },
            playAndSpeak: { name, gain, text, speech in
                spoken.append(text)
                return .playedAndSpoke(sound: name, soundGainDB: gain, text: text, voice: "Daniel",
                                       speechGainDB: speech.gainDB, outputSilent: false)
            },
            beginEscalation: { _, _, _, _ in },
            holdForSnooze: { snooze.holds($0) })
        pipeline.setRules([rule])
        func feed(at offset: TimeInterval) {
            pipeline.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: "Microsoft Teams, \(title), \(body)",
                                        subrole: "AXNotificationCenterBanner"),
                             textChildren: [title, body])
        }
        func everyWord(_ menu: SnoozeMenu) -> String {
            menu.items.flatMap { item -> [String] in
                switch item {
                case .snooze(let title, let submenu):
                    return [title] + submenu.map { entry -> String in
                        switch entry {
                        case .line(let text): return text
                        case .start(_, let title): return title
                        case .end(let title): return title
                        }
                    }
                case .line(let text): return [text]
                case .dismiss(let title, let shown):
                    return [title, String(describing: shown)]
                }
            }.joined(separator: "\n")
        }
        func build() -> SnoozeMenu {
            SnoozeText.menu(rules: pipeline.rules, onCall: .on(since: scheduler.now()), snoozeEndsAt: snooze.endsAt,
                            summary: snooze.summary, endedByOnCallAt: nil, now: scheduler.now(), time: clock)
        }

        // With no snooze the words do flow in, to the row and to what was said, so
        // that what follows is a test of a leak and not of an empty pipe.
        feed(at: 0)
        let heard = try XCTUnwrap(pipeline.history.entries.first?.alertOutcome?.spokenText)
        for fragment in fragments.prefix(3) { XCTAssertTrue(heard.contains(fragment), "\(fragment) in \(heard)") }
        XCTAssertEqual(spoken.count, 1)

        snooze.start(.thirtyMinutes)
        feed(at: 10)
        feed(at: 20)
        XCTAssertEqual(spoken.count, 1, "nothing was said for the two held ones")
        XCTAssertEqual(snooze.summary.total, 2)

        let during = build()
        scheduler.advance(by: 30 * 60)
        let after = build()
        XCTAssertNil(snooze.endsAt)

        for (phase, menu) in [("during", during), ("after", after)] {
            let shown = everyWord(menu)
            XCTAssertTrue(shown.contains("On-call mentions"), "\(phase): the rule's own name is what is shown")
            XCTAssertTrue(shown.contains("2 matches \(SnoozeText.heldStem)"), phase)
            for fragment in fragments {
                XCTAssertFalse(shown.contains(fragment), "\(phase): \(fragment) reached the menu: \(shown)")
            }
        }
        XCTAssertTrue(everyWord(during).contains("\(SnoozeText.activeStem) 14:43"), "30 minutes after 14:13")
    }
}
