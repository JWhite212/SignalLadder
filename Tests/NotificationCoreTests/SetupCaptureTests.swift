import XCTest
@testable import NotificationCore

/// What the first run reads of the banners captured so far, and how an app the user picked
/// leads back to the banner it was read from (M5 plan, Task 8, Ruling 10). The app target
/// has no tests, so which entry "Make a Rule from This…" is made from, and how names are
/// compared to find it, are decided in the core and held here. Nothing here reads a title or
/// a body, shows a window or waits on a clock: each test builds a list of entries as the
/// ring buffer gives them, newest first, and reads what the core makes of it.
final class SetupCaptureTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// An entry for a banner from `app`. The title and body differ for each, so that an
    /// entry that was found can be told from another of the same app. `age` is how many
    /// seconds before `start` it arrived, only so that the entries are distinct.
    private func entry(_ app: String, title: String = "title", age: Int = 0) -> InspectorEntry {
        let when = start.addingTimeInterval(-TimeInterval(age))
        let note = CapturedNotification(timestamp: when, appNameGuess: app, title: title, subtitle: "", body: "body",
                                        rawText: "\(app) \(title) body", subrole: "AXNotificationCenterBanner")
        return InspectorEntry(captured: note, context: ContextSnapshot(date: when, recentCountForApp: 1),
                              suppressedRepeatCount: 0)
    }

    // MARK: - Whether anything has arrived

    func testNothingHasBeenCapturedWithoutAnEntryAndSomethingHasWithOne() {
        XCTAssertFalse(SetupCapture.anythingCaptured(in: []))
        XCTAssertTrue(SetupCapture.anythingCaptured(in: [entry("Teams")]))
        XCTAssertTrue(SetupCapture.anythingCaptured(in: [entry(""), entry("Teams")]),
                      "a banner that gave no app name was still captured")
    }

    // MARK: - The names

    func testTheNamesAreTheAppOfEachEntryInTheOrderGivenWhichIsNewestFirst() {
        let entries = [entry("Teams", age: 0), entry("Mail", age: 5), entry("Teams", age: 9), entry("Weather", age: 20)]
        XCTAssertEqual(SetupCapture.appNames(in: entries), ["Teams", "Mail", "Teams", "Weather"])
        XCTAssertEqual(SetupCapture.appNames(in: []), [])
    }

    /// The name is the one a rule reads for the `app` field, so the name the step lists is
    /// the one a rule made from the entry will match.
    func testTheNameIsTheOneARuleReadsForTheAppField() {
        for app in ["Teams", "Microsoft Teams", "Météo", "  padded  ", ""] {
            let made = entry(app)
            XCTAssertEqual(SetupCapture.appNames(in: [made]), [made.captured.value(of: .app)], app)
            XCTAssertEqual(SetupCapture.appNames(in: [made]), [made.captured.appNameGuess], app)
        }
    }

    /// App names only: nothing the banner said is in them, however the entries differ.
    func testTheNamesHoldNothingButAppNames() {
        let said = entry("Teams", title: "Prod is down")
        let names = SetupCapture.appNames(in: [said])
        XCTAssertEqual(names, ["Teams"])
        XCTAssertFalse(names.joined().contains("Prod is down"))
        XCTAssertFalse(names.joined().contains("body"))
    }

    /// The list is repeated, blank where a banner gave no name, and not de-duplicated here:
    /// the step lists each app once, newest spelling first, and none that is blank
    /// (`SetupText`), so the spelling it shows is the newest entry's.
    func testTheStepListsTheNewestSpellingOfAnAppOnceAndNoBlankOne() {
        let entries = [entry("microsoft teams", age: 0), entry("", age: 1), entry("Microsoft Teams", age: 2),
                       entry("Mail", age: 3)]
        XCTAssertEqual(SetupCapture.appNames(in: entries), ["microsoft teams", "", "Microsoft Teams", "Mail"])
        let facts = SetupFacts(accessibilityTrusted: true, notifications: nil, health: .unknown, lastVerifiedAt: nil,
                               ruleStatus: .loaded(enabled: 0, disabled: 0),
                               ruleReach: RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0),
                               rulesFileReadOnly: nil, anythingCaptured: true,
                               capturedAppNames: SetupCapture.appNames(in: entries), appsToMute: [],
                               muteChecklist: MuteChecklist(), loginItem: .on, progress: SetupProgress())
        let words = SetupText.words(for: .firstRule, facts: facts, time: { _ in "" })
        XCTAssertEqual(words.apps, ["microsoft teams", "Mail"])
    }

    /// What the first rule's step shows for these entries as the ring buffer gives them, with a rules
    /// file that has none and nothing else to do: the facts the app gathers from the entries, and the
    /// words the core makes of them.
    private func firstRuleWords(_ entries: [InspectorEntry]) -> SetupText.StepWords {
        let facts = SetupFacts(accessibilityTrusted: true, notifications: nil, health: .unknown, lastVerifiedAt: nil,
                               ruleStatus: .noRulesFile,
                               ruleReach: RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0),
                               rulesFileReadOnly: nil, anythingCaptured: SetupCapture.anythingCaptured(in: entries),
                               capturedAppNames: SetupCapture.appNames(in: entries), appsToMute: [],
                               muteChecklist: MuteChecklist(), loginItem: .on, progress: SetupProgress())
        return SetupText.words(for: .firstRule, facts: facts, time: { _ in "" })
    }

    /// Banners that gave no app name leave nothing to pick, and a name that finds nothing is no
    /// reason for a button: the step lists no app, offers no "Make a Rule from This…" whose press
    /// would find no entry, and says where the rule is made instead. It does not claim there was
    /// nothing captured.
    func testBannersThatGaveNoAppNameLeaveNothingToPickAndNoButtonThatNeedsAPick() {
        for blanks in [[""], ["", "   "], ["\t", " ", ""]] {
            let entries = blanks.enumerated().map { entry($0.element, title: "t\($0.offset)", age: $0.offset) }
            XCTAssertTrue(SetupCapture.anythingCaptured(in: entries))
            let words = firstRuleWords(entries)
            XCTAssertEqual(words.apps, [], "\(blanks)")
            XCTAssertEqual(words.buttons.map(\.action), [.checkAgain], "\(blanks)")
            XCTAssertEqual(words.detail, [SetupText.bannersWithoutNames], "\(blanks)")
            XCTAssertNil(words.selectable, "something was captured, so the practice line is not shown")
            for name in blanks + ["", " "] {
                XCTAssertNil(SetupCapture.newestEntry(forApp: name, in: entries), "\"\(name)\" finds nothing")
            }
        }
    }

    /// Over lists of every shape the buffer can give, the step offers "Make a Rule from This…" exactly
    /// when it lists an app, and every app it lists leads back to an entry, so the button is never
    /// offered where the press would find nothing.
    func testTheButtonIsOfferedOnlyWhereEveryAppListedLeadsBackToAnEntry() {
        let lists: [[InspectorEntry]] = [
            [],
            [entry("")],
            [entry(""), entry("   ")],
            [entry("Teams"), entry("")],
            [entry(""), entry("microsoft teams"), entry("Microsoft Teams"), entry("  Mail ")],
            [entry("Météo"), entry("meteo"), entry("")],
        ]
        for entries in lists {
            let words = firstRuleWords(entries)
            XCTAssertEqual(words.buttons.map(\.action).contains(.makeRule), !words.apps.isEmpty, "\(entries.count) entries")
            for app in words.apps {
                XCTAssertNotNil(SetupCapture.newestEntry(forApp: app, in: entries), "\"\(app)\" is listed and finds nothing")
            }
        }
    }

    // MARK: - The newest entry an app was read from

    func testTheNewestEntryOfTheAppIsTheFirstGiven() {
        let newest = entry("Teams", title: "newest", age: 0)
        let older = entry("Teams", title: "older", age: 30)
        let other = entry("Mail", title: "mail", age: 10)
        let entries = [newest, other, older]
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "Teams", in: entries)?.id, newest.id)
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "Mail", in: entries)?.id, other.id)
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "Teams", in: [other, older])?.id, older.id,
                       "with the newest gone, the next newest is the one it was read from")
    }

    func testAnAppThatIsNotThereFindsNothing() {
        XCTAssertNil(SetupCapture.newestEntry(forApp: "Teams", in: []))
        XCTAssertNil(SetupCapture.newestEntry(forApp: "Teams", in: [entry("Mail"), entry("Weather")]))
        XCTAssertNil(SetupCapture.newestEntry(forApp: "Team", in: [entry("Teams")]), "a name is not a prefix")
        XCTAssertNil(SetupCapture.newestEntry(forApp: "Microsoft", in: [entry("Microsoft Teams")]))
    }

    /// Names are compared as rules and the mute checklist compare them: case, accents and
    /// surrounding spaces do not matter, so the spelling the step showed finds the entry
    /// whatever spelling that entry has.
    func testNamesAreComparedIgnoringCaseAccentsAndSurroundingSpaces() {
        let weather = entry("Météo", title: "w")
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "meteo", in: [weather])?.id, weather.id)
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "MÉTÉO", in: [weather])?.id, weather.id)
        let teams = entry("Microsoft Teams")
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "microsoft teams", in: [teams])?.id, teams.id)
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "  Microsoft Teams ", in: [teams])?.id, teams.id)
        let padded = entry("  Mail ")
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "Mail", in: [padded])?.id, padded.id)
    }

    /// Two spellings of one app are one app, and the newest of them is the entry, as the
    /// step lists them once.
    func testTwoSpellingsOfAnAppAreOneAppAndTheNewestIsFound() {
        let newer = entry("microsoft teams", title: "newer", age: 0)
        let older = entry("Microsoft Teams", title: "older", age: 40)
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "Microsoft Teams", in: [newer, older])?.id, newer.id)
        XCTAssertEqual(SetupCapture.newestEntry(forApp: "microsoft teams", in: [newer, older])?.id, newer.id)
    }

    /// A blank name is never an app: the step lists none, and a banner that gave no name is
    /// not found by an empty one.
    func testABlankNameFindsNothing() {
        let entries = [entry(""), entry("   "), entry("Teams")]
        for name in ["", " ", "   ", "\t"] {
            XCTAssertNil(SetupCapture.newestEntry(forApp: name, in: entries), "\"\(name)\"")
        }
    }

    /// The entry found is the entry as it stands, with what it read, so the editor can make
    /// the rule from it; the lookup keeps nothing and alters nothing.
    func testTheEntryFoundIsTheEntryItselfUnchanged() {
        let made = entry("Teams", title: "Prod is down")
        let found = SetupCapture.newestEntry(forApp: "Teams", in: [entry("Mail"), made])
        XCTAssertEqual(found, made)
        XCTAssertEqual(found?.captured.title, "Prod is down")
    }

    /// The name the step lists, picked back, finds an entry for every app in the list.
    func testEveryNameTheStepListsFindsAnEntry() {
        let entries = [entry("Teams"), entry("mail"), entry("Météo"), entry("Teams", age: 9)]
        for name in SetupCapture.appNames(in: entries) {
            XCTAssertNotNil(SetupCapture.newestEntry(forApp: name, in: entries), name)
        }
    }
}
