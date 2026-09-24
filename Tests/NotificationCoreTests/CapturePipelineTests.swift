import XCTest
@testable import NotificationCore

/// The first tests of the capture decision path. Until now it lived in a
/// closure in a target with no tests; the first half of this file pins what
/// it already did, so moving it could not change it unnoticed.
final class CapturePipelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
    private let marker = "SignalLadder canary TEST-MARKER"

    /// Stands in for the speaker: records every sound asked for, and answers
    /// as told.
    private final class FakeSpeaker {
        private(set) var requests: [String] = []
        var answer: (String, Double) -> AlertOutcome = { .played(sound: $0, gainDB: $1, outputSilent: false) }

        func play(_ name: String, _ gainDB: Double) -> AlertOutcome {
            requests.append("\(name) \(gainDB)")
            return answer(name, gainDB)
        }
    }

    private func pipeline(speaker: FakeSpeaker = FakeSpeaker()) -> CapturePipeline {
        CapturePipeline(ownAppName: "SignalLadder",
                        isSelfTest: { [marker] raw, children in
                            raw.contains(marker) || children.contains { $0.contains(marker) }
                        },
                        playSound: speaker.play)
    }

    /// A banner as the watcher delivers it: comma-joined description plus the
    /// text children that carry the fields separately (M1 finding).
    private func banner(_ app: String, _ title: String, _ body: String = "body",
                        at offset: TimeInterval = 0) -> (RawCapture, [String]) {
        (RawCapture(timestamp: t0.addingTimeInterval(offset),
                    rawText: "\(app), \(title), \(body)",
                    subrole: "AXNotificationCenterBanner"),
         [title, body])
    }

    @discardableResult
    private func feed(_ p: CapturePipeline, _ b: (RawCapture, [String])) -> CapturePipeline.Outcome {
        p.process(b.0, textChildren: b.1)
    }

    // MARK: - Pinned behaviour (moved, not changed)

    func testADistinctCaptureIsRecordedAndCounted() {
        let p = pipeline()
        XCTAssertEqual(feed(p, banner("Weather", "Rain")), .recorded(matchedRule: nil))
        XCTAssertEqual(p.captureCount, 1)
        XCTAssertEqual(p.history.entries.first?.captured.appNameGuess, "Weather")
    }

    func testTheSelfTestIsNeitherRecordedNorCounted() {
        let p = pipeline()
        XCTAssertEqual(feed(p, banner("SignalLadder", "SignalLadder self-test", marker)), .selfTest)
        XCTAssertEqual(p.captureCount, 0)
        XCTAssertTrue(p.history.isEmpty)
    }

    func testTheSelfTestIsFoundInTheChildrenWhenTheDescriptionIsEmpty() {
        let p = pipeline()
        let raw = RawCapture(timestamp: t0, rawText: "", subrole: "AXNotificationCenterBanner")
        XCTAssertEqual(p.process(raw, textChildren: ["SignalLadder self-test", marker]), .selfTest)
    }

    func testTheAppsOwnAlarmIsNeitherRecordedNorCounted() {
        let p = pipeline()
        XCTAssertEqual(feed(p, banner("SignalLadder", SelfNotification.blindTitle)), .ownNotification)
        XCTAssertEqual(p.captureCount, 0)
    }

    func testTheSelfTestNeverEntersTheDedupeWindow() {
        // Recognised once and then forgotten, exactly as CanaryService clears
        // its marker after the first match.
        var recognised = false
        let p = CapturePipeline(ownAppName: "SignalLadder", isSelfTest: { _, _ in
            defer { recognised = true }
            return !recognised
        }, playSound: FakeSpeaker().play)

        XCTAssertEqual(feed(p, banner("Weather", "Rain")), .selfTest)

        // Identical text inside dedupe's 1.5s window. Had the self-test been
        // admitted to dedupe, this would be suppressed as a repeat of it and
        // never recorded at all.
        XCTAssertEqual(feed(p, banner("Weather", "Rain", at: 0.5)), .recorded(matchedRule: nil))
    }

    func testARepeatLandsOnTheRowItDuplicatesAndIsNotRecordedAgain() {
        let p = pipeline()
        feed(p, banner("Teams", "ping", at: 0))
        feed(p, banner("Weather", "Rain", at: 0.2))
        XCTAssertEqual(feed(p, banner("Teams", "ping", at: 0.4)), .suppressedRepeat)

        XCTAssertEqual(p.captureCount, 2)
        XCTAssertEqual(p.history.entries.last?.captured.appNameGuess, "Teams")
        XCTAssertEqual(p.history.entries.last?.suppressedRepeatCount, 1)
        XCTAssertEqual(p.history.entries.first?.suppressedRepeatCount, 0, "Weather did not repeat")
    }

    // MARK: - Rules at capture

    private let teams = Rule(name: "Teams", condition: .field(.app, .equals, "Teams"))

    func testWithNoRulesARowIsNotEvaluatedRatherThanMatchingNothing() {
        let p = pipeline()
        feed(p, banner("Teams", "ping"))
        XCTAssertNil(p.history.entries.first?.annotation,
                     "no rules loaded is 'not evaluated' — never 'matched no rule'")
    }

    func testAMatchingRuleAnnotatesTheRowAndBecomesTheLastMatch() {
        let p = pipeline()
        p.setRules([teams])
        XCTAssertEqual(feed(p, banner("Teams", "ping", at: 5)), .recorded(matchedRule: "Teams"))
        XCTAssertEqual(p.history.entries.first?.annotation, MatchAnnotation(ruleName: "Teams"))
        XCTAssertEqual(p.lastMatch, .init(ruleName: "Teams", at: t0.addingTimeInterval(5), alert: .noAlertSet))
    }

    func testANonMatchingRowUnderLoadedRulesSaysItMatchedNothing() {
        let p = pipeline()
        p.setRules([teams])
        feed(p, banner("Weather", "Rain"))
        XCTAssertEqual(p.history.entries.first?.annotation, MatchAnnotation(ruleName: nil))
        XCTAssertNil(p.lastMatch)
    }

    func testRepeatsNeverReachTheRuleEngine() {
        // From M3b a match can sound an alert. One banner re-firing during its
        // animation must not sound it twice.
        let p = pipeline()
        p.setRules([teams])
        feed(p, banner("Teams", "ping", at: 0))
        let first = p.lastMatch
        XCTAssertEqual(feed(p, banner("Teams", "ping", at: 0.5)), .suppressedRepeat)
        XCTAssertEqual(p.lastMatch, first, "a repeat must not register as a fresh match")
    }

    // MARK: - Previewing new rules against what was already captured

    func testNewRulesArePreviewedAgainstEveryRetainedRow() {
        let p = pipeline()
        feed(p, banner("Teams", "ping", at: 0))
        feed(p, banner("Weather", "Rain", at: 1))

        XCTAssertEqual(p.setRules([teams]), 1, "one of the two retained rows would match")
        let byApp = Dictionary(uniqueKeysWithValues: p.history.entries.map { ($0.captured.appNameGuess, $0) })
        XCTAssertEqual(byApp["Teams"]?.preview, MatchAnnotation(ruleName: "Teams"))
        XCTAssertEqual(byApp["Weather"]?.preview, MatchAnnotation(ruleName: nil))
    }

    func testAPreviewNeverRewritesWhatHappenedAtCapture() {
        // `annotation` is the rule that matched on arrival — what M3b acts on.
        // A row that matched nothing when it arrived must go on saying so,
        // whatever the rules say now.
        let p = pipeline()
        p.setRules([Rule(name: "Weather", condition: .field(.app, .equals, "Weather"))])
        feed(p, banner("Teams", "ping"))

        p.setRules([teams])

        let row = p.history.entries.first
        XCTAssertEqual(row?.annotation, MatchAnnotation(ruleName: nil), "what happened")
        XCTAssertEqual(row?.preview, MatchAnnotation(ruleName: "Teams"), "what would happen now")
    }

    func testAPreviewIsNeverReportedAsTheLastMatch() {
        let p = pipeline()
        feed(p, banner("Teams", "ping"))
        p.setRules([teams])
        XCTAssertNil(p.lastMatch, "a preview describes what would happen, not an event that occurred")
    }

    func testClearingTheRulesClearsThePreviews() {
        let p = pipeline()
        feed(p, banner("Teams", "ping"))
        p.setRules([teams])
        XCTAssertEqual(p.setRules([]), 0)
        XCTAssertNil(p.history.entries.first?.preview)
    }

    // MARK: - The current rules' verdict on what is retained

    func testCurrentRuleMatchCountCombinesPreviewsWithLiveMatches() {
        let p = pipeline()
        feed(p, banner("Teams", "before rules", at: 0))  // previewed: matches
        p.setRules([teams])
        feed(p, banner("Teams", "after", at: 5))         // live: matches
        feed(p, banner("Weather", "Rain", at: 6))        // live: does not
        XCTAssertEqual(p.currentRuleMatchCount, 2)
    }

    func testWithNoRulesLoadedOldMatchesAreNotCountedAsTheCurrentVerdict() {
        let p = pipeline()
        p.setRules([teams])
        feed(p, banner("Teams", "ping"))   // annotated live by rules about to vanish
        p.setRules([])
        XCTAssertEqual(p.currentRuleMatchCount, 0,
                       "that annotation came from rules that no longer exist")
    }

    // MARK: - Honesty about rule history

    func testARowFromARulesGapDoesNotClaimToPredateAllRules() {
        // Review finding. Rules loaded, then emptied (a broken file on reload),
        // then a notification, then rules again. The row must not claim it
        // arrived "before any rules were loaded" — rules existed before it.
        let p = pipeline()
        p.setRules([teams])
        p.setRules([])
        feed(p, banner("Teams", "in the gap"))
        p.setRules([teams])

        let row = p.history.entries.first!
        XCTAssertEqual(InspectorRowText.outcome(row), "Arrived while no rules were loaded")
        XCTAssertFalse(InspectorRowText.outcome(row).contains("before"))
    }

    func testANeverEvaluatedRowDoesNotClaimNoRulesHaveEverExisted() {
        let p = pipeline()
        p.setRules([teams])
        p.setRules([])
        feed(p, banner("Teams", "after rules were cleared"))
        XCTAssertEqual(InspectorRowText.outcome(p.history.entries.first!), "Not evaluated — no rules loaded",
                       "\"no rules yet\" would claim none had ever been loaded")
    }

    // MARK: - Alerts

    private func rule(_ name: String, app: String, _ alert: AlertAction?) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, app), alert: alert)
    }

    func testASoundingRulePlaysItsSoundOnceAndTheRowSaysSo() {
        let speaker = FakeSpeaker()
        let p = pipeline(speaker: speaker)
        p.setRules([rule("On call", app: "Teams", .sound(name: "Glass", gainDB: 6))])

        feed(p, banner("Teams", "@you", at: 5))

        XCTAssertEqual(speaker.requests, ["Glass 6.0"])
        let played = AlertOutcome.played(sound: "Glass", gainDB: 6, outputSilent: false)
        XCTAssertEqual(p.history.entries.first?.alertOutcome, played)
        XCTAssertEqual(p.lastMatch, .init(ruleName: "On call", at: t0.addingTimeInterval(5), alert: played))
    }

    func testASilentRuleClaimsTheNotificationSoALaterSoundingRuleDoesNotPlay() {
        let speaker = FakeSpeaker()
        let p = pipeline(speaker: speaker)
        p.setRules([rule("Quiet weather", app: "Weather", .silent),
                    Rule(name: "Everything", condition: .field(.subrole, .equals, "AXNotificationCenterBanner"), alert: .sound(name: "Glass", gainDB: 0))])

        feed(p, banner("Weather", "Rain"))

        XCTAssertEqual(speaker.requests, [], "first match wins, and the first match is silent")
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .silentByRule)
    }

    func testARuleWithNoAlertPlaysNothingAndSaysSo() {
        let speaker = FakeSpeaker()
        let p = pipeline(speaker: speaker)
        p.setRules([rule("Teams", app: "Teams", nil)])

        feed(p, banner("Teams", "ping"))

        XCTAssertEqual(speaker.requests, [])
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .noAlertSet,
                       "a rule with no alert must read differently from a deliberately silent one")
    }

    func testARowThatMatchedNothingHasNoAlertOutcome() {
        let p = pipeline()
        p.setRules([rule("Teams", app: "Teams", .sound(name: "Glass", gainDB: 0))])
        feed(p, banner("Weather", "Rain"))
        XCTAssertNil(p.history.entries.first?.alertOutcome)
    }

    func testARepeatNeverSoundsTheAlertASecondTime() {
        let speaker = FakeSpeaker()
        let p = pipeline(speaker: speaker)
        p.setRules([rule("On call", app: "Teams", .sound(name: "Glass", gainDB: 0))])

        feed(p, banner("Teams", "@you", at: 0))
        feed(p, banner("Teams", "@you", at: 0.4))

        XCTAssertEqual(speaker.requests.count, 1)
    }

    func testTheAppsOwnTrafficNeverSoundsAnAlert() {
        let speaker = FakeSpeaker()
        let p = pipeline(speaker: speaker)
        p.setRules([Rule(name: "Everything", condition: .field(.subrole, .equals, "AXNotificationCenterBanner"), alert: .sound(name: "Glass", gainDB: 0))])

        feed(p, banner("SignalLadder", "SignalLadder self-test", marker))
        feed(p, banner("SignalLadder", SelfNotification.blindTitle))

        XCTAssertEqual(speaker.requests, [])
    }

    func testAPreviewNeverSoundsAnAlert() {
        let speaker = FakeSpeaker()
        let p = pipeline(speaker: speaker)
        feed(p, banner("Teams", "@you"))

        p.setRules([rule("On call", app: "Teams", .sound(name: "Glass", gainDB: 0))])

        XCTAssertEqual(p.history.entries.first?.preview, MatchAnnotation(ruleName: "On call"), "the preview did run")
        XCTAssertEqual(speaker.requests, [], "a preview is what would happen; playing it would make it happen")
        XCTAssertNil(p.history.entries.first?.alertOutcome)
        XCTAssertNil(p.lastMatch)
    }

    func testAFailedSoundStaysVisibleUntilALaterSoundPlays() {
        let speaker = FakeSpeaker()
        speaker.answer = { name, _ in .failed("sound \"\(name)\" was not found") }
        let p = pipeline(speaker: speaker)
        p.setRules([rule("On call", app: "Teams", .sound(name: "Glas", gainDB: 0)),
                    rule("Weather", app: "Weather", nil)])

        feed(p, banner("Teams", "@you", at: 0))
        let failure = p.lastMatch
        XCTAssertEqual(failure?.alert, .failed("sound \"Glas\" was not found"))
        XCTAssertEqual(p.unresolvedAlertFailure, failure)

        feed(p, banner("Weather", "Rain", at: 10))
        XCTAssertEqual(p.lastMatch?.ruleName, "Weather")
        XCTAssertEqual(p.unresolvedAlertFailure, failure, "a quieter match afterwards must not hide the failure")

        p.setRules(p.rules)
        XCTAssertEqual(p.unresolvedAlertFailure, failure,
                       "reloading proves nothing plays — a file can exist and still not decode")

        speaker.answer = { .played(sound: $0, gainDB: $1, outputSilent: false) }
        feed(p, banner("Teams", "@you again", at: 20))
        XCTAssertNil(p.unresolvedAlertFailure, "a sound playing is the evidence that clears it")
    }

    // MARK: - What reaches the UI

    func testOnlyUserTrafficChangesWhatTheUserSees() {
        XCTAssertFalse(CapturePipeline.Outcome.selfTest.changesWhatTheUserSees)
        XCTAssertFalse(CapturePipeline.Outcome.ownNotification.changesWhatTheUserSees)
        XCTAssertTrue(CapturePipeline.Outcome.suppressedRepeat.changesWhatTheUserSees)
        XCTAssertTrue(CapturePipeline.Outcome.recorded(matchedRule: nil).changesWhatTheUserSees)
        XCTAssertTrue(CapturePipeline.Outcome.recorded(matchedRule: "X").changesWhatTheUserSees)
    }
}
