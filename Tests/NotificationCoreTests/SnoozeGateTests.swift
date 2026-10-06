import XCTest
@testable import NotificationCore

/// The snooze gate in the capture pipeline (M5 plan, Task 4, Rulings 12 and 13,
/// O8): where in `process` a held match is decided, what it leaves behind and
/// what it never touches. The gate is a closure the app gives, so most of these
/// give a recording one, which says what it was asked and when; the ones about
/// what a snooze may hold use the real `SnoozeController`, on a clock that moves
/// only when a test moves it. Nothing plays, nothing is saved and nothing waits:
/// sounds and Shortcuts are lists, and the preferences are a dictionary.
/// Fixtures are invented text (§10.1).
@MainActor
final class SnoozeGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let marker = "SignalLadder canary TEST-MARKER"
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let pagerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private var clock: ManualScheduler!
    /// Every sound a tier played, in order.
    private var played: [String] = []
    /// Every line a tier spoke.
    private var spoken: [String] = []
    /// The rules whose ladders were begun, by name.
    private var begun: [String] = []
    /// The rules the gate was asked about, by name, in the order it was asked.
    private var asked: [String] = []
    /// What a sound's tier answers; nil is "played".
    private var soundAnswer: ((String) -> AlertOutcome)?
    /// What the preferences hold, and every save in order, as the app's store would see them.
    private var preferences: [String: Any] = [:]
    private var saves: [(key: String, value: Any?)] = []
    private var shortcutsRun: [String] = []
    private var coordinator: EscalationCoordinator!

    override func setUp() {
        clock = ManualScheduler(start: t0)
        played = []
        spoken = []
        begun = []
        asked = []
        soundAnswer = nil
        preferences = [:]
        saves = []
        shortcutsRun = []
        coordinator = nil
    }

    // MARK: - Fixtures

    private func makeSnooze() -> SnoozeController {
        SnoozeController(
            scheduler: clock,
            storedUntil: preferences[SnoozeController.untilKey],
            storedHeld: preferences[SnoozeController.heldKey],
            save: { [unowned self] key, value in
                saves.append((key, value))
                preferences[key] = value
            },
            changed: {},
            announce: {})
    }

    private func play(_ name: String, _ gainDB: Double) -> AlertOutcome {
        played.append(name)
        return soundAnswer?(name) ?? .played(sound: name, gainDB: gainDB, outputSilent: false)
    }

    private func speak(_ text: String, _ speech: SpeechAction) -> AlertOutcome {
        spoken.append(text)
        return .spoke(text: text, voice: "Daniel", gainDB: speech.gainDB, outputSilent: false)
    }

    private func playAndSpeak(_ name: String, _ gainDB: Double, _ text: String, _ speech: SpeechAction) -> AlertOutcome {
        played.append(name)
        spoken.append(text)
        return .playedAndSpoke(sound: name, soundGainDB: gainDB, text: text, voice: "Daniel",
                               speechGainDB: speech.gainDB, outputSilent: false)
    }

    /// The pipeline as the app builds it, with a gate that records what it is
    /// asked and answers as `gate` says.
    private func pipeline(gate: @escaping (Rule) -> Bool) -> CapturePipeline {
        CapturePipeline(ownAppName: "SignalLadder",
                        isSelfTest: { [marker] raw, children in
                            raw.contains(marker) || children.contains { $0.contains(marker) }
                        },
                        playSound: { [unowned self] name, gain in play(name, gain) },
                        speak: { [unowned self] text, speech in speak(text, speech) },
                        playAndSpeak: { [unowned self] name, gain, text, speech in
                            playAndSpeak(name, gain, text, speech)
                        },
                        beginEscalation: { [unowned self] rule, _, _, _ in begun.append(rule.name) },
                        holdForSnooze: { [unowned self] rule in
                            asked.append(rule.name)
                            return gate(rule)
                        },
                        joinEscalation: { _, _ in nil })
    }

    /// The pipeline and the coordinator as the app wires them, on the one clock
    /// the snooze is on, so a ladder that is running can be watched while a
    /// snooze starts and ends.
    private func wired(_ rules: [Rule], snooze: SnoozeController) -> CapturePipeline {
        var p: CapturePipeline!
        coordinator = EscalationCoordinator(
            scheduler: clock,
            playSound: { [unowned self] name, gain in play(name, gain) },
            speak: { [unowned self] text, speech in speak(text, speech) },
            playAndSpeak: { [unowned self] name, gain, text, speech in playAndSpeak(name, gain, text, speech) },
            runShortcut: { [unowned self] name, _, report in
                shortcutsRun.append(name)
                report(.shortcutLaunched(name: name))
            },
            updatePanel: { _ in },
            recordSummary: { [unowned self] entry, summary in p.recordEscalation(entryID: entry, summary, at: clock.now()) },
            retired: { entry in p.escalationRetired(entryID: entry) },
            beginPowerAssertion: {}, endPowerAssertion: {}, silenceIfIdle: {})
        p = CapturePipeline(ownAppName: "SignalLadder", isSelfTest: { _, _ in false },
                            playSound: { [unowned self] name, gain in play(name, gain) },
                            speak: { [unowned self] text, speech in speak(text, speech) },
                            playAndSpeak: { [unowned self] name, gain, text, speech in
                                playAndSpeak(name, gain, text, speech)
                            },
                            beginEscalation: { [unowned self] rule, notification, entry, tier1 in
                                coordinator.begin(rule: rule, notification: notification, entryID: entry,
                                                  tier1Outcome: tier1)
                            },
                            holdForSnooze: { [unowned self] rule in
                                asked.append(rule.name)
                                return snooze.holds(rule)
                            },
                            joinEscalation: { _, _ in nil })
        p.setRules(rules)
        return p
    }

    @discardableResult
    private func feed(_ p: CapturePipeline, _ app: String, _ title: String, _ body: String = "Placeholder body text",
                      at offset: TimeInterval = 0) -> CapturePipeline.Outcome {
        p.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: "\(app), \(title), \(body)",
                             subrole: "AXNotificationCenterBanner"),
                  textChildren: [title, body])
    }

    /// A rule that sounds, may be held, and matches Teams: the one a snooze is for.
    private func pager(name: String = "On-call mentions", alert: AlertAction? = .sound(name: "Glass", gainDB: 0),
                       escalation: Escalation? = nil, quiet: Bool = true) -> Rule {
        Rule(id: pagerID, name: name, condition: .field(.app, .equals, "Microsoft Teams"),
             alert: alert, escalation: escalation, quietWhenSnoozed: quiet)
    }

    /// Tier 3 every 30 seconds, then a last sound at 2 minutes.
    private let soundLadder = Escalation(
        tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0), intervalSeconds: 30),
        tier4: FinalAlert(afterSeconds: 120, action: .alert(.sound(name: "Bell", gainDB: 0))))

    /// The same ladder with the phone page as its last step.
    private let pagingLadder = Escalation(
        tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0), intervalSeconds: 30),
        tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me")))

    // MARK: - What a held match is

    func testAHeldMatchPlaysNothingAndBeginsNoLadder() {
        let p = pipeline(gate: { _ in true })
        let speaking = SpeechAction(voiceIdentifier: daniel)
        p.setRules([pager(alert: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: speaking),
                          escalation: soundLadder)])

        XCTAssertEqual(feed(p, "Microsoft Teams", "Alex Example mentioned you"), .recorded(matchedRule: "On-call mentions"))
        XCTAssertEqual(played, [], "no sound")
        XCTAssertEqual(spoken, [], "no spoken line")
        XCTAssertEqual(begun, [], "no ladder")
    }

    func testAHeldMatchIsAnnotatedCountedAndRecordedAsSnoozed() throws {
        let p = pipeline(gate: { _ in true })
        p.setRules([pager()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")

        XCTAssertEqual(p.captureCount, 1, "it was captured, so it is counted")
        let row = try XCTUnwrap(p.history.entries.first)
        XCTAssertEqual(row.annotation, MatchAnnotation(ruleName: "On-call mentions"),
                       "and it matched, which is what the Inspector says (Ruling 13)")
        XCTAssertEqual(InspectorRowText.outcome(row), "Matched On-call mentions")
        XCTAssertEqual(row.alertOutcome, .snoozed)
        XCTAssertEqual(InspectorRowText.alert(row), "Snoozed — no alert")
    }

    func testAHeldMatchSetsTheLastMatchAndTheMenuSaysItWasHeld() {
        let p = pipeline(gate: { _ in true })
        p.setRules([pager()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 5)

        XCTAssertEqual(p.lastMatch, .init(ruleName: "On-call mentions", at: t0.addingTimeInterval(5), alert: .snoozed))
        XCTAssertEqual(AlertMenuText.lines(lastMatch: p.lastMatch, unresolvedFailure: p.unresolvedAlertFailure,
                                           anyRulePlaysSound: true, outputSilent: false, time: { _ in "10:00" }),
                       ["Last match: On-call mentions at 10:00 — \(SnoozeText.heldStem)"])
    }

    func testAHeldMatchStillNamesItsAppForTheMuteWalkthrough() {
        let p = pipeline(gate: { _ in true })
        p.setRules([pager()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        XCTAssertEqual(p.appsThatAlerted, ["Microsoft Teams"],
                       "the rule would have sounded, so the source app's own sound is still in question")
    }

    // MARK: - The failure state

    func testAHeldMatchDoesNotClearAnUnresolvedFailure() throws {
        soundAnswer = { _ in .failed("sound \"Glass\" was not found") }
        let p = pipeline(gate: { $0.quietWhenSnoozed })
        p.setRules([Rule(name: "Mail", condition: .field(.app, .equals, "Mail"), alert: .sound(name: "Glass", gainDB: 0)),
                    pager()])
        feed(p, "Mail", "Weekly report", at: 0)
        let failure = try XCTUnwrap(p.unresolvedAlertFailure, "a sound that could not play is held")

        feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 10)
        XCTAssertEqual(p.lastMatch?.alert, .snoozed)
        XCTAssertEqual(p.unresolvedAlertFailure, failure, "a match nothing sounded for is no evidence that sounds work")
    }

    func testAHeldMatchDoesNotSetAnUnresolvedFailure() {
        soundAnswer = { _ in .failed("sound \"Glass\" was not found") }
        let p = pipeline(gate: { _ in true })
        p.setRules([pager()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        XCTAssertNil(p.unresolvedAlertFailure, "it was not tried, so it did not fail")
        XCTAssertEqual(played, [])
    }

    // MARK: - Where the gate is

    func testTheGateIsAskedOnceForEachLiveMatchAfterTheRowIsAnnotatedAndBeforeAnySound() {
        var p: CapturePipeline!
        var seen: [(rule: String, annotation: MatchAnnotation?, apps: [String], soundsSoFar: Int)] = []
        p = pipeline(gate: { [unowned self] rule in
            seen.append((rule.name, p.history.entries.first?.annotation, p.appsThatAlerted, played.count))
            return false
        })
        p.setRules([pager()])

        feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 0)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.rule, "On-call mentions")
        XCTAssertEqual(seen.first?.annotation, MatchAnnotation(ruleName: "On-call mentions"), "after the row is annotated")
        XCTAssertEqual(seen.first?.apps, ["Microsoft Teams"], "after the app is noted for the walkthrough")
        XCTAssertEqual(seen.first?.soundsSoFar, 0, "before tier 1")
        XCTAssertEqual(played, ["Glass"], "and when it says no, tier 1 goes as it always did")
        XCTAssertEqual(p.lastMatch?.alert, .played(sound: "Glass", gainDB: 0, outputSilent: false))

        feed(p, "Weather", "Rain", at: 10)
        XCTAssertEqual(asked, ["On-call mentions"], "a banner that matched no rule is not asked about")
    }

    func testADedupeRepeatNeverReachesTheGate() {
        let snooze = makeSnooze()
        snooze.start(.thirtyMinutes)
        let p = pipeline(gate: { snooze.holds($0) })
        p.setRules([pager()])

        XCTAssertEqual(feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 0), .recorded(matchedRule: "On-call mentions"))
        XCTAssertEqual(feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 0.4), .suppressedRepeat)

        XCTAssertEqual(asked, ["On-call mentions"], "asked for the banner, and not again for its repeat")
        XCTAssertEqual(snooze.summary.counts, [pagerID: 1], "one banner re-firing is one match held")
    }

    func testAPreviewNeverReachesTheGate() {
        let p = pipeline(gate: { _ in true })
        feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 0)
        feed(p, "Microsoft Teams", "Priya Example mentioned you", at: 10)

        XCTAssertEqual(p.setRules([pager()]), 2, "the new rules would have matched both retained rows")
        XCTAssertEqual(p.setRules([pager(), pager(name: "Other")]), 2)
        XCTAssertEqual(asked, [], "a preview describes what would happen and holds nothing")
        XCTAssertNil(p.lastMatch)
    }

    func testTheAppsOwnSelfTestAndNotificationNeverReachTheGate() {
        // A flagged rule that matches the app by its own name, so that anything
        // that got past the checks would be matched and asked about.
        let p = pipeline(gate: { _ in true })
        p.setRules([Rule(name: "Ourselves", condition: .field(.app, .equals, "SignalLadder"),
                         alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true)])

        XCTAssertEqual(feed(p, "SignalLadder", "SignalLadder self-test", marker), .selfTest)
        XCTAssertEqual(feed(p, "SignalLadder", SelfNotification.blindTitle), .ownNotification)
        XCTAssertEqual(asked, [], "the self-test and the health alarm are never gated, so a blind app still says so in a meeting")
        XCTAssertEqual(p.captureCount, 0)
    }

    // MARK: - What a snooze may hold

    func testARuleSnoozeMayHoldSaysNoToIsNeverHeldThoughTheGateIsAskedAndASnoozeRuns() throws {
        let snooze = makeSnooze()
        snooze.start(.thirtyMinutes)
        let p = pipeline(gate: { snooze.holds($0) })

        let paging = Escalation(tier2: PanelAlert(), tier4: FinalAlert(action: .shortcut(name: "Page me")))
        let cases: [(why: String, rule: Rule, outcome: AlertOutcome)] = [
            ("no tick", pager(name: "No tick", quiet: false), .played(sound: "Glass", gainDB: 0, outputSilent: false)),
            ("a silent alert", pager(name: "Silent", alert: .silent), .silentByRule),
            ("no alert", pager(name: "No alert", alert: nil), .noAlertSet),
            ("a Shortcut as the last step", pager(name: "Pages the phone", escalation: paging),
             .played(sound: "Glass", gainDB: 0, outputSilent: false)),
        ]
        for (index, test) in cases.enumerated() {
            p.setRules([test.rule])
            feed(p, "Microsoft Teams", "Match \(index)", at: Double(index) * 10)
            XCTAssertEqual(p.history.entries.first?.alertOutcome, test.outcome, test.why)
        }
        XCTAssertEqual(asked, cases.map(\.rule.name), "the pipeline asked about every one, and the snooze said no")
        XCTAssertEqual(played, ["Glass", "Glass"], "the two that sound, did")
        XCTAssertEqual(begun, ["Pages the phone"], "and the one with a ladder began it")
        XCTAssertTrue(snooze.summary.isEmpty, "none was counted")
        XCTAssertNil(preferences[SnoozeController.heldKey], "and nothing was saved about them")

        // The same snooze, the same pipeline, and a rule that may be held.
        p.setRules([pager()])
        feed(p, "Microsoft Teams", "Match 4", at: 50)
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .snoozed)
        XCTAssertEqual(snooze.summary.counts, [pagerID: 1])
        XCTAssertEqual(played, ["Glass", "Glass"])
    }

    // MARK: - A ladder already running

    func testASnoozeStartedMidLadderLeavesThatLadderRunningAndItsTier4StillFires() throws {
        let snooze = makeSnooze()
        let p = wired([pager(escalation: soundLadder)], snooze: snooze)

        feed(p, "Microsoft Teams", "First", at: 0)
        XCTAssertEqual(played, ["Glass"])
        clock.advance(by: 30)
        XCTAssertEqual(played, ["Glass", "Hero"])

        snooze.start(.thirtyMinutes)
        clock.advance(by: 30)
        XCTAssertEqual(played, ["Glass", "Hero", "Hero"], "the ladder goes on repeating through the snooze")

        // A match that begins during the snooze is held, and starts no second ladder.
        feed(p, "Microsoft Teams", "Second", at: 60)
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .snoozed)
        XCTAssertEqual(played, ["Glass", "Hero", "Hero"], "nothing sounds for it")
        XCTAssertEqual(snooze.summary.counts, [pagerID: 1])

        clock.advance(by: 60)
        XCTAssertTrue(snooze.isActive, "still snoozed")
        XCTAssertEqual(played.filter { $0 == "Hero" }.count, 4, "the repeats did not stop")
        XCTAssertEqual(played.filter { $0 == "Bell" }.count, 1, "and tier 4 fired, in the snooze")
        XCTAssertEqual(played.filter { $0 == "Glass" }.count, 1, "the held match's own first alert never did")

        let first = try XCTUnwrap(p.history.entries.last)
        XCTAssertEqual(first.escalation?.repeatCount, 4)
        XCTAssertEqual(first.escalation?.final, .alerted(.played(sound: "Bell", gainDB: 0, outputSilent: false)))
        XCTAssertNil(p.history.entries.first?.escalation, "the held row has no ladder")
    }

    func testARuleWhoseLastStepIsAShortcutStillSoundsClimbsAndPagesDuringASnooze() throws {
        let snooze = makeSnooze()
        snooze.start(.thirtyMinutes)
        let p = wired([pager(escalation: pagingLadder)], snooze: snooze)

        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        XCTAssertEqual(p.history.entries.first?.alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false))
        clock.advance(by: 120)
        XCTAssertEqual(played.filter { $0 == "Hero" }.count, 4, "it climbs")
        XCTAssertEqual(shortcutsRun, ["Page me"], "and the phone page goes while the Mac is snoozed")
        XCTAssertTrue(snooze.isActive)
        XCTAssertTrue(snooze.summary.isEmpty, "and it was never counted as held")
    }

    // MARK: - What a notification said

    func testWithASnoozeActiveANotificationsTextReachesNeitherWhatIsSavedNorTheSummaryLineNorTheMenu() throws {
        let title = "Zyxwv-4417 quartzite sundial"
        let body = "ledger-9f2c obsidian marmalade"
        let fragments = ["Zyxwv-4417", "Zyxwv", "quartzite", "sundial", "ledger-9f2c", "ledger", "obsidian", "marmalade"]
        // A rule that speaks what it read, and that was written from some of the
        // same words, as a real one is.
        let rule = Rule(id: pagerID, name: "On-call mentions", condition: .field(.body, .contains, "ledger-9f2c"),
                        alert: .soundAndSpeak(soundName: "Glass", soundGainDB: 0,
                                              speech: SpeechAction(voiceIdentifier: daniel, template: "{title}. {body}")),
                        quietWhenSnoozed: true)
        let snooze = makeSnooze()
        let p = pipeline(gate: { snooze.holds($0) })
        p.setRules([rule])

        // Without a snooze the words do flow in, to the row and to what was said:
        // so that what follows is a test of a leak, and not of an empty pipe.
        feed(p, "Microsoft Teams", title, body, at: 0)
        let heard = try XCTUnwrap(p.history.entries.first?.alertOutcome?.spokenText)
        for fragment in fragments.prefix(3) { XCTAssertTrue(heard.contains(fragment), "\(fragment) in \(heard)") }
        XCTAssertEqual(saves.count, 0)

        snooze.start(.thirtyMinutes)
        feed(p, "Microsoft Teams", title, body, at: 10)
        let row = try XCTUnwrap(p.history.entries.first)
        XCTAssertEqual(row.alertOutcome, .snoozed)
        XCTAssertEqual(spoken.count, 1, "nothing was said for the held one")
        XCTAssertEqual(snooze.summary.counts, [pagerID: 1])

        let held = try XCTUnwrap(saves.compactMap { $0.key == SnoozeController.heldKey ? $0.value : nil }.last)
        let line = try XCTUnwrap(SnoozeText.summaryLine(snooze.summary, names: SnoozeText.names(of: p.rules)))
        XCTAssertEqual(line, "\(SnoozeText.heldOneMatchStem): On-call mentions ×1")
        let menu = AlertMenuText.lines(lastMatch: p.lastMatch, unresolvedFailure: p.unresolvedAlertFailure,
                                       anyRulePlaysSound: true, outputSilent: false, time: { _ in "10:00" })
        XCTAssertEqual(menu, ["Last match: On-call mentions at 10:00 — \(SnoozeText.heldStem)"])

        var everythingSaved = ""
        for save in saves {
            everythingSaved += "\(save.key) \(String(describing: save.value)) "
            guard let value = save.value else { continue }
            for string in strings(in: value) {
                XCTAssertTrue(UUID(uuidString: string) != nil || ["counts", "since", "unannounced", "unreadable"].contains(string),
                              "\(save.key) holds a string that is neither a field nor a rule's id: \(string)")
            }
        }
        let shown: [String] = [line, menu.joined(), InspectorRowText.alert(row) ?? "", InspectorRowText.outcome(row),
                               String(describing: held), everythingSaved]
        for fragment in fragments {
            for text in shown {
                XCTAssertFalse(text.contains(fragment), "\(fragment) reached: \(text)")
            }
        }
    }

    /// Every string in a property list, keys included.
    private func strings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { [$0.key] + strings(in: $0.value) }
        }
        if let array = value as? [Any] { return array.flatMap(strings(in:)) }
        return []
    }
}
