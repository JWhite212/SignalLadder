import XCTest
@testable import NotificationCore

/// What the first run remembers because nothing it can read would show it (M5 plan,
/// Ruling 16, O13, Task 7): one list of tokens. The words saved are typed out in these
/// tests, and never read from the type, because a saved word that changed would read as
/// every earlier answer forgotten. Nothing here reads the real preferences, shows a
/// window or waits on a clock: each test gives a list and reads what the core makes of it.
final class SetupProgressTests: XCTestCase {
    /// One thing the progress can be told, the word it saves, and how it is read back.
    private struct Fact {
        let name: String
        let token: String
        let record: (inout SetupProgress) -> Void
        let isRecorded: (SetupProgress) -> Bool
    }

    private let facts: [Fact] = [
        Fact(name: "started", token: "started",
             record: { $0.recordStarted() }, isRecorded: { $0.hasStarted }),
        Fact(name: "introduction seen", token: "introductionSeen",
             record: { $0.recordIntroductionSeen() }, isRecorded: { $0.hasSeenIntroduction }),
        Fact(name: "Focus attested", token: "focusAttested",
             record: { $0.recordFocusAttested() }, isRecorded: { $0.focusIsAttested }),
        Fact(name: "dismissed", token: "dismissed",
             record: { $0.recordDismissed() }, isRecorded: { $0.isDismissed }),
        Fact(name: "finished", token: "finished",
             record: { $0.recordFinished() }, isRecorded: { $0.isFinished }),
    ]

    /// The eight steps in the plan's order (0 how it works, 1 Accessibility, 2
    /// Notifications, 3 prove it can read, 4 first rule, 5 mute the source app, 6 Do Not
    /// Disturb and Focus, 7 keep it running), each with the string it is saved as.
    private let steps: [(step: SetupStep, raw: String)] = [
        (.howItWorks, "howItWorks"),
        (.accessibility, "accessibility"),
        (.notifications, "notifications"),
        (.proveItCanRead, "proveItCanRead"),
        (.firstRule, "firstRule"),
        (.muteSourceApp, "muteSourceApp"),
        (.focus, "focus"),
        (.keepItRunning, "keepItRunning"),
    ]

    /// Every token the type can write, in the order it writes them.
    private var everyToken: [String] {
        var tokens: [String] = ["started", "introductionSeen"]
        tokens += steps.map { "skipped:" + $0.raw }
        tokens += ["focusAttested", "dismissed", "finished"]
        return tokens
    }

    /// Everything the progress can be told, with the dismissal before the finish so that
    /// both are kept (a finished guide is not dismissed).
    private func everythingRecorded() -> SetupProgress {
        var progress = SetupProgress()
        progress.recordStarted()
        progress.recordIntroductionSeen()
        for (step, _) in steps { progress.recordSkipped(step) }
        progress.recordFocusAttested()
        progress.recordDismissed()
        progress.recordFinished()
        return progress
    }

    /// Progresses to start from: nothing, started, the introduction seen with a step
    /// skipped and the Focus attested, a token only a newer build knows, started and
    /// finished, and started and dismissed.
    private var startingStates: [SetupProgress] {
        var started = SetupProgress()
        started.recordStarted()
        var seenAndSkipped = SetupProgress()
        seenAndSkipped.recordIntroductionSeen()
        seenAndSkipped.recordSkipped(.proveItCanRead)
        seenAndSkipped.recordFocusAttested()
        var finished = SetupProgress()
        finished.recordStarted()
        finished.recordFinished()
        var dismissed = SetupProgress()
        dismissed.recordStarted()
        dismissed.recordDismissed()
        return [SetupProgress(), started, seenAndSkipped, SetupProgress(stored: ["somethingNew"]),
                finished, dismissed]
    }

    // MARK: - A fresh install

