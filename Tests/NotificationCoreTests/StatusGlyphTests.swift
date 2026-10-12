import AppKit
import XCTest
@testable import NotificationCore

/// Which icon the status item shows, and what it says (M5 plan, Rulings 10, 17
/// and 18). The icon is a pure function of the facts the app has read, so every
/// precedence, every source of a problem and every word is reached from facts
/// alone. Nothing here draws an icon: the one test that asks the system for a
/// symbol only asks whether it knows the name.
final class StatusGlyphTests: XCTestCase {
    private typealias Glyph = StatusGlyph

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// The clock time of a snooze's end, as the menu shows one: 24-hour, in
    /// en_GB, in UTC, so that it is the same on every Mac whatever its settings.
    private let clock: (Date) -> String = { date in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 15:30 in UTC on 2026-09-21, which is the day `now` falls on, 14:13.
    private let endsAt = Date(timeIntervalSince1970: 1_790_004_600)

    private func appearance(for facts: Glyph.Facts, pulse: Bool) -> Glyph.Appearance {
        Glyph.appearance(for: facts, pulse: pulse, time: clock)
    }

    /// Every fact at rest: capture verified, no rule problem, nothing failed, an
    /// audible output and Alert volume with a rule that sounds, nothing escalating,
    /// no snooze and nothing held, off call, and self-tests running.
    private func facts(_ edit: (inout Glyph.Facts) -> Void = { _ in }) -> Glyph.Facts {
        var facts = Glyph.Facts(health: .verified, healthAlarmState: HealthAlarmPlan.State(), now: now,
                                ruleStatusProblem: false, shortcutWarningCount: 0, unresolvedAlertFailure: false,
                                unresolvedShortcutFailure: false, outputSilent: false, anEnabledRuleSounds: true,
                                alertVolume: 1, escalationLive: false, snoozeEndsAt: nil, heldSummary: HeldSummary(),
                                onCall: false, selfTestsRunning: true)
        edit(&facts)
        return facts
    }

    /// Three matches held, of one rule.
    private func held(_ count: Int = 3, unreadable: Bool = false) -> HeldSummary {
        HeldSummary(counts: count > 0 ? [UUID(uuidString: "11111111-1111-4111-8111-111111111111")!: count] : [:],
                    firstHeldAt: now.addingTimeInterval(-600), unannounced: count, recordUnreadable: unreadable)
    }

    /// Capture that has read unknown since `seconds` ago, as the health alarm
    /// remembers it.
    private func unknownFor(_ seconds: TimeInterval) -> HealthAlarmPlan.State {
        HealthAlarmPlan.State(lastReported: .unknown, unknownSince: now.addingTimeInterval(-seconds))
    }

    // MARK: - The precedence

    func testTheStatesAreSixInTheOrderOfPrecedenceAndTheNormalOneIsWhatRestingFactsGive() {
        XCTAssertEqual(Glyph.State.allCases, [.problem, .escalating, .snoozed, .heldSummary, .onCall, .normal])
        XCTAssertEqual(Glyph.state(for: facts()), .normal)
    }

    func testOnCallIsShownWhileNothingAboveItIs() {
        XCTAssertEqual(Glyph.state(for: facts { $0.onCall = true }), .onCall)
    }

    func testAnEscalationOutranksOnCallAndNormal() {
        XCTAssertEqual(Glyph.state(for: facts { $0.escalationLive = true }), .escalating)
        XCTAssertEqual(Glyph.state(for: facts { $0.escalationLive = true; $0.onCall = true }), .escalating)
    }

    /// A working ladder must not look like a broken pipeline, and a broken
    /// pipeline outranks it: the most important fact on screen.
    func testAProblemOutranksAnEscalationAndOnCall() {
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.escalationLive = true }), .problem)
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.onCall = true }), .problem)
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.escalationLive = true; $0.onCall = true }),
                       .problem)
    }

    // MARK: - What makes a problem

    func testEachOfTheFiveProblemSourcesThatHoldWhetherOrNotOnCallIsTheProblemStateAlone() {
        for onCall in [false, true] {
            func state(_ edit: (inout Glyph.Facts) -> Void) -> Glyph.State {
                Glyph.state(for: facts { $0.onCall = onCall; edit(&$0) })
            }
            let normal: Glyph.State = onCall ? .onCall : .normal
            XCTAssertEqual(state { _ in }, normal, "none of them, on call \(onCall)")
            XCTAssertEqual(state { $0.health = .degraded([.selfTestInconclusive]) }, .problem, "degraded")
            XCTAssertEqual(state { $0.health = .blind([.accessibilityNotTrusted]) }, .problem, "blind")
            XCTAssertEqual(state { $0.ruleStatusProblem = true }, .problem, "a rule that is not in effect")
            XCTAssertEqual(state { $0.shortcutWarningCount = 1 }, .problem, "a Shortcut not found")
            XCTAssertEqual(state { $0.shortcutWarningCount = 3 }, .problem, "more than one")
            XCTAssertEqual(state { $0.unresolvedAlertFailure = true }, .problem, "an alert that could not play")
            XCTAssertEqual(state { $0.unresolvedShortcutFailure = true }, .problem, "a Shortcut that did not run")
            XCTAssertEqual(state { $0.shortcutWarningCount = 0 }, normal, "a count of zero is not a problem")
        }
    }

    /// Capture that has stayed unverified past the bound the health alarm sounds
    /// for is a problem while on call, and the bound is asked of that same
    /// function, so the icon and the beep cannot disagree about it.
    func testCaptureUnverifiedPastTheBoundIsAProblemWhileOnCallAndNotWhileOffCall() {
        func state(onCall: Bool, unknownFor seconds: TimeInterval) -> Glyph.State {
            Glyph.state(for: facts { $0.health = .unknown; $0.healthAlarmState = unknownFor(seconds); $0.onCall = onCall })
        }
        XCTAssertEqual(state(onCall: true, unknownFor: 10 * 60), .problem)
        XCTAssertEqual(state(onCall: true, unknownFor: 10 * 3600), .problem)
        XCTAssertEqual(state(onCall: true, unknownFor: 9 * 60 + 59), .onCall, "a second short of the bound")
        XCTAssertEqual(state(onCall: true, unknownFor: 0), .onCall)
        XCTAssertEqual(state(onCall: false, unknownFor: 10 * 3600), .normal, "off call unknown never alarms, however long")
    }

    func testTheUnverifiedBoundIsTheHealthAlarmsAndNotACopyOfIt() {
        for seconds in [0, 100, 300, 599, 600, 601, 3600] as [TimeInterval] {
            let state = unknownFor(seconds)
            let alarm = HealthAlarmPlan.isUnverifiedFault(onCall: true, health: .unknown, state: state, now: now)
            let icon = Glyph.isProblem(facts { $0.health = .unknown; $0.healthAlarmState = state; $0.onCall = true })
            XCTAssertEqual(icon, alarm, "\(seconds) seconds")
        }
        // After a wake, the bound the alarm uses is two minutes, and so is the icon's.
        let woken = HealthAlarmPlan.State(lastReported: .unknown, unknownSince: now.addingTimeInterval(-150),
                                          lastWakeAt: now.addingTimeInterval(-121))
        XCTAssertTrue(Glyph.isProblem(facts { $0.health = .unknown; $0.healthAlarmState = woken; $0.onCall = true }))
        let freshWake = HealthAlarmPlan.State(lastReported: .unknown, unknownSince: now.addingTimeInterval(-150),
                                              lastWakeAt: now.addingTimeInterval(-119))
        XCTAssertFalse(Glyph.isProblem(facts { $0.health = .unknown; $0.healthAlarmState = freshWake; $0.onCall = true }))
    }

    func testAMutedOutputIsAProblemWhileOnCallWithARuleThatSoundsAndNotOtherwise() {
        func state(onCall: Bool = true, silent: Bool = true, sounds: Bool = true) -> Glyph.State {
            Glyph.state(for: facts { $0.onCall = onCall; $0.outputSilent = silent; $0.anEnabledRuleSounds = sounds })
        }
        XCTAssertEqual(state(), .problem)
        XCTAssertEqual(state(onCall: false), .normal, "off call")
        XCTAssertEqual(state(sounds: false), .onCall, "no rule sounds, so silence is what the user chose")
        XCTAssertEqual(state(silent: false), .onCall, "an audible output")
    }

    /// The beeps are the app's own channel and not a rule's, so a silent Alert
    /// volume is a problem whether or not a rule sounds.
    func testAnAlertVolumeAtZeroIsAProblemWhileOnCallWhetherOrNotARuleSounds() {
        func state(onCall: Bool = true, volume: Double?, sounds: Bool) -> Glyph.State {
            Glyph.state(for: facts { $0.onCall = onCall; $0.alertVolume = volume; $0.anEnabledRuleSounds = sounds })
        }
        for sounds in [true, false] {
            XCTAssertEqual(state(volume: 0, sounds: sounds), .problem, "zero, rule sounds \(sounds)")
            XCTAssertEqual(state(volume: 0.01, sounds: sounds), .problem, "0.01, rule sounds \(sounds)")
            XCTAssertEqual(state(volume: 0.02, sounds: sounds), .onCall, "0.02")
            XCTAssertEqual(state(volume: 1, sounds: sounds), .onCall)
            XCTAssertEqual(state(volume: nil, sounds: sounds), .onCall, "unread claims nothing")
            XCTAssertEqual(state(onCall: false, volume: 0, sounds: sounds), .normal, "off call")
        }
    }

    // MARK: - What each state shows

    func testEachStateHasASymbolOfItsOwnAndTheFallbackIsTheNormalOne() {
        let appearances = [
            appearance(for: facts { $0.ruleStatusProblem = true }, pulse: false),
            appearance(for: facts { $0.escalationLive = true }, pulse: false),
            appearance(for: facts { $0.escalationLive = true }, pulse: true),
            appearance(for: facts { $0.snoozeEndsAt = endsAt }, pulse: false),
            appearance(for: facts { $0.heldSummary = held() }, pulse: false),
            appearance(for: facts { $0.onCall = true }, pulse: false),
            appearance(for: facts(), pulse: false),
        ]
        XCTAssertEqual(appearances.map(\.symbol).count, Set(appearances.map(\.symbol)).count, "no two share a symbol")
        XCTAssertEqual(appearances.map(\.state),
                       [.problem, .escalating, .escalating, .snoozed, .heldSummary, .onCall, .normal])
        XCTAssertEqual(Glyph.fallbackSymbol, appearance(for: facts(), pulse: false).symbol)
        XCTAssertEqual(appearances.map(\.symbol), ["bell.slash.fill", "bell.and.waves.left.and.right",
                                                   "bell.and.waves.left.and.right.fill", "moon.zzz.fill",
                                                   "tray.full.fill", "bell.badge.fill", "bell.badge"])
    }

    /// An unknown symbol name makes `NSImage(systemSymbolName:)` answer nil and the
    /// status item blank, so every name an appearance can hold is one the system
    /// knows (Ruling 17).
    func testEverySymbolAnAppearanceNamesIsOneTheSystemKnows() {
        let names = [StatusGlyphText.problemSymbol, StatusGlyphText.escalatingSymbolBright,
                     StatusGlyphText.escalatingSymbolDim, StatusGlyphText.snoozedSymbol, StatusGlyphText.heldSymbol,
                     StatusGlyphText.onCallSymbol, StatusGlyphText.normalSymbol, Glyph.fallbackSymbol]
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testThePulseAlternatesOnlyWhileEscalating() {
        let escalating = facts { $0.escalationLive = true }
        XCTAssertNotEqual(appearance(for: escalating, pulse: false).symbol,
                          appearance(for: escalating, pulse: true).symbol)
        for resting in [facts(), facts { $0.onCall = true }, facts { $0.ruleStatusProblem = true },
                        facts { $0.snoozeEndsAt = endsAt }, facts { $0.heldSummary = held() }] {
            XCTAssertEqual(appearance(for: resting, pulse: false), appearance(for: resting, pulse: true),
                           "\(Glyph.state(for: resting)) does not pulse")
        }
    }

    func testTheDescriptionsAreTheWordsEachStateHadAndOnCallsIsNew() {
        XCTAssertEqual(appearance(for: facts(), pulse: false).description, "SignalLadder")
        XCTAssertEqual(appearance(for: facts { $0.ruleStatusProblem = true }, pulse: false).description,
                       "SignalLadder — problem")
        XCTAssertEqual(appearance(for: facts { $0.escalationLive = true }, pulse: true).description,
                       "SignalLadder — alert escalating")
        XCTAssertEqual(appearance(for: facts { $0.onCall = true }, pulse: false).description,
                       "SignalLadder — on call, self-test every 5 minutes")
    }

    /// Saying the cadence while a self-test is blocked would say more than the app
    /// has established (Ruling 17), so it is in the description only while
    /// self-tests are running.
    func testTheCadenceIsInTheOnCallDescriptionOnlyWhileSelfTestsAreRunning() {
        func description(_ running: Bool?) -> String {
            appearance(for: facts { $0.onCall = true; $0.selfTestsRunning = running }, pulse: false).description
        }
        XCTAssertEqual(description(true), "SignalLadder — on call, self-test every 5 minutes")
        XCTAssertEqual(description(false), "SignalLadder — on call")
        XCTAssertEqual(description(nil), "SignalLadder — on call", "before the first health check has said")
        XCTAssertFalse(appearance(for: facts { $0.selfTestsRunning = true }, pulse: false).description.contains("5 minutes"),
                       "off call there is no cadence to say")
    }

    func testEveryStateHasATooltipThatIsNotEmptyAndNamesTheApp() {
        let appearances = [
            appearance(for: facts { $0.ruleStatusProblem = true }, pulse: false),
            appearance(for: facts { $0.escalationLive = true }, pulse: false),
            appearance(for: facts { $0.snoozeEndsAt = endsAt }, pulse: false),
            appearance(for: facts { $0.heldSummary = held() }, pulse: false),
            appearance(for: facts { $0.onCall = true }, pulse: false),
            appearance(for: facts(), pulse: false),
        ]
        for appearance in appearances {
            XCTAssertTrue(appearance.tooltip.hasPrefix("SignalLadder"), appearance.tooltip)
            XCTAssertFalse(appearance.description.isEmpty)
        }
        XCTAssertEqual(Set(appearances.map(\.tooltip)).count, 6, "each state says its own")
    }

    // MARK: - A snooze and what it held (O9, O10, Ruling 17)

    /// Whether each of the facts that can be present is, in the order the plan gives
    /// them: problem, escalating, snoozed, held summary, on call.
    private func present(problem: Bool, escalating: Bool, snoozed: Bool, held summary: Bool, onCall: Bool) -> Glyph.Facts {
        facts {
            $0.ruleStatusProblem = problem
            $0.escalationLive = escalating
            $0.snoozeEndsAt = snoozed ? endsAt : nil
            $0.heldSummary = summary ? held() : HeldSummary()
            $0.onCall = onCall
        }
    }

    /// The precedence is problem, escalating, snoozed, held summary, on call,
    /// normal, and each state is the highest of the facts present: every one of the
    /// thirty-two combinations of the five says the highest that is there.
    func testEveryCombinationOfTheFiveFactsGivesTheHighestStateThatIsPresent() {
        let order: [Glyph.State] = [.problem, .escalating, .snoozed, .heldSummary, .onCall]
        for bits in 0..<32 {
            let flags = (0..<5).map { bits & (1 << $0) != 0 }
            let facts = present(problem: flags[0], escalating: flags[1], snoozed: flags[2], held: flags[3], onCall: flags[4])
            let expected = zip(order, flags).first(where: { $0.1 })?.0 ?? .normal
            XCTAssertEqual(Glyph.state(for: facts), expected, "\(flags)")
        }
    }

    /// The same, written out, for the rows that matter most: a held summary with no
    /// snooze, and a snooze over a held summary.
    func testASnoozeIsSnoozedAHeldSummaryWithNoSnoozeIsHeldAndASnoozeOverASummaryIsSnoozed() {
        XCTAssertEqual(Glyph.state(for: facts { $0.snoozeEndsAt = endsAt }), .snoozed)
        XCTAssertEqual(Glyph.state(for: facts { $0.heldSummary = held() }), .heldSummary, "no snooze is running")
        XCTAssertEqual(Glyph.state(for: facts { $0.snoozeEndsAt = endsAt; $0.heldSummary = held() }), .snoozed)
        XCTAssertEqual(Glyph.state(for: facts { $0.snoozeEndsAt = endsAt; $0.onCall = true }), .snoozed, "outranks on call")
        XCTAssertEqual(Glyph.state(for: facts { $0.heldSummary = held(); $0.onCall = true }), .heldSummary, "outranks on call")
        XCTAssertEqual(Glyph.state(for: facts { $0.escalationLive = true; $0.snoozeEndsAt = endsAt; $0.heldSummary = held() }),
                       .escalating, "a ladder already climbing is what the icon says")
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.escalationLive = true
            $0.snoozeEndsAt = endsAt; $0.heldSummary = held(); $0.onCall = true }), .problem)
    }

    /// A snooze is for quieting sound, and a fault is what the slashed bell means:
    /// a problem found during a snooze shows as one, so that a blind app is not
    /// mistaken for a quiet one.
    func testAProblemDuringASnoozeOrWithASummaryHeldIsAProblem() {
        for snoozed in [true, false] {
            func state(_ edit: (inout Glyph.Facts) -> Void) -> Glyph.State {
                Glyph.state(for: facts {
                    $0.snoozeEndsAt = snoozed ? endsAt : nil
                    $0.heldSummary = held()
                    edit(&$0)
                })
            }
            XCTAssertEqual(state { _ in }, snoozed ? .snoozed : .heldSummary)
            XCTAssertEqual(state { $0.health = .blind([.accessibilityNotTrusted]) }, .problem, "snoozed \(snoozed)")
            XCTAssertEqual(state { $0.shortcutWarningCount = 1 }, .problem, "snoozed \(snoozed)")
            XCTAssertEqual(state { $0.unresolvedAlertFailure = true }, .problem, "snoozed \(snoozed)")
        }
    }

    /// A summary exists when it holds anything or says that something could not be
    /// read: a page that may have been held is never left without the icon.
    func testASummaryThatCouldNotBeReadStillShowsTheHeldIcon() {
        XCTAssertEqual(Glyph.state(for: facts { $0.heldSummary = held(0, unreadable: true) }), .heldSummary)
        XCTAssertEqual(Glyph.state(for: facts { $0.heldSummary = held(2, unreadable: true) }), .heldSummary)
        XCTAssertEqual(Glyph.state(for: facts { $0.heldSummary = HeldSummary() }), .normal, "nothing held and nothing unread")
    }

    func testASnoozeShowsTheMoonAndAHeldSummaryTheTrayAndNeitherTheSlashedBell() {
        let snoozed = appearance(for: facts { $0.snoozeEndsAt = endsAt }, pulse: false)
        let withSummary = appearance(for: facts { $0.heldSummary = held() }, pulse: false)
        XCTAssertEqual(snoozed.symbol, "moon.zzz.fill")
        XCTAssertEqual(withSummary.symbol, "tray.full.fill")
        for symbol in [snoozed.symbol, withSummary.symbol] {
            XCTAssertNotEqual(symbol, StatusGlyphText.problemSymbol, "the slashed bell means a fault")
        }
        XCTAssertEqual(snoozed.state, .snoozed)
        XCTAssertEqual(withSummary.state, .heldSummary)
    }

    func testTheSnoozedDescriptionHasTheEndAsAClockTimeAndHowManyMatchesHaveBeenHeld() {
        func description(_ summary: HeldSummary) -> String {
            appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.heldSummary = summary }, pulse: false).description
        }
        XCTAssertEqual(description(held(3)), "SignalLadder — snoozed until 15:30, 3 matches held")
        XCTAssertEqual(description(held(1)), "SignalLadder — snoozed until 15:30, 1 match held")
        XCTAssertEqual(description(HeldSummary()), "SignalLadder — snoozed until 15:30, no matches held")
        XCTAssertTrue(description(held(3)).hasPrefix(StatusGlyphText.snoozedStem))
        // A record that could not be read is said, beside what could be counted and alone.
        XCTAssertEqual(description(held(3, unreadable: true)),
                       "SignalLadder — snoozed until 15:30, 3 matches held, and some others whose record could not be read")
        XCTAssertEqual(description(held(0, unreadable: true)),
                       "SignalLadder — snoozed until 15:30, some matches held whose record could not be read")
    }

    /// The count is of what the summary holds, which a new snooze adds to, and the
    /// words do not say it is this snooze's.
    func testTheSnoozedDescriptionCountsWhatTheSummaryHoldsAndDoesNotCallItThisSnoozes() {
        let text = appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.heldSummary = held(7) }, pulse: false).description
        XCTAssertTrue(text.contains("7 matches held"))
        XCTAssertFalse(text.contains("this snooze"))
    }

    func testTheEndIsFormattedByTheFormatterItIsGivenAndOnlyForTheEnd() {
        var asked: [Date] = []
        let snoozed = facts { $0.snoozeEndsAt = endsAt; $0.heldSummary = held() }
        let shown = Glyph.appearance(for: snoozed, pulse: false, time: { asked.append($0); return "TIME" })
        XCTAssertEqual(asked, [endsAt])
        XCTAssertEqual(shown.description, "SignalLadder — snoozed until TIME, 3 matches held")

        asked = []
        let heldOnly = facts { $0.heldSummary = held() }
        let onCallOnly = facts { $0.onCall = true }
        _ = Glyph.appearance(for: heldOnly, pulse: false, time: { asked.append($0); return "TIME" })
        _ = Glyph.appearance(for: onCallOnly, pulse: false, time: { asked.append($0); return "TIME" })
        XCTAssertEqual(asked, [], "a state with no end is never asked for one")
    }

    /// There is no countdown (O9): time passing changes nothing the icon says,
    /// and a countdown would need a timer of its own.
    func testNothingTheSnoozedIconSaysChangesAsTimePasses() {
        let first = appearance(for: facts { $0.snoozeEndsAt = endsAt }, pulse: false)
        for seconds in [1, 60, 900, 4000] as [TimeInterval] {
            XCTAssertEqual(appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.now = now.addingTimeInterval(seconds) },
                                      pulse: false), first, "\(seconds) seconds later")
        }
    }

    func testTheHeldDescriptionIsTheSentenceThePlanGivesAndTheTooltipIsTheSame() {
        let shown = appearance(for: facts { $0.heldSummary = held(3) }, pulse: false)
        XCTAssertEqual(shown.description, "SignalLadder — 3 matches were held while snoozed. Open the menu.")
        XCTAssertEqual(shown.tooltip, shown.description)
        XCTAssertEqual(appearance(for: facts { $0.heldSummary = held(1) }, pulse: false).description,
                       "SignalLadder — 1 match was held while snoozed. Open the menu.")
        XCTAssertEqual(appearance(for: facts { $0.heldSummary = held(3, unreadable: true) }, pulse: false).description,
                       "SignalLadder — 3 matches were held while snoozed, and some others whose record could not be read. Open the menu.")
        XCTAssertEqual(appearance(for: facts { $0.heldSummary = held(0, unreadable: true) }, pulse: false).description,
                       "SignalLadder — some matches were held while snoozed and their record could not be read. Open the menu.")
        // Asked for a summary with nothing in it, which the icon never does, the sentence is not left blank.
        XCTAssertEqual(StatusGlyphText.heldDescription(HeldSummary(), onCall: false),
                       "SignalLadder — no matches were held while snoozed. Open the menu.")
    }

    /// Each of these outranks on call, so each says it too while the mode is on, in
    /// its description and in its tooltip, and neither says it while the mode is off:
    /// the glyph never tells the user less than the mode does (O9, O10).
    func testTheSnoozedAndTheHeldDescriptionsAndTooltipsSayOnCallWhileOnCallAndNotWhileOff() {
        let summaries = [held(3), held(1), held(0, unreadable: true), held(2, unreadable: true)]
        for onCall in [true, false] {
            var shown: [Glyph.Appearance] = []
            for summary in summaries {
                shown.append(appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.heldSummary = summary; $0.onCall = onCall },
                                        pulse: false))
                shown.append(appearance(for: facts { $0.heldSummary = summary; $0.onCall = onCall }, pulse: false))
            }
            shown.append(appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.onCall = onCall }, pulse: false))
            XCTAssertEqual(Set(shown.map(\.state)), [.snoozed, .heldSummary])
            for appearance in shown {
                for text in [appearance.description, appearance.tooltip] {
                    XCTAssertEqual(text.contains("on call"), onCall, "on call \(onCall): \(text)")
                    XCTAssertEqual(text.contains(StatusGlyphText.onCallClause), onCall, text)
                }
            }
        }
        XCTAssertEqual(appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.onCall = true }, pulse: false).description,
                       "SignalLadder — snoozed until 15:30, no matches held, and you are on call")
        XCTAssertEqual(appearance(for: facts { $0.heldSummary = held(3); $0.onCall = true }, pulse: false).description,
                       "SignalLadder — 3 matches were held while snoozed, and you are on call. Open the menu.")
    }

    /// The cadence belongs to the on-call description and to no other: a snooze says
    /// that the user is on call, not how the self-tests are going.
    func testTheCadenceIsNotInTheSnoozedOrTheHeldDescriptions() {
        for running in [true, false, nil] as [Bool?] {
            let snoozed = appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.onCall = true; $0.selfTestsRunning = running },
                                     pulse: false)
            let withSummary = appearance(for: facts { $0.heldSummary = held(); $0.onCall = true; $0.selfTestsRunning = running },
                                         pulse: false)
            for text in [snoozed.description, snoozed.tooltip, withSummary.description, withSummary.tooltip] {
                XCTAssertFalse(text.contains("self-test"), text)
            }
        }
    }

    func testTheWordsOfASnoozeAndOfAHeldSummaryCountMatchesAndNeverMessages() {
        let texts = [
            appearance(for: facts { $0.snoozeEndsAt = endsAt; $0.heldSummary = held(5, unreadable: true) }, pulse: false).description,
            appearance(for: facts { $0.heldSummary = held(5, unreadable: true) }, pulse: false).description,
            StatusGlyphText.noMatchesHeld, StatusGlyphText.noMatchesWereHeld, StatusGlyphText.someOthersUncounted,
            StatusGlyphText.someMatchesHeldUncounted, StatusGlyphText.someMatchesWereHeldUncounted,
        ]
        for text in texts {
            XCTAssertFalse(text.lowercased().contains("message"), text)
            XCTAssertFalse(text.lowercased().contains("notification"), text)
        }
    }
}
