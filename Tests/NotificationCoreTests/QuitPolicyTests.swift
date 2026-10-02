import XCTest
@testable import NotificationCore

/// What quitting asks, and when it does not (M5 plan, Ruling 10, O6). The policy
/// has no alert, no Apple event and no clock: each test gives it what the app
/// would read, as numbers and closures, and reads what it answers.
final class QuitPolicyTests: XCTestCase {
    private typealias Standing = QuitPolicy.Standing

    /// A four-character code as the number the SDK gives it. The tests state
    /// each code twice, as characters here and as the decimal the SDK printed,
    /// so that a slip in one of them is not read back as agreement.
    private func code(_ characters: String) -> UInt32 {
        precondition(characters.utf8.count == 4)
        return characters.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private func prompt(_ reason: QuitPolicy.Reason = .user, noticeAge: TimeInterval? = nil,
                        escalating: Int = 0, missed: Int = 0, onCall: Bool = false) -> QuitPolicy.Prompt? {
        QuitPolicy.prompt(reason: reason, noticeAge: noticeAge, escalating: escalating, missed: missed, onCall: onCall)
    }

    // MARK: - The quit's own reason

    func testEachOfTheSixCodesGivesItsReason() {
        // As printed by this SDK on 2026-09-30.
        let expected: [(characters: String, number: UInt32, reason: QuitPolicy.Reason)] = [
            ("logo", 1819240303, .logOut),      // kAELogOut
            ("rlgo", 1919706991, .logOut),      // kAEReallyLogOut
            ("rrst", 1920103284, .restart),     // kAEShowRestartDialog
            ("rest", 1919251316, .restart),     // kAERestart
            ("rsdn", 1920164974, .shutDown),    // kAEShowShutdownDialog
            ("shut", 1936225652, .shutDown),    // kAEShutDown
        ]
        for item in expected {
            XCTAssertEqual(code(item.characters), item.number, "'\(item.characters)' is the number the SDK printed")
            XCTAssertEqual(QuitPolicy.reason(fromCode: item.number), item.reason, "'\(item.characters)'")
        }
    }

    func testAnAbsentCodeAndAnUnknownOneAreTheUser() {
        XCTAssertEqual(QuitPolicy.reason(fromCode: nil), .user)
        XCTAssertEqual(QuitPolicy.reason(fromCode: 0), .user, "what a descriptor that cannot be read gives")
        // kAEQuitAll is a value the SDK's header lists for the reason beside the
        // log out, restart and shut down codes, and the plan does not classify it.
        // It is asked about, the safe direction.
        XCTAssertEqual(QuitPolicy.reason(fromCode: code("quia")), .user)
        XCTAssertEqual(QuitPolicy.reason(fromCode: code("quit")), .user, "the event's own id")
        XCTAssertEqual(QuitPolicy.reason(fromCode: code("why?")), .user, "the key the reason is read under")
        XCTAssertEqual(QuitPolicy.reason(fromCode: UInt32.max), .user)
        for known: UInt32 in [1819240303, 1919706991, 1920103284, 1919251316, 1920164974, 1936225652] {
            XCTAssertEqual(QuitPolicy.reason(fromCode: known &+ 1), .user, "one past \(known)")
            XCTAssertEqual(QuitPolicy.reason(fromCode: known &- 1), .user, "one before \(known)")
        }
    }

    // MARK: - The system's notice

    func testANoticeCountsForTwoMinutes() {
        XCTAssertEqual(QuitPolicy.noticeLifetime, 120)
    }

    func testANoticeExcusesFromTheMomentItArrivedUpToItsLifetime() {
        for age: TimeInterval in [0, 0.5, 60, 119.9, 120] {
            XCTAssertTrue(QuitPolicy.noticeExcuses(age: age), "\(age) seconds")
        }
        for age: TimeInterval in [120.001, 121, 600, 36_000, .infinity] {
            XCTAssertFalse(QuitPolicy.noticeExcuses(age: age), "\(age) seconds")
        }
    }

    func testNoNoticeANegativeAgeAndANonNumberDoNotExcuse() {
        XCTAssertFalse(QuitPolicy.noticeExcuses(age: nil))
        XCTAssertFalse(QuitPolicy.noticeExcuses(age: -0.001))
        XCTAssertFalse(QuitPolicy.noticeExcuses(age: -60))
        XCTAssertFalse(QuitPolicy.noticeExcuses(age: .nan))
    }

    func testTheAgeIsTheAwakeTimeSinceTheNoticeArrived() {
        XCTAssertEqual(QuitPolicy.noticeAge(arrivedAt: 1000, now: 1030), 30)
        XCTAssertEqual(QuitPolicy.noticeAge(arrivedAt: 1000, now: 1000), 0)
        XCTAssertEqual(QuitPolicy.noticeAge(arrivedAt: 0, now: 5000), 5000, "a notice at awake time zero is a notice")
        XCTAssertNil(QuitPolicy.noticeAge(arrivedAt: nil, now: 1030), "none has arrived")
    }

    // MARK: - A log out, a restart and a shut down

    func testALogOutARestartAndAShutDownAreNeverAskedAbout() {
        for reason in [QuitPolicy.Reason.logOut, .restart, .shutDown] {
            for (escalating, missed) in [(0, 0), (1, 0), (0, 2), (3, 1)] {
                for onCall in [false, true] {
                    XCTAssertNil(prompt(reason, escalating: escalating, missed: missed, onCall: onCall),
                                 "\(reason), \(escalating) escalating, \(missed) missed, on call \(onCall)")
                }
            }
        }
    }

    func testANoticeNoOlderThanItsLifetimeExcusesEveryReasonIncludingTheUser() {
        for age: TimeInterval in [0, 60, 120] {
            for reason in [QuitPolicy.Reason.user, .logOut, .restart, .shutDown] {
                XCTAssertNil(prompt(reason, noticeAge: age, escalating: 2, missed: 1, onCall: true), "\(reason) at \(age) s")
                XCTAssertNil(prompt(reason, noticeAge: age, escalating: 2, missed: 0, onCall: false), "\(reason) at \(age) s")
                XCTAssertNil(prompt(reason, noticeAge: age, escalating: 0, missed: 0, onCall: true), "\(reason) at \(age) s")
            }
        }
    }

    func testANoticeOlderThanItsLifetimeAsksAsThoughNoneHadArrived() {
        // A log out that was aborted must not go on excusing the quits after it,
        // for the escalation prompt, the on-call prompt and both.
        let cases: [(escalating: Int, missed: Int, onCall: Bool)] = [(2, 0, false), (0, 1, false), (0, 0, true), (2, 1, true)]
        for age: TimeInterval in [120.001, 121, 36_000] {
            for item in cases {
                let asked = prompt(noticeAge: age, escalating: item.escalating, missed: item.missed, onCall: item.onCall)
                XCTAssertNotNil(asked, "\(item) at \(age) s")
                XCTAssertEqual(asked, prompt(noticeAge: nil, escalating: item.escalating, missed: item.missed, onCall: item.onCall),
                               "\(item) at \(age) s")
            }
        }
    }

    func testANegativeAgeIsNoNotice() {
        XCTAssertNotNil(prompt(noticeAge: -1, escalating: 1))
        XCTAssertNotNil(prompt(noticeAge: -1, onCall: true))
    }

    func testAnOldNoticeDoesNotMakeALogOutAsked() {
        // The notice is a second signal and not the only one: the reason alone
        // still excuses a log out whose notice is long gone.
        XCTAssertNil(prompt(.logOut, noticeAge: 36_000, escalating: 1, onCall: true))
    }

    // MARK: - A quit by the user

    func testWithNoNoticeAQuitWithNoCodeIsAskedAbout() {
        let reason = QuitPolicy.reason(fromCode: nil)
        XCTAssertNotNil(QuitPolicy.prompt(reason: reason, noticeAge: nil, escalating: 1, missed: 0, onCall: false))
        XCTAssertNotNil(QuitPolicy.prompt(reason: reason, noticeAge: nil, escalating: 0, missed: 0, onCall: true))
        // And one whose code is not one of the six.
        let unknown = QuitPolicy.reason(fromCode: code("quia"))
        XCTAssertNotNil(QuitPolicy.prompt(reason: unknown, noticeAge: nil, escalating: 1, missed: 0, onCall: false))
    }

    func testNothingStandingIsNotAskedAbout() {
        XCTAssertNil(prompt())
        XCTAssertNil(prompt(noticeAge: 500))
    }

    func testAnEscalationListedGivesTheEscalationPromptAsBefore() {
        XCTAssertEqual(prompt(escalating: 1)?.message, "1 alert is still waiting to be acknowledged. Quit anyway?")
        XCTAssertEqual(prompt(escalating: 1)?.detail,
                       "Quitting stops every alert still escalating. Nothing more will sound or show, and a Shortcut not yet run will not run.")
        XCTAssertEqual(prompt(escalating: 1), QuitPolicy.escalationPrompt(escalating: 1, missed: 0))
        XCTAssertEqual(prompt(escalating: 2, missed: 1), QuitPolicy.escalationPrompt(escalating: 2, missed: 1))
    }

    func testOnCallWithNothingListedGivesTheOnCallWordsAlone() {
        let asked = prompt(onCall: true)
        XCTAssertEqual(asked?.message, "You are on call. Quit anyway?")
        XCTAssertEqual(asked?.message, QuitPolicy.onCallMessage)
        XCTAssertEqual(asked?.detail, QuitPolicy.onCallLine)
    }

    func testOnCallWithAnEscalationListedGivesTheEscalationPromptOneLineLonger() {
        for (escalating, missed) in [(1, 0), (2, 1), (0, 1), (0, 3)] {
            let plain = QuitPolicy.escalationPrompt(escalating: escalating, missed: missed)
            let asked = prompt(escalating: escalating, missed: missed, onCall: true)
            XCTAssertEqual(asked?.message, plain.message, "the bold line is the escalation's")
            XCTAssertEqual(asked?.detail, plain.detail + " " + QuitPolicy.onCallLine,
                           "its detail, then the on-call line after it")
            XCTAssertNotEqual(asked, prompt(escalating: escalating, missed: missed, onCall: false))
        }
    }

    func testTheWordsForOneAndForSeveral() {
        XCTAssertEqual(prompt(escalating: 1)?.message, "1 alert is still waiting to be acknowledged. Quit anyway?")
        XCTAssertEqual(prompt(escalating: 3)?.message, "3 alerts are still waiting to be acknowledged. Quit anyway?")
        XCTAssertEqual(prompt(escalating: 1, missed: 1)?.message, "2 alerts are still waiting to be acknowledged. Quit anyway?",
                       "the count includes the missed")
        XCTAssertEqual(prompt(missed: 1)?.message, "1 alert is still waiting to be acknowledged. Quit anyway?")
        XCTAssertEqual(prompt(escalating: 3, onCall: true)?.message, "3 alerts are still waiting to be acknowledged. Quit anyway?")
    }

    func testQuittingWithOnlyMissedAlertsSaysNothingIsEscalating() {
        // Nothing is left to sound or run: saying quitting stops it would be
        // untrue.
        XCTAssertEqual(QuitPolicy.escalationPrompt(escalating: 0, missed: 1).detail,
                       "Nothing is escalating now. Quitting forgets the alert missed while the Mac was asleep, and the menu will not list it again.")
        XCTAssertEqual(QuitPolicy.escalationPrompt(escalating: 0, missed: 2).detail,
                       "Nothing is escalating now. Quitting forgets the alerts missed while the Mac was asleep, and the menu will not list them again.")
    }

    func testTheEscalationPromptSaysHowManyAreWaitingAndWhatQuittingStops() {
        XCTAssertEqual(QuitPolicy.escalationPrompt(escalating: 1, missed: 0).message,
                       "1 alert is still waiting to be acknowledged. Quit anyway?")
        XCTAssertEqual(QuitPolicy.escalationPrompt(escalating: 1, missed: 1).message,
                       "2 alerts are still waiting to be acknowledged. Quit anyway?")
        XCTAssertEqual(QuitPolicy.escalationPrompt(escalating: 1, missed: 1).detail,
                       "Quitting stops every alert still escalating. Nothing more will sound or show, and a Shortcut not yet run will not run.")
    }

    func testTheOnCallLineSaysWhatQuittingEndsAndNothingMore() {
        let line = QuitPolicy.onCallLine
        XCTAssertTrue(line.contains("on-call alerting"), line)
        XCTAssertTrue(line.contains("faster self-test"), line)
        XCTAssertTrue(line.contains("until SignalLadder is running again"), "a saved date covers nobody while the app is not running: \(line)")
        for claim in ["covered", "safe", "saved"] {
            XCTAssertFalse(line.lowercased().contains(claim), "it says nothing keeps anyone \(claim): \(line)")
        }
    }

    func testTheTwoButtonTitles() {
        XCTAssertEqual(QuitPolicy.cancelTitle, "Cancel")
        XCTAssertEqual(QuitPolicy.quitTitle, "Quit")
        XCTAssertEqual(QuitPolicy.buttonTitles, ["Cancel", "Quit"],
                       "Cancel first, so it is the default and a stray Return leaves everything running; Quit second, which the app reads as yes")
    }

    // MARK: - Asking again

    func testAskingAgainIsFalseForTheSameAndForFewer() {
        let asked = Standing(escalating: 2, missed: 1, onCall: true)
        XCTAssertFalse(QuitPolicy.askAgain(asked: asked, now: asked))
        XCTAssertFalse(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 1, missed: 1, onCall: true)))
        XCTAssertFalse(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 2, missed: 0, onCall: true)))
        XCTAssertFalse(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 0, missed: 0, onCall: true)))
        XCTAssertFalse(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 0, missed: 0, onCall: false)),
                       "on call ending is not more to say")
    }

    func testAskingAgainIsTrueWhenTheEscalatingCountRose() {
        let asked = Standing(escalating: 1, missed: 0, onCall: false)
        XCTAssertTrue(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 2, missed: 0, onCall: false)))
        XCTAssertTrue(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 5, missed: 0, onCall: false)))
    }

    func testAskingAgainIsTrueWhenTheMissedCountRose() {
        let asked = Standing(escalating: 1, missed: 0, onCall: false)
        XCTAssertTrue(QuitPolicy.askAgain(asked: asked, now: Standing(escalating: 1, missed: 1, onCall: false)))
        // An escalation converted to missed by a sleep while the prompt was up:
        // one fewer escalating and one more missed is more to say than was said.
        XCTAssertTrue(QuitPolicy.askAgain(asked: Standing(escalating: 2, missed: 0, onCall: false),
                                          now: Standing(escalating: 1, missed: 1, onCall: false)))
    }

    func testFromAnOnCallOnlyPromptToOneEscalationAsksAgain() {
        // An on-call-only prompt names none, so one is more.
        XCTAssertTrue(QuitPolicy.askAgain(asked: Standing(escalating: 0, missed: 0, onCall: true),
                                          now: Standing(escalating: 1, missed: 0, onCall: true)))
        XCTAssertTrue(QuitPolicy.askAgain(asked: Standing(escalating: 0, missed: 0, onCall: true),
                                          now: Standing(escalating: 0, missed: 1, onCall: true)))
    }

    func testOnCallBecomingOnWhereThePromptDidNotSayItAsksAgain() {
        XCTAssertTrue(QuitPolicy.askAgain(asked: Standing(escalating: 1, missed: 0, onCall: false),
                                          now: Standing(escalating: 1, missed: 0, onCall: true)))
        XCTAssertFalse(QuitPolicy.askAgain(asked: Standing(escalating: 1, missed: 0, onCall: true),
                                           now: Standing(escalating: 1, missed: 0, onCall: true)))
    }

    func testStandingCountsEscalatingAndMissedApart() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let listed: [EscalationSummary.Status] = [
            .live, .live, .capped(at: now),
            .missedWhileAsleep(convertedAt: now, acknowledgedAt: nil),
            .missedWhileAsleep(convertedAt: now, acknowledgedAt: now),
            .acknowledged(at: now),
        ]
        XCTAssertEqual(Standing(listed: listed, onCall: false), Standing(escalating: 3, missed: 1, onCall: false),
                       "live and capped are escalating; only a missed one not yet seen is missed")
        XCTAssertEqual(Standing(listed: listed, onCall: true), Standing(escalating: 3, missed: 1, onCall: true))
        XCTAssertEqual(Standing(listed: [], onCall: true), Standing(escalating: 0, missed: 0, onCall: true))
    }

    // MARK: - The whole question

    /// A scripted quit: what stands is read in turn, the notice's age is read in
    /// turn, and each prompt is answered in turn. It records every read and every
    /// prompt shown.
    private final class Script {
        static let mostPromptsAScriptMayShow = 12

        var standings: [Standing]
        var ages: [TimeInterval?]
        var answers: [Bool]
        private(set) var standingReads = 0
        private(set) var ageReads = 0
        private(set) var shown: [QuitPolicy.Prompt] = []

        init(standings: [Standing], ages: [TimeInterval?] = [nil], answers: [Bool]) {
            self.standings = standings
            self.ages = ages
            self.answers = answers
        }

        func mayQuit(_ reason: QuitPolicy.Reason = .user) -> Bool {
            QuitPolicy.mayQuit(
                reason: reason,
                standing: {
                    defer { self.standingReads += 1 }
                    return self.standings[min(self.standingReads, self.standings.count - 1)]
                },
                noticeAge: {
                    defer { self.ageReads += 1 }
                    return self.ages[min(self.ageReads, self.ages.count - 1)]
                },
                ask: { prompt in
                    self.shown.append(prompt)
                    // A policy that cannot stop asking must fail here and not
                    // hang the run.
                    guard self.shown.count <= Self.mostPromptsAScriptMayShow else {
                        XCTFail("asked more than \(Self.mostPromptsAScriptMayShow) times")
                        return false
                    }
                    return self.answers[min(self.shown.count - 1, self.answers.count - 1)]
                })
        }
    }

    private func standing(_ escalating: Int = 0, missed: Int = 0, onCall: Bool = false) -> Standing {
        Standing(escalating: escalating, missed: missed, onCall: onCall)
    }

    func testNothingStandingAsksNothingAndQuitGoesAhead() {
        let script = Script(standings: [standing()], answers: [false])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown, [])
    }

    func testAnAnswerOfQuitLetsItGoAheadAfterOnePrompt() {
        let script = Script(standings: [standing(1)], answers: [true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown, [QuitPolicy.escalationPrompt(escalating: 1, missed: 0)])
        XCTAssertEqual(script.standingReads, 2, "once before the prompt and once after the answer, so the listing is read as it is then")
    }

    func testAnAnswerOfCancelStopsItAndReadsNothingMore() {
        let script = Script(standings: [standing(1), standing(5)], answers: [false])
        XCTAssertFalse(script.mayQuit())
        XCTAssertEqual(script.shown.count, 1)
        XCTAssertEqual(script.standingReads, 1, "nothing is read after a cancel")
    }

    func testAnEscalationThatBeganWhileThePromptWasUpIsAskedAboutAgainWithTheNewCount() {
        let script = Script(standings: [standing(1), standing(2), standing(2)], answers: [true, true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown.map(\.message), [
            "1 alert is still waiting to be acknowledged. Quit anyway?",
            "2 alerts are still waiting to be acknowledged. Quit anyway?",
        ])
        XCTAssertEqual(script.standingReads, 3)
    }

    func testCancellingTheSecondPromptStopsIt() {
        let script = Script(standings: [standing(1), standing(2)], answers: [true, false])
        XCTAssertFalse(script.mayQuit())
        XCTAssertEqual(script.shown.count, 2)
    }

    func testCountsThatFellOrStayedTheSameAreNotAskedAboutAgain() {
        for after in [standing(1), standing(0), standing(1, onCall: false)] {
            let script = Script(standings: [standing(1), after], answers: [true])
            XCTAssertTrue(script.mayQuit(), "\(after)")
            XCTAssertEqual(script.shown.count, 1, "\(after)")
        }
    }

    func testItKeepsAskingWhileMoreKeepsArriving() {
        let script = Script(standings: [standing(1), standing(2), standing(3), standing(4), standing(4)],
                            answers: [true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown.map(\.message), [1, 2, 3, 4].map {
            QuitPolicy.escalationPrompt(escalating: $0, missed: 0).message
        })
    }

    func testAnOnCallOnlyPromptIsAskedAgainWhenAnEscalationBegins() {
        let script = Script(standings: [standing(onCall: true), standing(1, onCall: true), standing(1, onCall: true)],
                            answers: [true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown, [
            QuitPolicy.Prompt(message: QuitPolicy.onCallMessage, detail: QuitPolicy.onCallLine),
            prompt(escalating: 1, onCall: true),
        ].compactMap { $0 })
    }

    func testAMissedCountThatRoseIsAskedAboutAgain() {
        let script = Script(standings: [standing(1), standing(0, missed: 1), standing(0, missed: 1)], answers: [true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown.count, 2)
    }

    func testALogOutIsNeverAskedAboutWhateverStands() {
        for reason in [QuitPolicy.Reason.logOut, .restart, .shutDown] {
            let script = Script(standings: [standing(3, missed: 1, onCall: true)], answers: [false])
            XCTAssertTrue(script.mayQuit(reason), "\(reason)")
            XCTAssertEqual(script.shown, [], "\(reason)")
        }
    }

    func testANoticeThatArrivesWhileThePromptIsUpIsNotAskedAboutAgain() {
        // A log out begun while the alert is up must not meet a second one, even
        // though more has begun to escalate: the notice is read afresh when the
        // next prompt would be made.
        let script = Script(standings: [standing(1), standing(2)], ages: [nil, 5], answers: [true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown.count, 1)
        XCTAssertEqual(script.ageReads, 2, "read before each prompt is made, and not carried over")
    }

    func testANoticeThatWasAlreadyThereMeansNoPromptAtAll() {
        let script = Script(standings: [standing(2, onCall: true)], ages: [30], answers: [false])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown, [])
    }

    // MARK: - A prompt that is already showing

    func testANoticeAnswersAShowingPromptFromTheMomentItArrivedUpToItsLifetime() {
        // The app asks with the notice's age as it has just been remembered,
        // which is zero, and the answer is the notice's own: whatever excuses a
        // prompt about to be shown answers one that is up.
        for age: TimeInterval in [0, 0.5, 60, 119.9, 120] {
            XCTAssertTrue(QuitPolicy.noticeAnswersShowingPrompt(age: age), "\(age) seconds")
        }
    }

    func testNoNoticeAnOldOneANegativeAgeAndANonNumberLeaveAShowingPromptUp() {
        XCTAssertFalse(QuitPolicy.noticeAnswersShowingPrompt(age: nil), "no notice has arrived")
        for age: TimeInterval in [-0.001, -60, .nan, 120.001, 121, 36_000, .infinity] {
            XCTAssertFalse(QuitPolicy.noticeAnswersShowingPrompt(age: age), "\(age) seconds")
        }
    }

    func testAShowingPromptIsAnsweredExactlyWhenABeginningOneWouldNotBeShown() {
        // The two decisions are one: for a quit by the user with something to say,
        // the prompt is answered on screen exactly when it would not be shown.
        for age: TimeInterval? in [nil, 0, 60, 120, 120.5, -1, 36_000, .nan] {
            let notShown = prompt(.user, noticeAge: age, escalating: 2, missed: 1, onCall: true) == nil
            XCTAssertEqual(QuitPolicy.noticeAnswersShowingPrompt(age: age), notShown,
                           "a notice of \(String(describing: age))")
        }
    }

    func testAPromptAnsweredByANoticeIsNotAskedAgainHoweverMuchMoreNowStands() {
        // What the app does: the first prompt is up, the notice arrives, and the
        // alert's session ends with the answer the policy gave. More has begun to
        // escalate by then and on-call mode is on, which would ask again, but the
        // notice is read afresh when the next prompt would be made.
        let answer = QuitPolicy.noticeAnswersShowingPrompt(age: 0)
        XCTAssertTrue(answer, "the notice's answer is Quit")
        let script = Script(standings: [standing(1), standing(4, missed: 2, onCall: true)], ages: [nil, 0], answers: [answer])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown, [QuitPolicy.escalationPrompt(escalating: 1, missed: 0)], "the one prompt, and no second")
        XCTAssertEqual(script.standingReads, 2)
    }

    func testWithoutANoticeTheSameMoreIsAskedAboutAgain() {
        // The same script with nothing arriving: the more that stands is asked
        // about, so what the notice does is the notice's and no other's.
        let answer = QuitPolicy.noticeAnswersShowingPrompt(age: nil)
        XCTAssertFalse(answer)
        let script = Script(standings: [standing(1), standing(4, missed: 2, onCall: true), standing(4, missed: 2, onCall: true)],
                            ages: [nil, nil], answers: [true])
        XCTAssertTrue(script.mayQuit())
        XCTAssertEqual(script.shown.count, 2)
    }

    // MARK: - What the log says

    func testTheLogLineHoldsTheCodeAndTheNoticeAgeAndNothingElse() {
        XCTAssertEqual(QuitPolicy.logLine(code: 1819240303, noticeAge: 3.24),
                       "quit reason code: 'logo' (1819240303); power-off notice: 3.2 s old")
        XCTAssertEqual(QuitPolicy.logLine(code: nil, noticeAge: nil),
                       "quit reason code: none; power-off notice: none")
        XCTAssertEqual(QuitPolicy.logLine(code: nil, noticeAge: 0),
                       "quit reason code: none; power-off notice: 0.0 s old")
        XCTAssertEqual(QuitPolicy.logLine(code: 1936225652, noticeAge: nil),
                       "quit reason code: 'shut' (1936225652); power-off notice: none")
    }

    func testACodeIsLoggedAsItsFourCharactersWhenTheyCanBeRead() {
        XCTAssertEqual(QuitPolicy.characters(of: code("rlgo")), "'rlgo'")
        XCTAssertEqual(QuitPolicy.characters(of: code("why?")), "'why?'")
        XCTAssertEqual(QuitPolicy.characters(of: code("    ")), "'    '")
        XCTAssertEqual(QuitPolicy.characters(of: 1), "0x00000001", "not printable, so as a number")
        XCTAssertEqual(QuitPolicy.characters(of: 0x4C4F_0000 | 0x0067), "0x4C4F0067", "one byte that is not printable")
        XCTAssertEqual(QuitPolicy.characters(of: 0x7F41_4141), "0x7F414141", "a byte above printable")
    }
}