    func testNothingRecordedIsAFreshInstallThatSaysNothing() {
        let progress = SetupProgress()
        XCTAssertTrue(progress.isFresh)
        XCTAssertEqual(progress.stored, [])
        for fact in facts {
            XCTAssertFalse(fact.isRecorded(progress), fact.name)
        }
        for (step, raw) in steps {
            XCTAssertFalse(progress.isSkipped(step), raw)
        }
    }

    func testAnEmptyListIsAFreshInstallsProgress() {
        XCTAssertEqual(SetupProgress(stored: []), SetupProgress())
        XCTAssertTrue(SetupProgress(stored: []).isFresh)
        XCTAssertEqual(SetupProgress(stored: []).stored, [])
    }

    func testAnythingRecordedIsNoLongerFresh() {
        for fact in facts {
            var progress = SetupProgress()
            fact.record(&progress)
            XCTAssertFalse(progress.isFresh, fact.name)
        }
        for (step, raw) in steps {
            var progress = SetupProgress()
            progress.recordSkipped(step)
            XCTAssertFalse(progress.isFresh, raw)
        }
    }

    // MARK: - Recording and reading back

    func testEachFactIsReadAsRecordedByItsOwnMethodAndNoOtherFactIs() {
        for fact in facts {
            var progress = SetupProgress()
            fact.record(&progress)
            XCTAssertTrue(fact.isRecorded(progress), fact.name)
            for other in facts where other.name != fact.name {
                XCTAssertFalse(other.isRecorded(progress), "\(fact.name) recorded, \(other.name) read")
            }
            for (step, raw) in steps {
                XCTAssertFalse(progress.isSkipped(step), "\(fact.name) recorded, \(raw) read as skipped")
            }
        }
    }

    func testEachFactIsSavedAsItsOwnWordAndNothingElse() {
        for fact in facts {
            var progress = SetupProgress()
            fact.record(&progress)
            XCTAssertEqual(progress.stored, [fact.token], fact.name)
        }
    }

    func testRecordingATokenTwiceChangesNothing() {
        for fact in facts {
            var once = SetupProgress()
            fact.record(&once)
            var twice = once
            fact.record(&twice)
            XCTAssertEqual(twice, once, fact.name)
            XCTAssertEqual(twice.stored, [fact.token], fact.name)
        }
        for (step, raw) in steps {
            var once = SetupProgress()
            once.recordSkipped(step)
            var twice = once
            twice.recordSkipped(step)
            XCTAssertEqual(twice, once, raw)
            XCTAssertEqual(twice.stored, ["skipped:" + raw], raw)
        }
    }

    func testRecordingEverythingTwiceChangesNothing() {
        let once = everythingRecorded()
        var twice = once
        twice.recordStarted()
        twice.recordIntroductionSeen()
        for (step, _) in steps { twice.recordSkipped(step) }
        twice.recordFocusAttested()
        twice.recordDismissed()
        twice.recordFinished()
        XCTAssertEqual(twice, once)
        XCTAssertEqual(twice.stored, once.stored)
    }

    func testATokenInTheListTwiceIsOneToken() {
        let progress = SetupProgress(stored: ["started", "started", "skipped:focus", "skipped:focus",
                                              "somethingNew", "somethingNew"])
        XCTAssertEqual(progress.stored, ["started", "skipped:focus", "somethingNew"])
        XCTAssertEqual(progress, SetupProgress(stored: ["started", "skipped:focus", "somethingNew"]))
    }

    // MARK: - Round trips

    func testEverythingRecordedRoundTripsThroughTheList() {
        let progress = everythingRecorded()
        let list = progress.stored
        XCTAssertEqual(list.count, 13, "the five facts and the eight steps")
        let again = SetupProgress(stored: list)
        XCTAssertEqual(again, progress)
        XCTAssertEqual(again.stored, list)
        XCTAssertTrue(again.hasStarted && again.hasSeenIntroduction && again.focusIsAttested
                      && again.isDismissed && again.isFinished)
        for (step, raw) in steps {
            XCTAssertTrue(again.isSkipped(step), raw)
        }
    }

