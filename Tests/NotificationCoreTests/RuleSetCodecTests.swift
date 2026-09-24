import XCTest
@testable import NotificationCore

final class RuleSetCodecTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - The hand-written shape

    func testAHandWrittenFileDecodes() throws {
        let (rules, problems) = try RuleSetCodec.decode(data("""
        {
          "version": 1,
          "rules": [
            {
              "name": "Prod channels",
              "condition": {
                "or": [
                  {"field": "title", "op": "matches", "value": "#prod-*"},
                  {"field": "title", "op": "matches", "value": "#incident-*"}
                ]
              }
            }
          ]
        }
        """))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.map(\.name), ["Prod channels"])
        XCTAssertEqual(rules.first?.condition, .or([.field(.title, .matches, "#prod-*"),
                                                     .field(.title, .matches, "#incident-*")]))
    }

    func testOmittedEnabledMeansOn() throws {
        // A rule someone took the trouble to write, silently not running
        // because a key was left out, is the failure this app exists to prevent.
        let (rules, _) = try RuleSetCodec.decode(data("""
        {"version": 1, "rules": [{"name": "x", "condition": {"field": "app", "op": "equals", "value": "Weather"}}]}
        """))
        XCTAssertEqual(rules.first?.isEnabled, true)
    }

    func testOmittedIdIsMinted() throws {
        let (rules, _) = try RuleSetCodec.decode(data("""
        {"version": 1, "rules": [{"name": "x", "condition": {"field": "app", "op": "equals", "value": "Weather"}}]}
        """))
        XCTAssertNotNil(rules.first?.id)
    }

    func testEncodingIsTheReadableShapeNotSynthesisedPositionalKeys() throws {
        let rule = Rule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        name: "Prod", condition: .not(.field(.title, .contains, "resolved")))
        let text = String(decoding: try RuleSetCodec.encode([rule]), as: UTF8.self)
        XCTAssertTrue(text.contains(#""op" : "contains""#), text)
        XCTAssertTrue(text.contains(#""not" : {"#), text)
        XCTAssertFalse(text.contains("_0"), "synthesised Codable leaked through: \(text)")
    }

    func testEncodeThenDecodeIsLossless() throws {
        let rules = [
            Rule(name: "A", condition: .and([.field(.app, .equals, "Microsoft Teams"),
                                             .or([.field(.raw, .contains, "@Jamie"),
                                                  .not(.field(.subtitle, .equals, ""))])])),
            Rule(name: "B", condition: .field(.subrole, .matches, "*Alert"), isEnabled: false),
        ]
        let (decoded, problems) = try RuleSetCodec.decode(try RuleSetCodec.encode(rules))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(decoded, rules)
    }

    // MARK: - One bad rule must not silence the rest, nor hide itself

    func testAMalformedRuleIsReportedAndTheOthersStillLoad() throws {
        let (rules, problems) = try RuleSetCodec.decode(data("""
        {"version": 1, "rules": [
          {"name": "Good", "condition": {"field": "app", "op": "equals", "value": "Weather"}},
          {"name": "Typo", "condition": {"field": "app", "op": "startsWith", "value": "Micro"}},
          {"name": "Also good", "condition": {"field": "title", "op": "contains", "value": "#prod"}}
        ]}
        """))
        XCTAssertEqual(rules.map(\.name), ["Good", "Also good"])
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems.first?.index, 1)
        XCTAssertEqual(problems.first?.name, "Typo", "naming the broken rule is most of what makes the report useful")
    }

    func testAProblemSaysWhereInTheFileItWent() throws {
        let (_, problems) = try RuleSetCodec.decode(data("""
        {"version": 1, "rules": [
          {"name": "Missing op", "condition": {"and": [{"field": "app", "value": "Weather"}]}}
        ]}
        """))
        let reason = try XCTUnwrap(problems.first?.reason)
        XCTAssertTrue(reason.contains("\"op\""), reason)
        XCTAssertTrue(reason.contains("condition.and[0]"), reason)
    }

    func testAConditionWithTwoShapesIsRejectedAsAmbiguous() throws {
        let (_, problems) = try RuleSetCodec.decode(data("""
        {"version": 1, "rules": [
          {"name": "Both", "condition": {"field": "app", "op": "equals", "value": "x", "not": {"field": "app", "op": "equals", "value": "y"}}}
        ]}
        """))
        XCTAssertTrue(problems.first?.reason.contains("exactly one") ?? false, "\(problems)")
    }

    // MARK: - Rules that decode but cannot mean what was intended

    func testEmptyGroupsAreRejectedBecauseTheyMatchEverythingOrNothing() throws {
        let (rules, problems) = try RuleSetCodec.decode(data("""
        {"version": 1, "rules": [
          {"name": "Firehose", "condition": {"and": []}},
          {"name": "Never", "condition": {"or": []}}
        ]}
        """))
        XCTAssertEqual(rules, [])
        XCTAssertEqual(problems.map(\.name), ["Firehose", "Never"])
    }

    func testEmptyContainsOrMatchesIsRejectedButEmptyEqualsIsAllowed() {
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "x", condition: .field(.body, .contains, ""))).isEmpty)
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "x", condition: .field(.body, .matches, ""))).isEmpty)
        XCTAssertEqual(RuleSetCodec.problems(in: Rule(name: "x", condition: .field(.subtitle, .equals, ""))), [],
                       "equals \"\" means \"has no subtitle\" — a real, useful rule")
    }

    func testAnUnnamedRuleIsRejected() {
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "  ", condition: .field(.app, .equals, "x"))).isEmpty)
    }

    func testABlankNameIsOmittedFromTheReportRatherThanQuoted() {
        let problem = RuleSetCodec.Problem(index: 0, name: "  ", reason: "it has no name")
        XCTAssertEqual(problem.description, "Rule 1: it has no name")
    }

    func testAProblemBuriedInANestedGroupIsFound() {
        let buried = Rule(name: "Deep", condition: .and([.field(.app, .equals, "x"), .not(.or([]))]))
        XCTAssertFalse(RuleSetCodec.problems(in: buried).isEmpty)
    }

    // MARK: - Files that load nothing

    func testNotJSONIsUnreadableAndSaysWhere() {
        XCTAssertThrowsError(try RuleSetCodec.decode(data("{\"version\": 1, \"rules\": [ oops ]}"))) { error in
            guard case RuleSetCodec.FileError.unreadable(let reason) = error else {
                return XCTFail("expected unreadable, got \(error)")
            }
            XCTAssertTrue(reason.contains("not valid JSON"), reason)
        }
    }

    func testANewerFormatIsRefusedRatherThanMisread() {
        // A future format may shape rules differently. Decoding it with
        // today's rules would produce a list of misleading per-rule errors
        // instead of the one true fact.
        XCTAssertThrowsError(try RuleSetCodec.decode(data("{\"version\": 3, \"rules\": [{\"totally\": \"different\"}]}"))) {
            XCTAssertEqual($0 as? RuleSetCodec.FileError, .unsupportedVersion(3))
        }
    }

    func testAMissingVersionIsUnreadable() {
        XCTAssertThrowsError(try RuleSetCodec.decode(data("{\"rules\": []}"))) {
            guard case RuleSetCodec.FileError.unreadable = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: - What the menu shows

    func testNoFileIsNotAProblem() {
        let (rules, status) = RuleStoreStatus.load(nil, availableSounds: nil)
        XCTAssertEqual(rules, [])
        XCTAssertEqual(status, .noRulesFile)
        XCTAssertFalse(status.isProblem)
    }

    func testCountsSeparateEnabledFromDisabled() {
        let (_, status) = RuleStoreStatus.load(data("""
        {"version": 1, "rules": [
          {"name": "a", "condition": {"field": "app", "op": "equals", "value": "x"}},
          {"name": "b", "enabled": false, "condition": {"field": "app", "op": "equals", "value": "y"}}
        ]}
        """), availableSounds: nil)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 1))
        XCTAssertEqual(status.summary, "Rules: 1 active, 1 off")
        XCTAssertFalse(status.isProblem)
    }

    func testEveryStateWhereSomethingWrittenIsNotInEffectIsAProblem() {
        // These drive the warning glyph. An on-call tool whose rules did not
        // load is exactly as silent as one that cannot see banners.
        XCTAssertTrue(RuleStoreStatus.load(data("nope"), availableSounds: nil).status.isProblem)
        XCTAssertTrue(RuleStoreStatus.load(data("{\"version\": 9, \"rules\": []}"), availableSounds: nil).status.isProblem)
        XCTAssertTrue(RuleStoreStatus.load(data("""
        {"version": 1, "rules": [{"name": "x", "condition": {"and": []}}]}
        """), availableSounds: nil).status.isProblem)
    }

    func testAPartialLoadKeepsTheGoodRulesAndNamesTheBadOnesInTheDetail() {
        let (rules, status) = RuleStoreStatus.load(data("""
        {"version": 1, "rules": [
          {"name": "Good", "condition": {"field": "app", "op": "equals", "value": "x"}},
          {"name": "Bad", "condition": {"or": []}}
        ]}
        """), availableSounds: nil)
        XCTAssertEqual(rules.map(\.name), ["Good"])
        XCTAssertTrue(status.summary.contains("1 could not be used"), status.summary)
        XCTAssertTrue(status.detail.first?.contains("\"Bad\"") ?? false, "\(status.detail)")
    }

    func testAnUnreadableFileSaysNoRulesAreActive() {
        let status = RuleStoreStatus.load(data(""), availableSounds: nil).status
        XCTAssertTrue(status.summary.contains("no rules are active"), status.summary)
        XCTAssertFalse(status.detail.isEmpty, "the reason must be shown, not just the fact")
    }

    // MARK: - The starter file

    func testTheStarterFileLoadsCleanlyAndActivatesNothing() throws {
        let (rules, status) = RuleStoreStatus.load(try RuleSetCodec.encode([Rule.editingExample]), availableSounds: ["Glass"])
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(status, .loaded(enabled: 0, disabled: 1),
                       "creating the file must change nothing until the user enables something")
        XCTAssertFalse(status.isProblem, "a starter file that opened with a warning would be a poor first impression")
    }

    // MARK: - Alerts (format version 2)

    private func v2(_ rulesJSON: String) -> Data { data("{\"version\": 2, \"rules\": [\(rulesJSON)]}") }
    private let teamsCondition = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#

    func testASoundAlertDecodesWithItsGain() throws {
        let (rules, problems) = try RuleSetCodec.decode(v2(#"{"name": "a", \#(teamsCondition), "alert": {"sound": "Glass", "gainDB": 6}}"#))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.first?.alert, .sound(name: "Glass", gainDB: 6))
    }

    func testAnOmittedGainIsZero() throws {
        let (rules, _) = try RuleSetCodec.decode(v2(#"{"name": "a", \#(teamsCondition), "alert": {"sound": "Glass"}}"#))
        XCTAssertEqual(rules.first?.alert, .sound(name: "Glass", gainDB: 0))
    }

    func testSilentIsADeliberateAlertDistinctFromNone() throws {
        let (rules, _) = try RuleSetCodec.decode(v2(#"{"name": "quiet", \#(teamsCondition), "alert": "silent"}, {"name": "unset", \#(teamsCondition)}"#))
        XCTAssertEqual(rules.map(\.alert), [.silent, nil])
    }

    func testAnAlertThatIsNeitherSilentNorASoundIsRejected() throws {
        let (_, problems) = try RuleSetCodec.decode(v2(#"{"name": "a", \#(teamsCondition), "alert": "loud"}"#))
        XCTAssertTrue(problems.first?.reason.contains("\"silent\" or {\"sound\"") ?? false, "\(problems)")
    }

    func testAlertsRoundTripThroughTheReadableShape() throws {
        let rules = [Rule(name: "a", condition: .field(.app, .equals, "x"), alert: .sound(name: "Hero", gainDB: -3.5)),
                     Rule(name: "b", condition: .field(.app, .equals, "y"), alert: .silent),
                     Rule(name: "c", condition: .field(.app, .equals, "z"))]
        let encoded = try RuleSetCodec.encode(rules)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(text.contains(#""alert" : "silent""#), text)
        XCTAssertTrue(text.contains(#""version" : 2"#), text)
        XCTAssertEqual(try RuleSetCodec.decode(encoded).rules, rules)
    }

    // MARK: - Typos must not change meaning silently

    func testAMisspeltAlertKeyIsRejectedNotIgnored() throws {
        // Ignored, "alrt" would leave a rule that is quietly silent — the
        // author believing it alerts until the incident proves otherwise.
        let (rules, problems) = try RuleSetCodec.decode(v2(#"{"name": "Pager", \#(teamsCondition), "alrt": {"sound": "Glass"}}"#))
        XCTAssertEqual(rules, [])
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"alrt\"") ?? false, "\(problems)")
    }

    func testAMisspeltGainKeyIsRejectedNotDefaultedToZero() throws {
        let (_, problems) = try RuleSetCodec.decode(v2(#"{"name": "a", \#(teamsCondition), "alert": {"sound": "Glass", "gain": 6}}"#))
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"gain\"") ?? false, "\(problems)")
    }

    func testAMisspeltEnabledKeyIsRejectedNotLeftOn() throws {
        let (_, problems) = try RuleSetCodec.decode(v2(#"{"name": "a", \#(teamsCondition), "enabeld": false}"#))
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"enabeld\"") ?? false, "\(problems)")
    }

    func testAnExtraKeyInAConditionIsRejected() throws {
        let (_, problems) = try RuleSetCodec.decode(v2(#"{"name": "a", "condition": {"field": "app", "op": "equals", "value": "x", "vlaue": "y"}}"#))
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"vlaue\"") ?? false, "\(problems)")
    }

    // MARK: - Validation

    func testGainOutsideTheSafeRangeIsRejected() {
        // The EQ stage applied +40 dB when asked; the bound is ours to enforce.
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "a", condition: .field(.app, .equals, "x"), alert: .sound(name: "Glass", gainDB: 40))).isEmpty)
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "a", condition: .field(.app, .equals, "x"), alert: .sound(name: "Glass", gainDB: -41))).isEmpty)
        XCTAssertEqual(RuleSetCodec.problems(in: Rule(name: "a", condition: .field(.app, .equals, "x"), alert: .sound(name: "Glass", gainDB: 12))), [])
        XCTAssertEqual(RuleSetCodec.problems(in: Rule(name: "a", condition: .field(.app, .equals, "x"), alert: .sound(name: "Glass", gainDB: -40))), [])
    }

    func testAHugeGainIsReportedNotACrash() throws {
        // Valid JSON, and a hand-written file can hold anything. Formatting it
        // for the message once converted it to Int, which traps.
        let (rules, problems) = try RuleSetCodec.decode(v2(#"{"name": "a", "condition": {"field": "app", "op": "equals", "value": "x"}, "alert": {"sound": "Glass", "gainDB": 1e300}}"#))
        XCTAssertEqual(rules, [])
        XCTAssertEqual(problems.first?.reason, "gainDB 1e+300 is outside -40…+12 dB")
    }

    func testAnAlertNamingNoSoundIsRejected() {
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "a", condition: .field(.app, .equals, "x"), alert: .sound(name: " ", gainDB: 0))).isEmpty)
    }

    // MARK: - Version 1 files

    func testAVersion1FileWithoutAlertsStillLoads() throws {
        let (rules, problems) = try RuleSetCodec.decode(data(#"{"version": 1, "rules": [{"name": "a", "condition": {"field": "app", "op": "equals", "value": "x"}}]}"#))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.count, 1)
    }

    func testAnAlertInAVersion1FileIsRejectedBecauseAnOlderBuildWouldDropIt() throws {
        let (rules, problems) = try RuleSetCodec.decode(data(#"{"version": 1, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "x"}, "alert": {"sound": "Glass"}}]}"#))
        XCTAssertEqual(rules, [])
        XCTAssertTrue(problems.first?.reason.contains("alerts need \"version\": 2") ?? false, "\(problems)")
    }

    // MARK: - Sounds that do not exist

    func testAMisspeltSoundIsReportedAtLoadByRuleNumberAndName() {
        let (rules, status) = RuleStoreStatus.load(v2(#"{"name": "Fine", \#(teamsCondition), "alert": {"sound": "Glass"}}, {"name": "Pager", \#(teamsCondition), "alert": {"sound": "Glas"}}"#),
                                                   availableSounds: ["Glass", "Hero"])
        XCTAssertEqual(rules.map(\.name), ["Fine"])
        let detail = status.detail.first ?? ""
        XCTAssertTrue(detail.hasPrefix("Rule 2 (\"Pager\")"), "must name the rule by its real position: \(detail)")
        XCTAssertTrue(detail.contains("sound \"Glas\" was not found"), detail)
        XCTAssertTrue(detail.contains("Glass, Hero"), "the available names help the user fix it: \(detail)")
        XCTAssertTrue(status.isProblem)
    }

    func testSoundNamesAreMatchedIgnoringCase() {
        let (rules, status) = RuleStoreStatus.load(v2(#"{"name": "a", \#(teamsCondition), "alert": {"sound": "glass"}}"#), availableSounds: ["Glass"])
        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(status.isProblem)
    }

    func testProblemsAreListedInFileOrderWhateverFoundThem() {
        // A format problem (rule 3) and a missing sound (rule 1) are found by
        // different passes; the report must still read top to bottom.
        let (_, status) = RuleStoreStatus.load(v2(#"{"name": "One", \#(teamsCondition), "alert": {"sound": "Nope"}}, {"name": "Two", \#(teamsCondition)}, {"name": "Three", "condition": {"or": []}}"#),
                                               availableSounds: ["Glass"])
        XCTAssertEqual(status.detail.map { String($0.prefix(6)) }, ["Rule 1", "Rule 3"])
    }

    func testTheStarterFileShowsAnAlertAndStillActivatesNothing() throws {
        let starter = try RuleSetCodec.encode([Rule.editingExample])
        XCTAssertTrue(String(decoding: starter, as: UTF8.self).contains(#""sound" : "Glass""#), "the starter shows how an alert is written")
        let (_, status) = RuleStoreStatus.load(starter, availableSounds: ["Glass"])
        XCTAssertEqual(status, .loaded(enabled: 0, disabled: 1))
    }
}
