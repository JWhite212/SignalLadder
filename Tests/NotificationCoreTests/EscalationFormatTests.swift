import XCTest
@testable import NotificationCore

/// The escalation ladder in the rule format (M4 Task 1). Fixtures are invented
/// text, never captured content (§10.1).
final class EscalationFormatTests: XCTestCase {
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#

    private func file(version: Int = 4, _ rules: String) -> Data {
        Data("{\"version\": \(version), \"rules\": [\(rules)]}".utf8)
    }

    /// One rule, silent on tier 1 unless told otherwise, with this ladder.
    private func escalating(_ escalation: String, alert: String = #""silent""#, version: Int = 4) -> Data {
        file(version: version, #"{"name": "Pager", \#(teams), "alert": \#(alert), "escalation": \#(escalation)}"#)
    }

    private func decodeOne(_ data: Data) throws -> (rule: Rule?, reason: String) {
        let (rules, problems) = try RuleSetCodec.decode(data)
        return (rules.first, problems.first?.reason ?? "")
    }

    private func rule(alert: AlertAction? = .silent, _ escalation: Escalation?) -> Rule {
        Rule(name: "Pager", condition: .field(.app, .equals, "Microsoft Teams"), alert: alert, escalation: escalation)
    }

    private let hero = AlertAction.sound(name: "Hero", gainDB: 0)

    // MARK: - The shape

    func testTheWorkedExampleDecodes() throws {
        let (rule, reason) = try decodeOne(escalating(#"""
            {"tier2": {"delaySeconds": 10},
             "tier3": {"action": {"sound": "Hero", "gainDB": 0}, "intervalSeconds": 30, "maxRepeats": 20, "maxDurationSeconds": 600},
             "tier4": {"afterSeconds": 120, "shortcut": "Page the on-call phone"}}
            """#))
        XCTAssertEqual(reason, "")
        XCTAssertEqual(rule?.escalation, Escalation(
            tier2: PanelAlert(delaySeconds: 10),
            tier3: RepeatAlert(action: hero, intervalSeconds: 30, maxRepeats: 20, maxDurationSeconds: 600),
            tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page the on-call phone"))))
    }

    func testEveryLadderShapeRoundTrips() throws {
        let speech = SpeechAction(voiceIdentifier: daniel, template: "{app}")
        let rules = [
            rule(Escalation(tier2: PanelAlert(delaySeconds: 5))),
            rule(alert: hero, Escalation(tier3: RepeatAlert(action: .speak(speech), intervalSeconds: 45,
                                                            maxRepeats: nil, maxDurationSeconds: nil))),
            rule(Escalation(tier3: RepeatAlert(action: hero, maxRepeats: 3, maxDurationSeconds: nil))),
            rule(Escalation(tier3: RepeatAlert(action: hero, maxRepeats: nil, maxDurationSeconds: 90))),
            rule(Escalation(tier4: FinalAlert(afterSeconds: 60, action: .alert(.soundAndSpeak(
                soundName: "Glass", soundGainDB: 6, speech: speech))))),
            rule(Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: hero),
                            tier4: FinalAlert(action: .shortcut(name: "Page me")))),
        ]
        let (decoded, problems) = try RuleSetCodec.decode(try RuleSetCodec.encode(rules))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(decoded, rules)
    }

    func testAWrittenLadderSpellsOutEveryKeyAndNullForNoLimit() throws {
        // A file the app writes never leans on a default, so it cannot change
        // meaning when read back, even by a build whose defaults differ.
        let text = String(decoding: try RuleSetCodec.encode([rule(Escalation(
            tier2: PanelAlert(), tier3: RepeatAlert(action: hero, maxRepeats: nil, maxDurationSeconds: nil),
            tier4: FinalAlert(action: .shortcut(name: "Page me"))))]), as: UTF8.self)
        for expected in [#""version" : 4"#, #""delaySeconds" : 10"#, #""intervalSeconds" : 30"#,
                         #""maxRepeats" : null"#, #""maxDurationSeconds" : null"#, #""afterSeconds" : 120"#,
                         #""shortcut" : "Page me""#] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in \(text)")
        }
    }

    func testAnOmittedCapIsTheDefaultCapNeverNoCap() throws {
        // A hand-written repeat that forgot its limits must stop (§5.12).
        let (rule, reason) = try decodeOne(escalating(#"{"tier3": {"action": {"sound": "Hero"}}}"#))
        XCTAssertEqual(reason, "")
        XCTAssertEqual(rule?.escalation?.tier3, RepeatAlert(action: hero, intervalSeconds: 30,
                                                            maxRepeats: 20, maxDurationSeconds: 600))
    }

    func testNullIsNoLimitAndOnlyForThatCap() throws {
        let (rule, reason) = try decodeOne(escalating(
            #"{"tier3": {"action": {"sound": "Hero"}, "maxRepeats": null, "maxDurationSeconds": 900}}"#))
        XCTAssertEqual(reason, "")
        XCTAssertNil(rule?.escalation?.tier3?.maxRepeats)
        XCTAssertEqual(rule?.escalation?.tier3?.maxDurationSeconds, 900)
    }

    func testOmittedTimingsAreTheirDefaults() throws {
        let (rule, reason) = try decodeOne(escalating(#"{"tier2": {}, "tier4": {"shortcut": "Page me"}}"#))
        XCTAssertEqual(reason, "")
        XCTAssertEqual(rule?.escalation?.tier2?.delaySeconds, 10)
        XCTAssertEqual(rule?.escalation?.tier4?.afterSeconds, 120)
    }

    func testARepeatCountMustBeAWholeNumberAndSaysSo() throws {
        // Decoded straight into an Int, 2.5 failed with an error naming
        // neither the key nor the value.
        let (rule, reason) = try decodeOne(escalating(#"{"tier3": {"action": {"sound": "Hero"}, "maxRepeats": 2.5}}"#))
        XCTAssertNil(rule)
        XCTAssertTrue(reason.contains("maxRepeats must be a whole number, or null for no limit — found 2.5"), reason)
        XCTAssertTrue(reason.contains("tier3"), reason)
        let whole = try decodeOne(escalating(#"{"tier3": {"action": {"sound": "Hero"}, "maxRepeats": 20.0}}"#))
        XCTAssertEqual(whole.rule?.escalation?.tier3?.maxRepeats, 20)
    }

    func testARuleSetWithNoLadderWritesNoEscalationKey() throws {
        // A file below version 4 must stay readable by the builds that wrote it.
        for rules in [[rule(alert: nil, nil)], [rule(alert: hero, nil)],
                      [rule(alert: .speak(SpeechAction(voiceIdentifier: daniel)), nil)]] {
            let text = String(decoding: try RuleSetCodec.encode(rules), as: UTF8.self)
            XCTAssertFalse(text.contains("escalation"), text)
        }
    }

    func testARepeatNeedsAnAction() throws {
        let (rule, reason) = try decodeOne(escalating(#"{"tier3": {"intervalSeconds": 30}}"#))
        XCTAssertNil(rule)
        XCTAssertTrue(reason.contains("missing \"action\""), reason)
    }

    func testAFinalAlertIsAnActionOrAShortcutNeverBothOrNeither() throws {
        let both = try decodeOne(escalating(#"{"tier4": {"action": {"sound": "Hero"}, "shortcut": "Page me"}}"#))
        XCTAssertNil(both.rule)
        XCTAssertTrue(both.reason.contains("both \"action\" and \"shortcut\""), both.reason)

        let neither = try decodeOne(escalating(#"{"tier4": {"afterSeconds": 60}}"#))
        XCTAssertNil(neither.rule)
        XCTAssertTrue(neither.reason.contains("needs \"action\" or \"shortcut\""), neither.reason)
    }

    func testAFinalAlertIsShapedLikeTier1s() throws {
        let (rule, reason) = try decodeOne(escalating(#"{"tier4": {"action": {"speak": {"voice": "\#(daniel)"}}}}"#))
        XCTAssertEqual(reason, "")
        XCTAssertEqual(rule?.escalation?.tier4?.action, .alert(.speak(SpeechAction(voiceIdentifier: daniel))))
    }

    // MARK: - Unknown keys

    func testAnUnknownKeyIsRejectedByNameAtEveryLevel() throws {
        let cases: [(escalation: String, key: String, level: String)] = [
            (#"{"tier5": {}}"#, "tier5", #""escalation""#),
            (#"{"tier2": {"delay": 10}}"#, "delay", #""tier2""#),
            (#"{"tier3": {"action": {"sound": "Hero"}, "interval": 30}}"#, "interval", #""tier3""#),
            (#"{"tier4": {"shortcut": "Page me", "after": 60}}"#, "after", #""tier4""#),
            (#"{"tier4": {"shortcut": "Page me", "delaySeconds": 60}}"#, "delaySeconds", #""tier4""#),
        ]
        for (escalation, key, level) in cases {
            let (rule, reason) = try decodeOne(escalating(escalation))
            XCTAssertNil(rule, escalation)
            XCTAssertTrue(reason.contains("unknown key \"\(key)\" in \(level)"), reason)
        }
    }

    func testTier2sDelayIsNotCalledAfterSeconds() throws {
        // The two are named apart on purpose, so one written in the wrong tier
        // is caught; an early draft of the plan made exactly this mistake.
        let (rule, reason) = try decodeOne(escalating(#"{"tier2": {"afterSeconds": 10}}"#))
        XCTAssertNil(rule)
        XCTAssertTrue(reason.contains("unknown key \"afterSeconds\" in \"tier2\""), reason)
    }

    func testAMisspeltEscalationKeyIsRejectedNotIgnored() throws {
        // Ignored, it would leave a rule that alerts once while its author
        // believes it climbs a ladder.
        let (rule, reason) = try decodeOne(file(#"{"name": "Pager", \#(teams), "alert": "silent", "escalaton": {"tier2": {}}}"#))
        XCTAssertNil(rule)
        XCTAssertTrue(reason.contains("unknown key \"escalaton\""), reason)
    }

    // MARK: - Versions

    func testALadderInAVersion3FileIsRefusedNamingTheFix() throws {
        let (rule, reason) = try decodeOne(escalating(#"{"tier2": {}}"#, version: 3))
        XCTAssertNil(rule)
        XCTAssertTrue(reason.contains("escalation needs \"version\": 4"), reason)
    }

    func testAVersion1FileNamesOnlyTheVersionTheRuleNeeds() throws {
        let (_, reason) = try decodeOne(escalating(#"{"tier2": {}}"#, alert: #"{"speak": {"voice": "\#(daniel)"}}"#, version: 1))
        XCTAssertTrue(reason.contains("\"version\": 4"), reason)
        XCTAssertFalse(reason.contains("\"version\": 3") || reason.contains("\"version\": 2"),
                       "one version message, the right one: \(reason)")
    }

    func testFilesWithALadderAreWrittenAtVersion4AndOthersAsBefore() {
        let speech = rule(alert: .speak(SpeechAction(voiceIdentifier: daniel)), nil)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(Escalation(tier2: PanelAlert()))]), 4)
        XCTAssertEqual(RuleSetCodec.version(for: [speech, rule(Escalation(tier2: PanelAlert()))]), 4)
        XCTAssertEqual(RuleSetCodec.version(for: [speech]), 3)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(alert: hero, nil)]), 2)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(alert: nil, nil)]), 1)
    }

    func testAVersion4FileIsUnderstoodAndVersion5IsNot() throws {
        XCTAssertEqual(RuleSetCodec.currentVersion, 4)
        XCTAssertNoThrow(try RuleSetCodec.decode(file(version: 4, #"{"name": "a", \#(teams)}"#)))
        XCTAssertThrowsError(try RuleSetCodec.decode(file(version: 5, #"{"name": "a", \#(teams)}"#))) {
            XCTAssertEqual($0 as? RuleSetCodec.FileError, .unsupportedVersion(5))
        }
    }

    // MARK: - Ladders that decode but cannot mean what was intended

    func testALadderWithNoAlertIsReported() {
        // Nothing would mark the match until tier 2's panel (ruling 6).
        XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: nil, Escalation(tier2: PanelAlert()))),
                       ["it has an escalation but no alert — give it at least a silent alert, or remove the escalation"])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: .silent, Escalation(tier2: PanelAlert()))), [])
    }

    func testALadderWithNoTiersIsReported() throws {
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation())),
                       ["its escalation has no tiers, so it would start and never climb — add \"tier2\", \"tier3\" or \"tier4\", or remove it"])
        let (rule, reason) = try decodeOne(escalating("{}"))
        XCTAssertNil(rule)
        XCTAssertTrue(reason.contains("no tiers"), reason)
    }

    func testEveryDelayAndIntervalMustBeMoreThanZero() {
        let problems = RuleSetCodec.problems(in: rule(Escalation(
            tier2: PanelAlert(delaySeconds: 0),
            tier3: RepeatAlert(action: hero, intervalSeconds: -1),
            tier4: FinalAlert(afterSeconds: 0, action: .shortcut(name: "Page me")))))
        XCTAssertEqual(problems, ["delaySeconds in \"tier2\" must be more than 0, found 0",
                                  "intervalSeconds in \"tier3\" must be more than 0, found -1",
                                  "afterSeconds in \"tier4\" must be more than 0, found 0"])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(
            tier2: PanelAlert(delaySeconds: 0.5), tier3: RepeatAlert(action: hero, intervalSeconds: 1),
            tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: "Page me"))))), [])
    }

    func testACapThatIsSetMustAllowSomething() {
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(tier3: RepeatAlert(action: hero, maxRepeats: 0,
                                                                                   maxDurationSeconds: 0)))),
                       ["maxRepeats in \"tier3\" must be at least 1, found 0 — use null for no limit",
                        "maxDurationSeconds in \"tier3\" must be more than 0, found 0 — use null for no limit"])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(tier3: RepeatAlert(action: hero, maxRepeats: 1,
                                                                                   maxDurationSeconds: nil)))), [])
    }

    func testANegativeCapIsRefusedLikeZero() {
        // -1 is the likeliest way to try to write "no limit"; the message
        // says how to write it instead.
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(tier3: RepeatAlert(action: hero, maxRepeats: -1,
                                                                                   maxDurationSeconds: -1)))),
                       ["maxRepeats in \"tier3\" must be at least 1, found -1 — use null for no limit",
                        "maxDurationSeconds in \"tier3\" must be more than 0, found -1 — use null for no limit"])
    }

    func testASilentRepeatOrFinalAlertIsReported() {
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(tier3: RepeatAlert(action: .silent)))),
                       ["its repeat is silent, so it would repeat nothing — give it a sound or speech, or remove \"tier3\""])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(tier4: FinalAlert(action: .alert(.silent))))),
                       ["its final alert is silent, so it would do nothing — give it a sound, speech or a Shortcut, or remove \"tier4\""])
    }

    func testABlankShortcutNameIsAProblemEvenWhenShortcutsCannotBeListed() {
        // Nothing can be run by no name. With no list to check against, any
        // other name is found out only by running it (ruling 11).
        for blank in ["", "   "] {
            XCTAssertEqual(RuleSetCodec.problems(in: rule(Escalation(tier4: FinalAlert(action: .shortcut(name: blank))))),
                           ["its final alert names no Shortcut"])
        }
        let (rules, status) = RuleStoreStatus.load(
            escalating(#"{"tier4": {"shortcut": "Surely no Shortcut is called this ✓"}}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel], availableShortcuts: nil)
        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(status.isProblem, "\(status.detail)")
    }

    // MARK: - A Shortcut that is not there

    private func loadShortcut(_ name: String, listed: Set<String>?) -> (rules: [Rule], status: RuleStoreStatus) {
        RuleStoreStatus.load(escalating(#"{"tier4": {"shortcut": "\#(name)"}}"#),
                             availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel],
                             availableShortcuts: listed.map { names in { names } })
    }

    func testAShortcutThatIsNotListedIsReportedAtLoad() {
        // Found now, not at the incident, when a Shortcut that pages a phone
        // is the one thing that must work.
        let (rules, status) = loadShortcut("Page the on-call phone", listed: ["Page on-call", "Log it"])
        XCTAssertEqual(rules, [])
        let detail = status.detail.first ?? ""
        XCTAssertTrue(detail.contains("its final alert's Shortcut \"Page the on-call phone\" was not found in the Shortcuts app"),
                      detail)
    }

    func testAListedShortcutLoads() {
        let (rules, status) = loadShortcut("Page on-call", listed: ["Page on-call", "Log it"])
        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(status.isProblem, "\(status.detail)")
    }

    func testAShortcutNameMustMatchExactly() {
        // Whether running forgives a difference in case was not measured, so
        // the check does not: refused now beats failing at the incident.
        for near in ["page on-call", "Page on-call ", "Page  on-call"] {
            let (rules, status) = loadShortcut(near, listed: ["Page on-call"])
            XCTAssertEqual(rules, [], near)
            XCTAssertTrue(status.detail.first?.contains("must match one there exactly") ?? false, "\(status.detail)")
        }
    }

    func testShortcutsThatCannotBeListedAreNotChecked() {
        let (rules, status) = loadShortcut("Page on-call", listed: nil)
        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(status.isProblem)
    }

    func testABlankShortcutNameIsReportedOnceNotAlsoAsMissing() {
        let (_, status) = loadShortcut("  ", listed: ["Page on-call"])
        let detail = status.detail.first ?? ""
        XCTAssertTrue(detail.contains("its final alert names no Shortcut"), detail)
        XCTAssertFalse(detail.contains("was not found"), detail)
    }

    func testShortcutsAreListedOnlyWhenARuleNamesOneAndOnlyOncePerLoad() {
        // A Mac whose rules name no Shortcut never has them listed at all.
        var listings = 0
        let list: () -> Set<String>? = { listings += 1; return ["Page on-call"] }
        let plain = file(#"{"name": "a", \#(teams), "alert": {"sound": "Glass"}}, {"name": "b", \#(teams), "alert": "silent", "escalation": {"tier3": {"action": {"sound": "Glass"}}, "tier4": {"action": {"sound": "Glass"}}}}"#)
        XCTAssertEqual(RuleStoreStatus.load(plain, availableSounds: ["Glass"], unplayable: nil, availableVoices: nil,
                                            availableShortcuts: list).rules.count, 2)
        XCTAssertEqual(listings, 0)

        let three = (1...3).map { #"{"name": "r\#($0)", \#(teams), "alert": "silent", "escalation": {"tier4": {"shortcut": "Page on-call"}}}"# }
        XCTAssertEqual(RuleStoreStatus.load(file(three.joined(separator: ", ")), availableSounds: nil, unplayable: nil,
                                            availableVoices: nil, availableShortcuts: list).rules.count, 3)
        XCTAssertEqual(listings, 1)
    }

    func testAnEmptyListRefusesEveryShortcut() {
        // No Shortcuts at all is a real answer, not a failure to list.
        let (rules, status) = loadShortcut("Page on-call", listed: [])
        XCTAssertEqual(rules, [])
        XCTAssertTrue(status.detail.first?.contains("was not found in the Shortcuts app") ?? false, "\(status.detail)")
    }

    func testAListThatCannotBeReadSkipsTheCheck() {
        let (rules, status) = RuleStoreStatus.load(escalating(#"{"tier4": {"shortcut": "Page on-call"}}"#),
                                                   availableSounds: nil, unplayable: nil, availableVoices: nil,
                                                   availableShortcuts: { nil })
        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(status.isProblem)
    }

    func testTheEditorSeesAMissingShortcutToo() {
        let check = RuleSetCodec.SoundCheck(available: nil, unplayable: nil, voices: nil, shortcuts: { ["Log it"] })
        XCTAssertEqual(RulesDocument.problems(in: rule(Escalation(tier4: FinalAlert(action: .shortcut(name: "Page me")))),
                                              sounds: check),
                       ["its final alert's Shortcut \"Page me\" was not found in the Shortcuts app — the name must match one there exactly, including capitals, spaces and punctuation"])
    }

    // MARK: - A later tier's sound and speech

    func testALaterTiersSoundIsCheckedAtLoadAndNamesItsTier() {
        let (rules, status) = RuleStoreStatus.load(
            escalating(#"{"tier3": {"action": {"sound": "Hreo"}}, "tier4": {"action": {"sound": "Glas"}}}"#,
                       alert: #"{"sound": "Hreo"}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel], availableShortcuts: nil)
        XCTAssertEqual(rules, [])
        let detail = status.detail.first ?? ""
        // One sentence per tier, each telling which, never the same one twice.
        XCTAssertTrue(detail.contains("): sound \"Hreo\" was not found"), detail)
        XCTAssertTrue(detail.contains("its repeat's sound \"Hreo\" was not found"), detail)
        XCTAssertTrue(detail.contains("its final alert's sound \"Glas\" was not found"), detail)
    }

    func testALaterTiersVoiceIsCheckedAtLoadAndNamesItsTier() {
        let (rules, status) = RuleStoreStatus.load(
            escalating(#"{"tier3": {"action": {"speak": {"voice": "com.example.gone"}}}}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel], availableShortcuts: nil)
        XCTAssertEqual(rules, [])
        XCTAssertTrue(status.detail.first?.contains("its repeat's voice \"com.example.gone\" is not installed") ?? false,
                      "\(status.detail)")

        let final = RuleStoreStatus.load(
            escalating(#"{"tier4": {"action": {"speak": {"voice": "com.example.gone"}}}}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel], availableShortcuts: nil)
        XCTAssertEqual(final.rules, [])
        XCTAssertTrue(final.status.detail.first?.contains("its final alert's voice \"com.example.gone\" is not installed") ?? false,
                      "\(final.status.detail)")
    }

    func testEveryLaterTierSpeechProblemNamesItsTier() {
        let speech = SpeechAction(voiceIdentifier: " ", template: "{sender} at {app", pitchMultiplier: 3, gainDB: 99)
        let problems = RuleSetCodec.problems(in: rule(Escalation(
            tier3: RepeatAlert(action: .speak(speech)),
            tier4: FinalAlert(action: .alert(.soundAndSpeak(soundName: " ", soundGainDB: 0, speech: speech))))))
        XCTAssertEqual(problems, [
            "its repeat's speech names no voice",
            "its repeat's spoken template has a \"{\" that is never closed",
            "its repeat's spoken template has {sender}, which is not a placeholder — use {app}, {title} or {body}",
            "its repeat's speech pitch 3 is outside 0.5…2",
            "its repeat's speech gainDB 99 is outside -40…+12 dB",
            "its final alert names no sound",
            "its final alert's speech names no voice",
            "its final alert's spoken template has a \"{\" that is never closed",
            "its final alert's spoken template has {sender}, which is not a placeholder — use {app}, {title} or {body}",
            "its final alert's speech pitch 3 is outside 0.5…2",
            "its final alert's speech gainDB 99 is outside -40…+12 dB",
        ])
    }

    func testALaterTiersSoundAndSpeechProblemsNameTheirTier() {
        let problems = RuleSetCodec.problems(in: rule(Escalation(
            tier3: RepeatAlert(action: .sound(name: " ", gainDB: 40)),
            tier4: FinalAlert(action: .alert(.speak(SpeechAction(voiceIdentifier: " ", template: "", rate: 2)))))))
        XCTAssertEqual(problems, ["its repeat names no sound",
                                  "its repeat's gainDB 40 is outside -40…+12 dB",
                                  "its final alert's speech names no voice",
                                  "its final alert's spoken template is empty",
                                  "its final alert's speech rate 2 is outside 0…1"])
    }

    func testTier1sWordsAreUnchanged() {
        // Every message tier 1 had before tiers existed reads as it did.
        XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: .soundAndSpeak(soundName: " ", soundGainDB: 40,
                                                                           speech: SpeechAction(voiceIdentifier: " ")), nil)),
                       ["its alert names no sound", "gainDB 40 is outside -40…+12 dB", "its spoken alert names no voice"])
    }

    func testTheEditorSeesTheSameLadderProblemsWithoutTheVersionGate() {
        // The editor writes whatever version the rules need, so it never
        // reports one; everything else it reports as a load would.
        let problems = RulesDocument.problems(in: rule(alert: nil, Escalation(tier3: RepeatAlert(action: .silent))),
                                              sounds: .none)
        XCTAssertEqual(problems, ["it has an escalation but no alert — give it at least a silent alert, or remove the escalation",
                                  "its repeat is silent, so it would repeat nothing — give it a sound or speech, or remove \"tier3\""])
    }

    // MARK: - What alerts aloud

    func testALaterTierThatSoundsOrSpeaksAlertsAloud() {
        // A silent tier 1 with a sounding repeat still makes a noise, so the
        // mute walkthrough and the muted-output warning must count it.
        XCTAssertTrue(rule(Escalation(tier3: RepeatAlert(action: hero))).alertsAloud)
        XCTAssertTrue(rule(Escalation(tier4: FinalAlert(action: .alert(.speak(SpeechAction(voiceIdentifier: daniel)))))).alertsAloud)
        XCTAssertFalse(rule(Escalation(tier2: PanelAlert())).alertsAloud, "a panel makes no sound")
        XCTAssertFalse(rule(Escalation(tier4: FinalAlert(action: .shortcut(name: "Page me")))).alertsAloud,
                       "a Shortcut is not a sound on this Mac")
        var off = rule(Escalation(tier3: RepeatAlert(action: hero)))
        off.isEnabled = false
        XCTAssertFalse(off.alertsAloud)
    }

    func testAShortcutIsNotAmongALaddersAlerts() {
        let escalation = Escalation(tier3: RepeatAlert(action: hero), tier4: FinalAlert(action: .shortcut(name: "Page me")))
        XCTAssertEqual(escalation.alerts.map(\.tier), [3])
        XCTAssertEqual(escalation.alerts.map(\.action), [hero])
    }
}