    /// Every one of the thirty-two sets the five facts can be in, each with no step
    /// skipped, with one skipped and with all of them skipped.
    func testEveryCombinationOfTheFactsAndSkipsRoundTrips() {
        // The dismissal goes in before the finish, so that both are kept (see
        // `testAFinishedGuideIsNotDismissed`).
        let order = ["started", "introductionSeen", "focusAttested", "dismissed", "finished"]
        let byToken = Dictionary(uniqueKeysWithValues: facts.map { ($0.token, $0) })
        let skips: [[SetupStep]] = [[], [.focus], steps.map { $0.step }]
        for mask in 0..<(1 << order.count) {
            for skipped in skips {
                var progress = SetupProgress()
                var expectedFacts: [String] = []
                for (index, token) in order.enumerated() where mask & (1 << index) != 0 {
                    byToken[token]?.record(&progress)
                    expectedFacts.append(token)
                }
                for step in skipped { progress.recordSkipped(step) }

                let again = SetupProgress(stored: progress.stored)
                XCTAssertEqual(again, progress, "mask \(mask), \(skipped.count) skipped")
                XCTAssertEqual(again.stored, progress.stored, "mask \(mask), \(skipped.count) skipped")
                for fact in facts {
                    XCTAssertEqual(fact.isRecorded(again), expectedFacts.contains(fact.token),
                                   "\(fact.name), mask \(mask)")
                }
                for (step, raw) in steps {
                    XCTAssertEqual(again.isSkipped(step), skipped.contains(step), "\(raw), mask \(mask)")
                }
            }
        }
    }

    /// What is saved is the same whatever order things were recorded or read in, and
    /// two progresses that hold the same facts are equal. The dismissal and the finish
    /// are left out of the other order here, since that pair is the one where the order
    /// matters (`testTheOrderOfADismissalAndAFinishIsTheOnePairWhereItMatters`).
    func testWhatIsSavedAndWhatIsEqualDoNotDependOnTheOrderThingsWereRecordedIn() {
        var forwards = SetupProgress()
        forwards.recordStarted()
        forwards.recordSkipped(.accessibility)
        forwards.recordFocusAttested()
        forwards.recordDismissed()
        var backwards = SetupProgress()
        backwards.recordDismissed()
        backwards.recordFocusAttested()
        backwards.recordSkipped(.accessibility)
        backwards.recordStarted()
        XCTAssertEqual(forwards, backwards)
        XCTAssertEqual(forwards.stored, backwards.stored)
        XCTAssertEqual(SetupProgress(stored: ["dismissed", "focusAttested", "skipped:accessibility", "started"]),
                       forwards)
    }

    func testTheKnownTokensAreWrittenInOneFixedOrderWhateverOrderTheyWereReadIn() {
        let scrambled = ["finished", "skipped:keepItRunning", "dismissed", "focusAttested", "skipped:howItWorks",
                         "introductionSeen", "skipped:firstRule", "started"]
        XCTAssertEqual(SetupProgress(stored: scrambled).stored,
                       ["started", "introductionSeen", "skipped:howItWorks", "skipped:firstRule",
                        "skipped:keepItRunning", "focusAttested", "dismissed", "finished"])
    }

    // MARK: - What is written

    /// The words are saved, so each is typed here: a rename that changed one would read as
    /// every earlier answer forgotten, and nothing but this test would say so.
    func testEveryTokenTheTypeCanWriteIsExactlyTheWordsTheTableGives() {
        XCTAssertEqual(everythingRecorded().stored, everyToken)
        XCTAssertEqual(everyToken, [
            "started", "introductionSeen",
            "skipped:howItWorks", "skipped:accessibility", "skipped:notifications", "skipped:proveItCanRead",
            "skipped:firstRule", "skipped:muteSourceApp", "skipped:focus", "skipped:keepItRunning",
            "focusAttested", "dismissed", "finished",
        ])
    }

    func testTheKeyTheListIsSavedUnderIsPinned() {
        XCTAssertEqual(SetupProgress.storageKey, "setupProgress")
    }

    /// Nothing a notification said, no app and no rule is in a token (Global Constraints):
    /// every token is a short word from a closed list, and a skipped one carries a step's
    /// string and nothing else.
    func testNoTokenCanCarryWhatANotificationSaidOrAnAppOrARuleIsCalled() {
        let closedList = Set(everyToken)
        XCTAssertEqual(closedList.count, 13)
        for token in everythingRecorded().stored {
            XCTAssertTrue(closedList.contains(token), token)
            XCTAssertLessThan(token.count, 30, token)
            XCTAssertNil(token.rangeOfCharacter(from: .whitespacesAndNewlines), token)
        }
        let skippedWords = everyToken.filter { $0.hasPrefix("skipped:") }
        XCTAssertEqual(skippedWords.map { String($0.dropFirst("skipped:".count)) }, steps.map { $0.raw })
    }

    // MARK: - The steps

    /// The steps are saved by these strings, and they are the plan's order (Ruling 16,
    /// O13): `allCases` is the order the guide shows them.
    func testTheStepRawStringsArePinnedAndInThePlansOrder() {
        XCTAssertEqual(SetupStep.allCases.map(\.rawValue), steps.map { $0.raw })
        XCTAssertEqual(SetupStep.allCases, steps.map { $0.step })
        XCTAssertEqual(SetupStep.allCases.count, 8)
        for (step, raw) in steps {
            XCTAssertEqual(step.rawValue, raw)
            XCTAssertEqual(SetupStep(rawValue: raw), step)
        }
        XCTAssertEqual(SetupStep.allCases.map(\.rawValue), [
            "howItWorks", "accessibility", "notifications", "proveItCanRead",
            "firstRule", "muteSourceApp", "focus", "keepItRunning",
        ])
    }

    func testTheStepStringsAreDistinctAndCannotBreakAToken() {
        let raws = SetupStep.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
        for raw in raws {
            XCTAssertFalse(raw.isEmpty)
            XCTAssertFalse(raw.contains(":"), "a colon would make the token ambiguous: \(raw)")
            XCTAssertNil(raw.rangeOfCharacter(from: .whitespacesAndNewlines), raw)
        }
    }

    func testASkippedTokenIsWrittenForEachStepAndReadsBackForThatStepOnly() {
        for (step, raw) in steps {
            var progress = SetupProgress()
            progress.recordSkipped(step)
            XCTAssertEqual(progress.stored, ["skipped:" + raw], raw)
            for (other, otherRaw) in steps {
                XCTAssertEqual(progress.isSkipped(other), other == step, "\(raw) skipped, \(otherRaw) read")
            }
            for fact in facts {
                XCTAssertFalse(fact.isRecorded(progress), "\(raw) skipped, \(fact.name) read")
            }
            XCTAssertEqual(SetupProgress(stored: ["skipped:" + raw]), progress, raw)
        }
    }

    func testSkippingSeveralStepsKeepsEachAndSkippingOneTwiceIsOnce() {
        var progress = SetupProgress()
        progress.recordSkipped(.proveItCanRead)
        progress.recordSkipped(.keepItRunning)
        progress.recordSkipped(.proveItCanRead)
        XCTAssertEqual(progress.stored, ["skipped:proveItCanRead", "skipped:keepItRunning"])
        for (step, raw) in steps {
            XCTAssertEqual(progress.isSkipped(step), step == .proveItCanRead || step == .keepItRunning, raw)
        }
    }

    /// The progress records what it is told. Which steps may be skipped is the plan's
    /// decision, so the introduction, and the steps a fact shows, can each be recorded.
    func testAnyStepCanBeRecordedAsSkippedBecauseWhichMayBeIsThePlansToSay() {
        var progress = SetupProgress()
        for (step, _) in steps { progress.recordSkipped(step) }
        for (step, raw) in steps {
            XCTAssertTrue(progress.isSkipped(step), raw)
        }
        XCTAssertFalse(progress.hasSeenIntroduction, "skipping step 0 is not seeing the introduction")
        XCTAssertFalse(progress.focusIsAttested, "skipping step 6 is not attesting it")
    }

    // MARK: - Malformed and unknown tokens

    func testAMalformedSkippedTokenSkipsNothing() {
        let malformed = ["skipped:", "skipped", "skipped:nonsense", "skipped:accessibility:extra",
                         "skipped: accessibility", "skipped:accessibility ", "Skipped:accessibility",
                         "skipped:Accessibility", "skipped::accessibility", "skip:accessibility",
                         "skipped:0", "skipped:1", "SKIPPED:FOCUS", "skipped:\u{0}"]
        for token in malformed {
            let progress = SetupProgress(stored: [token])
            for (step, raw) in steps {
                XCTAssertFalse(progress.isSkipped(step), "\(token.debugDescription) read as \(raw) skipped")
            }
            XCTAssertTrue(progress.isFresh, token.debugDescription)
            XCTAssertEqual(progress.stored, [token], "kept like any token this build does not know")
        }
    }

    func testAMalformedSkippedTokenBesideAGoodOneLeavesTheGoodOneRead() {
        let progress = SetupProgress(stored: ["skipped:", "skipped:focus", "skipped:nonsense"])
        for (step, raw) in steps {
            XCTAssertEqual(progress.isSkipped(step), step == .focus, raw)
        }
        XCTAssertFalse(progress.isFresh)
        XCTAssertEqual(progress.stored, ["skipped:focus", "skipped:", "skipped:nonsense"])
    }

    func testTokensThatAreNotTheExactWordsAreNotFacts() {
        let near = ["Started", "STARTED", " started", "started ", "start", "dismiss", "Dismissed", "finish", "done",
                    "finished\n", "introduction", "introductionseen", "focus", "focusattested", "FocusAttested", ""]
        for token in near {
            let progress = SetupProgress(stored: [token])
            XCTAssertTrue(progress.isFresh, token.debugDescription)
            for fact in facts {
                XCTAssertFalse(fact.isRecorded(progress), "\(token.debugDescription) read as \(fact.name)")
            }
            XCTAssertEqual(progress.stored, [token], token.debugDescription)
        }
    }

    func testUnknownTokensAreIgnoredWhenRead() {
        let progress = SetupProgress(stored: ["somethingNew", "started", "alsoNew", "skipped:accessibility"])
        XCTAssertTrue(progress.hasStarted)
        XCTAssertTrue(progress.isSkipped(.accessibility))
        XCTAssertFalse(progress.isDismissed)
        XCTAssertFalse(progress.isFinished)
        XCTAssertFalse(progress.hasSeenIntroduction)
        XCTAssertFalse(progress.focusIsAttested)
        XCTAssertFalse(progress.isFresh)
        for (step, raw) in steps where step != .accessibility {
            XCTAssertFalse(progress.isSkipped(step), raw)
        }
    }

    /// A list that holds only tokens this build does not know is a fresh install's: they
    /// are no fact, so none of them can make the guide read as started or finished.
    func testAListOfOnlyUnknownTokensIsAFreshInstallsProgress() {
        let progress = SetupProgress(stored: ["somethingNew", "finished2", "v2:started"])
        XCTAssertTrue(progress.isFresh)
        for fact in facts {
            XCTAssertFalse(fact.isRecorded(progress), fact.name)
        }
        for (step, raw) in steps {
            XCTAssertFalse(progress.isSkipped(step), raw)
        }
    }

    // MARK: - Unknown tokens are kept

    /// A newer build's token survives an older build's write: the older build reads the
    /// list, records something, and writes the whole list back.
    func testAnUnknownTokenIsKeptWhenTheListIsWrittenBack() {
        let progress = SetupProgress(stored: ["somethingNew"])
        XCTAssertEqual(progress.stored, ["somethingNew"])

        var recorded = progress
        recorded.recordStarted()
        recorded.recordSkipped(.focus)
        recorded.recordDismissed()
        XCTAssertEqual(recorded.stored, ["started", "skipped:focus", "dismissed", "somethingNew"])
        XCTAssertEqual(SetupProgress(stored: recorded.stored), recorded)
    }

    func testUnknownTokensAreWrittenAfterTheKnownOnesAndSorted() {
        let progress = SetupProgress(stored: ["zeta", "finished", "alpha", "started", "mid"])
        XCTAssertEqual(progress.stored, ["started", "finished", "alpha", "mid", "zeta"])
    }

    // MARK: - Dismissed

    /// "Not now" and closing the window are one act (O13), and one method records it,
    /// from whatever the progress was: it adds the one token and changes nothing else.
    func testDismissedIsRecordedByTheOneMethodFromAnyStateThatIsNotFinished() {
        let starts = startingStates.filter { !$0.isFinished && !$0.isDismissed }
        XCTAssertEqual(starts.count, 4, "nothing, started, seen and skipped, and an unknown token")
        for start in starts {
            var dismissed = start
            dismissed.recordDismissed()
            XCTAssertTrue(dismissed.isDismissed)
            XCTAssertEqual(Set(dismissed.stored).subtracting(start.stored), ["dismissed"])
            XCTAssertEqual(Set(dismissed.stored).intersection(start.stored), Set(start.stored))
            XCTAssertEqual(dismissed.hasStarted, start.hasStarted)
            XCTAssertEqual(dismissed.isFinished, start.isFinished)
            XCTAssertEqual(dismissed.hasSeenIntroduction, start.hasSeenIntroduction)
            XCTAssertEqual(dismissed.focusIsAttested, start.focusIsAttested)
        }
    }

    func testDismissingTwiceIsOnceWhicheverActAsksFirst() {
        var notNowThenClose = SetupProgress()
        notNowThenClose.recordStarted()
        notNowThenClose.recordDismissed()
        notNowThenClose.recordDismissed()
        var closeAlone = SetupProgress()
        closeAlone.recordStarted()
        closeAlone.recordDismissed()
        XCTAssertEqual(notNowThenClose, closeAlone)
        XCTAssertEqual(notNowThenClose.stored, ["started", "dismissed"])
    }

    /// There is no second way to write a dismissal: nothing else records it, whatever
    /// the progress already held, and a guide that was started, finished or had its steps
    /// skipped is not thereby dismissed. Each of the other recorders is run from every
    /// starting state, a finished one and one already dismissed among them, and none
    /// changes whether the guide is dismissed.
    func testNothingButTheDismissalMethodRecordsADismissal() {
        let starts = startingStates
        XCTAssertEqual(starts.count, 6)
        for start in starts {
            for fact in facts where fact.name != "dismissed" {
                var progress = start
                fact.record(&progress)
                XCTAssertEqual(progress.isDismissed, start.isDismissed, "\(fact.name) recorded on \(start.stored)")
                XCTAssertEqual(progress.stored.contains("dismissed"), start.stored.contains("dismissed"),
                               "\(fact.name) recorded on \(start.stored)")
            }
            for (step, raw) in steps {
                var progress = start
                progress.recordSkipped(step)
                XCTAssertEqual(progress.isDismissed, start.isDismissed, "\(raw) skipped on \(start.stored)")
                XCTAssertEqual(progress.stored.contains("dismissed"), start.stored.contains("dismissed"),
                               "\(raw) skipped on \(start.stored)")
            }
        }
        var skipped = SetupProgress()
        for (step, _) in steps { skipped.recordSkipped(step) }
        XCTAssertFalse(skipped.isDismissed)
        XCTAssertFalse(skipped.stored.contains("dismissed"))
        XCTAssertFalse(SetupProgress(stored: ["started", "finished"]).isDismissed)
    }

    /// Closing the window after the last step is not a "Not now": the close path calls
    /// the one method every time, and it records nothing for a finished guide, so the
    /// app target has no decision to make there (Ruling 10).
    func testAFinishedGuideIsNotDismissed() {
        var progress = SetupProgress()
        progress.recordStarted()
        progress.recordFinished()
        let before = progress
        progress.recordDismissed()
        XCTAssertEqual(progress, before)
        XCTAssertFalse(progress.isDismissed)
        XCTAssertEqual(progress.stored, ["started", "finished"])

        var fromAList = SetupProgress(stored: ["finished"])
        fromAList.recordDismissed()
        XCTAssertEqual(fromAList.stored, ["finished"])
    }

    /// A guide dismissed and then finished (opened again from Settings, and completed)
    /// keeps both, and one record does not undo the other.
    func testFinishingADismissedGuideKeepsBothRecords() {
        var progress = SetupProgress()
        progress.recordStarted()
        progress.recordDismissed()
        progress.recordFinished()
        XCTAssertTrue(progress.isDismissed)
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.stored, ["started", "dismissed", "finished"])
        XCTAssertEqual(SetupProgress(stored: progress.stored), progress)
    }

    /// The one pair of records where the order they are made in is what is saved: the
    /// guard in `recordDismissed()` is deliberate, so a dismissal after a finish is not
    /// written and a dismissal before one is kept. Every other pair is in
    /// `testWhatIsSavedAndWhatIsEqualDoNotDependOnTheOrderThingsWereRecordedIn`.
    func testTheOrderOfADismissalAndAFinishIsTheOnePairWhereItMatters() {
        var dismissedThenFinished = SetupProgress()
        dismissedThenFinished.recordDismissed()
        dismissedThenFinished.recordFinished()
        var finishedThenDismissed = SetupProgress()
        finishedThenDismissed.recordFinished()
        finishedThenDismissed.recordDismissed()
        XCTAssertEqual(dismissedThenFinished.stored, ["dismissed", "finished"])
        XCTAssertEqual(finishedThenDismissed.stored, ["finished"])
        XCTAssertNotEqual(dismissedThenFinished, finishedThenDismissed)
        XCTAssertTrue(dismissedThenFinished.isDismissed)
        XCTAssertFalse(finishedThenDismissed.isDismissed)
        XCTAssertTrue(dismissedThenFinished.isFinished && finishedThenDismissed.isFinished)
    }

    /// A list may hold both, from a build that wrote them in either order, and each is
    /// read as it says.
    func testAListThatHoldsBothDismissedAndFinishedReadsBoth() {
        let progress = SetupProgress(stored: ["finished", "dismissed"])
        XCTAssertTrue(progress.isDismissed)
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.stored, ["dismissed", "finished"])
    }

    // MARK: - Equality

    func testProgressesAreEqualWhenTheyHoldTheSameFactsAndUnequalWhenTheyDoNot() {
        XCTAssertEqual(SetupProgress(stored: ["started"]), SetupProgress(stored: ["started"]))
        XCTAssertNotEqual(SetupProgress(stored: ["started"]), SetupProgress())
        XCTAssertNotEqual(SetupProgress(stored: ["started"]), SetupProgress(stored: ["dismissed"]))
        XCTAssertNotEqual(SetupProgress(stored: ["skipped:focus"]), SetupProgress(stored: ["skipped:firstRule"]))
        XCTAssertNotEqual(SetupProgress(stored: ["started"]), SetupProgress(stored: ["started", "somethingNew"]),
                          "what is kept is part of what is held")
    }
}
